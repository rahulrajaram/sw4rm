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

//! Negotiation Room storage backend abstraction.
//!
//! This module provides a pluggable storage layer for `NegotiationRoomClient`,
//! enabling shared state across multiple client instances.
//!
//! The key insight is that `NegotiationRoomClient` previously used instance-local
//! storage (each `new()` created fresh storage), which broke multi-instance
//! deployments. By extracting storage into a separate abstraction that can be
//! shared via `Arc`, we enable:
//!
//! 1. Multiple client instances sharing the same storage
//! 2. Producer/Critic/Coordinator agents in different threads sharing state
//! 3. Future gRPC integration where the server becomes the source of truth
//!
//! For persistent storage backends (JSON file, Redis, PostgreSQL), see the
//! `colony/stores` module which provides optional persistence implementations.
//!
//! Based on the `PolicyStore` pattern established in `policy_store.rs`.

use crate::clients::negotiation_room::{
    NegotiationDecision, NegotiationProposal, NegotiationVote,
};
use crate::{Error, Result};
use std::collections::HashMap;
use std::sync::{Arc, RwLock};

/// Trait defining the interface for negotiation room storage backends.
///
/// All storage implementations must support these operations for proposals,
/// votes, and decisions. Thread-safety is guaranteed by implementations.
///
/// This follows the same pattern as `PolicyStore` from `policy_store.rs`,
/// enabling pluggable backends ranging from in-memory to file-based to gRPC-based.
pub trait NegotiationRoomStore: Send + Sync {
    /// Check if a proposal exists for the given artifact_id.
    fn has_proposal(&self, artifact_id: &str) -> Result<bool>;

    /// Retrieve a proposal by artifact_id.
    fn get_proposal(&self, artifact_id: &str) -> Result<Option<NegotiationProposal>>;

    /// Save a proposal to storage.
    ///
    /// # Errors
    ///
    /// Returns an error if a proposal with the same artifact_id already exists.
    fn save_proposal(&self, proposal: NegotiationProposal) -> Result<()>;

    /// List all proposals, optionally filtered by negotiation room.
    fn list_proposals(&self, negotiation_room_id: Option<&str>) -> Result<Vec<NegotiationProposal>>;

    /// Retrieve all votes for a specific artifact.
    fn get_votes(&self, artifact_id: &str) -> Result<Vec<NegotiationVote>>;

    /// Add a vote for an artifact.
    ///
    /// # Errors
    ///
    /// Returns an error if the critic has already voted for this artifact.
    fn add_vote(&self, vote: NegotiationVote) -> Result<()>;

    /// Retrieve the decision for an artifact.
    fn get_decision(&self, artifact_id: &str) -> Result<Option<NegotiationDecision>>;

    /// Save a decision for an artifact.
    ///
    /// # Errors
    ///
    /// Returns an error if a decision already exists for this artifact.
    fn save_decision(&self, decision: NegotiationDecision) -> Result<()>;
}

/// Internal storage structure for in-memory store.
struct InMemoryStorage {
    proposals: HashMap<String, NegotiationProposal>,
    votes: HashMap<String, Vec<NegotiationVote>>,
    decisions: HashMap<String, NegotiationDecision>,
}

impl InMemoryStorage {
    fn new() -> Self {
        Self {
            proposals: HashMap::new(),
            votes: HashMap::new(),
            decisions: HashMap::new(),
        }
    }
}

/// Thread-safe in-memory implementation of `NegotiationRoomStore`.
///
/// Stores proposals, votes, and decisions in memory with thread-safe access.
/// Data is lost when the process terminates. Suitable for testing and
/// single-process deployments.
///
/// Thread-safety: This implementation IS thread-safe. All operations are
/// protected by `RwLock`.
///
/// # Usage for shared state across multiple client instances
///
/// ```rust
/// use sw4rm_sdk::clients::negotiation_room_store::InMemoryNegotiationRoomStore;
/// use sw4rm_sdk::clients::NegotiationRoomClient;
/// use std::sync::Arc;
///
/// // Create a single shared store
/// let shared_store = Arc::new(InMemoryNegotiationRoomStore::new());
///
/// // Pass to multiple clients
/// let producer_client = NegotiationRoomClient::with_store(shared_store.clone());
/// let critic_client = NegotiationRoomClient::with_store(shared_store.clone());
/// let coordinator_client = NegotiationRoomClient::with_store(shared_store.clone());
///
/// // Now all clients share the same state
/// ```
#[derive(Clone)]
pub struct InMemoryNegotiationRoomStore {
    storage: Arc<RwLock<InMemoryStorage>>,
}

impl Default for InMemoryNegotiationRoomStore {
    fn default() -> Self {
        Self::new()
    }
}

impl InMemoryNegotiationRoomStore {
    /// Create a new in-memory store with thread-safe access.
    pub fn new() -> Self {
        Self {
            storage: Arc::new(RwLock::new(InMemoryStorage::new())),
        }
    }
}

impl NegotiationRoomStore for InMemoryNegotiationRoomStore {
    fn has_proposal(&self, artifact_id: &str) -> Result<bool> {
        let storage = self
            .storage
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        Ok(storage.proposals.contains_key(artifact_id))
    }

    fn get_proposal(&self, artifact_id: &str) -> Result<Option<NegotiationProposal>> {
        let storage = self
            .storage
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        Ok(storage.proposals.get(artifact_id).cloned())
    }

    fn save_proposal(&self, proposal: NegotiationProposal) -> Result<()> {
        let artifact_id = proposal.artifact_id.clone();

        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        if storage.proposals.contains_key(&artifact_id) {
            return Err(Error::Config(format!(
                "Proposal with artifact_id '{}' already exists",
                artifact_id
            )));
        }

        storage.proposals.insert(artifact_id.clone(), proposal);
        storage.votes.insert(artifact_id, Vec::new());

        Ok(())
    }

    fn list_proposals(&self, negotiation_room_id: Option<&str>) -> Result<Vec<NegotiationProposal>> {
        let storage = self
            .storage
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        let proposals: Vec<NegotiationProposal> = match negotiation_room_id {
            Some(room_id) => storage
                .proposals
                .values()
                .filter(|p| p.negotiation_room_id == room_id)
                .cloned()
                .collect(),
            None => storage.proposals.values().cloned().collect(),
        };

        Ok(proposals)
    }

    fn get_votes(&self, artifact_id: &str) -> Result<Vec<NegotiationVote>> {
        let storage = self
            .storage
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        Ok(storage.votes.get(artifact_id).cloned().unwrap_or_default())
    }

    fn add_vote(&self, vote: NegotiationVote) -> Result<()> {
        let artifact_id = vote.artifact_id.clone();
        let critic_id = vote.critic_id.clone();

        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        // Check if this critic has already voted
        if let Some(existing_votes) = storage.votes.get(&artifact_id) {
            for existing_vote in existing_votes {
                if existing_vote.critic_id == critic_id {
                    return Err(Error::Config(format!(
                        "Critic '{}' has already voted for artifact '{}'",
                        critic_id, artifact_id
                    )));
                }
            }
        }

        storage
            .votes
            .entry(artifact_id)
            .or_insert_with(Vec::new)
            .push(vote);

        Ok(())
    }

    fn get_decision(&self, artifact_id: &str) -> Result<Option<NegotiationDecision>> {
        let storage = self
            .storage
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        Ok(storage.decisions.get(artifact_id).cloned())
    }

    fn save_decision(&self, decision: NegotiationDecision) -> Result<()> {
        let artifact_id = decision.artifact_id.clone();

        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        if storage.decisions.contains_key(&artifact_id) {
            return Err(Error::Config(format!(
                "Decision already exists for artifact_id '{}'",
                artifact_id
            )));
        }

        storage.decisions.insert(artifact_id, decision);

        Ok(())
    }
}

impl std::fmt::Debug for InMemoryNegotiationRoomStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("InMemoryNegotiationRoomStore").finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::clients::negotiation_room::ArtifactType;

    fn create_test_proposal(artifact_id: &str) -> NegotiationProposal {
        NegotiationProposal::new(
            ArtifactType::Code,
            artifact_id.to_string(),
            "producer-1".to_string(),
            b"test content".to_vec(),
            "text/plain".to_string(),
            vec!["critic-1".to_string()],
            "room-1".to_string(),
        )
    }

    fn create_test_vote(artifact_id: &str, critic_id: &str) -> NegotiationVote {
        NegotiationVote::new(
            artifact_id.to_string(),
            critic_id.to_string(),
            8.0,
            0.9,
            true,
            vec!["Good".to_string()],
            vec![],
            vec![],
            "room-1".to_string(),
        )
        .unwrap()
    }

    #[test]
    fn test_in_memory_store_proposal_lifecycle() {
        let store = InMemoryNegotiationRoomStore::new();

        // No proposal initially
        assert!(!store.has_proposal("test-1").unwrap());
        assert!(store.get_proposal("test-1").unwrap().is_none());

        // Save proposal
        let proposal = create_test_proposal("test-1");
        store.save_proposal(proposal).unwrap();

        // Proposal now exists
        assert!(store.has_proposal("test-1").unwrap());
        assert!(store.get_proposal("test-1").unwrap().is_some());

        // Duplicate fails
        let proposal2 = create_test_proposal("test-1");
        assert!(store.save_proposal(proposal2).is_err());
    }

    #[test]
    fn test_in_memory_store_vote_lifecycle() {
        let store = InMemoryNegotiationRoomStore::new();

        // Save proposal first
        let proposal = create_test_proposal("test-1");
        store.save_proposal(proposal).unwrap();

        // No votes initially
        assert!(store.get_votes("test-1").unwrap().is_empty());

        // Add vote
        let vote = create_test_vote("test-1", "critic-1");
        store.add_vote(vote).unwrap();

        // Vote exists
        let votes = store.get_votes("test-1").unwrap();
        assert_eq!(votes.len(), 1);

        // Duplicate vote fails
        let vote2 = create_test_vote("test-1", "critic-1");
        assert!(store.add_vote(vote2).is_err());

        // Different critic can vote
        let vote3 = create_test_vote("test-1", "critic-2");
        store.add_vote(vote3).unwrap();
        assert_eq!(store.get_votes("test-1").unwrap().len(), 2);
    }

    #[test]
    fn test_in_memory_store_shared_state() {
        // Create one store and clone it (shares underlying Arc)
        let store1 = InMemoryNegotiationRoomStore::new();
        let store2 = store1.clone();

        // Add via store1
        let proposal = create_test_proposal("shared-1");
        store1.save_proposal(proposal).unwrap();

        // Visible via store2
        assert!(store2.has_proposal("shared-1").unwrap());

        // Add vote via store2
        let vote = create_test_vote("shared-1", "critic-1");
        store2.add_vote(vote).unwrap();

        // Visible via store1
        assert_eq!(store1.get_votes("shared-1").unwrap().len(), 1);
    }
}
