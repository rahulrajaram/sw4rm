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

//! Negotiation Room Service gRPC Server Implementation.
//!
//! This module provides the gRPC server implementation for the NegotiationRoomService,
//! enabling distributed multi-agent artifact approval workflows with centralized state.

use crate::proto::sw4rm::negotiation_room::{
    negotiation_room_service_server::{NegotiationRoomService, NegotiationRoomServiceServer},
    AggregatedScore, GetDecisionRequest, GetDecisionResponse, GetVotesRequest,
    GetVotesResponse, NegotiationDecision, NegotiationProposal, NegotiationVote,
    SubmitProposalRequest, SubmitProposalResponse, SubmitVoteRequest, SubmitVoteResponse,
    WaitForDecisionRequest, WaitForDecisionResponse,
};
use dashmap::DashMap;
use prost_types::Timestamp;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::broadcast;
use tonic::{Request, Response, Status};
use tracing::{debug, info, warn};

fn current_timestamp() -> Timestamp {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap();
    Timestamp {
        seconds: now.as_secs() as i64,
        nanos: now.subsec_nanos() as i32,
    }
}

/// gRPC server implementation for NegotiationRoomService.
///
/// Provides centralized artifact approval workflows for distributed agent deployments.
/// Thread-safe implementation using DashMap for concurrent access.
#[derive(Debug)]
pub struct NegotiationRoomServiceImpl {
    /// Proposals indexed by artifact_id
    proposals: Arc<DashMap<String, NegotiationProposal>>,
    /// Votes indexed by artifact_id
    votes: Arc<DashMap<String, Vec<NegotiationVote>>>,
    /// Decisions indexed by artifact_id
    decisions: Arc<DashMap<String, NegotiationDecision>>,
    /// Broadcast channels for decision notifications
    decision_senders: Arc<DashMap<String, broadcast::Sender<()>>>,
}

impl Default for NegotiationRoomServiceImpl {
    fn default() -> Self {
        Self::new()
    }
}

impl NegotiationRoomServiceImpl {
    /// Create a new NegotiationRoomServiceImpl with empty state.
    pub fn new() -> Self {
        info!("NegotiationRoomService initialized");
        Self {
            proposals: Arc::new(DashMap::new()),
            votes: Arc::new(DashMap::new()),
            decisions: Arc::new(DashMap::new()),
            decision_senders: Arc::new(DashMap::new()),
        }
    }

    /// Convert this service into a tonic service.
    pub fn into_service(self) -> NegotiationRoomServiceServer<Self> {
        NegotiationRoomServiceServer::new(self)
    }

    /// Store a decision for an artifact (for coordinator use).
    pub fn store_decision(&self, decision: NegotiationDecision) -> bool {
        let artifact_id = decision.artifact_id.clone();

        if !self.proposals.contains_key(&artifact_id) {
            return false;
        }

        if self.decisions.contains_key(&artifact_id) {
            return false;
        }

        let mut dec = decision;
        if dec.decided_at.is_none() {
            dec.decided_at = Some(current_timestamp());
        }

        self.decisions.insert(artifact_id.clone(), dec);

        // Notify waiting clients
        if let Some(sender) = self.decision_senders.get(&artifact_id) {
            let _ = sender.send(());
        }

        info!("Decision stored for artifact: {}", artifact_id);
        true
    }

    /// Compute aggregated statistics for votes on an artifact.
    pub fn aggregate_votes(&self, artifact_id: &str) -> Option<AggregatedScore> {
        let votes = self.votes.get(artifact_id)?;
        if votes.is_empty() {
            return None;
        }

        let scores: Vec<f64> = votes.iter().map(|v| v.score).collect();
        let confidences: Vec<f64> = votes.iter().map(|v| v.confidence).collect();

        let mean = scores.iter().sum::<f64>() / scores.len() as f64;
        let min_score = scores.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_score = scores.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

        let variance = scores.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / scores.len() as f64;
        let std_dev = variance.sqrt();

        let total_confidence: f64 = confidences.iter().sum();
        let weighted_mean = if total_confidence > 0.0 {
            scores
                .iter()
                .zip(confidences.iter())
                .map(|(s, c)| s * c)
                .sum::<f64>()
                / total_confidence
        } else {
            mean
        };

        Some(AggregatedScore {
            mean,
            min_score,
            max_score,
            std_dev,
            weighted_mean,
            vote_count: votes.len() as i32,
        })
    }

    /// Get a proposal by artifact_id.
    pub fn get_proposal(&self, artifact_id: &str) -> Option<NegotiationProposal> {
        self.proposals.get(artifact_id).map(|v| v.clone())
    }

    /// List all proposals, optionally filtered by room.
    pub fn list_proposals(&self, negotiation_room_id: Option<&str>) -> Vec<NegotiationProposal> {
        self.proposals
            .iter()
            .filter(|entry| {
                negotiation_room_id
                    .map(|id| entry.negotiation_room_id == id)
                    .unwrap_or(true)
            })
            .map(|entry| entry.clone())
            .collect()
    }

    /// Clear all negotiation room data (for testing).
    pub fn clear_all(&self) {
        self.proposals.clear();
        self.votes.clear();
        self.decisions.clear();
        // Notify all waiting clients
        for entry in self.decision_senders.iter() {
            let _ = entry.send(());
        }
        self.decision_senders.clear();
        info!("NegotiationRoomService state cleared");
    }
}

#[tonic::async_trait]
impl NegotiationRoomService for NegotiationRoomServiceImpl {
    /// Submit an artifact proposal for multi-agent review.
    async fn submit_proposal(
        &self,
        request: Request<SubmitProposalRequest>,
    ) -> Result<Response<SubmitProposalResponse>, Status> {
        let req = request.into_inner();
        let proposal = match req.proposal {
            Some(p) => p,
            None => {
                return Err(Status::invalid_argument("proposal is required"));
            }
        };

        let artifact_id = proposal.artifact_id.clone();
        let negotiation_room_id = proposal.negotiation_room_id.clone();

        // Validate required fields
        if artifact_id.is_empty() {
            return Err(Status::invalid_argument("artifact_id is required"));
        }
        if proposal.producer_id.is_empty() {
            return Err(Status::invalid_argument("producer_id is required"));
        }

        // Check for duplicates
        if self.proposals.contains_key(&artifact_id) {
            return Err(Status::already_exists(format!(
                "Proposal with artifact_id '{}' already exists",
                artifact_id
            )));
        }

        // Set created_at if not provided
        let mut prop = proposal;
        if prop.created_at.is_none() {
            prop.created_at = Some(current_timestamp());
        }

        self.proposals.insert(artifact_id.clone(), prop.clone());
        self.votes.insert(artifact_id.clone(), Vec::new());

        // Create broadcast channel for this artifact
        let (tx, _) = broadcast::channel(1);
        self.decision_senders.insert(artifact_id.clone(), tx);

        info!(
            "Proposal submitted: {} by {} in room {}",
            artifact_id, prop.producer_id, negotiation_room_id
        );

        Ok(Response::new(SubmitProposalResponse {
            artifact_id,
            negotiation_room_id,
        }))
    }

    /// Submit a critic's vote for an artifact.
    async fn submit_vote(
        &self,
        request: Request<SubmitVoteRequest>,
    ) -> Result<Response<SubmitVoteResponse>, Status> {
        let req = request.into_inner();
        let vote = match req.vote {
            Some(v) => v,
            None => {
                return Err(Status::invalid_argument("vote is required"));
            }
        };

        let artifact_id = vote.artifact_id.clone();
        let critic_id = vote.critic_id.clone();

        // Validate required fields
        if artifact_id.is_empty() {
            return Err(Status::invalid_argument("artifact_id is required"));
        }
        if critic_id.is_empty() {
            return Err(Status::invalid_argument("critic_id is required"));
        }

        // Validate score range [0, 10]
        if vote.score < 0.0 || vote.score > 10.0 {
            return Err(Status::invalid_argument(format!(
                "score must be in range [0, 10], got {}",
                vote.score
            )));
        }

        // Validate confidence range [0, 1]
        if vote.confidence < 0.0 || vote.confidence > 1.0 {
            return Err(Status::invalid_argument(format!(
                "confidence must be in range [0, 1], got {}",
                vote.confidence
            )));
        }

        // Check proposal exists
        if !self.proposals.contains_key(&artifact_id) {
            return Err(Status::not_found(format!(
                "No proposal found for artifact_id '{}'",
                artifact_id
            )));
        }

        // Check for duplicate votes
        if let Some(existing) = self.votes.get(&artifact_id) {
            for v in existing.iter() {
                if v.critic_id == critic_id {
                    return Err(Status::already_exists(format!(
                        "Critic '{}' has already voted for artifact '{}'",
                        critic_id, artifact_id
                    )));
                }
            }
        }

        // Set voted_at if not provided
        let mut v = vote;
        if v.voted_at.is_none() {
            v.voted_at = Some(current_timestamp());
        }

        // Add vote
        self.votes
            .entry(artifact_id.clone())
            .or_insert_with(Vec::new)
            .push(v.clone());

        info!(
            "Vote submitted: {} for {} (score={}, confidence={})",
            critic_id, artifact_id, v.score, v.confidence
        );

        Ok(Response::new(SubmitVoteResponse {
            artifact_id,
            critic_id,
        }))
    }

    /// Retrieve all votes for a specific artifact.
    async fn get_votes(
        &self,
        request: Request<GetVotesRequest>,
    ) -> Result<Response<GetVotesResponse>, Status> {
        let artifact_id = request.into_inner().artifact_id;

        // Check proposal exists
        if !self.proposals.contains_key(&artifact_id) {
            return Err(Status::not_found(format!(
                "No proposal found for artifact_id '{}'",
                artifact_id
            )));
        }

        let votes = self
            .votes
            .get(&artifact_id)
            .map(|v| v.clone())
            .unwrap_or_default();

        debug!("GetVotes: {} has {} votes", artifact_id, votes.len());

        Ok(Response::new(GetVotesResponse {
            votes: votes.clone(),
            vote_count: votes.len() as i32,
        }))
    }

    /// Retrieve the decision for an artifact (non-blocking).
    async fn get_decision(
        &self,
        request: Request<GetDecisionRequest>,
    ) -> Result<Response<GetDecisionResponse>, Status> {
        let artifact_id = request.into_inner().artifact_id;

        // Check proposal exists
        if !self.proposals.contains_key(&artifact_id) {
            return Err(Status::not_found(format!(
                "No proposal found for artifact_id '{}'",
                artifact_id
            )));
        }

        let decision = self.decisions.get(&artifact_id).map(|v| v.clone());

        if let Some(ref d) = decision {
            debug!("GetDecision: {} -> {:?}", artifact_id, d.outcome);
        } else {
            debug!("GetDecision: {} -> no decision yet", artifact_id);
        }

        Ok(Response::new(GetDecisionResponse { decision }))
    }

    /// Wait for a decision to be made on an artifact (blocking).
    async fn wait_for_decision(
        &self,
        request: Request<WaitForDecisionRequest>,
    ) -> Result<Response<WaitForDecisionResponse>, Status> {
        let req = request.into_inner();
        let artifact_id = req.artifact_id;
        let timeout_seconds = if req.timeout_seconds > 0 {
            req.timeout_seconds
        } else {
            30
        };

        // Check proposal exists
        if !self.proposals.contains_key(&artifact_id) {
            return Err(Status::not_found(format!(
                "No proposal found for artifact_id '{}'",
                artifact_id
            )));
        }

        // Check if decision already exists
        if let Some(decision) = self.decisions.get(&artifact_id) {
            return Ok(Response::new(WaitForDecisionResponse {
                decision: Some(decision.clone()),
            }));
        }

        // Get or create broadcast receiver
        let mut rx = {
            let sender = self
                .decision_senders
                .entry(artifact_id.clone())
                .or_insert_with(|| {
                    let (tx, _) = broadcast::channel(1);
                    tx
                })
                .subscribe();
            sender
        };

        // Wait for notification or timeout
        let timeout = Duration::from_secs(timeout_seconds as u64);
        match tokio::time::timeout(timeout, rx.recv()).await {
            Ok(_) => {
                // Check for decision
                if let Some(decision) = self.decisions.get(&artifact_id) {
                    return Ok(Response::new(WaitForDecisionResponse {
                        decision: Some(decision.clone()),
                    }));
                }
            }
            Err(_) => {
                // Timeout
            }
        }

        Err(Status::deadline_exceeded(format!(
            "No decision made for artifact '{}' within {} seconds",
            artifact_id, timeout_seconds
        )))
    }
}
