// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Handoff Service gRPC Server Implementation.
//!
//! This module provides the gRPC server implementation for the HandoffService,
//! enabling distributed agent-to-agent task handoffs with centralized state.

use crate::proto::sw4rm::handoff::{
    handoff_service_server::{HandoffService, HandoffServiceServer},
    CompleteHandoffRequest, CompleteHandoffResponse, GetPendingHandoffsRequest,
    GetPendingHandoffsResponse, HandoffRequest, HandoffResponse, HandoffStatus,
};
use crate::proto::sw4rm::common::Empty;
use dashmap::DashMap;
use std::collections::HashSet;
use std::sync::Arc;
use tonic::{Request, Response, Status};
use tracing::{debug, info, warn};

/// gRPC server implementation for HandoffService.
///
/// Provides centralized handoff coordination for distributed agent deployments.
/// Thread-safe implementation using DashMap for concurrent access.
#[derive(Debug)]
pub struct HandoffServiceImpl {
    /// All handoff requests indexed by request_id
    requests: Arc<DashMap<String, HandoffRequest>>,
    /// Responses for completed handoffs
    responses: Arc<DashMap<String, HandoffResponse>>,
    /// Pending handoffs indexed by target agent_id
    pending_by_agent: Arc<DashMap<String, HashSet<String>>>,
    /// Current status of each handoff
    status: Arc<DashMap<String, i32>>,
}

impl Default for HandoffServiceImpl {
    fn default() -> Self {
        Self::new()
    }
}

impl HandoffServiceImpl {
    /// Create a new HandoffServiceImpl with empty state.
    pub fn new() -> Self {
        info!("HandoffService initialized");
        Self {
            requests: Arc::new(DashMap::new()),
            responses: Arc::new(DashMap::new()),
            pending_by_agent: Arc::new(DashMap::new()),
            status: Arc::new(DashMap::new()),
        }
    }

    /// Convert this service into a tonic service.
    pub fn into_service(self) -> HandoffServiceServer<Self> {
        HandoffServiceServer::new(self)
    }

    /// Get the current status of a handoff.
    pub fn get_status(&self, request_id: &str) -> Option<i32> {
        self.status.get(request_id).map(|v| *v)
    }

    /// Get the response for a handoff if available.
    pub fn get_response(&self, request_id: &str) -> Option<HandoffResponse> {
        self.responses.get(request_id).map(|v| v.clone())
    }

    /// Clear all handoff data (for testing).
    pub fn clear_all(&self) {
        self.requests.clear();
        self.responses.clear();
        self.pending_by_agent.clear();
        self.status.clear();
        info!("HandoffService state cleared");
    }
}

#[tonic::async_trait]
impl HandoffService for HandoffServiceImpl {
    /// Request a handoff to another agent.
    async fn request_handoff(
        &self,
        request: Request<HandoffRequest>,
    ) -> Result<Response<Empty>, Status> {
        let req = request.into_inner();
        let request_id = req.request_id.clone();
        let from_agent = req.from_agent.clone();
        let to_agent = req.to_agent.clone();

        // Validate required fields
        if request_id.is_empty() {
            return Err(Status::invalid_argument("request_id is required"));
        }
        if from_agent.is_empty() {
            return Err(Status::invalid_argument("from_agent is required"));
        }
        if to_agent.is_empty() {
            return Err(Status::invalid_argument("to_agent is required"));
        }

        // Check if request already exists
        if self.requests.contains_key(&request_id) {
            return Err(Status::already_exists(format!(
                "Handoff request '{}' already exists",
                request_id
            )));
        }

        // Store the request
        self.requests.insert(request_id.clone(), req);
        self.status.insert(request_id.clone(), HandoffStatus::Pending as i32);

        // Add to pending queue for target agent
        self.pending_by_agent
            .entry(to_agent.clone())
            .or_insert_with(HashSet::new)
            .insert(request_id.clone());

        info!(
            "Handoff requested: {} from {} to {}",
            request_id, from_agent, to_agent
        );

        Ok(Response::new(Empty {}))
    }

    /// Accept a pending handoff request.
    async fn accept_handoff(
        &self,
        request: Request<HandoffResponse>,
    ) -> Result<Response<Empty>, Status> {
        let req = request.into_inner();
        let request_id = req.request_id.clone();

        // Check if request exists
        if !self.requests.contains_key(&request_id) {
            return Err(Status::not_found(format!(
                "Handoff request '{}' not found",
                request_id
            )));
        }

        // Check current status
        let current_status = self.status.get(&request_id).map(|v| *v);
        if current_status != Some(HandoffStatus::Pending as i32) {
            return Err(Status::failed_precondition(format!(
                "Handoff '{}' is not in PENDING status",
                request_id
            )));
        }

        // Update status
        self.status.insert(request_id.clone(), HandoffStatus::Accepted as i32);

        // Store response
        let response = HandoffResponse {
            request_id: request_id.clone(),
            accepted: true,
            accepting_agent: req.accepting_agent.clone(),
            rejection_reason: String::new(),
        };
        self.responses.insert(request_id.clone(), response);

        // Remove from pending queue
        if let Some(original) = self.requests.get(&request_id) {
            let to_agent = original.to_agent.clone();
            if let Some(mut pending) = self.pending_by_agent.get_mut(&to_agent) {
                pending.remove(&request_id);
            }
        }

        info!(
            "Handoff accepted: {} by {}",
            request_id, req.accepting_agent
        );

        Ok(Response::new(Empty {}))
    }

    /// Reject a pending handoff request.
    async fn reject_handoff(
        &self,
        request: Request<HandoffResponse>,
    ) -> Result<Response<Empty>, Status> {
        let req = request.into_inner();
        let request_id = req.request_id.clone();

        // Check if request exists
        if !self.requests.contains_key(&request_id) {
            return Err(Status::not_found(format!(
                "Handoff request '{}' not found",
                request_id
            )));
        }

        // Check current status
        let current_status = self.status.get(&request_id).map(|v| *v);
        if current_status != Some(HandoffStatus::Pending as i32) {
            return Err(Status::failed_precondition(format!(
                "Handoff '{}' is not in PENDING status",
                request_id
            )));
        }

        // Update status
        self.status.insert(request_id.clone(), HandoffStatus::Rejected as i32);

        // Store response
        let response = HandoffResponse {
            request_id: request_id.clone(),
            accepted: false,
            accepting_agent: String::new(),
            rejection_reason: req.rejection_reason.clone(),
        };
        self.responses.insert(request_id.clone(), response);

        // Remove from pending queue
        if let Some(original) = self.requests.get(&request_id) {
            let to_agent = original.to_agent.clone();
            if let Some(mut pending) = self.pending_by_agent.get_mut(&to_agent) {
                pending.remove(&request_id);
            }
        }

        info!(
            "Handoff rejected: {}, reason: {}",
            request_id, req.rejection_reason
        );

        Ok(Response::new(Empty {}))
    }

    /// Get all pending handoff requests for an agent.
    async fn get_pending_handoffs(
        &self,
        request: Request<GetPendingHandoffsRequest>,
    ) -> Result<Response<GetPendingHandoffsResponse>, Status> {
        let agent_id = request.into_inner().agent_id;

        let pending_ids = self
            .pending_by_agent
            .get(&agent_id)
            .map(|v| v.clone())
            .unwrap_or_default();

        let mut pending_requests = Vec::new();
        for request_id in pending_ids {
            if let Some(req) = self.requests.get(&request_id) {
                let status = self.status.get(&request_id).map(|v| *v);
                if status == Some(HandoffStatus::Pending as i32) {
                    pending_requests.push(req.clone());
                }
            }
        }

        debug!(
            "GetPendingHandoffs for {}: {} pending",
            agent_id,
            pending_requests.len()
        );

        Ok(Response::new(GetPendingHandoffsResponse {
            pending_requests,
        }))
    }

    /// Complete or expire a handoff.
    async fn complete_handoff(
        &self,
        request: Request<CompleteHandoffRequest>,
    ) -> Result<Response<CompleteHandoffResponse>, Status> {
        let req = request.into_inner();
        let request_id = req.request_id.clone();
        let new_status = req.status;

        // Check if request exists
        if !self.requests.contains_key(&request_id) {
            return Ok(Response::new(CompleteHandoffResponse {
                success: false,
                message: format!("Handoff request '{}' not found", request_id),
            }));
        }

        // Update status
        self.status.insert(request_id.clone(), new_status);

        // Clean up pending queue
        if let Some(original) = self.requests.get(&request_id) {
            let to_agent = original.to_agent.clone();
            if let Some(mut pending) = self.pending_by_agent.get_mut(&to_agent) {
                pending.remove(&request_id);
            }
        }

        let status_name = match new_status {
            x if x == HandoffStatus::Completed as i32 => "COMPLETED",
            x if x == HandoffStatus::Expired as i32 => "EXPIRED",
            _ => "UNKNOWN",
        };

        info!("Handoff completed: {} with status {}", request_id, status_name);

        Ok(Response::new(CompleteHandoffResponse {
            success: true,
            message: format!("Handoff '{}' marked as {}", request_id, status_name),
        }))
    }
}
