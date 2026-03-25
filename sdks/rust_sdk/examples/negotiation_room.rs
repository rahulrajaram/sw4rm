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

//! Negotiation Room Example for SW4RM Protocol.
//!
//! Demonstrates the producer-critic-coordinator pattern using the real SDK
//! `NegotiationRoomClient`:
//! - A producer agent submits an artifact (code, plan, requirements)
//! - Multiple critic agents evaluate and vote on the artifact
//! - A coordinator aggregates votes and stores a final decision
//!
//! Uses the `ConfidenceWeightedAggregator` from the SDK's voting module
//! for statistical aggregation of critic scores.
//!
//! Execution mode: Local in-memory demo. All three client instances share
//! the same `InMemoryNegotiationRoomStore` via `Arc`. No external services
//! are required.
//!
//! Run:
//! ```bash
//! cargo run --example negotiation_room
//! ```

use std::sync::Arc;
use sw4rm_sdk::clients::negotiation_room::{
    ArtifactType, DecisionOutcome, NegotiationDecision, NegotiationProposal, NegotiationRoomClient,
    NegotiationVote,
};
use sw4rm_sdk::clients::negotiation_room_store::InMemoryNegotiationRoomStore;
use sw4rm_sdk::voting::{AggregationStrategy, ConfidenceWeightedAggregator};

// ============================================================================
// Policy constants
// ============================================================================

const APPROVAL_THRESHOLD: f64 = 7.0;
const MIN_CONFIDENCE: f64 = 0.6;
const MIN_VOTES: usize = 2;

// ============================================================================
// Coordinator decision logic
// ============================================================================

/// Apply policy thresholds to determine the decision outcome.
fn determine_outcome(
    aggregated: &sw4rm_sdk::clients::negotiation_room::AggregatedScore,
    votes: &[NegotiationVote],
) -> (DecisionOutcome, String) {
    if aggregated.vote_count < MIN_VOTES {
        return (
            DecisionOutcome::EscalatedToHitl,
            format!(
                "Insufficient votes ({}/{})",
                aggregated.vote_count, MIN_VOTES
            ),
        );
    }

    let avg_confidence: f64 =
        votes.iter().map(|v| v.confidence).sum::<f64>() / votes.len() as f64;
    if avg_confidence < MIN_CONFIDENCE {
        return (
            DecisionOutcome::EscalatedToHitl,
            format!(
                "Low average confidence ({:.0}% < {:.0}%)",
                avg_confidence * 100.0,
                MIN_CONFIDENCE * 100.0
            ),
        );
    }

    let all_passed = votes.iter().all(|v| v.passed);

    if aggregated.weighted_mean >= APPROVAL_THRESHOLD && all_passed {
        return (
            DecisionOutcome::Approved,
            format!(
                "Weighted mean {:.2} >= {}, all critics passed",
                aggregated.weighted_mean, APPROVAL_THRESHOLD
            ),
        );
    }

    if aggregated.weighted_mean >= APPROVAL_THRESHOLD * 0.8 {
        let weaknesses: Vec<_> = votes
            .iter()
            .flat_map(|v| v.weaknesses.iter())
            .take(3)
            .collect();
        return (
            DecisionOutcome::RevisionRequested,
            format!(
                "Score {:.2} needs improvement. Issues: {}",
                aggregated.weighted_mean,
                weaknesses
                    .iter()
                    .map(|s| s.as_str())
                    .collect::<Vec<_>>()
                    .join("; ")
            ),
        );
    }

    if aggregated.std_dev > 2.0 {
        return (
            DecisionOutcome::EscalatedToHitl,
            format!(
                "High disagreement among critics (std dev: {:.2})",
                aggregated.std_dev
            ),
        );
    }

    (
        DecisionOutcome::RevisionRequested,
        format!(
            "Score {:.2} below threshold {}",
            aggregated.weighted_mean, APPROVAL_THRESHOLD
        ),
    )
}

// ============================================================================
// Agent simulation
// ============================================================================

/// Simulate a producer submitting code for review.
fn simulate_producer(client: &NegotiationRoomClient, room_id: &str) -> String {
    println!("\n{}", "=".repeat(60));
    println!("PRODUCER: Submitting code for review");
    println!("{}", "=".repeat(60));

    let artifact_content = serde_json::json!({
        "language": "rust",
        "file": "auth.rs",
        "content": "pub async fn authenticate(token: &str) -> Result<User> { ... }",
    });

    let proposal = NegotiationProposal::new(
        ArtifactType::Code,
        format!("artifact-{}", chrono::Utc::now().timestamp_millis()),
        "producer-agent-1".to_string(),
        serde_json::to_vec(&artifact_content).unwrap(),
        "application/json".to_string(),
        vec![
            "security-critic".to_string(),
            "code-quality-critic".to_string(),
            "architecture-critic".to_string(),
        ],
        room_id.to_string(),
    );

    let artifact_id = client.submit_proposal(proposal).unwrap();
    println!("  Artifact ID: {}", artifact_id);
    println!("  Type: Code");
    println!("  Requested Critics: security-critic, code-quality-critic, architecture-critic");

    artifact_id
}

/// Simulate a security critic evaluating the code.
fn simulate_security_critic(client: &NegotiationRoomClient, artifact_id: &str, room_id: &str) {
    println!("\n{}", "-".repeat(60));
    println!("CRITIC: Security Review");
    println!("{}", "-".repeat(60));

    let vote = NegotiationVote::new(
        artifact_id.to_string(),
        "security-critic".to_string(),
        6.5,
        0.85,
        false,
        vec![
            "Uses JWT verification".to_string(),
            "Async/await pattern for database calls".to_string(),
        ],
        vec![
            "SECRET_KEY should not be hardcoded".to_string(),
            "Missing token expiration check".to_string(),
            "No rate limiting on authentication".to_string(),
        ],
        vec![
            "Use environment variables for secrets".to_string(),
            "Add explicit expiration validation".to_string(),
        ],
        room_id.to_string(),
    )
    .unwrap();

    client.submit_vote(vote).unwrap();
    println!("  Score: 6.5/10  Confidence: 85%  Passed: false");
}

/// Simulate a code quality critic evaluating the code.
fn simulate_code_quality_critic(
    client: &NegotiationRoomClient,
    artifact_id: &str,
    room_id: &str,
) {
    println!("\n{}", "-".repeat(60));
    println!("CRITIC: Code Quality Review");
    println!("{}", "-".repeat(60));

    let vote = NegotiationVote::new(
        artifact_id.to_string(),
        "code-quality-critic".to_string(),
        8.0,
        0.9,
        true,
        vec![
            "Clean function signature with types".to_string(),
            "Proper async/await usage".to_string(),
            "Single responsibility principle".to_string(),
        ],
        vec![
            "Missing error handling for jwt.verify".to_string(),
            "No input validation for token".to_string(),
        ],
        vec![
            "Add try-catch for JWT verification".to_string(),
            "Validate token format before processing".to_string(),
        ],
        room_id.to_string(),
    )
    .unwrap();

    client.submit_vote(vote).unwrap();
    println!("  Score: 8.0/10  Confidence: 90%  Passed: true");
}

/// Simulate an architecture critic evaluating the code.
fn simulate_architecture_critic(
    client: &NegotiationRoomClient,
    artifact_id: &str,
    room_id: &str,
) {
    println!("\n{}", "-".repeat(60));
    println!("CRITIC: Architecture Review");
    println!("{}", "-".repeat(60));

    let vote = NegotiationVote::new(
        artifact_id.to_string(),
        "architecture-critic".to_string(),
        7.5,
        0.75,
        true,
        vec![
            "Clean separation of concerns".to_string(),
            "Uses service layer pattern".to_string(),
            "Async-first design".to_string(),
        ],
        vec![
            "Direct dependency on UserService".to_string(),
            "No dependency injection".to_string(),
        ],
        vec![
            "Consider dependency injection for UserService".to_string(),
            "Add interface for service abstraction".to_string(),
        ],
        room_id.to_string(),
    )
    .unwrap();

    client.submit_vote(vote).unwrap();
    println!("  Score: 7.5/10  Confidence: 75%  Passed: true");
}

/// Simulate the coordinator aggregating votes and making a decision.
fn simulate_coordinator(
    client: &NegotiationRoomClient,
    artifact_id: &str,
    room_id: &str,
) -> NegotiationDecision {
    println!("\n{}", "=".repeat(60));
    println!("COORDINATOR: Aggregating votes and deciding");
    println!("{}", "=".repeat(60));

    let votes = client.get_votes(artifact_id).unwrap();

    // Use the SDK's ConfidenceWeightedAggregator
    let aggregator = ConfidenceWeightedAggregator::new();
    let aggregated = aggregator.aggregate(&votes).unwrap();

    let (outcome, reason) = determine_outcome(&aggregated, &votes);

    let decision = NegotiationDecision::new(
        artifact_id.to_string(),
        outcome,
        votes.clone(),
        aggregated.clone(),
        "v1.0.0".to_string(),
        reason,
        room_id.to_string(),
    );

    client.store_decision(decision.clone()).unwrap();

    println!("\n[Decision Summary]");
    println!("  Outcome: {:?}", decision.outcome);
    println!("  Reason: {}", decision.reason);
    println!("  Vote Count: {}", aggregated.vote_count);
    println!("  Mean Score: {:.2}", aggregated.mean);
    println!("  Weighted Mean: {:.2}", aggregated.weighted_mean);
    println!(
        "  Score Range: {:.1} - {:.1}",
        aggregated.min_score, aggregated.max_score
    );
    println!("  Std Dev: {:.2}", aggregated.std_dev);

    decision
}

// ============================================================================
// Main
// ============================================================================

fn main() {
    println!("SW4RM Negotiation Room Example");
    println!("{}", "=".repeat(60));
    println!("\nThis example uses the SDK NegotiationRoomClient to demonstrate");
    println!("the producer-critic-coordinator pattern for artifact approval.\n");

    // All clients share the same in-memory store via Arc
    let store = Arc::new(InMemoryNegotiationRoomStore::new());
    let producer_client = NegotiationRoomClient::with_store(store.clone());
    let critic_client = NegotiationRoomClient::with_store(store.clone());
    let coordinator_client = NegotiationRoomClient::with_store(store);

    let room_id = format!("room-{}", chrono::Utc::now().timestamp_millis());

    // Producer submits artifact
    let artifact_id = simulate_producer(&producer_client, &room_id);

    // Critics evaluate
    simulate_security_critic(&critic_client, &artifact_id, &room_id);
    simulate_code_quality_critic(&critic_client, &artifact_id, &room_id);
    simulate_architecture_critic(&critic_client, &artifact_id, &room_id);

    // Coordinator aggregates and decides
    let decision = simulate_coordinator(&coordinator_client, &artifact_id, &room_id);

    // Verify: a subsequent get_decision call returns the stored decision
    let retrieved = coordinator_client.get_decision(&artifact_id).unwrap();
    println!(
        "\n[Verification] Decision retrievable: {}",
        retrieved.is_some()
    );

    // Summary
    println!("\n{}", "=".repeat(60));
    println!("FINAL RESULT");
    println!("{}", "=".repeat(60));

    match decision.outcome {
        DecisionOutcome::Approved => {
            println!("\nArtifact APPROVED — Ready for deployment");
        }
        DecisionOutcome::RevisionRequested => {
            println!("\nRevision REQUESTED — Producer must address issues:");
            for vote in &decision.votes {
                if !vote.weaknesses.is_empty() {
                    println!("  [{}] {}", vote.critic_id, vote.weaknesses.join("; "));
                }
            }
        }
        DecisionOutcome::EscalatedToHitl => {
            println!("\nESCALATED to Human-in-the-Loop for manual review");
            println!("  Reason: {}", decision.reason);
        }
        DecisionOutcome::Unspecified => {
            println!("\nUnspecified outcome");
        }
    }

    // --------------------------------------------------------------------------
    // Failure Path: HITL Escalation via high disagreement
    // --------------------------------------------------------------------------
    println!("\n{}", "=".repeat(60));
    println!("FAILURE PATH: HITL Escalation (Polarized Votes)");
    println!("{}", "=".repeat(60));

    let esc_room_id = format!("room-esc-{}", chrono::Utc::now().timestamp_millis());
    let esc_proposal = NegotiationProposal::new(
        ArtifactType::Code,
        format!("artifact-esc-{}", chrono::Utc::now().timestamp_millis()),
        "producer-agent-2".to_string(),
        b"experimental code".to_vec(),
        "text/plain".to_string(),
        vec![
            "optimist-critic".to_string(),
            "pessimist-critic".to_string(),
        ],
        esc_room_id.clone(),
    );

    let esc_artifact_id = producer_client.submit_proposal(esc_proposal).unwrap();
    println!("\n  Submitted polarizing artifact: {}", esc_artifact_id);

    // Two critics with wildly different scores → high stdDev
    let optimist_vote = NegotiationVote::new(
        esc_artifact_id.clone(),
        "optimist-critic".to_string(),
        9.5,
        0.9,
        true,
        vec!["Innovative approach".to_string()],
        vec![],
        vec![],
        esc_room_id.clone(),
    )
    .unwrap();

    let pessimist_vote = NegotiationVote::new(
        esc_artifact_id.clone(),
        "pessimist-critic".to_string(),
        3.0,
        0.85,
        false,
        vec![],
        vec![
            "Fundamental design flaw".to_string(),
            "No error handling".to_string(),
        ],
        vec!["Complete rewrite needed".to_string()],
        esc_room_id.clone(),
    )
    .unwrap();

    critic_client.submit_vote(optimist_vote).unwrap();
    critic_client.submit_vote(pessimist_vote).unwrap();
    println!("  optimist-critic: 9.5/10   pessimist-critic: 3.0/10");

    let esc_votes = coordinator_client.get_votes(&esc_artifact_id).unwrap();
    let aggregator = ConfidenceWeightedAggregator::new();
    let esc_aggregated = aggregator.aggregate(&esc_votes).unwrap();
    let (esc_outcome, esc_reason) = determine_outcome(&esc_aggregated, &esc_votes);

    println!("\n  Std Dev: {:.2}", esc_aggregated.std_dev);
    println!("  Outcome: {:?}", esc_outcome);
    println!("  Reason: {}", esc_reason);

    // Demonstrate vote validation error
    println!("\n--- Vote Validation Error ---");
    let bad_vote = NegotiationVote::new(
        esc_artifact_id.clone(),
        "bad-critic".to_string(),
        15.0, // Out of range [0, 10]
        0.9,
        true,
        vec![],
        vec![],
        vec![],
        esc_room_id,
    );
    match bad_vote {
        Ok(_) => println!("  Unexpected success"),
        Err(e) => println!("  Caught: {}", e),
    }

    println!("\nKey takeaways:");
    println!("1. NegotiationRoomClient::with_store() shares state across client instances via Arc");
    println!("2. submit_vote() validates score/confidence ranges and prevents duplicate votes");
    println!("3. ConfidenceWeightedAggregator computes POMDP-inspired weighted scoring");
    println!("4. store_decision() records the coordinator verdict for later retrieval");
    println!("5. Policy thresholds determine approval/revision/escalation outcomes");
    println!("6. High vote disagreement (stdDev > 2.0) triggers HITL escalation");
    println!("7. Out-of-range scores return Err at construction time");
}
