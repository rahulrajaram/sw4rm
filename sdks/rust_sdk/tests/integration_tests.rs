//! Integration tests for the SW4RM Rust SDK

use sw4rm_sdk::*;
use tempfile::NamedTempFile;
use serde_json::json;

#[cfg(test)]
mod envelope_tests {
    use super::*;

    #[test]
    fn test_envelope_builder() {
        let envelope = EnvelopeBuilder::new("test-producer".to_string(), constants::message_type::DATA)
            .with_content_type("application/json".to_string())
            .with_json_payload(&json!({"test": "data"}))
            .unwrap()
            .with_repo_id("repo-123".to_string())
            .with_worktree_id("tree-456".to_string())
            .with_ttl_ms(30000)
            .build();

        assert_eq!(envelope.producer_id, "test-producer");
        assert_eq!(envelope.message_type, constants::message_type::DATA);
        assert_eq!(envelope.content_type, "application/json");
        assert_eq!(envelope.repo_id, "repo-123");
        assert_eq!(envelope.worktree_id, "tree-456");
        assert_eq!(envelope.ttl_ms, 30000);
        assert!(!envelope.message_id.is_empty());
        assert!(!envelope.correlation_id.is_empty());
        assert!(envelope.content_length > 0);

        // Verify payload can be parsed back
        let parsed: serde_json::Value = envelope.json_payload().unwrap();
        assert_eq!(parsed["test"], "data");
    }

    #[test]
    fn test_envelope_string_payload() {
        let test_data = "Hello, SW4RM!";
        let envelope = EnvelopeBuilder::new("test".to_string(), constants::message_type::DATA)
            .with_payload(test_data.as_bytes().to_vec())
            .build();

        assert_eq!(envelope.string_payload().unwrap(), test_data);
    }
}

#[cfg(test)]
mod activity_buffer_tests {
    use super::*;
    use sw4rm_sdk::activity_buffer::*;
    use sw4rm_sdk::persistence::JsonFilePersistence;

    #[test]
    fn test_in_memory_activity_buffer() {
        let mut buffer = ActivityBuffer::new(10);

        // Test incoming message
        let envelope = json!({
            "message_id": "test-msg-1",
            "producer_id": "test-agent",
            "message_type": constants::message_type::DATA,
            "payload": "test data"
        });

        let record = buffer.record_incoming(envelope).unwrap();
        assert_eq!(record.message_id, "test-msg-1");
        assert_eq!(record.direction, "in");

        // Test ACK processing
        let ack = json!({
            "ack_for_message_id": "test-msg-1",
            "ack_stage": constants::ack_stage::RECEIVED,
            "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
            "note": "Received successfully"
        });

        let updated = buffer.ack(&ack);
        assert!(updated.is_some());
        assert_eq!(updated.unwrap().ack_stage, constants::ack_stage::RECEIVED);

        // Test retrieval
        let retrieved = buffer.get("test-msg-1").unwrap();
        assert_eq!(retrieved.ack_stage, constants::ack_stage::RECEIVED);
        assert_eq!(retrieved.ack_note, "Received successfully");
    }

    #[test]
    fn test_persistent_activity_buffer() {
        let temp_file = NamedTempFile::new().unwrap();
        let persistence = Box::new(JsonFilePersistence::new(temp_file.path()));
        let buffer = PersistentActivityBuffer::new(10, Some(persistence)).unwrap();

        // Record a message
        let envelope = json!({
            "message_id": "persistent-test",
            "producer_id": "test-agent",
            "message_type": constants::message_type::DATA,
            "payload": "persistent data"
        });

        let record = buffer.record_incoming(envelope).unwrap();
        assert_eq!(record.message_id, "persistent-test");

        // Flush to persistence
        buffer.flush().unwrap();

        // Create new buffer to test persistence using same file path
        let persistence2 = Box::new(JsonFilePersistence::new(temp_file.path()));
        let buffer2 = PersistentActivityBuffer::new(10, Some(persistence2)).unwrap();

        // Should be able to retrieve the previously recorded message
        let retrieved = buffer2.get("persistent-test").unwrap();
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().message_id, "persistent-test");
    }

    #[test]
    fn test_buffer_pruning() {
        let mut buffer = ActivityBuffer::new(3); // Small buffer for testing

        // Add more messages than the buffer can hold
        for i in 1..=5 {
            let envelope = json!({
                "message_id": format!("msg-{}", i),
                "producer_id": "test-agent",
                "message_type": constants::message_type::DATA
            });
            buffer.record_incoming(envelope).unwrap();
        }

        // Should only have the last 3 messages
        assert!(buffer.get("msg-1").is_none());
        assert!(buffer.get("msg-2").is_none());
        assert!(buffer.get("msg-3").is_some());
        assert!(buffer.get("msg-4").is_some());
        assert!(buffer.get("msg-5").is_some());
    }
}

#[cfg(test)]
mod acks_tests {
    use super::*;
    use sw4rm_sdk::acks::*;

    #[test]
    fn test_build_ack() {
        let ack = build_ack(
            "original-message-id".to_string(),
            constants::ack_stage::FULFILLED,
            constants::error_code::ERROR_CODE_UNSPECIFIED,
            "Processing completed".to_string(),
        );

        assert_eq!(ack["ack_for_message_id"], "original-message-id");
        assert_eq!(ack["ack_stage"], constants::ack_stage::FULFILLED);
        assert_eq!(ack["error_code"], constants::error_code::ERROR_CODE_UNSPECIFIED);
        assert_eq!(ack["note"], "Processing completed");
    }

    #[test]
    fn test_build_ack_envelope() {
        let envelope = build_ack_envelope(
            "ack-producer".to_string(),
            "target-message".to_string(),
            constants::ack_stage::REJECTED,
            Some(constants::error_code::VALIDATION_ERROR),
            Some("Invalid input".to_string()),
            None,
            None,
        ).unwrap();

        assert_eq!(envelope.producer_id, "ack-producer");
        assert_eq!(envelope.message_type, constants::message_type::ACKNOWLEDGEMENT);
        assert_eq!(envelope.content_type, "application/json");

        // Parse and verify ACK payload
        let ack_payload: serde_json::Value = envelope.json_payload().unwrap();
        assert_eq!(ack_payload["ack_for_message_id"], "target-message");
        assert_eq!(ack_payload["ack_stage"], constants::ack_stage::REJECTED);
        assert_eq!(ack_payload["error_code"], constants::error_code::VALIDATION_ERROR);
        assert_eq!(ack_payload["note"], "Invalid input");
    }

    #[test]
    fn test_ack_for_send_result() {
        // Test successful result
        let success_ack = ack_for_send_result(
            "producer".to_string(),
            "original-msg".to_string(),
            true,
            "Success".to_string(),
        ).unwrap();

        let payload: serde_json::Value = success_ack.json_payload().unwrap();
        assert_eq!(payload["ack_stage"], constants::ack_stage::FULFILLED);
        assert_eq!(payload["error_code"], constants::error_code::ERROR_CODE_UNSPECIFIED);

        // Test failed result
        let failed_ack = ack_for_send_result(
            "producer".to_string(),
            "original-msg".to_string(),
            false,
            "Validation failed".to_string(),
        ).unwrap();

        let payload: serde_json::Value = failed_ack.json_payload().unwrap();
        assert_eq!(payload["ack_stage"], constants::ack_stage::REJECTED);
        assert_eq!(payload["error_code"], constants::error_code::VALIDATION_ERROR);
    }

    #[test]
    fn test_error_mapping() {
        let timeout_error = Error::Timeout("Request timed out".to_string());
        assert_eq!(map_error_to_error_code(&timeout_error), constants::error_code::ACK_TIMEOUT);

        let connection_error = Error::Connection("Failed to connect".to_string());
        assert_eq!(map_error_to_error_code(&connection_error), constants::error_code::NO_ROUTE);

        let validation_error = Error::InvalidEnvelope("Invalid message".to_string());
        assert_eq!(map_error_to_error_code(&validation_error), constants::error_code::VALIDATION_ERROR);
    }
}

#[cfg(test)]
mod worktree_tests {
    use super::*;
    use sw4rm_sdk::worktree_state::*;
    use std::collections::HashMap;

    #[test]
    fn test_worktree_binding() {
        let mut metadata = HashMap::new();
        metadata.insert("branch".to_string(), "main".to_string());

        let binding = WorktreeBinding::new("repo-1".to_string(), "tree-1".to_string())
            .with_metadata(metadata);

        assert_eq!(binding.repo_id, "repo-1");
        assert_eq!(binding.worktree_id, "tree-1");
        assert_eq!(binding.metadata.get("branch"), Some(&"main".to_string()));
        assert!(binding.bound_at > 0);
    }

    #[test]
    fn test_default_worktree_policy() {
        let policy = DefaultWorktreePolicy::new();

        // Should allow initial binding
        assert!(policy.before_bind("repo", "tree", None));

        // Should reject empty inputs
        assert!(!policy.before_bind("", "tree", None));
        assert!(!policy.before_bind("repo", "", None));

        let existing_binding = WorktreeBinding::new("old-repo".to_string(), "old-tree".to_string());

        // Should allow rebinding by default
        assert!(policy.before_bind("new-repo", "new-tree", Some(&existing_binding)));

        // Should always allow unbinding
        assert!(policy.before_unbind(&existing_binding));

        // Test non-rebinding policy
        let strict_policy = DefaultWorktreePolicy::new().with_rebinding(false);
        assert!(!strict_policy.before_bind("new-repo", "new-tree", Some(&existing_binding)));
    }

    #[test]
    fn test_json_worktree_persistence() {
        let temp_file = NamedTempFile::new().unwrap();
        let mut persistence = JsonWorktreePersistence::new(temp_file.path());

        // Test saving and loading
        let binding = WorktreeBinding::new("test-repo".to_string(), "test-tree".to_string());
        persistence.save_binding(Some(&binding)).unwrap();

        let loaded = persistence.load_binding().unwrap().unwrap();
        assert_eq!(loaded.repo_id, "test-repo");
        assert_eq!(loaded.worktree_id, "test-tree");

        // Test clearing
        persistence.clear().unwrap();
        let after_clear = persistence.load_binding().unwrap();
        assert!(after_clear.is_none());
    }

    #[test]
    fn test_persistent_worktree_state() {
        let temp_file = NamedTempFile::new().unwrap();
        let persistence = Box::new(JsonWorktreePersistence::new(temp_file.path()));
        let policy = Box::new(DefaultWorktreePolicy::new());

        let mut state = PersistentWorktreeState::new(Some(persistence), Some(policy)).unwrap();

        // Test binding
        assert!(!state.is_bound());
        assert!(state.bind("repo-1".to_string(), "tree-1".to_string(), None).unwrap());
        assert!(state.is_bound());

        let current = state.current().unwrap();
        assert_eq!(current.repo_id, "repo-1");
        assert_eq!(current.worktree_id, "tree-1");

        // Test status
        let status = state.status();
        assert_eq!(status["bound"], true);
        assert_eq!(status["repo_id"], "repo-1");

        // Test unbinding
        assert!(state.unbind().unwrap());
        assert!(!state.is_bound());
        assert!(state.current().is_none());

        // Test switching
        assert!(state.switch("repo-2".to_string(), "tree-2".to_string(), None).unwrap());
        assert!(state.is_bound());
        assert_eq!(state.current().unwrap().repo_id, "repo-2");
    }
}

#[cfg(test)]
mod config_tests {
    use super::*;

    #[test]
    fn test_agent_config() {
        let config = AgentConfig::new("test-agent".to_string(), "Test Agent".to_string())
            .with_description("A test agent for SW4RM".to_string())
            .with_capabilities(vec!["test".to_string(), "demo".to_string()]);

        assert_eq!(config.agent_id, "test-agent");
        assert_eq!(config.name, "Test Agent");
        assert_eq!(config.description, Some("A test agent for SW4RM".to_string()));
        assert_eq!(config.capabilities, vec!["test", "demo"]);
        assert_eq!(config.version, "0.1.0");
    }

    #[test]
    fn test_endpoints_default() {
        let endpoints = Endpoints::default();
        
        assert_eq!(endpoints.registry, "http://localhost:50051");
        assert_eq!(endpoints.router, "http://localhost:50052");
        assert_eq!(endpoints.scheduler, "http://localhost:50053");
        assert_eq!(endpoints.hitl, "http://localhost:50054");
        assert_eq!(endpoints.worktree, "http://localhost:50055");
    }
}

#[cfg(test)]
mod constants_tests {
    use super::*;
    use sw4rm_sdk::constants::*;

    #[test]
    fn test_message_type_constants() {
        assert_eq!(message_type::CONTROL, 1);
        assert_eq!(message_type::DATA, 2);
        assert_eq!(message_type::ACKNOWLEDGEMENT, 5);
        assert_eq!(message_type::TOOL_CALL, 9);
    }

    #[test]
    fn test_ack_stage_constants() {
        assert_eq!(ack_stage::RECEIVED, 1);
        assert_eq!(ack_stage::READ, 2);
        assert_eq!(ack_stage::FULFILLED, 3);
        assert_eq!(ack_stage::REJECTED, 4);
        assert_eq!(ack_stage::FAILED, 5);
    }

    #[test]
    fn test_error_code_constants() {
        assert_eq!(error_code::BUFFER_FULL, 1);
        assert_eq!(error_code::NO_ROUTE, 2);
        assert_eq!(error_code::ACK_TIMEOUT, 3);
        assert_eq!(error_code::VALIDATION_ERROR, 6);
        assert_eq!(error_code::INTERNAL_ERROR, 99);
    }
}

#[cfg(test)]
mod types_tests {
    use super::*;

    #[test]
    fn test_sequence_tracker() {
        let tracker = SequenceTracker::new(10);
        
        assert_eq!(tracker.next(), 10);
        assert_eq!(tracker.next(), 11);
        assert_eq!(tracker.next(), 12);
    }

    #[test]
    fn test_uuid_generation() {
        let uuid1 = new_uuid();
        let uuid2 = new_uuid();
        
        assert_ne!(uuid1, uuid2);
        assert_eq!(uuid1.len(), 36); // Standard UUID length with hyphens
    }

    #[test]
    fn test_hlc_timestamp() {
        let ts1 = now_hlc_stub();
        std::thread::sleep(std::time::Duration::from_millis(1));
        let ts2 = now_hlc_stub();
        
        // Should be different timestamps
        assert_ne!(ts1, ts2);
        
        // Should be numeric strings
        assert!(ts1.parse::<i64>().is_ok());
        assert!(ts2.parse::<i64>().is_ok());
    }

    #[test]
    fn test_idempotency_token() {
        let token = make_idempotency_token("agent-1", "send", "hash123");
        assert_eq!(token, "agent-1:send:hash123");
    }
}
