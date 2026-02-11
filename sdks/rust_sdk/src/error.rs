use thiserror::Error;

/// Result type alias for SW4RM SDK operations
pub type Result<T> = std::result::Result<T, Error>;

/// SW4RM SDK Error types
#[derive(Error, Debug)]
pub enum Error {
    #[error("gRPC transport error: {0}")]
    Transport(#[from] tonic::transport::Error),

    #[error("gRPC status error: {0}")]
    Status(#[from] tonic::Status),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Invalid envelope: {0}")]
    InvalidEnvelope(String),

    #[error("Agent not found: {0}")]
    AgentNotFound(String),

    #[error("Not found: {0}")]
    NotFound(String),

    #[error("Validation error: {0}")]
    Validation(String),

    #[error("Connection error: {0}")]
    Connection(String),

    #[error("Timeout error: {0}")]
    Timeout(String),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Protocol error: {0}")]
    Protocol(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("UUID error: {0}")]
    Uuid(#[from] uuid::Error),

    #[error("Internal error: {0}")]
    Internal(String),

    #[error("Buffer full: {current}/{max} items")]
    BufferFull { current: usize, max: usize },

    #[error("Negotiation failed: {0}")]
    NegotiationFailed(String),

    #[error("Worktree error: {0}")]
    WorktreeError(String),

    #[error("Policy violation: {0}")]
    PolicyViolation(String),

    #[error("Duplicate detected: {0}")]
    DuplicateDetected(String),

    #[error("Agent {agent_id} preempted: {reason}")]
    Preemption { agent_id: String, reason: String },
}
