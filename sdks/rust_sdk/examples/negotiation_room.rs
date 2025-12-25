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

//! Negotiation Room Example
//!
//! Demonstrates the producer-critic-coordinator pattern for multi-agent
//! artifact approval workflows:
//!
//! 1. Producer submits an artifact (e.g., code, plan, requirements)
//! 2. Critics evaluate and vote on the artifact
//! 3. Coordinator aggregates votes and makes a decision
//!
//! This example uses stub implementations since NegotiationRoomClient
//! is not yet implemented in the Rust SDK. See Phase 3.1 of the
//! IMPLEMENTATION_PLAN.md for the full client implementation.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use sw4rm_sdk::prelude::*;

// ============================================================================
// Stub Types (will be replaced by proto-generated types in Phase 3.1)
// ============================================================================

/// Artifact type being negotiated
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum ArtifactType {
    Unspecified = 0,
    Requirements = 1,
    Plan = 2,
    Code = 3,
    Deployment = 4,
}

/// Outcome of the coordinator's decision
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum DecisionOutcome {
    Unspecified = 0,
    Approved = 1,
    RevisionRequested = 2,
    EscalatedToHitl = 3,
}

/// A proposal submitted by a producer agent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NegotiationProposal {
    pub artifact_type: ArtifactType,
    pub artifact_id: String,
    pub producer_id: String,
    pub artifact: Vec<u8>,
    pub artifact_content_type: String,
    pub requested_critics: Vec<String>,
    pub negotiation_room_id: String,
}

/// A vote cast by a critic agent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NegotiationVote {
    pub artifact_id: String,
    pub critic_id: String,
    pub score: f64,
    pub confidence: f64,
    pub passed: bool,
    pub strengths: Vec<String>,
    pub weaknesses: Vec<String>,
    pub recommendations: Vec<String>,
    pub negotiation_room_id: String,
}

/// Aggregated score from multiple votes
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct AggregatedScore {
    pub mean: f64,
    pub min_score: f64,
    pub max_score: f64,
    pub std_dev: f64,
    pub weighted_mean: f64,
    pub vote_count: i32,
}

/// Decision made by the coordinator
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NegotiationDecision {
    pub artifact_id: String,
    pub outcome: DecisionOutcome,
    pub votes: Vec<NegotiationVote>,
    pub aggregated_score: AggregatedScore,
    pub policy_version: String,
    pub reason: String,
    pub negotiation_room_id: String,
}

// ============================================================================
// Stub Client (will be replaced by actual gRPC client in Phase 3.1)
// ============================================================================

/// Stub client for NegotiationRoom service
///
/// NOTE: This is a demonstration stub. The actual implementation will use
/// gRPC to communicate with the NegotiationRoom service.
#[derive(Debug, Clone)]
pub struct NegotiationRoomClientStub {
    proposals: HashMap<String, NegotiationProposal>,
    votes: HashMap<String, Vec<NegotiationVote>>,
    decisions: HashMap<String, NegotiationDecision>,
}

impl NegotiationRoomClientStub {
    pub fn new() -> Self {
        Self {
            proposals: HashMap::new(),
            votes: HashMap::new(),
            decisions: HashMap::new(),
        }
    }

    /// Submit a proposal for evaluation
    pub fn submit_proposal(&mut self, proposal: NegotiationProposal) -> Result<String> {
        let artifact_id = proposal.artifact_id.clone();
        tracing::info!(
            "Submitting proposal: {} (type: {:?})",
            artifact_id,
            proposal.artifact_type
        );
        self.proposals.insert(artifact_id.clone(), proposal);
        self.votes.insert(artifact_id.clone(), Vec::new());
        Ok(artifact_id)
    }

    /// Submit a vote for an artifact
    pub fn submit_vote(&mut self, vote: NegotiationVote) -> Result<()> {
        tracing::info!(
            "Submitting vote from {} for {} (score: {:.1}, confidence: {:.2})",
            vote.critic_id,
            vote.artifact_id,
            vote.score,
            vote.confidence
        );

        if let Some(votes) = self.votes.get_mut(&vote.artifact_id) {
            votes.push(vote);
            Ok(())
        } else {
            Err(Error::NotFound(format!(
                "No proposal found for artifact: {}",
                vote.artifact_id
            )))
        }
    }

    /// Get all votes for an artifact
    pub fn get_votes(&self, artifact_id: &str) -> Result<Vec<NegotiationVote>> {
        self.votes
            .get(artifact_id)
            .cloned()
            .ok_or_else(|| Error::NotFound(format!("No votes found for: {}", artifact_id)))
    }

    /// Aggregate votes using confidence-weighted mean
    pub fn aggregate_votes(&self, artifact_id: &str) -> Result<AggregatedScore> {
        let votes = self.get_votes(artifact_id)?;

        if votes.is_empty() {
            return Ok(AggregatedScore::default());
        }

        let vote_count = votes.len() as i32;
        let scores: Vec<f64> = votes.iter().map(|v| v.score).collect();
        let confidences: Vec<f64> = votes.iter().map(|v| v.confidence).collect();

        // Calculate mean
        let mean = scores.iter().sum::<f64>() / vote_count as f64;

        // Calculate min/max
        let min_score = scores.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_score = scores.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

        // Calculate standard deviation
        let variance = scores.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / vote_count as f64;
        let std_dev = variance.sqrt();

        // Calculate confidence-weighted mean
        let total_confidence: f64 = confidences.iter().sum();
        let weighted_mean = if total_confidence > 0.0 {
            votes
                .iter()
                .map(|v| v.score * v.confidence)
                .sum::<f64>()
                / total_confidence
        } else {
            mean
        };

        Ok(AggregatedScore {
            mean,
            min_score,
            max_score,
            std_dev,
            weighted_mean,
            vote_count,
        })
    }

    /// Make a decision based on aggregated votes and policy thresholds
    pub fn decide(
        &mut self,
        artifact_id: &str,
        policy_version: &str,
        approve_threshold: f64,
        hitl_threshold: f64,
    ) -> Result<NegotiationDecision> {
        let votes = self.get_votes(artifact_id)?;
        let aggregated = self.aggregate_votes(artifact_id)?;

        let proposal = self
            .proposals
            .get(artifact_id)
            .ok_or_else(|| Error::NotFound(format!("No proposal found: {}", artifact_id)))?;

        // Determine outcome based on thresholds
        let (outcome, reason) = if aggregated.weighted_mean >= approve_threshold {
            (
                DecisionOutcome::Approved,
                format!(
                    "Weighted mean score {:.2} meets approval threshold {:.2}",
                    aggregated.weighted_mean, approve_threshold
                ),
            )
        } else if aggregated.weighted_mean < hitl_threshold || aggregated.std_dev > 2.0 {
            (
                DecisionOutcome::EscalatedToHitl,
                format!(
                    "Weighted mean {:.2} below HITL threshold {:.2} or high disagreement (std_dev={:.2})",
                    aggregated.weighted_mean, hitl_threshold, aggregated.std_dev
                ),
            )
        } else {
            (
                DecisionOutcome::RevisionRequested,
                format!(
                    "Weighted mean {:.2} between thresholds, revision needed",
                    aggregated.weighted_mean
                ),
            )
        };

        let decision = NegotiationDecision {
            artifact_id: artifact_id.to_string(),
            outcome,
            votes,
            aggregated_score: aggregated,
            policy_version: policy_version.to_string(),
            reason,
            negotiation_room_id: proposal.negotiation_room_id.clone(),
        };

        self.decisions
            .insert(artifact_id.to_string(), decision.clone());

        Ok(decision)
    }

    /// Get a decision for an artifact
    pub fn get_decision(&self, artifact_id: &str) -> Result<Option<NegotiationDecision>> {
        Ok(self.decisions.get(artifact_id).cloned())
    }
}

// ============================================================================
// Demo Agents
// ============================================================================

/// Producer agent that submits artifacts for review
struct ProducerAgent {
    agent_id: String,
    client: NegotiationRoomClientStub,
}

impl ProducerAgent {
    fn new(agent_id: &str, client: NegotiationRoomClientStub) -> Self {
        Self {
            agent_id: agent_id.to_string(),
            client,
        }
    }

    fn submit_code_artifact(&mut self, code: &str, critics: Vec<&str>) -> Result<String> {
        let artifact_id = new_uuid();
        let negotiation_room_id = format!("room-{}", new_uuid().split('-').next().unwrap());

        let proposal = NegotiationProposal {
            artifact_type: ArtifactType::Code,
            artifact_id: artifact_id.clone(),
            producer_id: self.agent_id.clone(),
            artifact: code.as_bytes().to_vec(),
            artifact_content_type: "text/rust".to_string(),
            requested_critics: critics.iter().map(|s| s.to_string()).collect(),
            negotiation_room_id,
        };

        self.client.submit_proposal(proposal)?;
        tracing::info!("[Producer] Submitted artifact: {}", artifact_id);

        Ok(artifact_id)
    }
}

/// Critic agent that evaluates artifacts
struct CriticAgent {
    agent_id: String,
    specialty: String,
}

impl CriticAgent {
    fn new(agent_id: &str, specialty: &str) -> Self {
        Self {
            agent_id: agent_id.to_string(),
            specialty: specialty.to_string(),
        }
    }

    fn evaluate_artifact(
        &self,
        artifact_id: &str,
        negotiation_room_id: &str,
    ) -> NegotiationVote {
        // Simulate evaluation based on specialty
        let (score, confidence, strengths, weaknesses, recommendations) = match self.specialty.as_str() {
            "security" => (
                8.5,
                0.90,
                vec!["Good input validation".to_string(), "Proper error handling".to_string()],
                vec!["Missing rate limiting".to_string()],
                vec!["Add rate limiting to API endpoints".to_string()],
            ),
            "performance" => (
                7.0,
                0.75,
                vec!["Efficient algorithms".to_string()],
                vec!["No caching strategy".to_string(), "Potential N+1 queries".to_string()],
                vec!["Consider adding Redis cache".to_string(), "Batch database queries".to_string()],
            ),
            "code_quality" => (
                6.5,
                0.80,
                vec!["Clean code structure".to_string(), "Good documentation".to_string()],
                vec!["Some functions are too long".to_string()],
                vec!["Refactor large functions".to_string()],
            ),
            "testing" => (
                9.0,
                0.95,
                vec!["Excellent test coverage".to_string(), "Good edge case handling".to_string()],
                vec![],
                vec!["Add more integration tests".to_string()],
            ),
            _ => (
                7.5,
                0.70,
                vec!["Generally acceptable".to_string()],
                vec!["Minor issues".to_string()],
                vec!["Review and address feedback".to_string()],
            ),
        };

        tracing::info!(
            "[Critic:{}] Evaluating artifact {}: score={:.1}, confidence={:.2}",
            self.specialty,
            artifact_id,
            score,
            confidence
        );

        NegotiationVote {
            artifact_id: artifact_id.to_string(),
            critic_id: self.agent_id.clone(),
            score,
            confidence,
            passed: score >= 6.0,
            strengths,
            weaknesses,
            recommendations,
            negotiation_room_id: negotiation_room_id.to_string(),
        }
    }
}

/// Coordinator agent that aggregates votes and makes decisions
struct CoordinatorAgent {
    #[allow(dead_code)]
    agent_id: String,
    policy_version: String,
    approve_threshold: f64,
    hitl_threshold: f64,
}

impl CoordinatorAgent {
    fn new(agent_id: &str) -> Self {
        Self {
            agent_id: agent_id.to_string(),
            policy_version: "v1.0.0".to_string(),
            approve_threshold: 7.5,
            hitl_threshold: 5.0,
        }
    }

    fn make_decision(
        &self,
        client: &mut NegotiationRoomClientStub,
        artifact_id: &str,
    ) -> Result<NegotiationDecision> {
        tracing::info!("[Coordinator] Making decision for artifact: {}", artifact_id);

        let decision = client.decide(
            artifact_id,
            &self.policy_version,
            self.approve_threshold,
            self.hitl_threshold,
        )?;

        tracing::info!(
            "[Coordinator] Decision: {:?} - {}",
            decision.outcome,
            decision.reason
        );

        Ok(decision)
    }
}

// ============================================================================
// Main Demo
// ============================================================================

fn print_separator(title: &str) {
    println!("\n{}", "=".repeat(70));
    println!("{}", title);
    println!("{}\n", "=".repeat(70));
}

fn print_votes(votes: &[NegotiationVote]) {
    println!("\nVotes Summary:");
    println!("{:-<70}", "");
    for vote in votes {
        println!(
            "  {} ({}): score={:.1}, confidence={:.2}, passed={}",
            vote.critic_id,
            if vote.passed { "PASS" } else { "FAIL" },
            vote.score,
            vote.confidence,
            vote.passed
        );
        if !vote.strengths.is_empty() {
            println!("    Strengths: {:?}", vote.strengths);
        }
        if !vote.weaknesses.is_empty() {
            println!("    Weaknesses: {:?}", vote.weaknesses);
        }
    }
    println!("{:-<70}", "");
}

fn print_decision(decision: &NegotiationDecision) {
    println!("\nDecision Summary:");
    println!("{:-<70}", "");
    println!("  Outcome: {:?}", decision.outcome);
    println!("  Reason: {}", decision.reason);
    println!("  Policy Version: {}", decision.policy_version);
    println!("\nAggregated Scores:");
    println!("  Mean: {:.2}", decision.aggregated_score.mean);
    println!("  Weighted Mean: {:.2}", decision.aggregated_score.weighted_mean);
    println!("  Std Dev: {:.2}", decision.aggregated_score.std_dev);
    println!(
        "  Range: {:.2} - {:.2}",
        decision.aggregated_score.min_score, decision.aggregated_score.max_score
    );
    println!("  Vote Count: {}", decision.aggregated_score.vote_count);
    println!("{:-<70}", "");
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_target(false)
        .with_level(true)
        .init();

    print_separator("SW4RM Negotiation Room Demo");
    println!("SDK Version: {}", sw4rm_sdk::VERSION);
    println!("\nThis example demonstrates the producer-critic-coordinator pattern");
    println!("for multi-agent artifact approval workflows.\n");

    // Create shared client (in reality, each agent would have its own client)
    let mut client = NegotiationRoomClientStub::new();

    // Create agents
    let mut producer = ProducerAgent::new("producer-agent-1", client.clone());
    let critics = vec![
        CriticAgent::new("critic-security", "security"),
        CriticAgent::new("critic-performance", "performance"),
        CriticAgent::new("critic-quality", "code_quality"),
        CriticAgent::new("critic-testing", "testing"),
    ];
    let coordinator = CoordinatorAgent::new("coordinator-agent-1");

    // =========================================================================
    // Scenario 1: Code artifact that gets APPROVED
    // =========================================================================
    print_separator("Scenario 1: Code Submission (Expected: APPROVED)");

    // Producer submits artifact
    let sample_code = r#"
fn process_data(input: &str) -> Result<Data, Error> {
    // Validate input
    if input.is_empty() {
        return Err(Error::EmptyInput);
    }

    // Process and return
    let data = parse_and_validate(input)?;
    Ok(data)
}
"#;

    let artifact_id = producer.submit_code_artifact(
        sample_code,
        critics.iter().map(|c| c.agent_id.as_str()).collect(),
    )?;

    // Re-get the client from producer since we need to share state
    client = producer.client.clone();

    // Critics evaluate
    let negotiation_room_id = "room-demo-1";
    for critic in &critics {
        let vote = critic.evaluate_artifact(&artifact_id, negotiation_room_id);
        client.submit_vote(vote)?;
    }

    // Show votes
    let votes = client.get_votes(&artifact_id)?;
    print_votes(&votes);

    // Coordinator makes decision
    let decision = coordinator.make_decision(&mut client, &artifact_id)?;
    print_decision(&decision);

    assert_eq!(decision.outcome, DecisionOutcome::Approved);

    // =========================================================================
    // Scenario 2: Polarized votes (Expected: ESCALATE_TO_HITL)
    // =========================================================================
    print_separator("Scenario 2: Polarized Votes (Expected: HITL Escalation)");

    let artifact_id_2 = format!("artifact-{}", new_uuid().split('-').next().unwrap());

    // Submit a controversial artifact
    let proposal = NegotiationProposal {
        artifact_type: ArtifactType::Code,
        artifact_id: artifact_id_2.clone(),
        producer_id: "producer-agent-1".to_string(),
        artifact: b"controversial code here".to_vec(),
        artifact_content_type: "text/rust".to_string(),
        requested_critics: vec!["critic-1".to_string(), "critic-2".to_string()],
        negotiation_room_id: "room-demo-2".to_string(),
    };
    client.submit_proposal(proposal)?;

    // Submit polarized votes (some love it, some hate it)
    let polarized_votes = vec![
        NegotiationVote {
            artifact_id: artifact_id_2.clone(),
            critic_id: "critic-optimist".to_string(),
            score: 9.0,
            confidence: 0.85,
            passed: true,
            strengths: vec!["Innovative approach".to_string()],
            weaknesses: vec![],
            recommendations: vec![],
            negotiation_room_id: "room-demo-2".to_string(),
        },
        NegotiationVote {
            artifact_id: artifact_id_2.clone(),
            critic_id: "critic-pessimist".to_string(),
            score: 2.0,
            confidence: 0.80,
            passed: false,
            strengths: vec![],
            weaknesses: vec!["Major security concerns".to_string()],
            recommendations: vec!["Complete rewrite needed".to_string()],
            negotiation_room_id: "room-demo-2".to_string(),
        },
    ];

    for vote in polarized_votes {
        client.submit_vote(vote)?;
    }

    let votes = client.get_votes(&artifact_id_2)?;
    print_votes(&votes);

    let decision = coordinator.make_decision(&mut client, &artifact_id_2)?;
    print_decision(&decision);

    assert_eq!(decision.outcome, DecisionOutcome::EscalatedToHitl);

    // =========================================================================
    // Summary
    // =========================================================================
    print_separator("Demo Complete");
    println!("The Negotiation Room pattern enables structured multi-agent review:");
    println!();
    println!("1. Producer agents submit artifacts for review");
    println!("2. Critic agents evaluate based on their specialty");
    println!("3. Coordinator aggregates votes and applies policy thresholds");
    println!("4. Decisions are: APPROVED, REVISION_REQUESTED, or ESCALATED_TO_HITL");
    println!();
    println!("Key features demonstrated:");
    println!("  - Confidence-weighted voting");
    println!("  - Polarization detection (high std_dev triggers HITL)");
    println!("  - Policy-based thresholds");
    println!("  - Structured feedback (strengths, weaknesses, recommendations)");
    println!();

    Ok(())
}
