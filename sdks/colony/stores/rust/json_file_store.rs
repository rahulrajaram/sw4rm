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

//! JSON file-based storage backend for NegotiationRoomClient.
//!
//! This is a Colony module - an optional persistence backend that is not part
//! of the core SW4RM protocol. For production deployments requiring horizontal
//! scaling, consider the Redis or PostgreSQL backends instead.
//!
//! # Usage
//!
//! ```rust,ignore
//! use sw4rm_sdk::clients::NegotiationRoomClient;
//! use colony::stores::rust::JsonFileNegotiationRoomStore;
//! use std::sync::Arc;
//!
//! let store = Arc::new(JsonFileNegotiationRoomStore::new("/var/lib/sw4rm/negotiation")?);
//! let client = NegotiationRoomClient::with_store(store);
//! ```
//!
//! # Limitations
//!
//! - Not suitable for multi-node deployments (use Redis/PostgreSQL instead)
//! - No file locking for cross-process safety
//! - No crash recovery for partial writes

use sw4rm_sdk::clients::negotiation_room::{
    NegotiationDecision, NegotiationProposal, NegotiationVote,
};
use sw4rm_sdk::clients::negotiation_room_store::NegotiationRoomStore;
use sw4rm_sdk::{Error, Result};
use std::fs;
use std::path::{Path, PathBuf};

/// File-based implementation of `NegotiationRoomStore` using JSON.
///
/// Persists proposals, votes, and decisions to disk as JSON files. This enables
/// state sharing across multiple processes on the same machine, as well as
/// persistence across process restarts.
///
/// Storage format:
/// ```text
/// {storage_dir}/
///     proposals/
///         {artifact_id}.json
///     votes/
///         {artifact_id}.json  # Array of votes
///     decisions/
///         {artifact_id}.json
/// ```
///
/// Thread-safety: This implementation IS thread-safe within a single process.
/// For multi-process safety, uses atomic file operations.
pub struct JsonFileNegotiationRoomStore {
    proposals_dir: PathBuf,
    votes_dir: PathBuf,
    decisions_dir: PathBuf,
}

impl JsonFileNegotiationRoomStore {
    /// Create a new JSON file-based store.
    ///
    /// Creates the storage directory structure if it doesn't exist.
    ///
    /// # Arguments
    ///
    /// * `storage_dir` - Directory to store JSON files
    pub fn new<P: AsRef<Path>>(storage_dir: P) -> Result<Self> {
        let storage_dir = storage_dir.as_ref().to_path_buf();
        let proposals_dir = storage_dir.join("proposals");
        let votes_dir = storage_dir.join("votes");
        let decisions_dir = storage_dir.join("decisions");

        fs::create_dir_all(&proposals_dir).map_err(Error::Io)?;
        fs::create_dir_all(&votes_dir).map_err(Error::Io)?;
        fs::create_dir_all(&decisions_dir).map_err(Error::Io)?;

        Ok(Self {
            proposals_dir,
            votes_dir,
            decisions_dir,
        })
    }

    fn sanitize_id(artifact_id: &str) -> String {
        artifact_id.replace(['/', '\\'], "_")
    }

    fn proposal_file(&self, artifact_id: &str) -> PathBuf {
        let safe_id = Self::sanitize_id(artifact_id);
        self.proposals_dir.join(format!("{}.json", safe_id))
    }

    fn votes_file(&self, artifact_id: &str) -> PathBuf {
        let safe_id = Self::sanitize_id(artifact_id);
        self.votes_dir.join(format!("{}.json", safe_id))
    }

    fn decision_file(&self, artifact_id: &str) -> PathBuf {
        let safe_id = Self::sanitize_id(artifact_id);
        self.decisions_dir.join(format!("{}.json", safe_id))
    }
}

impl NegotiationRoomStore for JsonFileNegotiationRoomStore {
    fn has_proposal(&self, artifact_id: &str) -> Result<bool> {
        let proposal_file = self.proposal_file(artifact_id);
        Ok(proposal_file.exists())
    }

    fn get_proposal(&self, artifact_id: &str) -> Result<Option<NegotiationProposal>> {
        let proposal_file = self.proposal_file(artifact_id);

        if !proposal_file.exists() {
            return Ok(None);
        }

        let content = fs::read_to_string(&proposal_file).map_err(Error::Io)?;
        let proposal: NegotiationProposal =
            serde_json::from_str(&content).map_err(Error::Serialization)?;

        Ok(Some(proposal))
    }

    fn save_proposal(&self, proposal: NegotiationProposal) -> Result<()> {
        let artifact_id = proposal.artifact_id.clone();
        let proposal_file = self.proposal_file(&artifact_id);

        if proposal_file.exists() {
            return Err(Error::Config(format!(
                "Proposal with artifact_id '{}' already exists",
                artifact_id
            )));
        }

        let content = serde_json::to_string_pretty(&proposal).map_err(Error::Serialization)?;

        // Atomic write: write to temp file, then rename
        let temp_file = proposal_file.with_extension("tmp");
        fs::write(&temp_file, content).map_err(Error::Io)?;
        fs::rename(temp_file, proposal_file).map_err(Error::Io)?;

        // Initialize empty votes file
        let votes_file = self.votes_file(&artifact_id);
        if !votes_file.exists() {
            fs::write(&votes_file, "[]").map_err(Error::Io)?;
        }

        Ok(())
    }

    fn list_proposals(&self, negotiation_room_id: Option<&str>) -> Result<Vec<NegotiationProposal>> {
        let mut proposals = Vec::new();

        for entry in fs::read_dir(&self.proposals_dir).map_err(Error::Io)? {
            let entry = entry.map_err(Error::Io)?;
            let path = entry.path();

            if path.extension().is_some_and(|ext| ext == "json") {
                if let Ok(content) = fs::read_to_string(&path) {
                    if let Ok(proposal) = serde_json::from_str::<NegotiationProposal>(&content) {
                        match negotiation_room_id {
                            Some(room_id) if proposal.negotiation_room_id == room_id => {
                                proposals.push(proposal);
                            }
                            Some(_) => {} // Skip, doesn't match filter
                            None => {
                                proposals.push(proposal);
                            }
                        }
                    }
                }
            }
        }

        Ok(proposals)
    }

    fn get_votes(&self, artifact_id: &str) -> Result<Vec<NegotiationVote>> {
        let votes_file = self.votes_file(artifact_id);

        if !votes_file.exists() {
            return Ok(Vec::new());
        }

        let content = fs::read_to_string(&votes_file).map_err(Error::Io)?;
        let votes: Vec<NegotiationVote> =
            serde_json::from_str(&content).map_err(Error::Serialization)?;

        Ok(votes)
    }

    fn add_vote(&self, vote: NegotiationVote) -> Result<()> {
        let artifact_id = vote.artifact_id.clone();
        let critic_id = vote.critic_id.clone();
        let votes_file = self.votes_file(&artifact_id);

        // Load existing votes
        let mut votes: Vec<NegotiationVote> = if votes_file.exists() {
            let content = fs::read_to_string(&votes_file).map_err(Error::Io)?;
            serde_json::from_str(&content).map_err(Error::Serialization)?
        } else {
            Vec::new()
        };

        // Check for duplicate vote
        for v in &votes {
            if v.critic_id == critic_id {
                return Err(Error::Config(format!(
                    "Critic '{}' has already voted for artifact '{}'",
                    critic_id, artifact_id
                )));
            }
        }

        // Add new vote
        votes.push(vote);

        // Atomic write
        let content = serde_json::to_string_pretty(&votes).map_err(Error::Serialization)?;
        let temp_file = votes_file.with_extension("tmp");
        fs::write(&temp_file, content).map_err(Error::Io)?;
        fs::rename(temp_file, votes_file).map_err(Error::Io)?;

        Ok(())
    }

    fn get_decision(&self, artifact_id: &str) -> Result<Option<NegotiationDecision>> {
        let decision_file = self.decision_file(artifact_id);

        if !decision_file.exists() {
            return Ok(None);
        }

        let content = fs::read_to_string(&decision_file).map_err(Error::Io)?;
        let decision: NegotiationDecision =
            serde_json::from_str(&content).map_err(Error::Serialization)?;

        Ok(Some(decision))
    }

    fn save_decision(&self, decision: NegotiationDecision) -> Result<()> {
        let artifact_id = decision.artifact_id.clone();
        let decision_file = self.decision_file(&artifact_id);

        if decision_file.exists() {
            return Err(Error::Config(format!(
                "Decision already exists for artifact_id '{}'",
                artifact_id
            )));
        }

        let content = serde_json::to_string_pretty(&decision).map_err(Error::Serialization)?;

        // Atomic write
        let temp_file = decision_file.with_extension("tmp");
        fs::write(&temp_file, content).map_err(Error::Io)?;
        fs::rename(temp_file, decision_file).map_err(Error::Io)?;

        Ok(())
    }
}

impl std::fmt::Debug for JsonFileNegotiationRoomStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("JsonFileNegotiationRoomStore")
            .field("proposals_dir", &self.proposals_dir)
            .field("votes_dir", &self.votes_dir)
            .field("decisions_dir", &self.decisions_dir)
            .finish()
    }
}
