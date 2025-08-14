use thiserror::Error;

#[derive(Debug, Error)]
pub enum SecretError {
    #[error("secret not found: scope={scope} key={key}")]
    NotFound { scope: String, key: String },
    #[error("secret scope error: {0}")]
    Scope(String),
    #[error("secret backend error: {0}")]
    Backend(String),
    #[error("secret permission error: {0}")]
    Permission(String),
    #[error("secret validation error: {0}")]
    Validation(String),
}

pub type Result<T> = std::result::Result<T, SecretError>;
