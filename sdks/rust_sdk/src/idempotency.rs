//! Idempotency token helpers for deduplication.
//!
//! Provides helpers to compute deterministic hashes and construct
//! idempotency tokens in the format: `{producer_id}:{operation_type}:{deterministic_hash}`.

use sha2::{Digest, Sha256};
use thiserror::Error;

/// Error returned by the idempotency helpers for invalid input.
#[derive(Debug, Error)]
pub enum IdempotencyError {
    /// producer_id or operation contains LF, the bytes-v1 field separator.
    #[error("idempotency input error: {0}")]
    InvalidInput(String),
}

/// Compute a deterministic hash from canonical operation parameters.
///
/// Legacy language-local helper: Serde serializes the supplied value directly.
/// Struct and map ordering are not normalized here. For cross-SDK tokens use
/// `compute_idempotency_token` with application-defined canonical bytes.
/// The SHA256 digest is truncated to 16 hex characters.
///
/// # Arguments
/// * `params` - Serializable value representing canonical operation parameters
///
/// # Returns
/// 16-character hex string (first 64 bits of SHA256)
pub fn compute_deterministic_hash<T: serde::Serialize>(
    params: &T,
) -> Result<String, serde_json::Error> {
    let canonical = serde_json::to_string(params)?;
    let mut hasher = Sha256::new();
    hasher.update(canonical.as_bytes());
    let result = hasher.finalize();
    Ok(hex::encode(&result[..8])) // 16 hex chars = 8 bytes
}

/// Create an idempotency token in the format: `{producer_id}:{operation_type}:{deterministic_hash}`.
///
/// # Arguments
/// * `producer_id` - ID of the agent/service producing the message
/// * `operation_type` - Type of operation (e.g., "tool_call", "task_submit")
/// * `deterministic_hash` - Hash computed from canonical operation parameters
///
/// # Returns
/// Formatted idempotency token string
pub fn make_idempotency_token(
    producer_id: &str,
    operation_type: &str,
    deterministic_hash: &str,
) -> String {
    format!("{producer_id}:{operation_type}:{deterministic_hash}")
}

/// Convenience function to compute hash and create token in one step.
///
/// # Arguments
/// * `producer_id` - ID of the agent/service
/// * `operation_type` - Type of operation
/// * `params` - Serializable parameters for hash computation
pub fn create_idempotency_token<T: serde::Serialize>(
    producer_id: &str,
    operation_type: &str,
    params: &T,
) -> Result<String, serde_json::Error> {
    let hash = compute_deterministic_hash(params)?;
    Ok(make_idempotency_token(producer_id, operation_type, &hash))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_deterministic_hash_stability() {
        let params = json!({"tool": "git_commit", "repo": "myrepo", "files": ["a.py"]});
        let hash1 = compute_deterministic_hash(&params).unwrap();
        let hash2 = compute_deterministic_hash(&params).unwrap();
        assert_eq!(hash1, hash2);
        assert_eq!(hash1.len(), 16);
    }

    #[test]
    fn test_make_idempotency_token() {
        let token = make_idempotency_token("agent-1", "git_commit", "abc123");
        assert_eq!(token, "agent-1:git_commit:abc123");
    }

    #[test]
    fn test_create_idempotency_token() {
        let params = json!({"key": "value"});
        let token = create_idempotency_token("agent-1", "test_op", &params).unwrap();
        assert!(token.starts_with("agent-1:test_op:"));
        assert_eq!(token.split(':').count(), 3);
    }
}

/// Portable bytes-v1 token. Supply identical canonical bytes in every language.
/// The digest covers UTF-8 producer, LF, UTF-8 operation, LF, then the exact bytes.
/// Legacy JSON helpers use a different input format and are not portable.
///
/// Rejects LF inside producer_id or operation (R43): LF is the digest field
/// separator, so an embedded LF would make the prefix ambiguous.
pub fn compute_idempotency_token(
    producer_id: &str,
    operation: &str,
    canonical_bytes: &[u8],
) -> std::result::Result<String, IdempotencyError> {
    if contains_lf(producer_id) || contains_lf(operation) {
        return Err(IdempotencyError::InvalidInput(
            "producer_id/operation must not contain LF in the bytes-v1 digest".to_string()
        ));
    }
    let mut hasher = Sha256::new();
    hasher.update(producer_id.as_bytes());
    hasher.update(b"\n");
    hasher.update(operation.as_bytes());
    hasher.update(b"\n");
    hasher.update(canonical_bytes);
    Ok(make_idempotency_token(
        producer_id,
        operation,
        &hex::encode(&hasher.finalize()[..8]),
    ))
}

fn contains_lf(value: &str) -> bool {
    value.contains("\n")
}
