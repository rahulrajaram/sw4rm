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

//! Agent handoff protocol for SW4RM.
//!
//! This module provides the `HandoffClient` for managing agent-to-agent
//! task handoffs, including context preservation and capability matching.
//!
//! The handoff protocol enables:
//! - Requesting handoffs to other agents
//! - Accepting or rejecting handoff requests
//! - Querying pending handoffs
//! - Preserving context during handoffs

use crate::{Error, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use uuid::Uuid;

/// Status of a handoff request.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum HandoffStatus {
    /// Handoff has been requested but not yet accepted or rejected
    Pending = 1,
    /// Handoff has been accepted by the target agent
    Accepted = 2,
    /// Handoff has been rejected by the target agent
    Rejected = 3,
    /// Handoff has been completed successfully
    Completed = 4,
    /// Handoff has expired
    Expired = 5,
}

impl Default for HandoffStatus {
    fn default() -> Self {
        Self::Pending
    }
}

/// Request to hand off execution to another agent.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HandoffRequest {
    /// Unique identifier for this handoff request
    pub request_id: String,
    /// ID of the agent initiating the handoff
    pub from_agent: String,
    /// ID of the agent that should receive the handoff
    pub to_agent: String,
    /// Human-readable explanation of why the handoff is needed
    pub reason: String,
    /// Serialized context data (conversation history, tool state, etc.)
    pub context_snapshot: Option<Vec<u8>>,
    /// Whether to preserve conversation history in the handoff
    pub preserve_history: bool,
    /// List of capabilities the target agent must have
    pub capabilities_required: Vec<String>,
    /// Priority level for the handoff (higher = more urgent)
    pub priority: i32,
    /// Additional metadata for the handoff
    pub metadata: HashMap<String, String>,
    /// Timestamp when the request was created
    pub created_at: DateTime<Utc>,
    /// Timeout for the handoff to be accepted (spec §17.6 MUST)
    pub timeout: Option<std::time::Duration>,
}

impl HandoffRequest {
    /// Create a new handoff request.
    ///
    /// # Arguments
    ///
    /// * `from_agent` - ID of the agent initiating the handoff
    /// * `to_agent` - ID of the agent that should receive the handoff
    /// * `reason` - Human-readable explanation of why the handoff is needed
    pub fn new(from_agent: String, to_agent: String, reason: String) -> Self {
        Self {
            request_id: Uuid::new_v4().to_string(),
            from_agent,
            to_agent,
            reason,
            context_snapshot: None,
            preserve_history: true,
            capabilities_required: Vec::new(),
            priority: 0,
            metadata: HashMap::new(),
            created_at: Utc::now(),
            timeout: None,
        }
    }

    /// Set the timeout for the handoff to be accepted (spec §17.6).
    pub fn with_timeout(mut self, timeout: std::time::Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }

    /// Set the context snapshot for this handoff.
    pub fn with_context(mut self, context: Vec<u8>) -> Self {
        self.context_snapshot = Some(context);
        self
    }

    /// Set the preserve history flag.
    pub fn with_preserve_history(mut self, preserve: bool) -> Self {
        self.preserve_history = preserve;
        self
    }

    /// Set the required capabilities.
    pub fn with_capabilities(mut self, capabilities: Vec<String>) -> Self {
        self.capabilities_required = capabilities;
        self
    }

    /// Set the priority level.
    pub fn with_priority(mut self, priority: i32) -> Self {
        self.priority = priority;
        self
    }

    /// Add metadata to the request.
    pub fn with_metadata(mut self, key: String, value: String) -> Self {
        self.metadata.insert(key, value);
        self
    }
}

/// Response to a handoff request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HandoffResponse {
    /// Whether the handoff was accepted (for processing)
    pub accepted: bool,
    /// Unique identifier for the handoff transaction
    pub handoff_id: String,
    /// Explanation if the handoff was rejected
    pub rejection_reason: Option<String>,
    /// Current status of the handoff
    pub status: HandoffStatus,
    /// Additional metadata about the handoff
    pub metadata: HashMap<String, String>,
}

impl HandoffResponse {
    /// Create a new pending handoff response.
    pub fn pending(handoff_id: String) -> Self {
        Self {
            accepted: true,
            handoff_id,
            rejection_reason: None,
            status: HandoffStatus::Pending,
            metadata: HashMap::new(),
        }
    }

    /// Create a rejected handoff response.
    pub fn rejected(handoff_id: String, reason: String) -> Self {
        Self {
            accepted: false,
            handoff_id,
            rejection_reason: Some(reason),
            status: HandoffStatus::Rejected,
            metadata: HashMap::new(),
        }
    }
}

/// Internal storage for handoffs.
struct HandoffStorage {
    handoffs: HashMap<String, (HandoffRequest, HandoffResponse)>,
    pending_by_agent: HashMap<String, Vec<String>>,
}

impl HandoffStorage {
    fn new() -> Self {
        Self {
            handoffs: HashMap::new(),
            pending_by_agent: HashMap::new(),
        }
    }
}

/// Client for managing agent handoff operations.
///
/// This client provides methods for requesting handoffs, accepting/rejecting
/// handoff requests, and querying pending handoffs. It maintains an in-memory
/// store of handoff requests and their statuses.
///
/// In a production system, this would interface with a distributed handoff
/// service via gRPC. For now, it provides a local implementation suitable
/// for development and testing.
///
/// # Example
///
/// ```rust
/// use sw4rm_sdk::clients::handoff::{HandoffClient, HandoffRequest};
///
/// let client = HandoffClient::new();
///
/// let request = HandoffRequest::new(
///     "agent-1".to_string(),
///     "agent-2".to_string(),
///     "Task requires specialized capabilities".to_string(),
/// );
///
/// let response = client.request_handoff(request).unwrap();
/// println!("Handoff ID: {}", response.handoff_id);
/// ```
#[derive(Clone)]
pub struct HandoffClient {
    storage: Arc<RwLock<HandoffStorage>>,
}

impl Default for HandoffClient {
    fn default() -> Self {
        Self::new()
    }
}

impl HandoffClient {
    /// Create a new handoff client with in-memory storage.
    pub fn new() -> Self {
        Self {
            storage: Arc::new(RwLock::new(HandoffStorage::new())),
        }
    }

    /// Request a handoff to another agent.
    ///
    /// Creates a new handoff request and returns a response with a unique
    /// handoff ID. The handoff will be in PENDING status until the target
    /// agent accepts or rejects it.
    ///
    /// # Arguments
    ///
    /// * `request` - The handoff request containing from_agent, to_agent,
    ///   reason, context, and other parameters
    ///
    /// # Returns
    ///
    /// `HandoffResponse` with accepted=true (pending acceptance), handoff_id,
    /// and status=PENDING.
    pub fn request_handoff(&self, request: HandoffRequest) -> Result<HandoffResponse> {
        let handoff_id = request.request_id.clone();
        let to_agent = request.to_agent.clone();

        let response = HandoffResponse {
            accepted: true,
            handoff_id: handoff_id.clone(),
            rejection_reason: None,
            status: HandoffStatus::Pending,
            metadata: {
                let mut m = HashMap::new();
                m.insert("created_at".to_string(), Utc::now().to_rfc3339());
                m
            },
        };

        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        storage
            .handoffs
            .insert(handoff_id.clone(), (request, response.clone()));
        storage
            .pending_by_agent
            .entry(to_agent)
            .or_insert_with(Vec::new)
            .push(handoff_id);

        Ok(response)
    }

    /// Accept a pending handoff request.
    ///
    /// Updates the handoff status to ACCEPTED and removes it from the
    /// pending list for the target agent.
    ///
    /// # Arguments
    ///
    /// * `handoff_id` - Unique identifier of the handoff to accept
    ///
    /// # Errors
    ///
    /// Returns an error if handoff_id is not found or handoff is not in PENDING status.
    pub fn accept_handoff(&self, handoff_id: &str) -> Result<()> {
        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        let to_agent = {
            let (request, response) = storage
                .handoffs
                .get_mut(handoff_id)
                .ok_or_else(|| Error::Config(format!("Handoff {} not found", handoff_id)))?;

            if response.status != HandoffStatus::Pending {
                return Err(Error::Config(format!(
                    "Handoff {} is not in PENDING status (current: {:?})",
                    handoff_id, response.status
                )));
            }

            response.accepted = true;
            response.status = HandoffStatus::Accepted;
            response
                .metadata
                .insert("accepted_at".to_string(), Utc::now().to_rfc3339());

            request.to_agent.clone()
        };

        // Remove from pending list
        if let Some(pending) = storage.pending_by_agent.get_mut(&to_agent) {
            pending.retain(|id| id != handoff_id);
        }

        Ok(())
    }

    /// Reject a pending handoff request.
    ///
    /// Updates the handoff status to REJECTED with the provided reason
    /// and removes it from the pending list for the target agent.
    ///
    /// # Arguments
    ///
    /// * `handoff_id` - Unique identifier of the handoff to reject
    /// * `reason` - Human-readable explanation of why the handoff was rejected
    ///
    /// # Errors
    ///
    /// Returns an error if handoff_id is not found or handoff is not in PENDING status.
    pub fn reject_handoff(&self, handoff_id: &str, reason: &str) -> Result<()> {
        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        let to_agent = {
            let (request, response) = storage
                .handoffs
                .get_mut(handoff_id)
                .ok_or_else(|| Error::Config(format!("Handoff {} not found", handoff_id)))?;

            if response.status != HandoffStatus::Pending {
                return Err(Error::Config(format!(
                    "Handoff {} is not in PENDING status (current: {:?})",
                    handoff_id, response.status
                )));
            }

            response.accepted = false;
            response.status = HandoffStatus::Rejected;
            response.rejection_reason = Some(reason.to_string());
            response
                .metadata
                .insert("rejected_at".to_string(), Utc::now().to_rfc3339());

            request.to_agent.clone()
        };

        // Remove from pending list
        if let Some(pending) = storage.pending_by_agent.get_mut(&to_agent) {
            pending.retain(|id| id != handoff_id);
        }

        Ok(())
    }

    /// Mark a handoff as completed.
    ///
    /// Updates the handoff status to COMPLETED after the receiving agent
    /// has successfully taken over execution.
    ///
    /// # Arguments
    ///
    /// * `handoff_id` - Unique identifier of the handoff to complete
    ///
    /// # Errors
    ///
    /// Returns an error if handoff_id is not found or handoff is not in ACCEPTED status.
    pub fn complete_handoff(&self, handoff_id: &str) -> Result<()> {
        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        let (_, response) = storage
            .handoffs
            .get_mut(handoff_id)
            .ok_or_else(|| Error::Config(format!("Handoff {} not found", handoff_id)))?;

        if response.status != HandoffStatus::Accepted {
            return Err(Error::Config(format!(
                "Handoff {} is not in ACCEPTED status (current: {:?})",
                handoff_id, response.status
            )));
        }

        response.status = HandoffStatus::Completed;
        response
            .metadata
            .insert("completed_at".to_string(), Utc::now().to_rfc3339());

        Ok(())
    }

    /// Get all pending handoffs for a specific agent.
    ///
    /// Returns all handoff requests that are waiting for the specified
    /// agent to accept or reject them.
    ///
    /// # Arguments
    ///
    /// * `agent_id` - ID of the agent to query for pending handoffs
    ///
    /// # Returns
    ///
    /// Vector of `HandoffRequest` objects in PENDING status for this agent.
    pub fn get_pending_handoffs(&self, agent_id: &str) -> Result<Vec<HandoffRequest>> {
        let storage = self
            .storage
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        let pending_ids = storage
            .pending_by_agent
            .get(agent_id)
            .cloned()
            .unwrap_or_default();

        let mut requests = Vec::new();
        for handoff_id in pending_ids {
            if let Some((request, response)) = storage.handoffs.get(&handoff_id) {
                if response.status == HandoffStatus::Pending {
                    requests.push(request.clone());
                }
            }
        }

        Ok(requests)
    }

    /// Get the current status of a handoff.
    ///
    /// # Arguments
    ///
    /// * `handoff_id` - Unique identifier of the handoff
    ///
    /// # Returns
    ///
    /// `HandoffResponse` if found, None otherwise.
    pub fn get_handoff_status(&self, handoff_id: &str) -> Result<Option<HandoffResponse>> {
        let storage = self
            .storage
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        Ok(storage.handoffs.get(handoff_id).map(|(_, r)| r.clone()))
    }

    /// Clear all handoff data from storage.
    ///
    /// This is primarily for testing purposes.
    pub fn clear_all_handoffs(&self) -> Result<()> {
        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        storage.handoffs.clear();
        storage.pending_by_agent.clear();

        Ok(())
    }
}

impl std::fmt::Debug for HandoffClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("HandoffClient").finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_request_handoff() {
        let client = HandoffClient::new();
        let request = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Need specialized help".to_string(),
        );

        let response = client.request_handoff(request).unwrap();
        assert!(response.accepted);
        assert_eq!(response.status, HandoffStatus::Pending);
        assert!(!response.handoff_id.is_empty());
    }

    #[test]
    fn test_accept_handoff() {
        let client = HandoffClient::new();
        let request = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Need specialized help".to_string(),
        );

        let response = client.request_handoff(request).unwrap();
        let handoff_id = response.handoff_id.clone();

        client.accept_handoff(&handoff_id).unwrap();

        let status = client.get_handoff_status(&handoff_id).unwrap().unwrap();
        assert_eq!(status.status, HandoffStatus::Accepted);
    }

    #[test]
    fn test_reject_handoff() {
        let client = HandoffClient::new();
        let request = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Need specialized help".to_string(),
        );

        let response = client.request_handoff(request).unwrap();
        let handoff_id = response.handoff_id.clone();

        client
            .reject_handoff(&handoff_id, "Busy with other tasks")
            .unwrap();

        let status = client.get_handoff_status(&handoff_id).unwrap().unwrap();
        assert_eq!(status.status, HandoffStatus::Rejected);
        assert_eq!(
            status.rejection_reason,
            Some("Busy with other tasks".to_string())
        );
    }

    #[test]
    fn test_complete_handoff() {
        let client = HandoffClient::new();
        let request = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Need specialized help".to_string(),
        );

        let response = client.request_handoff(request).unwrap();
        let handoff_id = response.handoff_id.clone();

        client.accept_handoff(&handoff_id).unwrap();
        client.complete_handoff(&handoff_id).unwrap();

        let status = client.get_handoff_status(&handoff_id).unwrap().unwrap();
        assert_eq!(status.status, HandoffStatus::Completed);
    }

    #[test]
    fn test_get_pending_handoffs() {
        let client = HandoffClient::new();

        let request1 = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Request 1".to_string(),
        );
        let request2 = HandoffRequest::new(
            "agent-3".to_string(),
            "agent-2".to_string(),
            "Request 2".to_string(),
        );

        client.request_handoff(request1).unwrap();
        client.request_handoff(request2).unwrap();

        let pending = client.get_pending_handoffs("agent-2").unwrap();
        assert_eq!(pending.len(), 2);
    }

    #[test]
    fn test_handoff_not_found() {
        let client = HandoffClient::new();
        let result = client.accept_handoff("nonexistent-id");
        assert!(result.is_err());
    }

    #[test]
    fn test_double_accept_fails() {
        let client = HandoffClient::new();
        let request = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Need help".to_string(),
        );

        let response = client.request_handoff(request).unwrap();
        let handoff_id = response.handoff_id.clone();

        client.accept_handoff(&handoff_id).unwrap();
        let result = client.accept_handoff(&handoff_id);
        assert!(result.is_err());
    }

    #[test]
    fn test_handoff_request_builder() {
        let request = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Need specialized help".to_string(),
        )
        .with_context(b"context data".to_vec())
        .with_preserve_history(true)
        .with_capabilities(vec!["file-operations".to_string()])
        .with_priority(5)
        .with_metadata("key".to_string(), "value".to_string());

        assert!(request.context_snapshot.is_some());
        assert!(request.preserve_history);
        assert_eq!(request.capabilities_required.len(), 1);
        assert_eq!(request.priority, 5);
        assert_eq!(request.metadata.get("key"), Some(&"value".to_string()));
    }

    #[test]
    fn test_pending_removed_after_rejection() {
        let client = HandoffClient::new();
        let request = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Test".to_string(),
        );

        let response = client.request_handoff(request).unwrap();
        let handoff_id = response.handoff_id.clone();

        // Initially pending
        let pending = client.get_pending_handoffs("agent-2").unwrap();
        assert_eq!(pending.len(), 1);

        // After rejection, should be removed
        client.reject_handoff(&handoff_id, "Busy").unwrap();
        let pending = client.get_pending_handoffs("agent-2").unwrap();
        assert_eq!(pending.len(), 0);
    }

    #[test]
    fn test_double_reject_fails() {
        let client = HandoffClient::new();
        let request = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Test".to_string(),
        );

        let response = client.request_handoff(request).unwrap();
        let handoff_id = response.handoff_id.clone();

        client.reject_handoff(&handoff_id, "First rejection").unwrap();
        let result = client.reject_handoff(&handoff_id, "Second rejection");
        assert!(result.is_err());
    }

    #[test]
    fn test_request_accept_complete_flow() {
        let client = HandoffClient::new();
        let request = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Workflow test".to_string(),
        );

        let response = client.request_handoff(request).unwrap();
        assert_eq!(response.status, HandoffStatus::Pending);

        client.accept_handoff(&response.handoff_id).unwrap();
        let status = client.get_handoff_status(&response.handoff_id).unwrap().unwrap();
        assert_eq!(status.status, HandoffStatus::Accepted);

        client.complete_handoff(&response.handoff_id).unwrap();
        let status = client.get_handoff_status(&response.handoff_id).unwrap().unwrap();
        assert_eq!(status.status, HandoffStatus::Completed);
    }

    #[test]
    fn test_request_reject_flow() {
        let client = HandoffClient::new();
        let request = HandoffRequest::new(
            "agent-1".to_string(),
            "agent-2".to_string(),
            "Workflow test".to_string(),
        );

        let response = client.request_handoff(request).unwrap();
        assert_eq!(response.status, HandoffStatus::Pending);

        client
            .reject_handoff(&response.handoff_id, "Not equipped")
            .unwrap();
        let status = client.get_handoff_status(&response.handoff_id).unwrap().unwrap();
        assert_eq!(status.status, HandoffStatus::Rejected);
        assert!(status.rejection_reason.is_some());
    }
}
