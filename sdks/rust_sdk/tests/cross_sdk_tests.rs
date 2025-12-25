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
    constants::message_type,
    envelope::EnvelopeBuilder,
    policy_store::EffectivePolicy,
    voting::aggregate_votes,
    clients::negotiation_room::NegotiationVote,
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
    let parsed: serde_json::Value =
        serde_json::from_str(&json).expect("Should parse JSON");

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
    let parsed: serde_json::Value =
        serde_json::from_str(&json).expect("Should parse JSON");

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
