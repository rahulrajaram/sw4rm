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
}