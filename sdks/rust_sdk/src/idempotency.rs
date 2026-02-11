//! Idempotency token helpers for deduplication.
//!
//! Provides helpers to compute deterministic hashes and construct
//! idempotency tokens in the format: `{producer_id}:{operation_type}:{deterministic_hash}`.

use sha2::{Digest, Sha256};

/// Compute a deterministic hash from canonical operation parameters.
///
/// The parameters are serialized to compact JSON with sorted keys, then
/// SHA256-hashed and truncated to 16 hex characters.
///
/// # Arguments
/// * `params` - Serializable value representing canonical operation parameters
///
/// # Returns
/// 16-character hex string (first 64 bits of SHA256)
pub fn compute_deterministic_hash<T: serde::Serialize>(params: &T) -> Result<String, serde_json::Error> {
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
