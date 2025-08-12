use crate::types::{new_uuid, now_hlc_stub};
use serde::{Deserialize, Serialize};

/// Envelope builder for SW4RM protocol messages
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvelopeBuilder {
    pub message_id: String,
    pub idempotency_token: String,
    pub producer_id: String,
    pub correlation_id: String,
    pub sequence_number: u64,
    pub retry_count: u32,
    pub message_type: i32,
    pub content_type: String,
    pub content_length: u64,
    pub repo_id: String,
    pub worktree_id: String,
    pub hlc_timestamp: String,
    pub ttl_ms: u64,
    pub payload: Vec<u8>,
}

impl EnvelopeBuilder {
    /// Create a new envelope builder with required fields
    pub fn new(producer_id: String, message_type: i32) -> Self {
        Self {
            message_id: new_uuid(),
            idempotency_token: String::new(),
            producer_id,
            correlation_id: new_uuid(),
            sequence_number: 1,
            retry_count: 0,
            message_type,
            content_type: "application/json".to_string(),
            content_length: 0,
            repo_id: String::new(),
            worktree_id: String::new(),
            hlc_timestamp: now_hlc_stub(),
            ttl_ms: 0,
            payload: Vec::new(),
        }
    }

    /// Set the idempotency token
    pub fn with_idempotency_token(mut self, token: String) -> Self {
        self.idempotency_token = token;
        self
    }

    /// Set the correlation ID
    pub fn with_correlation_id(mut self, id: String) -> Self {
        self.correlation_id = id;
        self
    }

    /// Set the sequence number
    pub fn with_sequence_number(mut self, seq: u64) -> Self {
        self.sequence_number = seq;
        self
    }

    /// Set the retry count
    pub fn with_retry_count(mut self, count: u32) -> Self {
        self.retry_count = count;
        self
    }

    /// Set the content type
    pub fn with_content_type(mut self, content_type: String) -> Self {
        self.content_type = content_type;
        self
    }

    /// Set the payload
    pub fn with_payload(mut self, payload: Vec<u8>) -> Self {
        self.content_length = payload.len() as u64;
        self.payload = payload;
        // Default to binary when raw payload is supplied
        self.content_type = "application/octet-stream".to_string();
        self
    }

    /// Set the JSON payload
    pub fn with_json_payload<T: Serialize>(mut self, data: &T) -> Result<Self, serde_json::Error> {
        let payload = serde_json::to_vec(data)?;
        self.content_length = payload.len() as u64;
        self.payload = payload;
        self.content_type = "application/json".to_string();
        Ok(self)
    }

    /// Set the repository ID
    pub fn with_repo_id(mut self, repo_id: String) -> Self {
        self.repo_id = repo_id;
        self
    }

    /// Set the worktree ID
    pub fn with_worktree_id(mut self, worktree_id: String) -> Self {
        self.worktree_id = worktree_id;
        self
    }

    /// Set the TTL in milliseconds
    pub fn with_ttl_ms(mut self, ttl_ms: u64) -> Self {
        self.ttl_ms = ttl_ms;
        self
    }

    /// Build the envelope
    pub fn build(self) -> EnvelopeData {
        EnvelopeData {
            message_id: self.message_id,
            idempotency_token: self.idempotency_token,
            producer_id: self.producer_id,
            correlation_id: self.correlation_id,
            sequence_number: self.sequence_number,
            retry_count: self.retry_count,
            message_type: self.message_type,
            content_type: self.content_type,
            content_length: self.content_length,
            repo_id: self.repo_id,
            worktree_id: self.worktree_id,
            hlc_timestamp: self.hlc_timestamp,
            ttl_ms: self.ttl_ms,
            payload: self.payload,
        }
    }
}

/// Final envelope data structure
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EnvelopeData {
    pub message_id: String,
    pub idempotency_token: String,
    pub producer_id: String,
    pub correlation_id: String,
    pub sequence_number: u64,
    pub retry_count: u32,
    pub message_type: i32,
    pub content_type: String,
    pub content_length: u64,
    pub repo_id: String,
    pub worktree_id: String,
    pub hlc_timestamp: String,
    pub ttl_ms: u64,
    pub payload: Vec<u8>,
}

impl EnvelopeData {
    /// Extract JSON payload from envelope
    pub fn json_payload<T: for<'de> Deserialize<'de>>(&self) -> Result<T, serde_json::Error> {
        serde_json::from_slice(&self.payload)
    }

    /// Get payload as string
    pub fn string_payload(&self) -> Result<String, std::string::FromUtf8Error> {
        String::from_utf8(self.payload.clone())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_envelope_builder_basic_creation() {
        let envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        ).build();

        assert_eq!(envelope.producer_id, "test-agent");
        assert_eq!(envelope.message_type, crate::constants::message_type::DATA);
        assert!(!envelope.message_id.is_empty());
        // idempotency_token is optional; may be empty by default
        assert!(envelope.sequence_number > 0);
        assert_eq!(envelope.retry_count, 0);
    }

    #[test]
    fn test_envelope_builder_with_payload() {
        let test_payload = b"Hello, World!".to_vec();
        let envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_payload(test_payload.clone())
        .build();

        assert_eq!(envelope.payload, test_payload);
        assert_eq!(envelope.content_length, test_payload.len() as u64);
        assert_eq!(envelope.content_type, "application/octet-stream");
    }

    #[test]
    fn test_envelope_builder_with_json_payload() {
        let test_data = json!({
            "message": "Hello, JSON!",
            "timestamp": "2024-01-01T00:00:00Z",
            "data": [1, 2, 3, 4, 5]
        });

        let envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_json_payload(&test_data)
        .unwrap()
        .build();

        assert_eq!(envelope.content_type, "application/json");
        assert!(envelope.content_length > 0);
        assert!(!envelope.payload.is_empty());

        // Verify we can deserialize back to the original data
        let deserialized: serde_json::Value = envelope.json_payload().unwrap();
        assert_eq!(deserialized, test_data);
    }

    #[test]
    fn test_envelope_serialization_roundtrip() {
        let original_data = json!({
            "message": "Test serialization",
            "nested": {"value": 42, "array": [1, 2, 3]}
        });

        let envelope = EnvelopeBuilder::new(
            "serialize-test".to_string(),
            crate::constants::message_type::DATA
        )
        .with_json_payload(&original_data)
        .unwrap()
        .build();

        // Serialize to JSON
        let serialized = serde_json::to_string(&envelope).unwrap();

        // Deserialize back
        let deserialized: EnvelopeData = serde_json::from_str(&serialized).unwrap();

        // Verify all fields match
        assert_eq!(deserialized.message_id, envelope.message_id);
        assert_eq!(deserialized.producer_id, envelope.producer_id);
        assert_eq!(deserialized.message_type, envelope.message_type);
        assert_eq!(deserialized.payload, envelope.payload);
    }

    #[test]
    fn test_envelope_payload_extraction_methods() {
        // Test with JSON payload
        let json_data = json!({"message": "JSON test", "number": 42});
        let json_envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_json_payload(&json_data)
        .unwrap()
        .build();

        let extracted_json: serde_json::Value = json_envelope.json_payload().unwrap();
        assert_eq!(extracted_json, json_data);
    }

    #[test]
    fn test_envelope_error_handling() {
        // Test invalid JSON payload extraction
        let bad_json_envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_payload(b"invalid json {".to_vec())
        .with_content_type("application/json".to_string())
        .build();

        let json_result: Result<serde_json::Value, _> = bad_json_envelope.json_payload();
        assert!(json_result.is_err());

        // But string extraction should still work
        let string_result = bad_json_envelope.string_payload();
        assert!(string_result.is_ok());
        assert_eq!(string_result.unwrap(), "invalid json {");
    }
}
