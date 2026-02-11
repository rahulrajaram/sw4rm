//! State transition validation matrix for Agent lifecycle.
//!
//! Provides a compile-time transition matrix matching the spec section 8
//! state diagram. All SDKs (Python, JS, Rust) share the same transition rules.

use crate::constants::agent_state;

/// Check if a state transition is valid per spec section 8.
///
/// # Arguments
/// * `from` - Current agent state (i32 constant from `agent_state`)
/// * `to` - Target agent state
///
/// # Returns
/// `true` if the transition is valid, `false` otherwise
pub fn is_valid_transition(from: i32, to: i32) -> bool {
    matches!(
        (from, to),
        // INITIALIZING -> RUNNABLE, FAILED (init timeout)
        (agent_state::INITIALIZING, agent_state::RUNNABLE)
            | (agent_state::INITIALIZING, agent_state::FAILED)

            // RUNNABLE -> SCHEDULED
            | (agent_state::RUNNABLE, agent_state::SCHEDULED)

            // SCHEDULED -> RUNNING
            | (agent_state::SCHEDULED, agent_state::RUNNING)

            // RUNNING -> WAITING, WAITING_RESOURCES, SUSPENDED, COMPLETED, FAILED, SHUTTING_DOWN
            | (agent_state::RUNNING, agent_state::WAITING)
            | (agent_state::RUNNING, agent_state::WAITING_RESOURCES)
            | (agent_state::RUNNING, agent_state::SUSPENDED)
            | (agent_state::RUNNING, agent_state::COMPLETED)
            | (agent_state::RUNNING, agent_state::FAILED)
            | (agent_state::RUNNING, agent_state::SHUTTING_DOWN)

            // WAITING -> RUNNING
            | (agent_state::WAITING, agent_state::RUNNING)

            // WAITING_RESOURCES -> RUNNING, FAILED (resource timeout)
            | (agent_state::WAITING_RESOURCES, agent_state::RUNNING)
            | (agent_state::WAITING_RESOURCES, agent_state::FAILED)

            // SUSPENDED -> RESUMED, FAILED (suspension timeout)
            | (agent_state::SUSPENDED, agent_state::RESUMED)
            | (agent_state::SUSPENDED, agent_state::FAILED)

            // RESUMED -> RUNNING
            | (agent_state::RESUMED, agent_state::RUNNING)

            // COMPLETED -> RUNNABLE
            | (agent_state::COMPLETED, agent_state::RUNNABLE)

            // FAILED -> RECOVERING
            | (agent_state::FAILED, agent_state::RECOVERING)

            // SHUTTING_DOWN -> FAILED (shutdown timeout)
            | (agent_state::SHUTTING_DOWN, agent_state::FAILED)

            // RECOVERING -> RUNNABLE, SHUTTING_DOWN (abort), FAILED (recovery timeout)
            | (agent_state::RECOVERING, agent_state::RUNNABLE)
            | (agent_state::RECOVERING, agent_state::SHUTTING_DOWN)
            | (agent_state::RECOVERING, agent_state::FAILED)
    )
}

/// Get all valid target states from a given state.
pub fn valid_transitions(from: i32) -> Vec<i32> {
    let all_states = [
        agent_state::AGENT_STATE_UNSPECIFIED,
        agent_state::INITIALIZING,
        agent_state::RUNNABLE,
        agent_state::SCHEDULED,
        agent_state::RUNNING,
        agent_state::WAITING,
        agent_state::WAITING_RESOURCES,
        agent_state::SUSPENDED,
        agent_state::RESUMED,
        agent_state::COMPLETED,
        agent_state::FAILED,
        agent_state::SHUTTING_DOWN,
        agent_state::RECOVERING,
    ];

    all_states
        .iter()
        .copied()
        .filter(|&to| is_valid_transition(from, to))
        .collect()
}

/// Error for invalid state transitions.
#[derive(Debug, Clone)]
pub struct StateTransitionError {
    pub from_state: i32,
    pub to_state: i32,
}

impl std::fmt::Display for StateTransitionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "Invalid state transition from {} to {}",
            state_name(self.from_state),
            state_name(self.to_state)
        )
    }
}

impl std::error::Error for StateTransitionError {}

/// Get human-readable name for a state.
pub fn state_name(state: i32) -> &'static str {
    match state {
        agent_state::AGENT_STATE_UNSPECIFIED => "UNSPECIFIED",
        agent_state::INITIALIZING => "INITIALIZING",
        agent_state::RUNNABLE => "RUNNABLE",
        agent_state::SCHEDULED => "SCHEDULED",
        agent_state::RUNNING => "RUNNING",
        agent_state::WAITING => "WAITING",
        agent_state::WAITING_RESOURCES => "WAITING_RESOURCES",
        agent_state::SUSPENDED => "SUSPENDED",
        agent_state::RESUMED => "RESUMED",
        agent_state::COMPLETED => "COMPLETED",
        agent_state::FAILED => "FAILED",
        agent_state::SHUTTING_DOWN => "SHUTTING_DOWN",
        agent_state::RECOVERING => "RECOVERING",
        _ => "UNKNOWN",
    }
}

/// Validate and perform a state transition, returning error if invalid.
pub fn validate_transition(from: i32, to: i32) -> Result<(), StateTransitionError> {
    if is_valid_transition(from, to) {
        Ok(())
    } else {
        Err(StateTransitionError {
            from_state: from,
            to_state: to,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_valid_transitions() {
        assert!(is_valid_transition(agent_state::INITIALIZING, agent_state::RUNNABLE));
        assert!(is_valid_transition(agent_state::INITIALIZING, agent_state::FAILED));
        assert!(is_valid_transition(agent_state::RUNNING, agent_state::SUSPENDED));
        assert!(is_valid_transition(agent_state::SUSPENDED, agent_state::RESUMED));
        assert!(is_valid_transition(agent_state::SUSPENDED, agent_state::FAILED));
        assert!(is_valid_transition(agent_state::RECOVERING, agent_state::FAILED));
    }

    #[test]
    fn test_invalid_transitions() {
        assert!(!is_valid_transition(agent_state::INITIALIZING, agent_state::COMPLETED));
        assert!(!is_valid_transition(agent_state::RUNNABLE, agent_state::RUNNING));
        assert!(!is_valid_transition(agent_state::COMPLETED, agent_state::RUNNING));
    }

    #[test]
    fn test_valid_transitions_list() {
        let from_running = valid_transitions(agent_state::RUNNING);
        assert!(from_running.contains(&agent_state::WAITING));
        assert!(from_running.contains(&agent_state::SUSPENDED));
        assert!(from_running.contains(&agent_state::COMPLETED));
        assert!(from_running.contains(&agent_state::FAILED));
        assert!(!from_running.contains(&agent_state::RUNNABLE));
    }

    #[test]
    fn test_validate_transition() {
        assert!(validate_transition(agent_state::INITIALIZING, agent_state::RUNNABLE).is_ok());
        assert!(validate_transition(agent_state::INITIALIZING, agent_state::COMPLETED).is_err());
    }
}
