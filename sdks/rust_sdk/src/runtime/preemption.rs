use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Preemption state for cooperative agent shutdown
#[derive(Debug, Clone, Default)]
pub struct PreemptionState {
    pub requested: bool,
    pub reason: Option<String>,
    pub deadline: Option<Instant>,
}

impl PreemptionState {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn request_preemption(&mut self, reason: Option<String>) {
        self.requested = true;
        self.reason = reason;
    }

    pub fn with_deadline(&mut self, deadline_ms: u64) {
        self.deadline = Some(Instant::now() + Duration::from_millis(deadline_ms));
    }

    pub fn is_requested(&self) -> bool {
        self.requested
    }

    pub fn is_deadline_exceeded(&self) -> bool {
        if let Some(deadline) = self.deadline {
            Instant::now() > deadline
        } else {
            false
        }
    }

    pub fn clear(&mut self) {
        self.requested = false;
        self.reason = None;
        self.deadline = None;
    }
}

/// Cooperative preemption manager
#[derive(Debug, Clone)]
pub struct PreemptionManager {
    state: Arc<Mutex<PreemptionState>>,
}

impl PreemptionManager {
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(PreemptionState::new())),
        }
    }

    /// Check if preemption has been requested
    pub fn is_preemption_requested(&self) -> bool {
        if let Ok(state) = self.state.lock() {
            state.is_requested() || state.is_deadline_exceeded()
        } else {
            false
        }
    }

    /// Request preemption with an optional reason
    pub fn request_preemption(&self, reason: Option<String>) {
        if let Ok(mut state) = self.state.lock() {
            state.request_preemption(reason);
        }
    }

    /// Set a deadline for preemption
    pub fn set_deadline(&self, deadline_ms: u64) {
        if let Ok(mut state) = self.state.lock() {
            state.with_deadline(deadline_ms);
        }
    }

    /// Clear preemption state
    pub fn clear_preemption(&self) {
        if let Ok(mut state) = self.state.lock() {
            state.clear();
        }
    }

    /// Get the preemption reason if available
    pub fn preemption_reason(&self) -> Option<String> {
        if let Ok(state) = self.state.lock() {
            state.reason.clone()
        } else {
            None
        }
    }

    /// Create a non-preemptible section guard
    pub fn non_preemptible(&self) -> NonPreemptibleGuard {
        NonPreemptibleGuard::new(self.clone())
    }
}

impl Default for PreemptionManager {
    fn default() -> Self {
        Self::new()
    }
}

/// RAII guard for non-preemptible code sections
pub struct NonPreemptibleGuard {
    manager: PreemptionManager,
    previous_state: bool,
}

impl NonPreemptibleGuard {
    fn new(manager: PreemptionManager) -> Self {
        let previous_state = if let Ok(mut state) = manager.state.lock() {
            let prev = state.requested;
            state.requested = false;
            prev
        } else {
            false
        };

        Self {
            manager,
            previous_state,
        }
    }
}

impl Drop for NonPreemptibleGuard {
    fn drop(&mut self) {
        if let Ok(mut state) = self.manager.state.lock() {
            state.requested = self.previous_state;
        }
    }
}