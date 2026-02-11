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

//! Negotiation Room client for SW4RM.
//!
//! This module provides the `NegotiationRoomClient` for managing multi-agent
//! artifact approval workflows using the Negotiation Room pattern. The client
//! supports:
//! - Submitting artifacts for review
//! - Collecting votes from critics
//! - Retrieving and waiting for decisions
//! - Coordinating the review process
//!
//! Based on SPEC_REQUESTS.md section 6.1.
//!
//! # Concurrency Fix (v0.5.0)
//!
//! The client now uses a pluggable storage backend (`NegotiationRoomStore`) instead
//! of instance-local storage. This enables multiple client instances to share
//! state, which is essential for multi-agent deployments where producer, critic,
//! and coordinator agents run in different threads or processes.
//!
//! ## Usage patterns
//!
//! ### 1. Single-process with shared store (recommended)
//! ```rust
//! use sw4rm_sdk::clients::negotiation_room_store::InMemoryNegotiationRoomStore;
//! use sw4rm_sdk::clients::NegotiationRoomClient;
//! use std::sync::Arc;
//!
//! let store = Arc::new(InMemoryNegotiationRoomStore::new());
//! let producer = NegotiationRoomClient::with_store(store.clone());
//! let critic = NegotiationRoomClient::with_store(store.clone());
//! let coordinator = NegotiationRoomClient::with_store(store.clone());
//! ```
//!
//! ### 2. File-based persistence (multi-process, requires colony)
//! ```rust,ignore
//! use colony::stores::rust::JsonFileNegotiationRoomStore;
//! use sw4rm_sdk::clients::NegotiationRoomClient;
//! use std::sync::Arc;
//!
//! let store = Arc::new(JsonFileNegotiationRoomStore::new("/path/to/storage").unwrap());
//! let client = NegotiationRoomClient::with_store(store);
//! ```
//!
//! ### 3. Backward-compatible (creates isolated store)
//! ```rust
//! use sw4rm_sdk::clients::NegotiationRoomClient;
//!
//! // Note: Each call creates a NEW isolated store - use with_store for sharing
//! let client = NegotiationRoomClient::new();
//! ```

use crate::clients::negotiation_room_store::{InMemoryNegotiationRoomStore, NegotiationRoomStore};
use crate::{Error, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;

/// Type of artifact being negotiated.
///
/// Maps to the artifact_type field in negotiation proposals to categorize
/// what stage of the workflow the artifact belongs to.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum ArtifactType {
    /// Unspecified artifact type
    Unspecified = 0,
    /// Requirements documentation
    Requirements = 1,
    /// Planning artifacts
    Plan = 2,
    /// Code artifacts
    Code = 3,
    /// Deployment artifacts
    Deployment = 4,
}

impl Default for ArtifactType {
    fn default() -> Self {
        Self::Unspecified
    }
}

/// Outcome of a negotiation decision.
///
/// Represents the final decision made by the coordinator after aggregating
/// critic votes and applying policy.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum DecisionOutcome {
    /// Unspecified outcome
    Unspecified = 0,
    /// Artifact approved
    Approved = 1,
    /// Revision requested
    RevisionRequested = 2,
    /// Escalated to human-in-the-loop
    EscalatedToHitl = 3,
}

impl Default for DecisionOutcome {
    fn default() -> Self {
        Self::Unspecified
    }
}

/// A proposal for artifact evaluation in a negotiation room.
///
/// Submitted by a producer agent to request multi-agent review of an artifact.
/// The proposal specifies which critics should evaluate the artifact and
/// includes the artifact content for review.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NegotiationProposal {
    /// Category of artifact (requirements, plan, code, deployment)
    pub artifact_type: ArtifactType,
    /// Unique identifier for this artifact
    pub artifact_id: String,
    /// Agent ID of the producer submitting the artifact
    pub producer_id: String,
    /// Binary artifact content (e.g., serialized JSON, code files)
    pub artifact: Vec<u8>,
    /// MIME type or content type identifier
    pub artifact_content_type: String,
    /// List of critic agent IDs requested for evaluation
    pub requested_critics: Vec<String>,
    /// Identifier for the negotiation room session
    pub negotiation_room_id: String,
    /// Timestamp when proposal was created
    pub created_at: DateTime<Utc>,
}

impl NegotiationProposal {
    /// Create a new negotiation proposal.
    ///
    /// # Arguments
    ///
    /// * `artifact_type` - Category of the artifact
    /// * `artifact_id` - Unique identifier for the artifact
    /// * `producer_id` - Agent ID of the producer
    /// * `artifact` - Binary artifact content
    /// * `artifact_content_type` - MIME type or content type
    /// * `requested_critics` - List of critic agent IDs
    /// * `negotiation_room_id` - Negotiation room session ID
    pub fn new(
        artifact_type: ArtifactType,
        artifact_id: String,
        producer_id: String,
        artifact: Vec<u8>,
        artifact_content_type: String,
        requested_critics: Vec<String>,
        negotiation_room_id: String,
    ) -> Self {
        Self {
            artifact_type,
            artifact_id,
            producer_id,
            artifact,
            artifact_content_type,
            requested_critics,
            negotiation_room_id,
            created_at: Utc::now(),
        }
    }
}

/// A critic's evaluation of an artifact.
///
/// Represents a single critic's assessment including numerical scoring,
/// qualitative feedback, and confidence level based on POMDP uncertainty.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NegotiationVote {
    /// Identifier of the artifact being evaluated
    pub artifact_id: String,
    /// Agent ID of the critic providing this vote
    pub critic_id: String,
    /// Numerical score from 0-10 (10 = excellent)
    pub score: f64,
    /// Confidence level from 0-1 (based on POMDP research)
    pub confidence: f64,
    /// Boolean indicating if artifact meets minimum criteria
    pub passed: bool,
    /// List of identified strengths in the artifact
    pub strengths: Vec<String>,
    /// List of identified weaknesses or concerns
    pub weaknesses: Vec<String>,
    /// List of suggestions for improvement
    pub recommendations: Vec<String>,
    /// Identifier for the negotiation room session
    pub negotiation_room_id: String,
    /// Timestamp when vote was cast
    pub voted_at: DateTime<Utc>,
}

impl NegotiationVote {
    /// Create a new negotiation vote.
    ///
    /// # Arguments
    ///
    /// * `artifact_id` - Identifier of the artifact being evaluated
    /// * `critic_id` - Agent ID of the critic
    /// * `score` - Numerical score from 0-10
    /// * `confidence` - Confidence level from 0-1
    /// * `passed` - Whether artifact meets minimum criteria
    /// * `strengths` - List of identified strengths
    /// * `weaknesses` - List of identified weaknesses
    /// * `recommendations` - List of suggestions for improvement
    /// * `negotiation_room_id` - Negotiation room session ID
    ///
    /// # Errors
    ///
    /// Returns an error if score is not in [0, 10] or confidence is not in [0, 1].
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        artifact_id: String,
        critic_id: String,
        score: f64,
        confidence: f64,
        passed: bool,
        strengths: Vec<String>,
        weaknesses: Vec<String>,
        recommendations: Vec<String>,
        negotiation_room_id: String,
    ) -> Result<Self> {
        if !(0.0..=10.0).contains(&score) {
            return Err(Error::Config(format!(
                "score must be in range [0, 10], got {}",
                score
            )));
        }
        if !(0.0..=1.0).contains(&confidence) {
            return Err(Error::Config(format!(
                "confidence must be in range [0, 1], got {}",
                confidence
            )));
        }
        Ok(Self {
            artifact_id,
            critic_id,
            score,
            confidence,
            passed,
            strengths,
            weaknesses,
            recommendations,
            negotiation_room_id,
            voted_at: Utc::now(),
        })
    }
}

/// Statistical aggregation of multiple critic votes.
///
/// Provides multiple views of the voting results including basic statistics
/// and confidence-weighted metrics for decision making.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AggregatedScore {
    /// Arithmetic mean of all scores
    pub mean: f64,
    /// Minimum score from any critic
    pub min_score: f64,
    /// Maximum score from any critic
    pub max_score: f64,
    /// Standard deviation of scores (measures consensus)
    pub std_dev: f64,
    /// Confidence-weighted mean (higher confidence votes weighted more)
    pub weighted_mean: f64,
    /// Number of votes included in aggregation
    pub vote_count: usize,
}

/// Final decision on an artifact after critic evaluation.
///
/// Represents the coordinator's decision after aggregating all critic votes
/// and applying policy thresholds. Includes full audit trail of votes and
/// reasoning.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NegotiationDecision {
    /// Identifier of the artifact that was evaluated
    pub artifact_id: String,
    /// Final decision (approved, revision requested, escalated to HITL)
    pub outcome: DecisionOutcome,
    /// Complete list of all critic votes considered
    pub votes: Vec<NegotiationVote>,
    /// Statistical summary of the votes
    pub aggregated_score: AggregatedScore,
    /// Version identifier of the policy used for decision
    pub policy_version: String,
    /// Human-readable explanation of the decision
    pub reason: String,
    /// Identifier for the negotiation room session
    pub negotiation_room_id: String,
    /// Timestamp when decision was made
    pub decided_at: DateTime<Utc>,
}

impl NegotiationDecision {
    /// Create a new negotiation decision.
    ///
    /// # Arguments
    ///
    /// * `artifact_id` - Identifier of the artifact
    /// * `outcome` - Final decision outcome
    /// * `votes` - List of all critic votes
    /// * `aggregated_score` - Statistical summary
    /// * `policy_version` - Version of policy used
    /// * `reason` - Explanation of the decision
    /// * `negotiation_room_id` - Negotiation room session ID
    pub fn new(
        artifact_id: String,
        outcome: DecisionOutcome,
        votes: Vec<NegotiationVote>,
        aggregated_score: AggregatedScore,
        policy_version: String,
        reason: String,
        negotiation_room_id: String,
    ) -> Self {
        Self {
            artifact_id,
            outcome,
            votes,
            aggregated_score,
            policy_version,
            reason,
            negotiation_room_id,
            decided_at: Utc::now(),
        }
    }
}

/// Client for interacting with negotiation rooms.
///
/// Manages the lifecycle of artifact proposals through the multi-agent
/// review process. Producers submit proposals, critics submit votes,
/// and coordinators retrieve votes to make decisions.
///
/// This client uses a pluggable storage backend, enabling state sharing
/// across multiple client instances. Use `with_store` to share a store
/// across multiple clients.
///
/// # Example
///
/// ```rust
/// use sw4rm_sdk::clients::negotiation_room::{NegotiationRoomClient, NegotiationProposal, ArtifactType};
/// use sw4rm_sdk::clients::negotiation_room_store::InMemoryNegotiationRoomStore;
/// use std::sync::Arc;
///
/// // Create shared store for multiple clients
/// let store = Arc::new(InMemoryNegotiationRoomStore::new());
///
/// let producer = NegotiationRoomClient::with_store(store.clone());
/// let critic = NegotiationRoomClient::with_store(store.clone());
///
/// let proposal = NegotiationProposal::new(
///     ArtifactType::Code,
///     "code-123".to_string(),
///     "agent-producer".to_string(),
///     b"def hello(): pass".to_vec(),
///     "text/x-python".to_string(),
///     vec!["critic-1".to_string(), "critic-2".to_string()],
///     "room-1".to_string(),
/// );
///
/// // Submitted by producer, visible to critic
/// let artifact_id = producer.submit_proposal(proposal).unwrap();
/// let retrieved = critic.get_proposal(&artifact_id).unwrap();
/// ```
#[derive(Clone)]
pub struct NegotiationRoomClient {
    store: Arc<dyn NegotiationRoomStore>,
}

impl Default for NegotiationRoomClient {
    fn default() -> Self {
        Self::new()
    }
}

impl NegotiationRoomClient {
    /// Create a new negotiation room client with a fresh in-memory storage.
    ///
    /// **Note**: This creates an isolated store. For shared state across
    /// multiple clients, use `with_store` instead.
    pub fn new() -> Self {
        Self {
            store: Arc::new(InMemoryNegotiationRoomStore::new()),
        }
    }

    /// Create a new negotiation room client with a shared storage backend.
    ///
    /// This is the recommended way to create clients when you need multiple
    /// instances to share state (e.g., producer, critic, and coordinator
    /// agents in different threads).
    ///
    /// # Arguments
    ///
    /// * `store` - Shared storage backend (wrapped in Arc)
    ///
    /// # Example
    ///
    /// ```rust
    /// use sw4rm_sdk::clients::negotiation_room_store::InMemoryNegotiationRoomStore;
    /// use sw4rm_sdk::clients::NegotiationRoomClient;
    /// use std::sync::Arc;
    ///
    /// let store = Arc::new(InMemoryNegotiationRoomStore::new());
    /// let client = NegotiationRoomClient::with_store(store);
    /// ```
    pub fn with_store(store: Arc<dyn NegotiationRoomStore>) -> Self {
        Self { store }
    }

    /// Submit an artifact proposal for multi-agent review.
    ///
    /// Stores the proposal and initializes empty vote tracking for the artifact.
    /// This method is typically called by producer agents.
    ///
    /// # Arguments
    ///
    /// * `proposal` - The negotiation proposal containing artifact details
    ///
    /// # Returns
    ///
    /// The artifact_id of the submitted proposal.
    ///
    /// # Errors
    ///
    /// Returns an error if a proposal with the same artifact_id already exists.
    pub fn submit_proposal(&self, proposal: NegotiationProposal) -> Result<String> {
        let artifact_id = proposal.artifact_id.clone();
        self.store.save_proposal(proposal)?;
        Ok(artifact_id)
    }

    /// Submit a critic's vote for an artifact.
    ///
    /// Adds the vote to the collection for the specified artifact.
    /// This method is typically called by critic agents after evaluating
    /// an artifact.
    ///
    /// # Arguments
    ///
    /// * `vote` - The negotiation vote containing the critic's evaluation
    ///
    /// # Errors
    ///
    /// Returns an error if no proposal exists for the vote's artifact_id,
    /// or if the critic has already voted for this artifact.
    pub fn submit_vote(&self, vote: NegotiationVote) -> Result<()> {
        let artifact_id = &vote.artifact_id;

        if !self.store.has_proposal(artifact_id)? {
            return Err(Error::Config(format!(
                "No proposal found for artifact_id '{}'",
                artifact_id
            )));
        }

        self.store.add_vote(vote)
    }

    /// Retrieve all votes for a specific artifact.
    ///
    /// Returns all critic votes that have been submitted for the artifact.
    /// This method is typically called by coordinator agents to aggregate
    /// votes and make decisions.
    ///
    /// # Arguments
    ///
    /// * `artifact_id` - The identifier of the artifact
    ///
    /// # Returns
    ///
    /// Vector of all votes for the artifact (empty vector if no votes yet).
    ///
    /// # Errors
    ///
    /// Returns an error if no proposal exists for the artifact_id.
    pub fn get_votes(&self, artifact_id: &str) -> Result<Vec<NegotiationVote>> {
        if !self.store.has_proposal(artifact_id)? {
            return Err(Error::Config(format!(
                "No proposal found for artifact_id '{}'",
                artifact_id
            )));
        }

        self.store.get_votes(artifact_id)
    }

    /// Retrieve the decision for a specific artifact if available.
    ///
    /// Returns the final decision if one has been made, or None if the
    /// artifact is still under review.
    ///
    /// # Arguments
    ///
    /// * `artifact_id` - The identifier of the artifact
    ///
    /// # Returns
    ///
    /// The negotiation decision if available, None otherwise.
    ///
    /// # Errors
    ///
    /// Returns an error if no proposal exists for the artifact_id.
    pub fn get_decision(&self, artifact_id: &str) -> Result<Option<NegotiationDecision>> {
        if !self.store.has_proposal(artifact_id)? {
            return Err(Error::Config(format!(
                "No proposal found for artifact_id '{}'",
                artifact_id
            )));
        }

        self.store.get_decision(artifact_id)
    }

    /// Store a decision for an artifact.
    ///
    /// This is an internal method used by coordinators to record the
    /// final decision after evaluating votes. Once a decision is stored,
    /// it becomes available via `get_decision()` and `wait_for_decision()`.
    ///
    /// # Arguments
    ///
    /// * `decision` - The negotiation decision to store
    ///
    /// # Errors
    ///
    /// Returns an error if no proposal exists for the decision's artifact_id,
    /// or if a decision already exists for this artifact.
    pub fn store_decision(&self, decision: NegotiationDecision) -> Result<()> {
        let artifact_id = &decision.artifact_id;

        if !self.store.has_proposal(artifact_id)? {
            return Err(Error::Config(format!(
                "No proposal found for artifact_id '{}'",
                artifact_id
            )));
        }

        self.store.save_decision(decision)
    }

    /// Wait for a decision to be made on an artifact.
    ///
    /// Polls for a decision until one is available or the timeout is reached.
    /// This method is useful for producer agents waiting for the outcome
    /// of their artifact review.
    ///
    /// # Arguments
    ///
    /// * `artifact_id` - The identifier of the artifact
    /// * `timeout` - Maximum time to wait
    ///
    /// # Returns
    ///
    /// The negotiation decision once available.
    ///
    /// # Errors
    ///
    /// Returns an error if no proposal exists for the artifact_id,
    /// or if no decision is made within the timeout period.
    pub fn wait_for_decision(
        &self,
        artifact_id: &str,
        timeout: Duration,
    ) -> Result<NegotiationDecision> {
        // Validate proposal exists first
        if !self.store.has_proposal(artifact_id)? {
            return Err(Error::Config(format!(
                "No proposal found for artifact_id '{}'",
                artifact_id
            )));
        }

        let start = std::time::Instant::now();
        let poll_interval = Duration::from_millis(100);

        while start.elapsed() < timeout {
            if let Some(decision) = self.store.get_decision(artifact_id)? {
                return Ok(decision);
            }
            std::thread::sleep(poll_interval);
        }

        Err(Error::Timeout(format!(
            "No decision made for artifact '{}' within {:?}",
            artifact_id, timeout
        )))
    }

    /// Retrieve the original proposal for an artifact.
    ///
    /// Useful for critics that need to review the original artifact
    /// before submitting a vote.
    ///
    /// # Arguments
    ///
    /// * `artifact_id` - The identifier of the artifact
    ///
    /// # Returns
    ///
    /// The negotiation proposal if it exists, None otherwise.
    pub fn get_proposal(&self, artifact_id: &str) -> Result<Option<NegotiationProposal>> {
        self.store.get_proposal(artifact_id)
    }

    /// List all proposals, optionally filtered by negotiation room.
    ///
    /// # Arguments
    ///
    /// * `negotiation_room_id` - If provided, only return proposals for this room
    ///
    /// # Returns
    ///
    /// Vector of proposals matching the filter criteria.
    pub fn list_proposals(
        &self,
        negotiation_room_id: Option<&str>,
    ) -> Result<Vec<NegotiationProposal>> {
        self.store.list_proposals(negotiation_room_id)
    }
}

impl std::fmt::Debug for NegotiationRoomClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NegotiationRoomClient").finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_submit_proposal() {
        let client = NegotiationRoomClient::new();
        let proposal = NegotiationProposal::new(
            ArtifactType::Code,
            "test-artifact".to_string(),
            "producer-1".to_string(),
            b"test content".to_vec(),
            "text/plain".to_string(),
            vec!["critic-1".to_string()],
            "room-1".to_string(),
        );

        let result = client.submit_proposal(proposal);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "test-artifact");
    }

    #[test]
    fn test_duplicate_proposal_fails() {
        let client = NegotiationRoomClient::new();
        let proposal = NegotiationProposal::new(
            ArtifactType::Code,
            "test-artifact".to_string(),
            "producer-1".to_string(),
            b"test content".to_vec(),
            "text/plain".to_string(),
            vec!["critic-1".to_string()],
            "room-1".to_string(),
        );

        client.submit_proposal(proposal.clone()).unwrap();
        let result = client.submit_proposal(proposal);
        assert!(result.is_err());
    }

    #[test]
    fn test_submit_vote() {
        let client = NegotiationRoomClient::new();
        let proposal = NegotiationProposal::new(
            ArtifactType::Code,
            "test-artifact".to_string(),
            "producer-1".to_string(),
            b"test content".to_vec(),
            "text/plain".to_string(),
            vec!["critic-1".to_string()],
            "room-1".to_string(),
        );

        client.submit_proposal(proposal).unwrap();

        let vote = NegotiationVote::new(
            "test-artifact".to_string(),
            "critic-1".to_string(),
            8.5,
            0.9,
            true,
            vec!["Good structure".to_string()],
            vec!["Needs tests".to_string()],
            vec!["Add unit tests".to_string()],
            "room-1".to_string(),
        )
        .unwrap();

        let result = client.submit_vote(vote);
        assert!(result.is_ok());
    }

    #[test]
    fn test_vote_validation() {
        // Test invalid score
        let result = NegotiationVote::new(
            "test-artifact".to_string(),
            "critic-1".to_string(),
            15.0, // Invalid: > 10
            0.9,
            true,
            vec![],
            vec![],
            vec![],
            "room-1".to_string(),
        );
        assert!(result.is_err());

        // Test invalid confidence
        let result = NegotiationVote::new(
            "test-artifact".to_string(),
            "critic-1".to_string(),
            8.0,
            1.5, // Invalid: > 1
            true,
            vec![],
            vec![],
            vec![],
            "room-1".to_string(),
        );
        assert!(result.is_err());
    }

    #[test]
    fn test_duplicate_vote_fails() {
        let client = NegotiationRoomClient::new();
        let proposal = NegotiationProposal::new(
            ArtifactType::Code,
            "test-artifact".to_string(),
            "producer-1".to_string(),
            b"test content".to_vec(),
            "text/plain".to_string(),
            vec!["critic-1".to_string()],
            "room-1".to_string(),
        );

        client.submit_proposal(proposal).unwrap();

        let vote1 = NegotiationVote::new(
            "test-artifact".to_string(),
            "critic-1".to_string(),
            8.0,
            0.9,
            true,
            vec![],
            vec![],
            vec![],
            "room-1".to_string(),
        )
        .unwrap();

        let vote2 = NegotiationVote::new(
            "test-artifact".to_string(),
            "critic-1".to_string(),
            7.0,
            0.8,
            true,
            vec![],
            vec![],
            vec![],
            "room-1".to_string(),
        )
        .unwrap();

        client.submit_vote(vote1).unwrap();
        let result = client.submit_vote(vote2);
        assert!(result.is_err());
    }

    #[test]
    fn test_get_votes() {
        let client = NegotiationRoomClient::new();
        let proposal = NegotiationProposal::new(
            ArtifactType::Code,
            "test-artifact".to_string(),
            "producer-1".to_string(),
            b"test content".to_vec(),
            "text/plain".to_string(),
            vec!["critic-1".to_string(), "critic-2".to_string()],
            "room-1".to_string(),
        );

        client.submit_proposal(proposal).unwrap();

        let vote1 = NegotiationVote::new(
            "test-artifact".to_string(),
            "critic-1".to_string(),
            8.0,
            0.9,
            true,
            vec![],
            vec![],
            vec![],
            "room-1".to_string(),
        )
        .unwrap();

        let vote2 = NegotiationVote::new(
            "test-artifact".to_string(),
            "critic-2".to_string(),
            7.0,
            0.8,
            true,
            vec![],
            vec![],
            vec![],
            "room-1".to_string(),
        )
        .unwrap();

        client.submit_vote(vote1).unwrap();
        client.submit_vote(vote2).unwrap();

        let votes = client.get_votes("test-artifact").unwrap();
        assert_eq!(votes.len(), 2);
    }

    #[test]
    fn test_store_and_get_decision() {
        let client = NegotiationRoomClient::new();
        let proposal = NegotiationProposal::new(
            ArtifactType::Code,
            "test-artifact".to_string(),
            "producer-1".to_string(),
            b"test content".to_vec(),
            "text/plain".to_string(),
            vec!["critic-1".to_string()],
            "room-1".to_string(),
        );

        client.submit_proposal(proposal).unwrap();

        let decision = NegotiationDecision::new(
            "test-artifact".to_string(),
            DecisionOutcome::Approved,
            vec![],
            AggregatedScore {
                mean: 8.0,
                min_score: 8.0,
                max_score: 8.0,
                std_dev: 0.0,
                weighted_mean: 8.0,
                vote_count: 1,
            },
            "1.0".to_string(),
            "Approved based on score threshold".to_string(),
            "room-1".to_string(),
        );

        client.store_decision(decision).unwrap();

        let retrieved = client.get_decision("test-artifact").unwrap();
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().outcome, DecisionOutcome::Approved);
    }

    #[test]
    fn test_shared_store_across_clients() {
        let store = Arc::new(InMemoryNegotiationRoomStore::new());

        let producer = NegotiationRoomClient::with_store(store.clone());
        let critic = NegotiationRoomClient::with_store(store.clone());

        // Producer submits proposal
        let proposal = NegotiationProposal::new(
            ArtifactType::Code,
            "shared-artifact".to_string(),
            "producer-1".to_string(),
            b"test content".to_vec(),
            "text/plain".to_string(),
            vec!["critic-1".to_string()],
            "room-1".to_string(),
        );

        producer.submit_proposal(proposal).unwrap();

        // Critic can see it
        let retrieved = critic.get_proposal("shared-artifact").unwrap();
        assert!(retrieved.is_some());

        // Critic submits vote
        let vote = NegotiationVote::new(
            "shared-artifact".to_string(),
            "critic-1".to_string(),
            8.0,
            0.9,
            true,
            vec![],
            vec![],
            vec![],
            "room-1".to_string(),
        )
        .unwrap();

        critic.submit_vote(vote).unwrap();

        // Producer can see the vote
        let votes = producer.get_votes("shared-artifact").unwrap();
        assert_eq!(votes.len(), 1);
    }
}
