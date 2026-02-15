// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Cross-SDK compatibility tests.
//!
//! These tests verify that envelope structures and message formats are
//! compatible between Rust and JavaScript SDK implementations.

use sw4rm_sdk::{
    clients::handoff::{
        BudgetEnvelope, HandoffClient, HandoffRequest, HandoffStatus, RejectHandoffOptions,
        SwarmDelegationPolicy, DEFAULT_BACKOFF_MULTIPLIER, DEFAULT_INITIAL_BACKOFF_MS,
        DEFAULT_MAX_BACKOFF_MS, REJECTION_CODE_OVERLOADED,
    },
    clients::negotiation_room::NegotiationVote,
    constants::message_type,
    envelope::EnvelopeBuilder,
    policy_store::EffectivePolicy,
    voting::aggregate_votes,
};

/// Test that envelope structure matches spec and JS SDK.
#[test]
fn test_envelope_three_id_model_compatibility() {
    let envelope = EnvelopeBuilder::new("agent-rust-1".to_string(), message_type::DATA)
        .with_content_type("application/json".to_string())
        .with_payload(b"{\"action\": \"test\"}".to_vec())
        .with_correlation_id("corr-123".to_string());

    // Verify Three-ID Model fields (SPEC_REQUESTS Phase 1)
    assert!(!envelope.message_id.is_empty(), "message_id should be set");
    assert!(
        envelope.message_id.len() == 36,
        "message_id should be UUID format"
    );
    assert_eq!(envelope.correlation_id, "corr-123");
    assert!(
        envelope.sequence_number >= 1,
        "sequence_number should be positive"
    );
    assert_eq!(envelope.retry_count, 0);

    // Verify message structure
    assert_eq!(envelope.producer_id, "agent-rust-1");
    assert_eq!(envelope.message_type, message_type::DATA);
    assert!(envelope.content_length > 0);
}

/// Test idempotency token support.
#[test]
fn test_envelope_idempotency_token() {
    let envelope = EnvelopeBuilder::new("agent-rust-1".to_string(), message_type::DATA)
        .with_content_type("application/json".to_string())
        .with_payload(b"{}".to_vec())
        .with_idempotency_token("idem-token-xyz".to_string());

    assert_eq!(envelope.idempotency_token, "idem-token-xyz");
}

/// Test JSON serialization compatibility.
#[test]
fn test_envelope_json_serialization() {
    let envelope = EnvelopeBuilder::new("agent-rust-1".to_string(), message_type::CONTROL)
        .with_content_type("application/vnd.sw4rm.scheduler-command-v1+json".to_string())
        .with_payload(b"{\"stage\": \"prompt\"}".to_vec());

    // Serialize to JSON
    let json = serde_json::to_string(&envelope).expect("Should serialize to JSON");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("Should parse JSON");

    // Verify all required fields are present
    assert!(parsed.get("message_id").is_some());
    assert!(parsed.get("producer_id").is_some());
    assert!(parsed.get("message_type").is_some());
    assert!(parsed.get("content_type").is_some());
    assert!(parsed.get("sequence_number").is_some());
    assert!(parsed.get("retry_count").is_some());
}

/// Test MessageType constants match proto spec numeric values.
#[test]
fn test_message_type_constants() {
    // These numeric values must match proto definitions and JS SDK values
    assert_eq!(message_type::MESSAGE_TYPE_UNSPECIFIED, 0);
    assert_eq!(message_type::CONTROL, 1);
    assert_eq!(message_type::DATA, 2);
    assert_eq!(message_type::HEARTBEAT, 3);
    assert_eq!(message_type::NOTIFICATION, 4);
    assert_eq!(message_type::ACKNOWLEDGEMENT, 5);
    assert_eq!(message_type::HITL_INVOCATION, 6);
    assert_eq!(message_type::WORKTREE_CONTROL, 7);
    assert_eq!(message_type::NEGOTIATION, 8);
    assert_eq!(message_type::TOOL_CALL, 9);
    assert_eq!(message_type::TOOL_RESULT, 10);
    assert_eq!(message_type::TOOL_ERROR, 11);
}

/// Test EffectivePolicy structure (SPEC_REQUESTS Phase 3).
#[test]
fn test_effective_policy_unified_model() {
    // Create policy with defaults
    let policy = EffectivePolicy::new("test-policy".to_string());

    // Verify unified model structure
    assert!(!policy.policy_id.is_empty());
    assert!(!policy.version.is_empty());

    // Verify NegotiationPolicy fields
    assert!(policy.negotiation.max_rounds > 0);
    assert!(policy.negotiation.score_threshold >= 0.0);
    assert!(policy.negotiation.oscillation_limit >= 0);

    // Verify ExecutionPolicy fields
    assert!(policy.execution.timeout_ms > 0);
    assert!(policy.execution.max_retries >= 0);
    assert!(!policy.execution.network_policy.is_empty());
    assert!(!policy.execution.privilege_level.is_empty());

    // Verify EscalationPolicy fields
    assert!(policy.escalation.deadlock_rounds >= 0);
}

/// Test aggregate_votes helper function.
#[test]
fn test_aggregate_votes_helper() {
    let votes = vec![
        NegotiationVote::new(
            "artifact-1".to_string(),
            "critic-1".to_string(),
            8.0,
            0.9,
            true,
            vec!["good structure".to_string()],
            vec![],
            vec![],
            "room-1".to_string(),
        )
        .unwrap(),
        NegotiationVote::new(
            "artifact-1".to_string(),
            "critic-2".to_string(),
            7.0,
            0.7,
            true,
            vec!["clear code".to_string()],
            vec!["minor issues".to_string()],
            vec!["refactor helper".to_string()],
            "room-1".to_string(),
        )
        .unwrap(),
    ];

    let aggregated = aggregate_votes(&votes).expect("Should aggregate votes");

    // Verify aggregation results
    assert_eq!(aggregated.vote_count, 2);
    assert!(aggregated.mean >= 7.0 && aggregated.mean <= 8.0);
    assert!(aggregated.weighted_mean >= 7.0 && aggregated.weighted_mean <= 8.0);
    assert!(aggregated.min_score >= 7.0);
    assert!(aggregated.max_score <= 8.0);
    assert!(aggregated.std_dev >= 0.0);
}

/// Test policy JSON serialization for cross-SDK compatibility.
#[test]
fn test_policy_json_serialization() {
    let policy = EffectivePolicy::new("test-policy".to_string());

    // Serialize to JSON
    let json = serde_json::to_string(&policy).expect("Should serialize to JSON");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("Should parse JSON");

    // Verify all three policy types are present
    assert!(parsed.get("negotiation").is_some());
    assert!(parsed.get("execution").is_some());
    assert!(parsed.get("escalation").is_some());

    // Verify negotiation policy fields
    let neg = parsed.get("negotiation").unwrap();
    assert!(neg.get("max_rounds").is_some());
    assert!(neg.get("score_threshold").is_some());

    // Verify execution policy fields
    let exec = parsed.get("execution").unwrap();
    assert!(exec.get("timeout_ms").is_some());
    assert!(exec.get("max_retries").is_some());

    // Verify escalation policy fields
    let esc = parsed.get("escalation").unwrap();
    assert!(esc.get("auto_escalate_on_deadlock").is_some());
    assert!(esc.get("deadlock_rounds").is_some());
}

#[test]
fn test_handoff_request_sw4_004_policy_defaults() {
    let client = HandoffClient::new();
    let request = HandoffRequest::new(
        "agent-a".to_string(),
        "agent-b".to_string(),
        "Cross-swarm handoff".to_string(),
    )
    .with_budget(BudgetEnvelope::new(1_735_000_000_000))
    .with_delegation_policy(SwarmDelegationPolicy {
        max_retries_on_overloaded: 3,
        initial_backoff_ms: 0,
        backoff_multiplier: 0.0,
        max_backoff_ms: 0,
        allow_spillover_routing: true,
        max_redirects: 2,
    });

    client.request_handoff(request).unwrap();
    let pending = client.get_pending_handoffs("agent-b").unwrap();
    assert_eq!(pending.len(), 1);
    let policy = pending[0].delegation_policy.as_ref().unwrap();
    assert_eq!(policy.max_retries_on_overloaded, 3);
    assert_eq!(policy.initial_backoff_ms, DEFAULT_INITIAL_BACKOFF_MS);
    assert_eq!(policy.backoff_multiplier, DEFAULT_BACKOFF_MULTIPLIER);
    assert_eq!(policy.max_backoff_ms, DEFAULT_MAX_BACKOFF_MS);
}

#[test]
fn test_handoff_response_sw4_005_metadata_surface() {
    let client = HandoffClient::new();
    let request = HandoffRequest::new(
        "agent-a".to_string(),
        "agent-b".to_string(),
        "Overloaded target".to_string(),
    );
    let response = client.request_handoff(request).unwrap();

    client
        .reject_handoff_with_options(
            &response.handoff_id,
            "Capacity exceeded",
            RejectHandoffOptions {
                rejection_code: Some(REJECTION_CODE_OVERLOADED),
                retry_after_ms: Some(400),
                redirect_to_agent_id: Some("agent-c".to_string()),
            },
        )
        .unwrap();

    let status = client
        .get_handoff_status(&response.handoff_id)
        .unwrap()
        .unwrap();
    assert_eq!(status.status, HandoffStatus::Rejected);
    assert_eq!(status.rejection_code, Some(REJECTION_CODE_OVERLOADED));
    assert_eq!(status.retry_after_ms, Some(400));
    assert_eq!(status.redirect_to_agent_id, Some("agent-c".to_string()));

    let json = serde_json::to_string(&status).expect("Should serialize handoff response");
    let parsed: serde_json::Value = serde_json::from_str(&json).expect("Should parse JSON");
    assert!(parsed.get("rejection_code").is_some());
    assert!(parsed.get("retry_after_ms").is_some());
    assert!(parsed.get("redirect_to_agent_id").is_some());
}
