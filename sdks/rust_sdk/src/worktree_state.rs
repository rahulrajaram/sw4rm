use crate::{Error, Result};
use chrono::Utc;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

/// Actions that can be taken on worktree bindings
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BindingAction {
    Bind,
    Unbind,
    Switch,
}

/// Represents a binding to a specific worktree
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorktreeBinding {
    pub repo_id: String,
    pub worktree_id: String,
    pub bound_at: i64, // timestamp when binding was created
    pub metadata: HashMap<String, String>,
}

impl WorktreeBinding {
    pub fn new(repo_id: String, worktree_id: String) -> Self {
        Self {
            repo_id,
            worktree_id,
            bound_at: Utc::now().timestamp(),
            metadata: HashMap::new(),
        }
    }

    pub fn with_metadata(mut self, metadata: HashMap<String, String>) -> Self {
        self.metadata = metadata;
        self
    }
}

/// Trait for worktree policy hooks
pub trait WorktreePolicyHook: Send + Sync {
    /// Called before binding to a worktree. Return false to reject the binding
    fn before_bind(
        &self,
        repo_id: &str,
        worktree_id: &str,
        current_binding: Option<&WorktreeBinding>,
    ) -> bool;

    /// Called after successful binding
    fn after_bind(&self, binding: &WorktreeBinding);

    /// Called before unbinding. Return false to reject the unbind
    fn before_unbind(&self, binding: &WorktreeBinding) -> bool;

    /// Called after successful unbinding
    fn after_unbind(&self, former_binding: &WorktreeBinding);

    /// Called when binding fails
    fn on_bind_error(&self, repo_id: &str, worktree_id: &str, error: &Error);
}

/// Default worktree policy with basic validation
#[derive(Debug)]
pub struct DefaultWorktreePolicy {
    pub allow_rebinding: bool,
    pub max_binding_age_hours: i64,
}

impl DefaultWorktreePolicy {
    pub fn new() -> Self {
        Self {
            allow_rebinding: true,
            max_binding_age_hours: 24,
        }
    }

    pub fn with_rebinding(mut self, allow_rebinding: bool) -> Self {
        self.allow_rebinding = allow_rebinding;
        self
    }

    pub fn with_max_age_hours(mut self, hours: i64) -> Self {
        self.max_binding_age_hours = hours;
        self
    }
}

impl Default for DefaultWorktreePolicy {
    fn default() -> Self {
        Self::new()
    }
}

impl WorktreePolicyHook for DefaultWorktreePolicy {
    fn before_bind(
        &self,
        repo_id: &str,
        worktree_id: &str,
        current_binding: Option<&WorktreeBinding>,
    ) -> bool {
        // Reject if already bound and rebinding not allowed
        if current_binding.is_some() && !self.allow_rebinding {
            return false;
        }

        // Basic validation
        if repo_id.is_empty() || worktree_id.is_empty() {
            return false;
        }

        true
    }

    fn after_bind(&self, binding: &WorktreeBinding) {
        tracing::info!(
            "Worktree bound to {}/{}",
            binding.repo_id,
            binding.worktree_id
        );
    }

    fn before_unbind(&self, _binding: &WorktreeBinding) -> bool {
        true // Always allow unbinding
    }

    fn after_unbind(&self, former_binding: &WorktreeBinding) {
        tracing::info!(
            "Worktree unbound from {}/{}",
            former_binding.repo_id,
            former_binding.worktree_id
        );
    }

    fn on_bind_error(&self, repo_id: &str, worktree_id: &str, error: &Error) {
        tracing::error!(
            "Failed to bind to worktree {}/{}: {}",
            repo_id,
            worktree_id,
            error
        );
    }
}

/// Persistence for worktree bindings
pub trait WorktreePersistence: Send + Sync {
    fn save_binding(&mut self, binding: Option<&WorktreeBinding>) -> Result<()>;
    fn load_binding(&mut self) -> Result<Option<WorktreeBinding>>;
    fn clear(&mut self) -> Result<()>;
}

/// JSON file-based persistence for worktree bindings
#[derive(Debug)]
pub struct JsonWorktreePersistence {
    file_path: std::path::PathBuf,
}

impl JsonWorktreePersistence {
    pub fn new(file_path: impl AsRef<Path>) -> Self {
        Self {
            file_path: file_path.as_ref().to_path_buf(),
        }
    }
}

impl Default for JsonWorktreePersistence {
    fn default() -> Self {
        Self::new("sw4rm_worktree.json")
    }
}

#[derive(Serialize, Deserialize)]
struct WorktreePersistenceData {
    binding: Option<WorktreeBinding>,
    version: String,
}

impl WorktreePersistence for JsonWorktreePersistence {
    fn save_binding(&mut self, binding: Option<&WorktreeBinding>) -> Result<()> {
        let data = WorktreePersistenceData {
            binding: binding.cloned(),
            version: "1.0".to_string(),
        };

        // Atomic write
        let temp_path = self.file_path.with_extension("tmp");
        let json_data = serde_json::to_string_pretty(&data).map_err(Error::Serialization)?;

        fs::write(&temp_path, json_data).map_err(Error::Io)?;
        fs::rename(temp_path, &self.file_path).map_err(Error::Io)?;

        Ok(())
    }

    fn load_binding(&mut self) -> Result<Option<WorktreeBinding>> {
        if !self.file_path.exists() {
            return Ok(None);
        }

        let content = fs::read_to_string(&self.file_path).map_err(Error::Io)?;
        let data: WorktreePersistenceData =
            serde_json::from_str(&content).map_err(Error::Serialization)?;

        Ok(data.binding)
    }

    fn clear(&mut self) -> Result<()> {
        if self.file_path.exists() {
            fs::remove_file(&self.file_path).map_err(Error::Io)?;
        }
        Ok(())
    }
}

/// Worktree state machine with persistent storage, policy hooks, and TTL enforcement.
///
/// Supports the full spec section 16 worktree state machine including:
/// - UNBOUND -> BOUND_HOME (via bind)
/// - BOUND_HOME -> SWITCH_PENDING (via request_switch)
/// - SWITCH_PENDING -> BOUND_NON_HOME (via approve_switch, with TTL)
/// - SWITCH_PENDING -> BOUND_HOME (via reject_switch)
/// - BOUND_NON_HOME -> BOUND_HOME (via revert_to_home or TTL expiry check)
/// - Any -> UNBOUND (via unbind)
///
/// Unlike the JS SDK which uses setTimeout, and the Python SDK which uses
/// threading.Timer, the Rust implementation uses a polling model: call
/// `check_ttl_expiry()` to test whether the TTL has elapsed and auto-revert.
pub struct PersistentWorktreeState {
    binding: Option<WorktreeBinding>,
    persistence: Box<dyn WorktreePersistence>,
    policy: Box<dyn WorktreePolicyHook>,
    /// Current state machine state
    state: String,
    /// Home worktree binding (saved on first bind, restored on revert)
    home_binding: Option<WorktreeBinding>,
    /// Pending switch target repo_id
    pending_repo_id: Option<String>,
    /// Pending switch target worktree_id
    pending_worktree_id: Option<String>,
    /// TTL in milliseconds for BOUND_NON_HOME state
    switch_ttl_ms: Option<u64>,
    /// Timestamp (unix ms) when BOUND_NON_HOME was entered
    switch_started_at: Option<i64>,
}

impl PersistentWorktreeState {
    pub fn new(
        persistence: Option<Box<dyn WorktreePersistence>>,
        policy: Option<Box<dyn WorktreePolicyHook>>,
    ) -> Result<Self> {
        let mut persistence =
            persistence.unwrap_or_else(|| Box::new(JsonWorktreePersistence::default()));
        let policy = policy.unwrap_or_else(|| Box::new(DefaultWorktreePolicy::default()));

        // Load existing binding on initialization
        let binding = persistence.load_binding().unwrap_or_else(|e| {
            tracing::warn!("Failed to load worktree binding from persistence: {}", e);
            None
        });

        let state = if binding.is_some() {
            "BOUND_HOME".to_string()
        } else {
            "UNBOUND".to_string()
        };

        if let Some(ref binding) = binding {
            tracing::info!(
                "Restored worktree binding to {}/{}",
                binding.repo_id,
                binding.worktree_id
            );
        }

        Ok(Self {
            home_binding: binding.clone(),
            binding,
            persistence,
            policy,
            state,
            pending_repo_id: None,
            pending_worktree_id: None,
            switch_ttl_ms: None,
            switch_started_at: None,
        })
    }

    fn save_to_persistence(&mut self) -> Result<()> {
        self.persistence
            .save_binding(self.binding.as_ref())
            .map_err(|e| {
                tracing::error!("Failed to save worktree binding to persistence: {}", e);
                e
            })
    }

    /// Bind to a worktree with policy validation (UNBOUND -> BOUND_HOME).
    pub fn bind(
        &mut self,
        repo_id: String,
        worktree_id: String,
        metadata: Option<HashMap<String, String>>,
    ) -> Result<bool> {
        // Call before_bind hook
        if !self
            .policy
            .before_bind(&repo_id, &worktree_id, self.binding.as_ref())
        {
            return Ok(false);
        }

        // Create new binding
        let new_binding = WorktreeBinding::new(repo_id.clone(), worktree_id.clone())
            .with_metadata(metadata.unwrap_or_default());

        // Update state
        self.binding = Some(new_binding.clone());
        self.home_binding = Some(new_binding.clone());
        self.state = "BOUND_HOME".to_string();

        match self.save_to_persistence() {
            Ok(()) => {
                // Call after_bind hook
                self.policy.after_bind(&new_binding);
                Ok(true)
            }
            Err(e) => {
                self.state = "BIND_FAILED".to_string();
                self.policy.on_bind_error(&repo_id, &worktree_id, &e);
                Err(e)
            }
        }
    }

    /// Unbind from current worktree with policy validation (Any -> UNBOUND).
    pub fn unbind(&mut self) -> Result<bool> {
        let binding = match &self.binding {
            Some(binding) => binding.clone(),
            None => return Ok(true), // Already unbound
        };

        // Call before_unbind hook
        if !self.policy.before_unbind(&binding) {
            return Ok(false);
        }

        // Update state
        self.binding = None;
        self.home_binding = None;
        self.state = "UNBOUND".to_string();
        self.switch_ttl_ms = None;
        self.switch_started_at = None;
        self.pending_repo_id = None;
        self.pending_worktree_id = None;
        self.save_to_persistence()?;

        // Call after_unbind hook
        self.policy.after_unbind(&binding);

        Ok(true)
    }

    /// Switch to a different worktree (unbind then bind).
    pub fn switch(
        &mut self,
        repo_id: String,
        worktree_id: String,
        metadata: Option<HashMap<String, String>>,
    ) -> Result<bool> {
        // Unbind first if bound
        if self.binding.is_some() && !self.unbind()? {
            return Ok(false);
        }

        // Then bind to new worktree
        self.bind(repo_id, worktree_id, metadata)
    }

    /// Request switch to a non-home worktree (BOUND_HOME -> SWITCH_PENDING).
    ///
    /// Requires approval via `approve_switch()` or rejection via `reject_switch()`
    /// before taking effect.
    pub fn request_switch(
        &mut self,
        target_repo_id: String,
        target_worktree_id: String,
    ) -> bool {
        if self.state != "BOUND_HOME" {
            return false;
        }
        self.pending_repo_id = Some(target_repo_id);
        self.pending_worktree_id = Some(target_worktree_id);
        self.state = "SWITCH_PENDING".to_string();
        true
    }

    /// Approve a pending switch (SWITCH_PENDING -> BOUND_NON_HOME).
    ///
    /// Records the TTL and the start time. Call `check_ttl_expiry()` periodically
    /// to auto-revert when the TTL elapses.
    ///
    /// # Arguments
    ///
    /// * `ttl_ms` - Time-to-live in milliseconds before auto-reverting to BOUND_HOME.
    ///              Defaults to 300000 (5 minutes) if 0 is passed.
    pub fn approve_switch(&mut self, ttl_ms: u64) -> bool {
        if self.state != "SWITCH_PENDING" {
            return false;
        }

        let repo_id = match self.pending_repo_id.take() {
            Some(r) => r,
            None => return false,
        };
        let worktree_id = match self.pending_worktree_id.take() {
            Some(w) => w,
            None => return false,
        };

        let new_binding = WorktreeBinding::new(repo_id, worktree_id);
        self.binding = Some(new_binding);
        self.state = "BOUND_NON_HOME".to_string();
        self.switch_ttl_ms = Some(if ttl_ms == 0 { 300_000 } else { ttl_ms });
        self.switch_started_at = Some(Utc::now().timestamp_millis());

        let _ = self.save_to_persistence();
        true
    }

    /// Reject a pending switch (SWITCH_PENDING -> BOUND_HOME).
    pub fn reject_switch(&mut self) -> bool {
        if self.state != "SWITCH_PENDING" {
            return false;
        }

        self.pending_repo_id = None;
        self.pending_worktree_id = None;

        // Restore home binding
        if let Some(ref home) = self.home_binding {
            self.binding = Some(home.clone());
        }
        self.state = "BOUND_HOME".to_string();
        let _ = self.save_to_persistence();
        true
    }

    /// Check if the BOUND_NON_HOME TTL has expired and auto-revert if so.
    ///
    /// This is the polling-based equivalent of the JS/Python timer approach.
    /// Callers should invoke this periodically (e.g., on each status check).
    ///
    /// Returns `true` if the state was reverted due to TTL expiry.
    pub fn check_ttl_expiry(&mut self) -> bool {
        if self.state != "BOUND_NON_HOME" {
            return false;
        }

        if let (Some(ttl_ms), Some(started_at)) = (self.switch_ttl_ms, self.switch_started_at) {
            let now_ms = Utc::now().timestamp_millis();
            if now_ms - started_at >= ttl_ms as i64 {
                self.revert_to_home();
                return true;
            }
        }
        false
    }

    /// Revert from non-home to home worktree (BOUND_NON_HOME -> BOUND_HOME).
    ///
    /// Called on TTL expiry or explicit revoke.
    pub fn revert_to_home(&mut self) {
        if self.state != "BOUND_NON_HOME" {
            return;
        }

        if let Some(ref home) = self.home_binding {
            self.binding = Some(home.clone());
        }
        self.state = "BOUND_HOME".to_string();
        self.switch_ttl_ms = None;
        self.switch_started_at = None;
        let _ = self.save_to_persistence();
    }

    /// Get the current state machine state.
    pub fn worktree_state(&self) -> &str {
        &self.state
    }

    /// Get current binding.
    pub fn current(&self) -> Option<&WorktreeBinding> {
        self.binding.as_ref()
    }

    /// Check if currently bound to a worktree.
    pub fn is_bound(&self) -> bool {
        self.binding.is_some()
    }

    /// Get detailed status information.
    pub fn status(&self) -> serde_json::Value {
        match &self.binding {
            Some(binding) => {
                let mut val = serde_json::json!({
                    "bound": true,
                    "state": self.state,
                    "repo_id": binding.repo_id,
                    "worktree_id": binding.worktree_id,
                    "bound_at": binding.bound_at,
                    "metadata": binding.metadata
                });
                if let Some(ref home) = self.home_binding {
                    val["home_repo_id"] = serde_json::json!(home.repo_id);
                    val["home_worktree_id"] = serde_json::json!(home.worktree_id);
                }
                if let Some(ttl) = self.switch_ttl_ms {
                    val["switch_ttl_ms"] = serde_json::json!(ttl);
                }
                val
            }
            None => serde_json::json!({
                "bound": false,
                "state": self.state
            }),
        }
    }

    /// Clear binding and persistent storage.
    pub fn clear(&mut self) -> Result<()> {
        self.binding = None;
        self.home_binding = None;
        self.state = "UNBOUND".to_string();
        self.switch_ttl_ms = None;
        self.switch_started_at = None;
        self.pending_repo_id = None;
        self.pending_worktree_id = None;
        self.persistence.clear()
    }
}

/// Legacy in-memory worktree state for backwards compatibility
#[derive(Debug, Default)]
pub struct WorktreeState {
    binding: Option<(String, String)>, // (repo_id, worktree_id)
}

impl WorktreeState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn bind(&mut self, repo_id: String, worktree_id: String) {
        self.binding = Some((repo_id, worktree_id));
    }

    pub fn unbind(&mut self) {
        self.binding = None;
    }

    pub fn current(&self) -> Option<(String, String)> {
        self.binding.clone()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::NamedTempFile;

    #[test]
    fn test_worktree_binding() {
        let binding = WorktreeBinding::new("repo1".to_string(), "tree1".to_string())
            .with_metadata(HashMap::from([("key1".to_string(), "value1".to_string())]));

        assert_eq!(binding.repo_id, "repo1");
        assert_eq!(binding.worktree_id, "tree1");
        assert_eq!(binding.metadata.get("key1"), Some(&"value1".to_string()));
    }

    #[test]
    fn test_json_persistence() {
        let temp_file = NamedTempFile::new().unwrap();
        let mut persistence = JsonWorktreePersistence::new(temp_file.path());

        let binding = WorktreeBinding::new("repo1".to_string(), "tree1".to_string());

        // Save
        persistence.save_binding(Some(&binding)).unwrap();

        // Load
        let loaded = persistence.load_binding().unwrap().unwrap();
        assert_eq!(loaded.repo_id, "repo1");
        assert_eq!(loaded.worktree_id, "tree1");

        // Clear
        persistence.clear().unwrap();
        let after_clear = persistence.load_binding().unwrap();
        assert!(after_clear.is_none());
    }

    #[test]
    fn test_default_policy() {
        let policy = DefaultWorktreePolicy::new();

        // Should allow initial binding
        assert!(policy.before_bind("repo1", "tree1", None));

        // Should reject empty repo/tree
        assert!(!policy.before_bind("", "tree1", None));
        assert!(!policy.before_bind("repo1", "", None));

        let binding = WorktreeBinding::new("repo1".to_string(), "tree1".to_string());

        // Should allow rebinding by default
        assert!(policy.before_bind("repo2", "tree2", Some(&binding)));

        // Should always allow unbinding
        assert!(policy.before_unbind(&binding));
    }
}
