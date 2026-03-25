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

//! Voting aggregation example for the SW4RM Rust SDK.
//!
//! This example demonstrates how to use different aggregation strategies to
//! combine critic votes in a negotiation room scenario. It mirrors the
//! Python SDK example at `sdks/py_sdk/examples/voting_example.py`.
//!
//! Four aggregation strategies are demonstrated:
//!
//! - `SimpleAverageAggregator`: Arithmetic mean of all scores
//! - `ConfidenceWeightedAggregator`: Weights each vote by its confidence level
//! - `MajorityVoteAggregator`: Binary pass/fail majority counting
//! - `BordaCountAggregator`: Ranked voting with position-based points
//!
//! Additional analytical capabilities shown:
//!
//! - Shannon entropy of vote distribution
//! - Consensus detection (low std dev + high pass/fail agreement)
//! - Polarization detection (bimodal score distribution)
//! - Confidence variance across critics
//!
//! Run with:
//!
//! ```bash
//! cargo run --example voting
//! ```

use anyhow::Result;
use sw4rm_sdk::clients::negotiation_room::NegotiationVote;
use sw4rm_sdk::{
    BordaCountAggregator, ConfidenceWeightedAggregator, MajorityVoteAggregator,
    SimpleAverageAggregator, VotingAggregator,
};

/// Create a realistic set of critic votes for demonstration.
///
/// Four critics evaluate the same artifact from different perspectives:
/// security, performance, code quality, and testing coverage.
fn create_example_votes() -> Result<Vec<NegotiationVote>> {
    let votes = vec![
        NegotiationVote::new(
            "artifact_123".to_string(),
            "security_critic".to_string(),
            8.5,
            0.9,
            true,
            vec![
                "Strong authentication".to_string(),
                "Good input validation".to_string(),
            ],
            vec!["Missing rate limiting".to_string()],
            vec!["Add rate limiting to API endpoints".to_string()],
            "room_001".to_string(),
        )?,
        NegotiationVote::new(
            "artifact_123".to_string(),
            "performance_critic".to_string(),
            7.0,
            0.75,
            true,
            vec!["Efficient database queries".to_string()],
            vec!["No caching strategy".to_string()],
            vec!["Consider adding Redis cache".to_string()],
            "room_001".to_string(),
        )?,
        NegotiationVote::new(
            "artifact_123".to_string(),
            "code_quality_critic".to_string(),
            6.5,
            0.8,
            true,
            vec![
                "Clean code structure".to_string(),
                "Good documentation".to_string(),
            ],
            vec!["Some functions are too long".to_string()],
            vec!["Refactor large functions into smaller ones".to_string()],
            "room_001".to_string(),
        )?,
        NegotiationVote::new(
            "artifact_123".to_string(),
            "testing_critic".to_string(),
            9.0,
            0.95,
            true,
            vec![
                "Excellent test coverage".to_string(),
                "Good edge case handling".to_string(),
            ],
            vec![],
            vec!["Add more integration tests".to_string()],
            "room_001".to_string(),
        )?,
    ];

    Ok(votes)
}

/// Demonstrate all four aggregation strategies with the example votes.
///
/// Prints a formatted comparison of each strategy's output, followed by
/// analytical metrics (entropy, consensus, polarization, confidence variance)
/// and a comprehensive summary.
fn demonstrate_strategies() -> Result<()> {
    let votes = create_example_votes()?;

    println!("{}", "=".repeat(70));
    println!("Voting Aggregation Strategies Demonstration");
    println!("{}", "=".repeat(70));
    println!("\nNumber of votes: {}", votes.len());
    println!("\nIndividual votes:");
    for vote in &votes {
        println!(
            "  {:<25}: score={:.1}, confidence={:.2}, passed={}",
            vote.critic_id, vote.score, vote.confidence, vote.passed
        );
    }

    println!("\n{}", "=".repeat(70));
    println!("Strategy Comparison");
    println!("{}", "=".repeat(70));

    // 1. Simple Average
    println!("\n1. Simple Average Strategy:");
    println!("   Treats all votes equally");
    let simple_agg = VotingAggregator::new(Box::new(SimpleAverageAggregator::new()));
    let simple_result = simple_agg.aggregate(&votes)?;
    println!("   Mean score:    {:.2}", simple_result.mean);
    println!("   Weighted mean: {:.2}", simple_result.weighted_mean);
    println!("   Std deviation: {:.2}", simple_result.std_dev);

    // 2. Confidence Weighted
    println!("\n2. Confidence-Weighted Strategy:");
    println!("   Weights votes by critic confidence (POMDP-based)");
    let conf_agg = VotingAggregator::new(Box::new(ConfidenceWeightedAggregator::new()));
    let conf_result = conf_agg.aggregate(&votes)?;
    println!("   Mean score:    {:.2}", conf_result.mean);
    println!("   Weighted mean: {:.2}", conf_result.weighted_mean);
    println!("   -> Testing critic (0.95 conf, 9.0 score) has more influence");

    // 3. Majority Vote
    println!("\n3. Majority Vote Strategy:");
    println!("   Based on pass/fail count (ignores numerical scores)");
    let majority_agg = VotingAggregator::new(Box::new(MajorityVoteAggregator::new()));
    let majority_result = majority_agg.aggregate(&votes)?;
    println!("   Mean score:      {:.2}", majority_result.mean);
    println!("   Majority outcome: {:.2}", majority_result.weighted_mean);
    println!("   -> All critics passed, so score is 10.0");

    // 4. Borda Count
    println!("\n4. Borda Count Strategy:");
    println!("   Ranked voting with position-based points");
    let borda_agg = VotingAggregator::new(Box::new(BordaCountAggregator::new()));
    let borda_result = borda_agg.aggregate(&votes)?;
    println!("   Mean score:  {:.2}", borda_result.mean);
    println!("   Borda score: {:.2}", borda_result.weighted_mean);
    println!("   -> Ranks: testing(9.0)->security(8.5)->performance(7.0)->quality(6.5)");

    // Analytical methods (reuse conf_agg for analysis)
    println!("\n{}", "=".repeat(70));
    println!("Vote Analysis");
    println!("{}", "=".repeat(70));

    let entropy = conf_agg.compute_entropy(&votes)?;
    println!("\nEntropy: {:.3} bits", entropy);
    println!("  (Low entropy = high agreement, High entropy = high disagreement)");

    let consensus = conf_agg.detect_consensus(&votes, 0.8)?;
    println!("\nConsensus detected: {}", consensus);
    println!("  (Low std dev + high pass/fail agreement)");

    let polarization = conf_agg.detect_polarization(&votes)?;
    println!("\nPolarization detected: {}", polarization);
    println!("  (Bimodal distribution with votes at extremes)");

    let conf_variance = conf_agg.compute_confidence_variance(&votes)?;
    println!("\nConfidence variance: {:.4}", conf_variance);
    println!("  (How much critics' confidence levels vary)");

    // Comprehensive summary
    println!("\n{}", "=".repeat(70));
    println!("Comprehensive Summary");
    println!("{}", "=".repeat(70));
    let summary = conf_agg.get_vote_summary(&votes)?;
    println!("\nPass rate:            {:.1}%", summary.pass_rate * 100.0);
    println!("Entropy:              {:.3} bits", summary.entropy);
    println!(
        "Consensus:            {}",
        if summary.consensus { "Yes" } else { "No" }
    );
    println!(
        "Polarization:         {}",
        if summary.polarization { "Yes" } else { "No" }
    );
    println!("Confidence variance:  {:.4}", summary.confidence_variance);

    println!("\n{}", "=".repeat(70));

    Ok(())
}

/// Demonstrate polarization detection with a strongly divided vote set.
///
/// Two critics give high scores (8.5-9.0) while two others give very low
/// scores (1.5-2.0), creating a bimodal distribution that triggers the
/// polarization detector. This scenario typically warrants HITL escalation.
fn demonstrate_polarization() -> Result<()> {
    println!("\n{}", "=".repeat(70));
    println!("Polarization Example");
    println!("{}", "=".repeat(70));

    let polarized_votes = vec![
        NegotiationVote::new(
            "artifact_456".to_string(),
            "critic_1".to_string(),
            9.0,
            0.85,
            true,
            vec!["Excellent".to_string()],
            vec![],
            vec![],
            "room_002".to_string(),
        )?,
        NegotiationVote::new(
            "artifact_456".to_string(),
            "critic_2".to_string(),
            8.5,
            0.9,
            true,
            vec!["Very good".to_string()],
            vec![],
            vec![],
            "room_002".to_string(),
        )?,
        NegotiationVote::new(
            "artifact_456".to_string(),
            "critic_3".to_string(),
            2.0,
            0.8,
            false,
            vec![],
            vec!["Major issues".to_string()],
            vec!["Complete rewrite".to_string()],
            "room_002".to_string(),
        )?,
        NegotiationVote::new(
            "artifact_456".to_string(),
            "critic_4".to_string(),
            1.5,
            0.75,
            false,
            vec![],
            vec!["Critical flaws".to_string()],
            vec!["Start over".to_string()],
            "room_002".to_string(),
        )?,
    ];

    println!("\nPolarized votes (critics strongly disagree):");
    for vote in &polarized_votes {
        println!(
            "  {}: score={:.1}, passed={}",
            vote.critic_id, vote.score, vote.passed
        );
    }

    let aggregator = VotingAggregator::new(Box::new(ConfidenceWeightedAggregator::new()));
    let result = aggregator.aggregate(&polarized_votes)?;

    println!("\nSimple mean:   {:.2}", result.mean);
    println!("Std deviation: {:.2} (high variance)", result.std_dev);
    println!(
        "Entropy:       {:.3} bits",
        aggregator.compute_entropy(&polarized_votes)?
    );
    println!(
        "Consensus:     {}",
        aggregator.detect_consensus(&polarized_votes, 0.8)?
    );
    println!(
        "Polarization:  {} <- Detected!",
        aggregator.detect_polarization(&polarized_votes)?
    );

    println!("\n-> This indicates the artifact needs human review (HITL escalation)");

    Ok(())
}

fn main() -> Result<()> {
    demonstrate_strategies()?;
    demonstrate_polarization()?;

    println!("\n{}", "=".repeat(70));
    println!("Example completed successfully!");
    println!("{}", "=".repeat(70));

    Ok(())
}
