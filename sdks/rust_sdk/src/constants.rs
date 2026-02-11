//! Protocol constants mirroring common.proto enums.
//!
//! These are numeric values to keep the reference SDK usable without generated stubs
//! at import time. When protobuf modules are available, prefer using those enums
//! directly. Values must match common.proto definitions.

/// MessageType constants
pub mod message_type {
    pub const MESSAGE_TYPE_UNSPECIFIED: i32 = 0;
    pub const CONTROL: i32 = 1;
    pub const DATA: i32 = 2;
    pub const HEARTBEAT: i32 = 3;
    pub const NOTIFICATION: i32 = 4;
    pub const ACKNOWLEDGEMENT: i32 = 5;
    pub const HITL_INVOCATION: i32 = 6;
    pub const WORKTREE_CONTROL: i32 = 7;
    pub const NEGOTIATION: i32 = 8;
    pub const TOOL_CALL: i32 = 9;
    pub const TOOL_RESULT: i32 = 10;
    pub const TOOL_ERROR: i32 = 11;
}

/// AckStage constants
pub mod ack_stage {
    pub const ACK_STAGE_UNSPECIFIED: i32 = 0;
    pub const RECEIVED: i32 = 1;
    pub const READ: i32 = 2;
    pub const FULFILLED: i32 = 3;
    pub const REJECTED: i32 = 4;
    pub const FAILED: i32 = 5;
    pub const TIMED_OUT: i32 = 6;
}

/// ErrorCode constants
pub mod error_code {
    pub const ERROR_CODE_UNSPECIFIED: i32 = 0;
    pub const BUFFER_FULL: i32 = 1;
    pub const NO_ROUTE: i32 = 2;
    pub const ACK_TIMEOUT: i32 = 3;
    pub const AGENT_UNAVAILABLE: i32 = 4;
    pub const AGENT_SHUTDOWN: i32 = 5;
    pub const VALIDATION_ERROR: i32 = 6;
    pub const PERMISSION_DENIED: i32 = 7;
    pub const UNSUPPORTED_MESSAGE_TYPE: i32 = 8;
    pub const OVERSIZE_PAYLOAD: i32 = 9;
    pub const TOOL_TIMEOUT: i32 = 10;
    pub const PARTIAL_DELIVERY: i32 = 11;
    pub const FORCED_PREEMPTION: i32 = 12;
    pub const TTL_EXPIRED: i32 = 13;
    pub const DUPLICATE_DETECTED: i32 = 14;
    pub const ALREADY_IN_PROGRESS: i32 = 15;
    pub const INTERNAL_ERROR: i32 = 99;
}

/// AgentState constants
pub mod agent_state {
    pub const AGENT_STATE_UNSPECIFIED: i32 = 0;
    pub const INITIALIZING: i32 = 1;
    pub const RUNNABLE: i32 = 2;
    pub const SCHEDULED: i32 = 3;
    pub const RUNNING: i32 = 4;
    pub const WAITING: i32 = 5;
    pub const WAITING_RESOURCES: i32 = 6;
    pub const SUSPENDED: i32 = 7;
    pub const RESUMED: i32 = 8;
    pub const COMPLETED: i32 = 9;
    pub const FAILED: i32 = 10;
    pub const SHUTTING_DOWN: i32 = 11;
    pub const RECOVERING: i32 = 12;
}

/// CommunicationClass constants
pub mod communication_class {
    pub const COMM_CLASS_UNSPECIFIED: i32 = 0;
    pub const PRIVILEGED: i32 = 1;
    pub const STANDARD: i32 = 2;
    pub const BULK: i32 = 3;
}

/// DebateIntensity constants
pub mod debate_intensity {
    pub const DEBATE_INTENSITY_UNSPECIFIED: i32 = 0;
    pub const LOWEST: i32 = 1;
    pub const LOW: i32 = 2;
    pub const MEDIUM: i32 = 3;
    pub const HIGH: i32 = 4;
    pub const HIGHEST: i32 = 5;
}

/// HitlReasonType constants
pub mod hitl_reason_type {
    pub const HITL_REASON_UNSPECIFIED: i32 = 0;
    pub const CONFLICT: i32 = 1;
    pub const SECURITY_APPROVAL: i32 = 2;
    pub const TASK_ESCALATION: i32 = 3;
    pub const MANUAL_OVERRIDE: i32 = 4;
    pub const WORKTREE_OVERRIDE: i32 = 5;
    pub const DEBATE_DEADLOCK: i32 = 6;
    pub const TOOL_PRIVILEGE_ESCALATION: i32 = 7;
    pub const CONNECTOR_APPROVAL: i32 = 8;
}

/// EnvelopeState lifecycle constants (spec §11)
/// Lifecycle: SENT -> RECEIVED -> READ -> FULFILLED
/// Error states: REJECTED, FAILED, TIMED_OUT
pub mod envelope_state {
    pub const ENVELOPE_STATE_UNSPECIFIED: i32 = 0;
    pub const SENT: i32 = 1;
    pub const RECEIVED: i32 = 2;
    pub const READ: i32 = 3;
    pub const FULFILLED: i32 = 4;
    pub const REJECTED: i32 = 5;
    pub const FAILED: i32 = 6;
    pub const TIMED_OUT: i32 = 7;

    // Backwards compatibility aliases
    pub const CREATED: i32 = SENT;
    pub const PENDING: i32 = RECEIVED;
    pub const RUNNING: i32 = READ;

    /// Check if an envelope state is terminal (no further transitions expected).
    pub fn is_terminal(state: i32) -> bool {
        matches!(state, FULFILLED | REJECTED | FAILED | TIMED_OUT)
    }
}

/// WorktreeState constants (spec section 16)
pub mod worktree_state_const {
    pub const WORKTREE_STATE_UNSPECIFIED: i32 = 0;
    pub const UNBOUND: i32 = 1;
    pub const BOUND_HOME: i32 = 2;
    pub const SWITCH_PENDING: i32 = 3;
    pub const BOUND_NON_HOME: i32 = 4;
    pub const BIND_FAILED: i32 = 5;
}

/// Default timeout for acknowledgement in milliseconds.
pub const DEFAULT_ACK_TIMEOUT_MS: u64 = 10000;

/// Deduplication window in seconds.
pub const DEDUP_WINDOW_S: u64 = 3600;

// Re-export for convenience
pub use ack_stage::*;
pub use communication_class::*;
pub use debate_intensity::*;
pub use error_code::*;
pub use hitl_reason_type::*;
pub use message_type::*;
// Note: agent_state, envelope_state, and worktree_state_const are not re-exported
// at top level to avoid name collisions (e.g. ack_stage::FAILED vs agent_state::FAILED).
// Use e.g. constants::agent_state::FAILED or constants::envelope_state::CREATED
