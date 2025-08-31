//! End-to-end tests for the SW4RM Rust SDK
//! These tests verify complete message flows and component integration

use sw4rm_sdk::activity_buffer::{ActivityBuffer, PersistentActivityBuffer};
use sw4rm_sdk::persistence::JsonFilePersistence;
use sw4rm_sdk::prelude::*;
// TODO: Add back when implementing integration tests
// use sw4rm_sdk::ack_integration::{AckLifecycleManager, MessageProcessor};
// use sw4rm_sdk::clients::{RegistryClient, RouterClient};
use serde_json::json;
use tempfile::NamedTempFile;
use tokio::time::{sleep, Duration};

/// Test complete envelope lifecycle: create -> serialize -> deserialize -> process
#[tokio::test]
async fn test_envelope_complete_lifecycle() {
    let agent_id = "test-agent-lifecycle";

    // Create an envelope
    let original_data = json!({
        "message": "Hello SW4RM!",
        "metadata": {
            "sender": "test-client",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }
    });

    let envelope = EnvelopeBuilder::new(agent_id.to_string(), constants::message_type::DATA)
        .with_json_payload(&original_data)
        .unwrap()
        .with_repo_id("test-repo".to_string())
        .with_worktree_id("main".to_string())
        .with_ttl_ms(30000)
        .build();

    // Verify envelope structure
    assert_eq!(envelope.producer_id, agent_id);
    assert_eq!(envelope.message_type, constants::message_type::DATA);
    assert_eq!(envelope.content_type, "application/json");
    assert_eq!(envelope.repo_id, "test-repo");
    assert_eq!(envelope.worktree_id, "main");
    assert_eq!(envelope.ttl_ms, 30000);
    assert!(!envelope.message_id.is_empty());
    assert!(envelope.content_length > 0);

    // Test payload extraction
    let extracted_data: serde_json::Value = envelope.json_payload().unwrap();
    assert_eq!(extracted_data["message"], "Hello SW4RM!");
    assert_eq!(extracted_data["metadata"]["sender"], "test-client");

    // Test serialization round-trip through serde
    let serialized = serde_json::to_string(&envelope).unwrap();
    let deserialized: EnvelopeData = serde_json::from_str(&serialized).unwrap();

    assert_eq!(deserialized.message_id, envelope.message_id);
    assert_eq!(deserialized.producer_id, envelope.producer_id);
    assert_eq!(deserialized.payload, envelope.payload);
}

/// Test activity buffer with full ACK lifecycle
#[tokio::test]
async fn test_activity_buffer_ack_lifecycle() {
    let temp_file = NamedTempFile::new().unwrap();
    let persistence = Box::new(JsonFilePersistence::new(temp_file.path()));
    let buffer = PersistentActivityBuffer::new(100, Some(persistence)).unwrap();

    let agent_id = "test-agent-activity";

    // Create test messages
    let messages = vec![
        json!({
            "message_id": "msg-1",
            "producer_id": agent_id,
            "message_type": constants::message_type::DATA,
            "payload": "Message 1"
        }),
        json!({
            "message_id": "msg-2",
            "producer_id": agent_id,
            "message_type": constants::message_type::DATA,
            "payload": "Message 2"
        }),
        json!({
            "message_id": "msg-3",
            "producer_id": agent_id,
            "message_type": constants::message_type::TOOL_CALL,
            "payload": "Tool call"
        }),
    ];

    // Record incoming messages
    for msg in &messages {
        let record = buffer.record_incoming(msg.clone()).unwrap();
        assert_eq!(record.direction, "in");
        assert_eq!(
            record.ack_stage,
            constants::ack_stage::ACK_STAGE_UNSPECIFIED
        );
    }

    // Test unacked messages
    let unacked = buffer.unacked().unwrap();
    assert_eq!(unacked.len(), 3);

    // Process ACK lifecycle: RECEIVED -> READ -> FULFILLED
    for (i, msg) in messages.iter().enumerate() {
        let msg_id = msg["message_id"].as_str().unwrap();

        // Send RECEIVED ACK
        let received_ack = json!({
            "ack_for_message_id": msg_id,
            "ack_stage": constants::ack_stage::RECEIVED,
            "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
            "note": format!("Message {} received", i + 1)
        });

        let record = buffer.ack(&received_ack).unwrap().unwrap();
        assert_eq!(record.ack_stage, constants::ack_stage::RECEIVED);
        assert!(record.ack_note.contains("received"));

        // Send READ ACK
        let read_ack = json!({
            "ack_for_message_id": msg_id,
            "ack_stage": constants::ack_stage::READ,
            "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
            "note": format!("Message {} being processed", i + 1)
        });

        let record = buffer.ack(&read_ack).unwrap().unwrap();
        assert_eq!(record.ack_stage, constants::ack_stage::READ);

        // Send FULFILLED ACK for first two, REJECT third
        if i < 2 {
            let fulfilled_ack = json!({
                "ack_for_message_id": msg_id,
                "ack_stage": constants::ack_stage::FULFILLED,
                "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
                "note": format!("Message {} completed successfully", i + 1)
            });

            let record = buffer.ack(&fulfilled_ack).unwrap().unwrap();
            assert_eq!(record.ack_stage, constants::ack_stage::FULFILLED);
        } else {
            let rejected_ack = json!({
                "ack_for_message_id": msg_id,
                "ack_stage": constants::ack_stage::REJECTED,
                "error_code": constants::error_code::UNSUPPORTED_MESSAGE_TYPE,
                "note": "Tool calls not supported"
            });

            let record = buffer.ack(&rejected_ack).unwrap().unwrap();
            assert_eq!(record.ack_stage, constants::ack_stage::REJECTED);
            assert_eq!(
                record.error_code,
                constants::error_code::UNSUPPORTED_MESSAGE_TYPE
            );
        }
    }

    // Verify final state
    let final_unacked = buffer.unacked().unwrap();
    assert_eq!(final_unacked.len(), 0, "All messages should be acked");

    let recent = buffer.recent(10).unwrap();
    assert_eq!(recent.len(), 3);

    // Test persistence
    buffer.flush().unwrap();

    // Create new buffer and verify data persisted
    let new_persistence = Box::new(JsonFilePersistence::new(temp_file.path()));
    let new_buffer = PersistentActivityBuffer::new(100, Some(new_persistence)).unwrap();
    let loaded_recent = new_buffer.recent(10).unwrap();
    assert_eq!(loaded_recent.len(), 3);
}

/// Test message processing with automatic ACK handling
#[tokio::test]
async fn test_message_processor_ack_integration() {
    // Note: This test uses the in-memory buffer since we can't easily
    // create a real AckLifecycleManager without running gRPC services
    let mut buffer = ActivityBuffer::new(100);

    // Simulate incoming message
    let envelope = EnvelopeBuilder::new("sender".to_string(), constants::message_type::DATA)
        .with_json_payload(&json!({"test": "data"}))
        .unwrap()
        .build();

    let record = buffer
        .record_incoming(serde_json::to_value(&envelope).unwrap())
        .unwrap();
    assert_eq!(record.message_id, envelope.message_id);
    assert_eq!(record.direction, "in");

    // Test ACK generation
    let ack_envelope = sw4rm_sdk::acks::build_ack_envelope(
        "test-agent".to_string(),
        envelope.message_id.clone(),
        constants::ack_stage::RECEIVED,
        None,
        Some("Message received".to_string()),
        None,
        None,
    )
    .unwrap();

    assert_eq!(
        ack_envelope.message_type,
        constants::message_type::ACKNOWLEDGEMENT
    );
    assert_eq!(ack_envelope.producer_id, "test-agent");

    // Parse ACK payload
    let ack_payload: serde_json::Value = ack_envelope.json_payload().unwrap();
    assert_eq!(ack_payload["ack_for_message_id"], envelope.message_id);
    assert_eq!(ack_payload["ack_stage"], constants::ack_stage::RECEIVED);
    assert_eq!(ack_payload["note"], "Message received");
}

/// Test complete agent lifecycle (without real gRPC services)
#[tokio::test]
async fn test_agent_lifecycle_simulation() {
    struct TestAgent {
        config: AgentConfig,
        preemption: PreemptionManager,
        messages_processed: u32,
        last_message: Option<String>,
    }

    impl TestAgent {
        fn new(config: AgentConfig) -> Self {
            Self {
                config,
                preemption: PreemptionManager::new(),
                messages_processed: 0,
                last_message: None,
            }
        }
    }

    #[async_trait]
    impl Agent for TestAgent {
        async fn on_startup(&mut self) -> Result<()> {
            println!("Test agent starting: {}", self.config.agent_id);
            Ok(())
        }

        async fn on_shutdown(&mut self) -> Result<()> {
            println!(
                "Test agent shutting down: {} ({} messages processed)",
                self.config.agent_id, self.messages_processed
            );
            Ok(())
        }

        async fn on_message(&mut self, envelope: EnvelopeData) -> Result<()> {
            self.messages_processed += 1;

            if let Ok(text) = envelope.string_payload() {
                self.last_message = Some(text);
            }

            // Simulate processing time
            sleep(Duration::from_millis(10)).await;

            Ok(())
        }

        async fn on_control(&mut self, envelope: EnvelopeData) -> Result<()> {
            if let Ok(body) = envelope.json_payload::<serde_json::Value>() {
                if let Some(msg_type) = body.get("type").and_then(|v| v.as_str()) {
                    if msg_type == "SHUTDOWN" {
                        self.preemption
                            .request_preemption(Some("Shutdown requested".to_string()));
                    }
                }
            }
            Ok(())
        }

        fn config(&self) -> &AgentConfig {
            &self.config
        }

        fn preemption_manager(&self) -> &PreemptionManager {
            &self.preemption
        }
    }

    // Create agent
    let config = AgentConfig::new("test-agent-e2e".to_string(), "E2E Test Agent".to_string())
        .with_capabilities(vec!["test".to_string(), "simulation".to_string()]);

    let mut agent = TestAgent::new(config);

    // Test startup
    agent.on_startup().await.unwrap();
    assert_eq!(agent.messages_processed, 0);

    // Process some messages
    let messages = vec![
        EnvelopeBuilder::new("sender1".to_string(), constants::message_type::DATA)
            .with_payload(b"Hello from sender 1".to_vec())
            .build(),
        EnvelopeBuilder::new("sender2".to_string(), constants::message_type::DATA)
            .with_payload(b"Hello from sender 2".to_vec())
            .build(),
        EnvelopeBuilder::new("sender3".to_string(), constants::message_type::DATA)
            .with_json_payload(&json!({"greeting": "Hello from sender 3"}))
            .unwrap()
            .build(),
    ];

    for envelope in messages {
        agent.on_message(envelope).await.unwrap();
    }

    assert_eq!(agent.messages_processed, 3);
    assert!(agent.last_message.is_some());

    // Test control message
    let control_envelope =
        EnvelopeBuilder::new("controller".to_string(), constants::message_type::CONTROL)
            .with_json_payload(&json!({"type": "SHUTDOWN", "reason": "Test complete"}))
            .unwrap()
            .build();

    agent.on_control(control_envelope).await.unwrap();
    assert!(agent.preemption_manager().is_preemption_requested());

    // Test shutdown
    agent.on_shutdown().await.unwrap();
}

/// Test worktree state management integration
#[tokio::test]
async fn test_worktree_integration() {
    let temp_file = NamedTempFile::new().unwrap();
    let persistence = Box::new(sw4rm_sdk::worktree_state::JsonWorktreePersistence::new(
        temp_file.path(),
    ));
    let policy = Box::new(sw4rm_sdk::worktree_state::DefaultWorktreePolicy::new());

    let mut worktree_state =
        sw4rm_sdk::worktree_state::PersistentWorktreeState::new(Some(persistence), Some(policy))
            .unwrap();

    // Test initial state
    assert!(!worktree_state.is_bound());
    assert!(worktree_state.current().is_none());

    // Test binding
    assert!(worktree_state
        .bind(
            "test-repo".to_string(),
            "main-branch".to_string(),
            Some(std::collections::HashMap::from([
                ("commit".to_string(), "abc123".to_string()),
                ("author".to_string(), "test-user".to_string())
            ]))
        )
        .unwrap());

    assert!(worktree_state.is_bound());
    let binding = worktree_state.current().unwrap();
    assert_eq!(binding.repo_id, "test-repo");
    assert_eq!(binding.worktree_id, "main-branch");
    assert_eq!(binding.metadata.get("commit"), Some(&"abc123".to_string()));

    // Test status
    let status = worktree_state.status();
    assert_eq!(status["bound"], true);
    assert_eq!(status["repo_id"], "test-repo");
    assert_eq!(status["worktree_id"], "main-branch");

    // Test switching
    assert!(worktree_state
        .switch("test-repo".to_string(), "feature-branch".to_string(), None)
        .unwrap());

    let new_binding = worktree_state.current().unwrap();
    assert_eq!(new_binding.worktree_id, "feature-branch");

    // Test persistence across restart
    let new_persistence = Box::new(sw4rm_sdk::worktree_state::JsonWorktreePersistence::new(
        temp_file.path(),
    ));
    let new_policy = Box::new(sw4rm_sdk::worktree_state::DefaultWorktreePolicy::new());
    let restored_state = sw4rm_sdk::worktree_state::PersistentWorktreeState::new(
        Some(new_persistence),
        Some(new_policy),
    )
    .unwrap();

    assert!(restored_state.is_bound());
    let restored_binding = restored_state.current().unwrap();
    assert_eq!(restored_binding.repo_id, "test-repo");
    assert_eq!(restored_binding.worktree_id, "feature-branch");

    // Test unbinding
    let mut final_state = restored_state;
    assert!(final_state.unbind().unwrap());
    assert!(!final_state.is_bound());
}

/// Test error handling and recovery
#[tokio::test]
async fn test_error_handling_and_recovery() {
    // Test envelope with invalid JSON
    let envelope = EnvelopeBuilder::new("test".to_string(), constants::message_type::DATA)
        .with_payload(b"invalid json {".to_vec())
        .with_content_type("application/json".to_string())
        .build();

    let json_result: serde_json::Result<serde_json::Value> = envelope.json_payload();
    assert!(json_result.is_err());

    // Test string fallback
    let string_result = envelope.string_payload();
    assert!(string_result.is_ok());
    assert_eq!(string_result.unwrap(), "invalid json {");

    // Test ACK error mapping
    let timeout_error = Error::Timeout("Connection timed out".to_string());
    assert_eq!(
        sw4rm_sdk::acks::map_error_to_error_code(&timeout_error),
        constants::error_code::ACK_TIMEOUT
    );

    let connection_error = Error::Connection("No route to host".to_string());
    assert_eq!(
        sw4rm_sdk::acks::map_error_to_error_code(&connection_error),
        constants::error_code::NO_ROUTE
    );

    // Test activity buffer with invalid data
    let mut buffer = ActivityBuffer::new(10);

    let invalid_envelope = json!({
        "invalid": "no message_id field"
    });

    let result = buffer.record_incoming(invalid_envelope);
    assert!(result.is_err());

    // Test ACK for non-existent message
    let nonexistent_ack = json!({
        "ack_for_message_id": "does-not-exist",
        "ack_stage": constants::ack_stage::RECEIVED,
        "error_code": constants::error_code::ERROR_CODE_UNSPECIFIED,
        "note": "Test ACK"
    });

    let ack_result = buffer.ack(&nonexistent_ack);
    assert!(ack_result.is_none());
}
