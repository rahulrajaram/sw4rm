//! Comprehensive unit tests for envelope operations

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
        assert!(!envelope.idempotency_token.is_empty());
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
        assert_eq!(envelope.content_length, test_payload.len() as i64);
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
    fn test_envelope_builder_with_string_payload() {
        let test_string = "Hello, String World!";
        let envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_string_payload(test_string)
        .build();

        assert_eq!(envelope.content_type, "text/plain");
        assert_eq!(envelope.content_length, test_string.len() as i64);

        let retrieved_string = envelope.string_payload().unwrap();
        assert_eq!(retrieved_string, test_string);
    }

    #[test]
    fn test_envelope_builder_chaining() {
        let test_data = json!({"test": "data"});
        
        let envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_json_payload(&test_data).unwrap()
        .with_repo_id("test-repo".to_string())
        .with_worktree_id("main".to_string())
        .with_correlation_id("corr-123".to_string())
        .with_ttl_ms(60000)
        .with_content_type("application/json".to_string())
        .build();

        assert_eq!(envelope.repo_id, "test-repo");
        assert_eq!(envelope.worktree_id, "main");
        assert_eq!(envelope.correlation_id, "corr-123");
        assert_eq!(envelope.ttl_ms, 60000);
        assert_eq!(envelope.content_type, "application/json");
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
        .with_repo_id("test-repo".to_string())
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
        assert_eq!(deserialized.repo_id, envelope.repo_id);
        assert_eq!(deserialized.content_type, envelope.content_type);
        assert_eq!(deserialized.content_length, envelope.content_length);

        // Verify payload content is preserved
        let original_payload: serde_json::Value = envelope.json_payload().unwrap();
        let deserialized_payload: serde_json::Value = deserialized.json_payload().unwrap();
        assert_eq!(original_payload, deserialized_payload);
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

        // Test with string payload
        let string_data = "Plain text message";
        let string_envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_string_payload(string_data)
        .build();

        let extracted_string = string_envelope.string_payload().unwrap();
        assert_eq!(extracted_string, string_data);

        // Test with raw bytes
        let byte_data = b"Raw binary data";
        let byte_envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_payload(byte_data.to_vec())
        .build();

        assert_eq!(byte_envelope.payload, byte_data.to_vec());
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

    #[test]
    fn test_envelope_clone_and_debug() {
        let envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_string_payload("Test message")
        .build();

        // Test Clone
        let cloned = envelope.clone();
        assert_eq!(envelope.message_id, cloned.message_id);
        assert_eq!(envelope.payload, cloned.payload);

        // Test Debug output contains expected fields
        let debug_str = format!("{:?}", envelope);
        assert!(debug_str.contains("message_id"));
        assert!(debug_str.contains("producer_id"));
    }

    #[test]
    fn test_envelope_unique_identifiers() {
        let envelope1 = EnvelopeBuilder::new(
            "agent1".to_string(),
            crate::constants::message_type::DATA
        ).build();

        let envelope2 = EnvelopeBuilder::new(
            "agent1".to_string(),  // Same agent
            crate::constants::message_type::DATA
        ).build();

        // Message IDs should be unique
        assert_ne!(envelope1.message_id, envelope2.message_id);
        
        // Idempotency tokens should be unique
        assert_ne!(envelope1.idempotency_token, envelope2.idempotency_token);
        
        // Sequence numbers should increment
        assert_ne!(envelope1.sequence_number, envelope2.sequence_number);
    }

    #[test]
    fn test_envelope_timestamps() {
        let envelope1 = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        ).build();

        // Small delay to ensure different timestamps
        std::thread::sleep(std::time::Duration::from_millis(1));

        let envelope2 = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        ).build();

        // HLC timestamps should be different
        assert_ne!(envelope1.hlc_timestamp, envelope2.hlc_timestamp);
    }

    #[test]
    fn test_envelope_content_types() {
        // Test various content types are set correctly
        let json_env = EnvelopeBuilder::new("agent".to_string(), 1)
            .with_json_payload(&json!({}))
            .unwrap()
            .build();
        assert_eq!(json_env.content_type, "application/json");

        let string_env = EnvelopeBuilder::new("agent".to_string(), 1)
            .with_string_payload("test")
            .build();
        assert_eq!(string_env.content_type, "text/plain");

        let binary_env = EnvelopeBuilder::new("agent".to_string(), 1)
            .with_payload(vec![0x01, 0x02])
            .build();
        assert_eq!(binary_env.content_type, "application/octet-stream");

        // Test custom content type override
        let custom_env = EnvelopeBuilder::new("agent".to_string(), 1)
            .with_payload(vec![])
            .with_content_type("application/custom".to_string())
            .build();
        assert_eq!(custom_env.content_type, "application/custom");
    }

    #[test]
    fn test_envelope_large_payloads() {
        // Test with larger payloads
        let large_data = "x".repeat(10_000);
        let envelope = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_string_payload(&large_data)
        .build();

        assert_eq!(envelope.content_length, 10_000);
        assert_eq!(envelope.string_payload().unwrap(), large_data);

        // Test serialization still works
        let serialized = serde_json::to_string(&envelope).unwrap();
        let deserialized: EnvelopeData = serde_json::from_str(&serialized).unwrap();
        assert_eq!(deserialized.string_payload().unwrap(), large_data);
    }

    #[test]  
    fn test_envelope_edge_cases() {
        // Empty payload
        let empty_env = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_payload(Vec::new())
        .build();
        
        assert_eq!(empty_env.payload.len(), 0);
        assert_eq!(empty_env.content_length, 0);

        // Empty string payload
        let empty_string_env = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_string_payload("")
        .build();
        
        assert_eq!(empty_string_env.string_payload().unwrap(), "");
        assert_eq!(empty_string_env.content_length, 0);

        // Empty JSON object
        let empty_json_env = EnvelopeBuilder::new(
            "test-agent".to_string(),
            crate::constants::message_type::DATA
        )
        .with_json_payload(&json!({}))
        .unwrap()
        .build();
        
        let extracted: serde_json::Value = empty_json_env.json_payload().unwrap();
        assert_eq!(extracted, json!({}));
    }
}