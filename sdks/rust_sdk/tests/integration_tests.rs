//! Integration tests for the SW4RM Rust SDK

use serde_json::json;
use sw4rm_sdk::*;
use tempfile::NamedTempFile;

#[cfg(test)]
mod envelope_tests {
    use super::*;

    #[test]
    fn test_envelope_builder() {
        let envelope =
            EnvelopeBuilder::new("test-producer".to_string(), constants::message_type::DATA)
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
    fn test_buffer_rejects_when_full() {
        let mut buffer = ActivityBuffer::new(3); // Small buffer for testing

        // Fill to capacity
        for i in 1..=3 {
            let envelope = json!({
                "message_id": format!("msg-{}", i),
                "producer_id": "test-agent",
                "message_type": constants::message_type::DATA
            });
            buffer.record_incoming(envelope).unwrap();
        }

        // Next insert should be rejected with BufferFull
        let envelope = json!({
            "message_id": "msg-4",
            "producer_id": "test-agent",
            "message_type": constants::message_type::DATA
        });
        let result = buffer.record_incoming(envelope);
        assert!(result.is_err());

        // Original messages should still be present
        assert!(buffer.get("msg-1").is_some());
        assert!(buffer.get("msg-2").is_some());
        assert!(buffer.get("msg-3").is_some());
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
        assert_eq!(
            ack["error_code"],
            constants::error_code::ERROR_CODE_UNSPECIFIED
        );
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
        )
        .unwrap();

        assert_eq!(envelope.producer_id, "ack-producer");
        assert_eq!(
            envelope.message_type,
            constants::message_type::ACKNOWLEDGEMENT
        );
        assert_eq!(envelope.content_type, "application/json");

        // Parse and verify ACK payload
        let ack_payload: serde_json::Value = envelope.json_payload().unwrap();
        assert_eq!(ack_payload["ack_for_message_id"], "target-message");
        assert_eq!(ack_payload["ack_stage"], constants::ack_stage::REJECTED);
        assert_eq!(
            ack_payload["error_code"],
            constants::error_code::VALIDATION_ERROR
        );
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
        )
        .unwrap();

        let payload: serde_json::Value = success_ack.json_payload().unwrap();
        assert_eq!(payload["ack_stage"], constants::ack_stage::FULFILLED);
        assert_eq!(
            payload["error_code"],
            constants::error_code::ERROR_CODE_UNSPECIFIED
        );

        // Test failed result
        let failed_ack = ack_for_send_result(
            "producer".to_string(),
            "original-msg".to_string(),
            false,
            "Validation failed".to_string(),
        )
        .unwrap();

        let payload: serde_json::Value = failed_ack.json_payload().unwrap();
        assert_eq!(payload["ack_stage"], constants::ack_stage::REJECTED);
        assert_eq!(
            payload["error_code"],
            constants::error_code::VALIDATION_ERROR
        );
    }

    #[test]
    fn test_error_mapping() {
        let timeout_error = Error::Timeout("Request timed out".to_string());
        assert_eq!(
            map_error_to_error_code(&timeout_error),
            constants::error_code::ACK_TIMEOUT
        );

        let connection_error = Error::Connection("Failed to connect".to_string());
        assert_eq!(
            map_error_to_error_code(&connection_error),
            constants::error_code::NO_ROUTE
        );

        let validation_error = Error::InvalidEnvelope("Invalid message".to_string());
        assert_eq!(
            map_error_to_error_code(&validation_error),
            constants::error_code::VALIDATION_ERROR
        );
    }
}

#[cfg(test)]
mod worktree_tests {
    use super::*;
    use std::collections::HashMap;
    use sw4rm_sdk::worktree_state::*;

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
        assert!(state
            .bind("repo-1".to_string(), "tree-1".to_string(), None)
            .unwrap());
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
        assert!(state
            .switch("repo-2".to_string(), "tree-2".to_string(), None)
            .unwrap());
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
        assert_eq!(
            config.description,
            Some("A test agent for SW4RM".to_string())
        );
        assert_eq!(config.capabilities, vec!["test", "demo"]);
        assert_eq!(config.version, "0.1.0");
    }

    #[test]
    fn test_endpoints_default() {
        let endpoints = Endpoints::default();

        assert_eq!(endpoints.registry, "http://localhost:50052");
        assert_eq!(endpoints.router, "http://localhost:50051");
        assert_eq!(endpoints.scheduler, "http://localhost:50053");
        assert_eq!(endpoints.hitl, "http://localhost:50054");
        assert_eq!(endpoints.worktree, "http://localhost:50055");
    }
}

#[cfg(test)]
mod constants_tests {
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
        std::thread::sleep(std::time::Duration::from_millis(2));
        let ts2 = now_hlc_stub();

        // Should be different timestamps
        assert_ne!(ts1, ts2);

        // Should follow HLC:<wall>:<logical>:<node> format
        assert!(ts1.starts_with("HLC:"));
        let parts: Vec<&str> = ts1.split(':').collect();
        assert_eq!(parts.len(), 4);
        assert!(parts[1].parse::<i64>().is_ok());
        assert_eq!(parts[2], "0");
    }

    #[test]
    fn test_idempotency_token() {
        let token = make_idempotency_token("agent-1", "send", "hash123");
        assert_eq!(token, "agent-1:send:hash123");
    }
}

#[cfg(test)]
mod delegation_tests {
    use serde::Deserialize;
    use std::collections::HashMap;
    use std::cell::Cell;
    use std::rc::Rc;
    use sw4rm_sdk::clients::handoff::{
        BudgetEnvelope, HandoffRequest, HandoffResponse, HandoffStatus, SwarmDelegationPolicy,
        REJECTION_CODE_OVERLOADED, REJECTION_CODE_REDIRECT,
    };
    use sw4rm_sdk::clients::{delegate_to_swarm_with_runtime, DelegateToSwarmOptions};
    use sw4rm_sdk::constants;

    #[derive(Debug, Deserialize)]
    struct VectorSuite {
        vectors: Vec<DelegationVector>,
    }

    #[derive(Debug, Deserialize)]
    struct DelegationVector {
        id: String,
        request_id: String,
        from_agent: String,
        to_agent: String,
        reason: String,
        budget: VectorBudget,
        policy: VectorPolicy,
        redirect_map: HashMap<String, String>,
        expected: VectorExpected,
    }

    #[derive(Debug, Deserialize)]
    struct VectorBudget {
        deadline_epoch_ms: u64,
        wall_time_remaining_ms: u64,
    }

    #[derive(Debug, Deserialize)]
    struct VectorPolicy {
        allow_spillover_routing: bool,
        max_redirects: u32,
    }

    #[derive(Debug, Deserialize)]
    struct VectorExpected {
        accepted: bool,
        rejection_code: String,
        attempts: Vec<String>,
        reason_contains: Option<String>,
        redirect_to_agent_id: Option<String>,
    }

    fn load_shared_vectors() -> VectorSuite {
        serde_json::from_str(include_str!(
            "../../../tests/conformance_vectors/sw4_005_delegation_vectors.json"
        ))
        .expect("shared conformance vectors should parse")
    }

    fn rejection_code_from_name(name: &str) -> i32 {
        match name {
            "VALIDATION_ERROR" => constants::error_code::VALIDATION_ERROR,
            "REDIRECT" => REJECTION_CODE_REDIRECT,
            other => panic!("unsupported rejection_code in vector: {other}"),
        }
    }

    fn redirect_response(request: &HandoffRequest, target: &str) -> HandoffResponse {
        HandoffResponse {
            accepted: false,
            handoff_id: request.request_id.clone(),
            rejection_reason: None,
            accepting_agent: None,
            rejection_code: Some(REJECTION_CODE_REDIRECT),
            retry_after_ms: None,
            redirect_to_agent_id: Some(target.to_string()),
            status: HandoffStatus::Rejected,
            metadata: std::collections::HashMap::new(),
        }
    }

    #[test]
    fn test_delegate_to_swarm_shared_conformance_vectors() {
        let suite = load_shared_vectors();
        for vector in suite.vectors {
            let mut attempts = Vec::new();
            let redirect_map = vector.redirect_map.clone();

            let options = DelegateToSwarmOptions::new(
                vector.from_agent.clone(),
                vector.to_agent.clone(),
                vector.reason.clone(),
                BudgetEnvelope {
                    token_budget_remaining: None,
                    wall_time_remaining_ms: Some(vector.budget.wall_time_remaining_ms),
                    deadline_epoch_ms: vector.budget.deadline_epoch_ms,
                    current_depth: None,
                    max_delegation_depth: None,
                },
            )
            .with_request_id(vector.request_id.clone())
            .with_delegation_policy(SwarmDelegationPolicy {
                allow_spillover_routing: vector.policy.allow_spillover_routing,
                max_redirects: vector.policy.max_redirects,
                ..SwarmDelegationPolicy::default()
            });

            let now_ms = vector.budget.deadline_epoch_ms.saturating_sub(1_000);
            let response = delegate_to_swarm_with_runtime(
                options,
                |request| {
                    attempts.push(request.to_agent.clone());
                    let target = redirect_map
                        .get(&request.to_agent)
                        .unwrap_or_else(|| panic!("vector '{}' missing redirect target", vector.id));
                    Ok(redirect_response(request, target))
                },
                move || now_ms,
                |_milliseconds| Ok(()),
                |_low, high| high,
            )
            .unwrap_or_else(|err| panic!("vector '{}' returned error: {err}", vector.id));

            assert_eq!(
                response.accepted, vector.expected.accepted,
                "vector '{}' accepted mismatch",
                vector.id
            );
            assert_eq!(
                response.rejection_code,
                Some(rejection_code_from_name(&vector.expected.rejection_code)),
                "vector '{}' rejection code mismatch",
                vector.id
            );
            assert_eq!(
                attempts, vector.expected.attempts,
                "vector '{}' attempts mismatch",
                vector.id
            );
            if let Some(reason_contains) = &vector.expected.reason_contains {
                let reason = response.rejection_reason.clone().unwrap_or_default();
                assert!(
                    reason.to_lowercase().contains(&reason_contains.to_lowercase()),
                    "vector '{}' expected rejection reason to contain '{}', got '{}'",
                    vector.id,
                    reason_contains,
                    reason
                );
            }
            if let Some(redirect_to_agent_id) = &vector.expected.redirect_to_agent_id {
                assert_eq!(
                    response.redirect_to_agent_id.as_deref(),
                    Some(redirect_to_agent_id.as_str()),
                    "vector '{}' redirect target mismatch",
                    vector.id
                );
            }
        }
    }

    #[test]
    fn test_delegate_to_swarm_rejects_redirect_loop() {
        let mut attempts = Vec::new();
        let options = DelegateToSwarmOptions::new(
            "parent".to_string(),
            "gateway-a".to_string(),
            "delegate".to_string(),
            BudgetEnvelope {
                token_budget_remaining: None,
                wall_time_remaining_ms: Some(10_000),
                deadline_epoch_ms: 1_000_000,
                current_depth: None,
                max_delegation_depth: None,
            },
        )
        .with_request_id("req-loop".to_string())
        .with_delegation_policy(SwarmDelegationPolicy {
            allow_spillover_routing: true,
            max_redirects: 4,
            ..SwarmDelegationPolicy::default()
        });

        let response = delegate_to_swarm_with_runtime(
            options,
            |request| {
                attempts.push(request.to_agent.clone());
                if request.to_agent == "gateway-a" {
                    return Ok(redirect_response(request, "gateway-b"));
                }
                Ok(redirect_response(request, "gateway-a"))
            },
            || 500_000,
            |_milliseconds| Ok(()),
            |_low, high| high,
        )
        .unwrap();

        assert!(!response.accepted);
        assert_eq!(
            response.rejection_code,
            Some(constants::error_code::VALIDATION_ERROR)
        );
        assert!(response
            .rejection_reason
            .unwrap_or_default()
            .to_lowercase()
            .contains("loop"));
        assert_eq!(attempts, vec!["gateway-a", "gateway-b"]);
    }

    #[test]
    fn test_delegate_to_swarm_enforces_effective_default_redirect_bound() {
        let mut attempts = Vec::new();
        let options = DelegateToSwarmOptions::new(
            "parent".to_string(),
            "gateway-a".to_string(),
            "delegate".to_string(),
            BudgetEnvelope {
                token_budget_remaining: None,
                wall_time_remaining_ms: Some(10_000),
                deadline_epoch_ms: 2_000_000,
                current_depth: None,
                max_delegation_depth: None,
            },
        )
        .with_request_id("req-default-bound".to_string())
        .with_delegation_policy(SwarmDelegationPolicy {
            allow_spillover_routing: true,
            max_redirects: 0,
            ..SwarmDelegationPolicy::default()
        });

        let response = delegate_to_swarm_with_runtime(
            options,
            |request| {
                attempts.push(request.to_agent.clone());
                let target = match request.to_agent.as_str() {
                    "gateway-a" => "gateway-b",
                    "gateway-b" => "gateway-c",
                    _ => "gateway-d",
                };
                Ok(redirect_response(request, target))
            },
            || 1_500_000,
            |_milliseconds| Ok(()),
            |_low, high| high,
        )
        .unwrap();

        assert!(!response.accepted);
        assert_eq!(response.rejection_code, Some(REJECTION_CODE_REDIRECT));
        assert_eq!(attempts, vec!["gateway-a", "gateway-b", "gateway-c"]);
    }

    #[test]
    fn test_delegate_to_swarm_fallback_when_spillover_disabled() {
        let mut attempts = Vec::new();
        let options = DelegateToSwarmOptions::new(
            "parent".to_string(),
            "gateway-a".to_string(),
            "delegate".to_string(),
            BudgetEnvelope {
                token_budget_remaining: None,
                wall_time_remaining_ms: Some(10_000),
                deadline_epoch_ms: 2_000_000,
                current_depth: None,
                max_delegation_depth: None,
            },
        )
        .with_request_id("req-no-spillover".to_string())
        .with_delegation_policy(SwarmDelegationPolicy {
            allow_spillover_routing: false,
            max_redirects: 5,
            ..SwarmDelegationPolicy::default()
        });

        let response = delegate_to_swarm_with_runtime(
            options,
            |request| {
                attempts.push(request.to_agent.clone());
                Ok(redirect_response(request, "gateway-b"))
            },
            || 1_500_000,
            |_milliseconds| Ok(()),
            |_low, high| high,
        )
        .unwrap();

        assert!(!response.accepted);
        assert_eq!(response.rejection_code, Some(REJECTION_CODE_REDIRECT));
        assert_eq!(response.redirect_to_agent_id, Some("gateway-b".to_string()));
        assert_eq!(attempts, vec!["gateway-a"]);
    }

    #[test]
    fn test_delegate_to_swarm_validates_redirect_target_before_bound_check() {
        let mut attempts = Vec::new();
        let options = DelegateToSwarmOptions::new(
            "parent".to_string(),
            "gateway-a".to_string(),
            "delegate".to_string(),
            BudgetEnvelope {
                token_budget_remaining: None,
                wall_time_remaining_ms: Some(10_000),
                deadline_epoch_ms: 2_000_000,
                current_depth: None,
                max_delegation_depth: None,
            },
        )
        .with_request_id("req-redirect-target-validation".to_string())
        .with_delegation_policy(SwarmDelegationPolicy {
            allow_spillover_routing: true,
            max_redirects: 1,
            ..SwarmDelegationPolicy::default()
        });

        let response = delegate_to_swarm_with_runtime(
            options,
            |request| {
                attempts.push(request.to_agent.clone());
                if request.to_agent == "gateway-a" {
                    return Ok(redirect_response(request, "gateway-b"));
                }
                Ok(redirect_response(request, "   "))
            },
            || 1_500_000,
            |_milliseconds| Ok(()),
            |_low, high| high,
        )
        .unwrap();

        assert!(!response.accepted);
        assert_eq!(
            response.rejection_code,
            Some(constants::error_code::VALIDATION_ERROR)
        );
        assert!(response
            .rejection_reason
            .unwrap_or_default()
            .contains("non-empty"));
        assert_eq!(attempts, vec!["gateway-a", "gateway-b"]);
    }

    #[test]
    fn test_delegate_to_swarm_fails_fast_when_budget_exhausted_after_attempt() {
        let mut attempts = Vec::new();
        let now_ms = Rc::new(Cell::new(10_000_u64));
        let options = DelegateToSwarmOptions::new(
            "parent".to_string(),
            "gateway-a".to_string(),
            "delegate".to_string(),
            BudgetEnvelope {
                token_budget_remaining: None,
                wall_time_remaining_ms: Some(50),
                deadline_epoch_ms: 20_000,
                current_depth: None,
                max_delegation_depth: None,
            },
        )
        .with_request_id("req-budget-fast-fail".to_string())
        .with_delegation_policy(SwarmDelegationPolicy {
            allow_spillover_routing: true,
            max_redirects: 3,
            ..SwarmDelegationPolicy::default()
        });
        let now_ms_for_send = now_ms.clone();
        let now_ms_for_now = now_ms.clone();

        let response = delegate_to_swarm_with_runtime(
            options,
            |request| {
                attempts.push(request.to_agent.clone());
                now_ms_for_send.set(now_ms_for_send.get() + 75);
                Ok(redirect_response(request, "gateway-b"))
            },
            move || now_ms_for_now.get(),
            |_milliseconds| Ok(()),
            |_low, high| high,
        )
        .unwrap();

        assert!(!response.accepted);
        assert_eq!(response.rejection_code, Some(constants::error_code::ACK_TIMEOUT));
        assert!(response
            .rejection_reason
            .unwrap_or_default()
            .contains("deadline exhausted"));
        assert_eq!(attempts, vec!["gateway-a"]);
    }

    #[test]
    fn test_delegate_to_swarm_deducts_wall_time_across_redirects_and_retries() {
        let mut attempts = Vec::new();
        let mut captured_wall_times = Vec::new();
        let now_ms = Rc::new(Cell::new(10_000_u64));
        let options = DelegateToSwarmOptions::new(
            "parent".to_string(),
            "gateway-a".to_string(),
            "delegate".to_string(),
            BudgetEnvelope {
                token_budget_remaining: None,
                wall_time_remaining_ms: Some(500),
                deadline_epoch_ms: 20_000,
                current_depth: None,
                max_delegation_depth: None,
            },
        )
        .with_request_id("req-budget".to_string())
        .with_delegation_policy(SwarmDelegationPolicy {
            allow_spillover_routing: true,
            max_redirects: 3,
            max_retries_on_overloaded: 1,
            ..SwarmDelegationPolicy::default()
        });
        let now_ms_for_send = now_ms.clone();
        let now_ms_for_now = now_ms.clone();
        let now_ms_for_sleep = now_ms.clone();

        let response = delegate_to_swarm_with_runtime(
            options,
            |request| {
                attempts.push(request.to_agent.clone());
                captured_wall_times.push(
                    request
                        .budget
                        .as_ref()
                        .and_then(|b| b.wall_time_remaining_ms)
                        .unwrap_or(0),
                );
                if attempts.len() == 1 {
                    now_ms_for_send.set(now_ms_for_send.get() + 30);
                    return Ok(redirect_response(request, "gateway-b"));
                }
                if attempts.len() == 2 {
                    now_ms_for_send.set(now_ms_for_send.get() + 20);
                    return Ok(HandoffResponse {
                        accepted: false,
                        handoff_id: request.request_id.clone(),
                        rejection_reason: Some("overloaded".to_string()),
                        accepting_agent: None,
                        rejection_code: Some(REJECTION_CODE_OVERLOADED),
                        retry_after_ms: Some(100),
                        redirect_to_agent_id: None,
                        status: HandoffStatus::Rejected,
                        metadata: std::collections::HashMap::new(),
                    });
                }
                Ok(HandoffResponse {
                    accepted: true,
                    handoff_id: request.request_id.clone(),
                    rejection_reason: None,
                    accepting_agent: Some(request.to_agent.clone()),
                    rejection_code: None,
                    retry_after_ms: None,
                    redirect_to_agent_id: None,
                    status: HandoffStatus::Accepted,
                    metadata: std::collections::HashMap::new(),
                })
            },
            move || now_ms_for_now.get(),
            |milliseconds| {
                now_ms_for_sleep.set(now_ms_for_sleep.get() + milliseconds);
                Ok(())
            },
            |_low, high| high,
        )
        .unwrap();

        assert!(response.accepted);
        assert_eq!(attempts, vec!["gateway-a", "gateway-b", "gateway-b"]);
        assert_eq!(captured_wall_times, vec![500, 470, 330]);
    }
}
