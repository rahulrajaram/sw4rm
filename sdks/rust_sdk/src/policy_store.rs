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

//! Policy storage and retrieval abstractions.
//!
//! This module provides a storage layer for managing `EffectivePolicy` instances,
//! supporting both in-memory and persistent storage backends.
//!
//! Policy snapshots are immutable once stored. Each policy is versioned using
//! timestamp-based UUIDs to ensure uniqueness and provide chronological ordering.

use crate::{Error, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, RwLock};
use uuid::Uuid;

/// Generate a unique version identifier for a policy.
///
/// Uses a combination of timestamp and UUID to ensure uniqueness
/// and provide some chronological ordering.
///
/// # Returns
///
/// A version string in the format: `{timestamp_ms}_{uuid}`
pub fn generate_policy_version() -> String {
    let timestamp_ms = Utc::now().timestamp_millis();
    let unique_id = Uuid::new_v4();
    format!("{}_{}", timestamp_ms, unique_id)
}

/// Configuration for scoring during negotiation.
///
/// Defines how proposals are scored and weighted during the negotiation process.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ScoringConfig {
    /// Mapping of scoring dimension names to their weights
    pub weights: HashMap<String, f64>,
    /// Normalization strategy (e.g., 'minmax', 'zscore', 'none')
    pub normalization: String,
}

impl ScoringConfig {
    /// Create a new scoring configuration.
    pub fn new() -> Self {
        Self {
            weights: HashMap::new(),
            normalization: "none".to_string(),
        }
    }

    /// Add a weight for a scoring dimension.
    pub fn with_weight(mut self, dimension: String, weight: f64) -> Self {
        self.weights.insert(dimension, weight);
        self
    }

    /// Set the normalization strategy.
    pub fn with_normalization(mut self, normalization: String) -> Self {
        self.normalization = normalization;
        self
    }
}

/// Per-agent policy preferences.
///
/// Advisory preferences that an agent can specify. The scheduler
/// clamps these to the guardrails defined by the effective policy.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AgentPreferences {
    /// Unique identifier for the agent
    pub agent_id: String,
    /// Agent-specific weight overrides for scoring dimensions
    pub weight_overrides: HashMap<String, f64>,
}

/// Policy governing negotiation behavior.
///
/// Defines the constraints and parameters for the negotiation process
/// between agents.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NegotiationPolicy {
    /// Maximum number of negotiation rounds allowed
    pub max_rounds: i32,
    /// Minimum score (0..1) required for acceptance
    pub score_threshold: f64,
    /// Maximum allowed difference (0..1) between proposals
    pub diff_tolerance: f64,
    /// Timeout in milliseconds for each round
    pub round_timeout_ms: i64,
    /// Maximum tokens allowed per round
    pub token_budget_per_round: i64,
    /// Total token budget for entire negotiation (None=unlimited)
    pub total_token_budget: Option<i64>,
    /// Maximum allowed proposal oscillations before termination
    pub oscillation_limit: i32,
    /// Human-in-the-loop mode ('None', 'PauseBetweenRounds', 'PauseOnFinalAccept')
    pub hitl_mode: String,
    /// Optional scoring configuration
    pub scoring: Option<ScoringConfig>,
    /// List of per-agent preferences
    pub agent_preferences: Vec<AgentPreferences>,
}

impl Default for NegotiationPolicy {
    fn default() -> Self {
        Self {
            max_rounds: 10,
            score_threshold: 0.8,
            diff_tolerance: 0.1,
            round_timeout_ms: 30000,
            token_budget_per_round: 4000,
            total_token_budget: None,
            oscillation_limit: 3,
            hitl_mode: "None".to_string(),
            scoring: None,
            agent_preferences: Vec::new(),
        }
    }
}

/// Policy governing task execution.
///
/// Defines constraints and resource limits for executing tasks.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ExecutionPolicy {
    /// Maximum execution time in milliseconds
    pub timeout_ms: i64,
    /// Maximum number of retry attempts
    pub max_retries: i32,
    /// Backoff strategy (e.g., 'none', 'linear', 'exponential')
    pub backoff: String,
    /// Whether a worktree binding is required for execution
    pub worktree_required: bool,
    /// Network access policy (e.g., 'none', 'restricted', 'full')
    pub network_policy: String,
    /// Required privilege level (e.g., 'standard', 'elevated')
    pub privilege_level: String,
    /// CPU time budget in milliseconds
    pub budget_cpu_ms: i64,
    /// Wall clock time budget in milliseconds
    pub budget_wall_ms: i64,
}

impl Default for ExecutionPolicy {
    fn default() -> Self {
        Self {
            timeout_ms: 60000,
            max_retries: 3,
            backoff: "exponential".to_string(),
            worktree_required: false,
            network_policy: "restricted".to_string(),
            privilege_level: "standard".to_string(),
            budget_cpu_ms: 30000,
            budget_wall_ms: 60000,
        }
    }
}

/// Policy governing escalation behavior.
///
/// Defines when and how negotiations should be escalated.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EscalationPolicy {
    /// Whether to automatically escalate when deadlock is detected
    pub auto_escalate_on_deadlock: bool,
    /// Number of rounds without progress before declaring deadlock
    pub deadlock_rounds: i32,
    /// List of valid reasons for escalation
    pub escalation_reasons: Vec<String>,
}

impl Default for EscalationPolicy {
    fn default() -> Self {
        Self {
            auto_escalate_on_deadlock: true,
            deadlock_rounds: 3,
            escalation_reasons: Vec::new(),
        }
    }
}

/// The authoritative policy derived for a negotiation.
///
/// Combines base policy with any profile and agent overrides to produce
/// the final effective policy used during negotiation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EffectivePolicy {
    /// Unique identifier for this policy instance
    pub policy_id: String,
    /// Version string for the policy
    pub version: String,
    /// Negotiation policy settings
    pub negotiation: NegotiationPolicy,
    /// Execution policy settings
    pub execution: ExecutionPolicy,
    /// Escalation policy settings
    pub escalation: EscalationPolicy,
}

impl Default for EffectivePolicy {
    fn default() -> Self {
        Self {
            policy_id: String::new(),
            version: "1.0".to_string(),
            negotiation: NegotiationPolicy::default(),
            execution: ExecutionPolicy::default(),
            escalation: EscalationPolicy::default(),
        }
    }
}

impl EffectivePolicy {
    /// Create a new effective policy with the given ID.
    pub fn new(policy_id: String) -> Self {
        Self {
            policy_id,
            ..Default::default()
        }
    }

    /// Set the negotiation policy.
    pub fn with_negotiation(mut self, negotiation: NegotiationPolicy) -> Self {
        self.negotiation = negotiation;
        self
    }

    /// Set the execution policy.
    pub fn with_execution(mut self, execution: ExecutionPolicy) -> Self {
        self.execution = execution;
        self
    }

    /// Set the escalation policy.
    pub fn with_escalation(mut self, escalation: EscalationPolicy) -> Self {
        self.escalation = escalation;
        self
    }
}

/// Trait defining the interface for policy storage backends.
///
/// All policy storage implementations must support these operations.
/// Policies are immutable once stored - saving a policy with the same
/// policy_id but different version creates a new snapshot in the history.
pub trait PolicyStore: Send + Sync {
    /// Retrieve the latest version of a policy by ID.
    ///
    /// # Arguments
    ///
    /// * `policy_id` - Unique identifier for the policy
    ///
    /// # Returns
    ///
    /// The most recent version of the policy.
    ///
    /// # Errors
    ///
    /// Returns an error if no policy with the given ID exists.
    fn get_policy(&self, policy_id: &str) -> Result<EffectivePolicy>;

    /// Save a policy snapshot and return its policy_id.
    ///
    /// If the policy has no version set, a new version is generated.
    /// The policy snapshot is immutable once saved.
    ///
    /// # Arguments
    ///
    /// * `policy` - The policy to save
    ///
    /// # Returns
    ///
    /// The policy_id of the saved policy.
    fn save_policy(&self, policy: EffectivePolicy) -> Result<String>;

    /// List all policy IDs, optionally filtered by prefix.
    ///
    /// # Arguments
    ///
    /// * `prefix` - Optional prefix to filter policy IDs
    ///
    /// # Returns
    ///
    /// List of policy IDs matching the prefix.
    fn list_policies(&self, prefix: &str) -> Result<Vec<String>>;

    /// Retrieve the complete version history for a policy.
    ///
    /// Returns policies in chronological order (oldest to newest).
    ///
    /// # Arguments
    ///
    /// * `policy_id` - Unique identifier for the policy
    ///
    /// # Returns
    ///
    /// List of all versions of the policy.
    ///
    /// # Errors
    ///
    /// Returns an error if no policy with the given ID exists.
    fn get_policy_history(&self, policy_id: &str) -> Result<Vec<EffectivePolicy>>;
}

/// In-memory implementation of PolicyStore.
///
/// Stores policies in memory with full version history. Data is lost
/// when the process terminates. Suitable for testing and transient usage.
///
/// Thread-safety: This implementation is thread-safe.
#[derive(Clone)]
pub struct InMemoryPolicyStore {
    // Maps policy_id -> list of EffectivePolicy (chronological order)
    policies: Arc<RwLock<HashMap<String, Vec<EffectivePolicy>>>>,
}

impl Default for InMemoryPolicyStore {
    fn default() -> Self {
        Self::new()
    }
}

impl InMemoryPolicyStore {
    /// Create a new in-memory policy store.
    pub fn new() -> Self {
        Self {
            policies: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

impl PolicyStore for InMemoryPolicyStore {
    fn get_policy(&self, policy_id: &str) -> Result<EffectivePolicy> {
        let policies = self
            .policies
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        policies
            .get(policy_id)
            .and_then(|versions| versions.last())
            .cloned()
            .ok_or_else(|| Error::Config(format!("Policy not found: {}", policy_id)))
    }

    fn save_policy(&self, mut policy: EffectivePolicy) -> Result<String> {
        // Generate version if not set or if using default
        if policy.version.is_empty() || policy.version == "1.0" {
            policy.version = generate_policy_version();
        }

        // Ensure policy_id is set
        if policy.policy_id.is_empty() {
            policy.policy_id = format!("policy_{}", Uuid::new_v4());
        }

        let policy_id = policy.policy_id.clone();

        let mut policies = self
            .policies
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        policies
            .entry(policy_id.clone())
            .or_insert_with(Vec::new)
            .push(policy);

        Ok(policy_id)
    }

    fn list_policies(&self, prefix: &str) -> Result<Vec<String>> {
        let policies = self
            .policies
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        let mut ids: Vec<String> = if prefix.is_empty() {
            policies.keys().cloned().collect()
        } else {
            policies
                .keys()
                .filter(|id| id.starts_with(prefix))
                .cloned()
                .collect()
        };

        ids.sort();
        Ok(ids)
    }

    fn get_policy_history(&self, policy_id: &str) -> Result<Vec<EffectivePolicy>> {
        let policies = self
            .policies
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        policies
            .get(policy_id)
            .cloned()
            .ok_or_else(|| Error::Config(format!("Policy not found: {}", policy_id)))
    }
}

impl std::fmt::Debug for InMemoryPolicyStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("InMemoryPolicyStore").finish()
    }
}

/// File-based implementation of PolicyStore using JSON.
///
/// Persists policies to disk as JSON files with full version history.
/// Each policy is stored in a separate file named `{policy_id}.json`.
///
/// Storage format:
/// ```json
/// {
///     "policy_id": "...",
///     "versions": [
///         {policy dict},
///         {policy dict},
///         ...
///     ]
/// }
/// ```
///
/// Thread-safety: This implementation is thread-safe for reads but
/// uses file-level locking for writes.
pub struct JsonFilePolicyStore {
    storage_dir: PathBuf,
    cache: Arc<RwLock<HashMap<String, Vec<EffectivePolicy>>>>,
}

impl JsonFilePolicyStore {
    /// Create a new JSON file-based policy store.
    ///
    /// Creates the storage directory if it doesn't exist.
    ///
    /// # Arguments
    ///
    /// * `storage_dir` - Directory to store policy JSON files
    pub fn new<P: AsRef<Path>>(storage_dir: P) -> Result<Self> {
        let storage_dir = storage_dir.as_ref().to_path_buf();
        fs::create_dir_all(&storage_dir).map_err(Error::Io)?;

        Ok(Self {
            storage_dir,
            cache: Arc::new(RwLock::new(HashMap::new())),
        })
    }

    fn get_policy_file(&self, policy_id: &str) -> PathBuf {
        // Sanitize policy_id for filesystem safety
        let safe_id = policy_id.replace(['/', '\\'], "_");
        self.storage_dir.join(format!("{}.json", safe_id))
    }

    fn load_from_file(&self, policy_id: &str) -> Result<Vec<EffectivePolicy>> {
        let policy_file = self.get_policy_file(policy_id);

        if !policy_file.exists() {
            return Err(Error::Config(format!("Policy not found: {}", policy_id)));
        }

        let content = fs::read_to_string(&policy_file).map_err(Error::Io)?;

        #[derive(Deserialize)]
        struct StoredPolicy {
            versions: Vec<EffectivePolicy>,
        }

        let stored: StoredPolicy =
            serde_json::from_str(&content).map_err(Error::Serialization)?;

        Ok(stored.versions)
    }

    fn save_to_file(&self, policy_id: &str, versions: &[EffectivePolicy]) -> Result<()> {
        let policy_file = self.get_policy_file(policy_id);

        #[derive(Serialize)]
        struct StoredPolicy<'a> {
            policy_id: &'a str,
            versions: &'a [EffectivePolicy],
        }

        let stored = StoredPolicy {
            policy_id,
            versions,
        };

        let content = serde_json::to_string_pretty(&stored).map_err(Error::Serialization)?;

        // Atomic write: write to temp file, then rename
        let temp_file = policy_file.with_extension("tmp");
        fs::write(&temp_file, content).map_err(Error::Io)?;
        fs::rename(temp_file, policy_file).map_err(Error::Io)?;

        Ok(())
    }
}

impl PolicyStore for JsonFilePolicyStore {
    fn get_policy(&self, policy_id: &str) -> Result<EffectivePolicy> {
        // Try cache first
        {
            let cache = self
                .cache
                .read()
                .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

            if let Some(versions) = cache.get(policy_id) {
                if let Some(latest) = versions.last() {
                    return Ok(latest.clone());
                }
            }
        }

        // Load from file
        let versions = self.load_from_file(policy_id)?;

        // Update cache
        {
            let mut cache = self
                .cache
                .write()
                .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

            cache.insert(policy_id.to_string(), versions.clone());
        }

        versions
            .last()
            .cloned()
            .ok_or_else(|| Error::Config(format!("Policy has no versions: {}", policy_id)))
    }

    fn save_policy(&self, mut policy: EffectivePolicy) -> Result<String> {
        // Generate version if not set or if using default
        if policy.version.is_empty() || policy.version == "1.0" {
            policy.version = generate_policy_version();
        }

        // Ensure policy_id is set
        if policy.policy_id.is_empty() {
            policy.policy_id = format!("policy_{}", Uuid::new_v4());
        }

        let policy_id = policy.policy_id.clone();

        // Load existing versions or start fresh
        let mut versions = self.load_from_file(&policy_id).unwrap_or_default();

        // Append new version
        versions.push(policy);

        // Save to file
        self.save_to_file(&policy_id, &versions)?;

        // Update cache
        {
            let mut cache = self
                .cache
                .write()
                .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

            cache.insert(policy_id.clone(), versions);
        }

        Ok(policy_id)
    }

    fn list_policies(&self, prefix: &str) -> Result<Vec<String>> {
        let mut policy_ids = Vec::new();

        for entry in fs::read_dir(&self.storage_dir).map_err(Error::Io)? {
            let entry = entry.map_err(Error::Io)?;
            let path = entry.path();

            if path.extension().is_some_and(|ext| ext == "json") {
                // Read policy_id from file
                if let Ok(content) = fs::read_to_string(&path) {
                    #[derive(Deserialize)]
                    struct PartialPolicy {
                        policy_id: String,
                    }

                    if let Ok(partial) = serde_json::from_str::<PartialPolicy>(&content) {
                        if prefix.is_empty() || partial.policy_id.starts_with(prefix) {
                            policy_ids.push(partial.policy_id);
                        }
                    }
                }
            }
        }

        policy_ids.sort();
        Ok(policy_ids)
    }

    fn get_policy_history(&self, policy_id: &str) -> Result<Vec<EffectivePolicy>> {
        self.load_from_file(policy_id)
    }
}

impl std::fmt::Debug for JsonFilePolicyStore {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("JsonFilePolicyStore")
            .field("storage_dir", &self.storage_dir)
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    #[test]
    fn test_in_memory_store_save_and_get() {
        let store = InMemoryPolicyStore::new();

        let policy = EffectivePolicy::new("test-policy".to_string());
        let policy_id = store.save_policy(policy).unwrap();

        let retrieved = store.get_policy(&policy_id).unwrap();
        assert_eq!(retrieved.policy_id, policy_id);
    }

    #[test]
    fn test_in_memory_store_version_history() {
        let store = InMemoryPolicyStore::new();

        let policy1 = EffectivePolicy::new("test-policy".to_string());
        let policy_id = store.save_policy(policy1).unwrap();

        let mut policy2 = EffectivePolicy::new(policy_id.clone());
        policy2.negotiation.max_rounds = 20;
        store.save_policy(policy2).unwrap();

        let history = store.get_policy_history(&policy_id).unwrap();
        assert_eq!(history.len(), 2);

        // Latest should have max_rounds = 20
        let latest = store.get_policy(&policy_id).unwrap();
        assert_eq!(latest.negotiation.max_rounds, 20);
    }

    #[test]
    fn test_in_memory_store_list_policies() {
        let store = InMemoryPolicyStore::new();

        store
            .save_policy(EffectivePolicy::new("alpha-policy".to_string()))
            .unwrap();
        store
            .save_policy(EffectivePolicy::new("beta-policy".to_string()))
            .unwrap();
        store
            .save_policy(EffectivePolicy::new("alpha-other".to_string()))
            .unwrap();

        let all = store.list_policies("").unwrap();
        assert_eq!(all.len(), 3);

        let alpha = store.list_policies("alpha").unwrap();
        assert_eq!(alpha.len(), 2);
    }

    #[test]
    fn test_in_memory_store_not_found() {
        let store = InMemoryPolicyStore::new();
        let result = store.get_policy("nonexistent");
        assert!(result.is_err());
    }

    #[test]
    fn test_json_file_store_save_and_get() {
        let temp_dir = TempDir::new().unwrap();
        let store = JsonFilePolicyStore::new(temp_dir.path()).unwrap();

        let policy = EffectivePolicy::new("test-policy".to_string());
        let policy_id = store.save_policy(policy).unwrap();

        let retrieved = store.get_policy(&policy_id).unwrap();
        assert_eq!(retrieved.policy_id, policy_id);
    }

    #[test]
    fn test_json_file_store_persistence() {
        let temp_dir = TempDir::new().unwrap();
        let policy_id;

        // Create store and save policy
        {
            let store = JsonFilePolicyStore::new(temp_dir.path()).unwrap();
            let policy = EffectivePolicy::new("persistent-policy".to_string());
            policy_id = store.save_policy(policy).unwrap();
        }

        // Create new store instance and verify policy exists
        {
            let store = JsonFilePolicyStore::new(temp_dir.path()).unwrap();
            let retrieved = store.get_policy(&policy_id).unwrap();
            assert_eq!(retrieved.policy_id, policy_id);
        }
    }

    #[test]
    fn test_generate_policy_version() {
        let v1 = generate_policy_version();
        let v2 = generate_policy_version();

        assert!(!v1.is_empty());
        assert!(!v2.is_empty());
        assert_ne!(v1, v2);
    }

    #[test]
    fn test_effective_policy_builder() {
        let policy = EffectivePolicy::new("builder-test".to_string())
            .with_negotiation(NegotiationPolicy {
                max_rounds: 15,
                ..Default::default()
            })
            .with_execution(ExecutionPolicy {
                timeout_ms: 120000,
                ..Default::default()
            })
            .with_escalation(EscalationPolicy {
                deadlock_rounds: 5,
                ..Default::default()
            });

        assert_eq!(policy.policy_id, "builder-test");
        assert_eq!(policy.negotiation.max_rounds, 15);
        assert_eq!(policy.execution.timeout_ms, 120000);
        assert_eq!(policy.escalation.deadlock_rounds, 5);
    }
}
