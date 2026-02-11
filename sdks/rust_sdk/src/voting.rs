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

//! Voting aggregation strategies for combining critic votes.
//!
//! This module provides traits and implementations for aggregating multiple
//! `NegotiationVote` instances into an `AggregatedScore`. Multiple strategies
//! are available:
//!
//! - `SimpleAverageAggregator`: Arithmetic mean of all scores
//! - `ConfidenceWeightedAggregator`: Weight votes by confidence (POMDP-based)
//! - `MajorityVoteAggregator`: Count passed vs failed votes
//! - `BordaCountAggregator`: Ranked voting with position-based points
//!
//! Additionally, the `VotingAggregator` struct provides analytical methods for
//! detecting consensus, polarization, and measuring uncertainty through entropy.

use crate::clients::negotiation_room::{AggregatedScore, NegotiationVote};
use crate::{Error, Result};
use serde::Serialize;

/// Trait for vote aggregation strategies.
///
/// Implementations must provide an aggregate method that takes a slice of votes
/// and returns an `AggregatedScore` with statistical summary.
pub trait AggregationStrategy: Send + Sync {
    /// Aggregate votes into a statistical summary.
    ///
    /// # Arguments
    ///
    /// * `votes` - Slice of critic votes to aggregate
    ///
    /// # Returns
    ///
    /// `AggregatedScore` with aggregation results.
    ///
    /// # Errors
    ///
    /// Returns an error if the votes slice is empty.
    fn aggregate(&self, votes: &[NegotiationVote]) -> Result<AggregatedScore>;
}

/// Simple arithmetic mean aggregation strategy.
///
/// Computes basic statistics without considering confidence levels.
/// All votes are weighted equally.
#[derive(Debug, Clone, Default)]
pub struct SimpleAverageAggregator;

impl SimpleAverageAggregator {
    /// Create a new simple average aggregator.
    pub fn new() -> Self {
        Self
    }
}

impl AggregationStrategy for SimpleAverageAggregator {
    fn aggregate(&self, votes: &[NegotiationVote]) -> Result<AggregatedScore> {
        if votes.is_empty() {
            return Err(Error::Config("Cannot aggregate empty list of votes".to_string()));
        }

        let scores: Vec<f64> = votes.iter().map(|v| v.score).collect();
        let n = scores.len() as f64;

        let mean = scores.iter().sum::<f64>() / n;
        let min_score = scores.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_score = scores.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

        let variance = scores.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / n;
        let std_dev = variance.sqrt();

        Ok(AggregatedScore {
            mean,
            min_score,
            max_score,
            std_dev,
            weighted_mean: mean, // Same as mean for simple average
            vote_count: votes.len(),
        })
    }
}

/// Confidence-weighted aggregation strategy based on POMDP research.
///
/// Weights each vote's score by its confidence value, giving more influence
/// to votes from critics with higher certainty. This implements the approach
/// from POMDP research where agent confidence reflects belief state certainty.
///
/// Formula: weighted_mean = sum(score_i * confidence_i) / sum(confidence_i)
#[derive(Debug, Clone, Default)]
pub struct ConfidenceWeightedAggregator;

impl ConfidenceWeightedAggregator {
    /// Create a new confidence-weighted aggregator.
    pub fn new() -> Self {
        Self
    }
}

impl AggregationStrategy for ConfidenceWeightedAggregator {
    fn aggregate(&self, votes: &[NegotiationVote]) -> Result<AggregatedScore> {
        if votes.is_empty() {
            return Err(Error::Config("Cannot aggregate empty list of votes".to_string()));
        }

        let scores: Vec<f64> = votes.iter().map(|v| v.score).collect();
        let confidences: Vec<f64> = votes.iter().map(|v| v.confidence).collect();
        let n = scores.len() as f64;

        // Basic statistics (unweighted)
        let mean = scores.iter().sum::<f64>() / n;
        let min_score = scores.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_score = scores.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

        let variance = scores.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / n;
        let std_dev = variance.sqrt();

        // Confidence-weighted mean
        let total_confidence: f64 = confidences.iter().sum();
        let weighted_mean = if total_confidence > 0.0 {
            scores
                .iter()
                .zip(confidences.iter())
                .map(|(s, c)| s * c)
                .sum::<f64>()
                / total_confidence
        } else {
            mean // Fallback to simple mean if all confidences are zero
        };

        Ok(AggregatedScore {
            mean,
            min_score,
            max_score,
            std_dev,
            weighted_mean,
            vote_count: votes.len(),
        })
    }
}

/// Majority voting aggregation strategy.
///
/// Counts the number of passed vs failed votes and returns a score based on
/// the majority outcome. This is a binary approach that ignores the numerical
/// score values and focuses on the pass/fail decision.
///
/// Score mapping:
/// - All passed: 10.0
/// - Majority passed (>50%): 7.5
/// - Tie: 5.0
/// - Majority failed (>50%): 2.5
/// - All failed: 0.0
#[derive(Debug, Clone, Default)]
pub struct MajorityVoteAggregator;

impl MajorityVoteAggregator {
    /// Create a new majority vote aggregator.
    pub fn new() -> Self {
        Self
    }
}

impl AggregationStrategy for MajorityVoteAggregator {
    fn aggregate(&self, votes: &[NegotiationVote]) -> Result<AggregatedScore> {
        if votes.is_empty() {
            return Err(Error::Config("Cannot aggregate empty list of votes".to_string()));
        }

        let scores: Vec<f64> = votes.iter().map(|v| v.score).collect();
        let passed_count = votes.iter().filter(|v| v.passed).count();
        let failed_count = votes.len() - passed_count;
        let n = scores.len() as f64;

        // Basic statistics on original scores
        let mean = scores.iter().sum::<f64>() / n;
        let min_score = scores.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_score = scores.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

        let variance = scores.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / n;
        let std_dev = variance.sqrt();

        // Determine majority outcome and assign score
        let majority_score = if passed_count == votes.len() {
            10.0 // All passed
        } else if failed_count == votes.len() {
            0.0 // All failed
        } else if passed_count > failed_count {
            7.5 // Majority passed
        } else if failed_count > passed_count {
            2.5 // Majority failed
        } else {
            5.0 // Tie
        };

        Ok(AggregatedScore {
            mean,
            min_score,
            max_score,
            std_dev,
            weighted_mean: majority_score,
            vote_count: votes.len(),
        })
    }
}

/// Borda count aggregation strategy.
///
/// Implements ranked voting where each vote receives points based on its
/// rank position. Higher scored votes receive more points.
///
/// Ranking system:
/// - Votes are sorted by score (highest to lowest)
/// - Highest score receives n points (where n = number of votes)
/// - Second highest receives n-1 points
/// - Lowest score receives 1 point
/// - Points are summed and normalized to 0-10 scale
///
/// This method is resistant to strategic voting and reduces impact of outliers.
#[derive(Debug, Clone, Default)]
pub struct BordaCountAggregator;

impl BordaCountAggregator {
    /// Create a new Borda count aggregator.
    pub fn new() -> Self {
        Self
    }
}

impl AggregationStrategy for BordaCountAggregator {
    fn aggregate(&self, votes: &[NegotiationVote]) -> Result<AggregatedScore> {
        if votes.is_empty() {
            return Err(Error::Config("Cannot aggregate empty list of votes".to_string()));
        }

        let scores: Vec<f64> = votes.iter().map(|v| v.score).collect();
        let n = scores.len();

        // Basic statistics
        let mean = scores.iter().sum::<f64>() / n as f64;
        let min_score = scores.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_score = scores.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

        let variance = scores.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / n as f64;
        let std_dev = variance.sqrt();

        // Borda count calculation
        // Sort scores with their indices to handle ties
        let mut indexed_scores: Vec<(usize, f64)> =
            scores.iter().enumerate().map(|(i, &s)| (i, s)).collect();
        indexed_scores.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        // Assign points based on rank (highest gets n points, lowest gets 1)
        let total_points: usize = indexed_scores
            .iter()
            .enumerate()
            .map(|(rank, _)| n - rank)
            .sum();

        // Normalize to 0-10 scale
        // Average points per position: total_points / n
        let avg_points = total_points as f64 / n as f64;
        // Normalize: avg_points / n * 10 gives us the normalized score
        let borda_score = (avg_points / n as f64) * 10.0;

        Ok(AggregatedScore {
            mean,
            min_score,
            max_score,
            std_dev,
            weighted_mean: borda_score,
            vote_count: n,
        })
    }
}

/// Main aggregator for combining critic votes with analytical capabilities.
///
/// Wraps an `AggregationStrategy` and provides additional methods for analyzing
/// vote distributions, detecting consensus, and identifying polarization.
pub struct VotingAggregator {
    strategy: Box<dyn AggregationStrategy>,
}

impl VotingAggregator {
    /// Create a new voting aggregator with the given strategy.
    ///
    /// # Arguments
    ///
    /// * `strategy` - The aggregation strategy to use
    pub fn new(strategy: Box<dyn AggregationStrategy>) -> Self {
        Self { strategy }
    }

    /// Aggregate votes using the configured strategy.
    ///
    /// # Arguments
    ///
    /// * `votes` - Slice of critic votes to aggregate
    ///
    /// # Returns
    ///
    /// `AggregatedScore` with aggregation results.
    ///
    /// # Errors
    ///
    /// Returns an error if the votes slice is empty.
    pub fn aggregate(&self, votes: &[NegotiationVote]) -> Result<AggregatedScore> {
        self.strategy.aggregate(votes)
    }

    /// Compute Shannon entropy of vote distribution.
    ///
    /// Entropy measures the uncertainty or disorder in the vote distribution.
    /// Higher entropy indicates more disagreement/uncertainty, lower entropy
    /// indicates more consensus.
    ///
    /// The score range [0, 10] is divided into bins, and entropy is computed
    /// over the probability distribution of votes across bins.
    ///
    /// # Arguments
    ///
    /// * `votes` - Slice of critic votes
    ///
    /// # Returns
    ///
    /// Entropy value in bits (0 = perfect consensus, higher = more uncertainty).
    ///
    /// # Errors
    ///
    /// Returns an error if the votes slice is empty.
    pub fn compute_entropy(&self, votes: &[NegotiationVote]) -> Result<f64> {
        if votes.is_empty() {
            return Err(Error::Config("Cannot compute entropy of empty vote list".to_string()));
        }

        // Create bins for score distribution (0-2, 2-4, 4-6, 6-8, 8-10)
        let num_bins = 5;
        let bin_width = 10.0 / num_bins as f64;
        let mut bin_counts = vec![0usize; num_bins];

        // Count votes in each bin
        for vote in votes {
            let bin_idx = ((vote.score / bin_width) as usize).min(num_bins - 1);
            bin_counts[bin_idx] += 1;
        }

        // Compute Shannon entropy
        let total = votes.len() as f64;
        let entropy: f64 = bin_counts
            .iter()
            .filter(|&&count| count > 0)
            .map(|&count| {
                let probability = count as f64 / total;
                -probability * probability.log2()
            })
            .sum();

        Ok(entropy)
    }

    /// Detect if votes show strong consensus.
    ///
    /// Consensus is detected when:
    /// 1. Standard deviation of scores is low (< 2.0)
    /// 2. A large proportion of critics agree on pass/fail (>= threshold)
    ///
    /// # Arguments
    ///
    /// * `votes` - Slice of critic votes
    /// * `threshold` - Minimum proportion of agreement required (default 0.8 = 80%)
    ///
    /// # Returns
    ///
    /// `true` if consensus is detected, `false` otherwise.
    ///
    /// # Errors
    ///
    /// Returns an error if the votes slice is empty or threshold is not in [0, 1].
    pub fn detect_consensus(&self, votes: &[NegotiationVote], threshold: f64) -> Result<bool> {
        if votes.is_empty() {
            return Err(Error::Config("Cannot detect consensus in empty vote list".to_string()));
        }
        if !(0.0..=1.0).contains(&threshold) {
            return Err(Error::Config(format!(
                "Threshold must be in [0, 1], got {}",
                threshold
            )));
        }

        let scores: Vec<f64> = votes.iter().map(|v| v.score).collect();
        let n = scores.len() as f64;

        // Compute standard deviation
        let mean = scores.iter().sum::<f64>() / n;
        let variance = scores.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / n;
        let std_dev = variance.sqrt();

        // Check if scores are tightly clustered
        if std_dev >= 2.0 {
            return Ok(false);
        }

        // Check if majority agrees on pass/fail
        let passed_count = votes.iter().filter(|v| v.passed).count();
        let failed_count = votes.len() - passed_count;

        let agreement_ratio = passed_count.max(failed_count) as f64 / votes.len() as f64;
        Ok(agreement_ratio >= threshold)
    }

    /// Detect if votes show polarization (bimodal distribution).
    ///
    /// Polarization is detected when votes cluster into two distinct groups,
    /// typically at opposite ends of the score spectrum. This is identified by:
    /// 1. High standard deviation (>= 3.0)
    /// 2. Low density in the middle range (4-6)
    /// 3. High density in the extremes (0-3 or 7-10)
    ///
    /// # Arguments
    ///
    /// * `votes` - Slice of critic votes
    ///
    /// # Returns
    ///
    /// `true` if polarization is detected, `false` otherwise.
    ///
    /// # Errors
    ///
    /// Returns an error if the votes slice is empty.
    pub fn detect_polarization(&self, votes: &[NegotiationVote]) -> Result<bool> {
        if votes.is_empty() {
            return Err(Error::Config(
                "Cannot detect polarization in empty vote list".to_string(),
            ));
        }

        if votes.len() < 3 {
            // Need at least 3 votes to meaningfully detect polarization
            return Ok(false);
        }

        let scores: Vec<f64> = votes.iter().map(|v| v.score).collect();
        let n = scores.len() as f64;

        // Compute standard deviation
        let mean = scores.iter().sum::<f64>() / n;
        let variance = scores.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / n;
        let std_dev = variance.sqrt();

        // High standard deviation suggests spread
        if std_dev < 3.0 {
            return Ok(false);
        }

        // Count votes in three regions: low (0-3), middle (4-6), high (7-10)
        let low_count = scores.iter().filter(|&&s| s <= 3.0).count();
        let middle_count = scores.iter().filter(|&&s| s > 3.0 && s < 7.0).count();
        let high_count = scores.iter().filter(|&&s| s >= 7.0).count();

        // Polarization: both extremes have votes, middle is sparse
        let has_low_cluster = low_count as f64 >= votes.len() as f64 * 0.3;
        let has_high_cluster = high_count as f64 >= votes.len() as f64 * 0.3;
        let middle_sparse = middle_count as f64 <= votes.len() as f64 * 0.2;

        Ok(has_low_cluster && has_high_cluster && middle_sparse)
    }

    /// Compute variance of confidence levels across votes.
    ///
    /// High variance in confidence suggests critics have different levels of
    /// certainty about their evaluations, which may indicate the artifact is
    /// harder to assess or has ambiguous quality.
    ///
    /// # Arguments
    ///
    /// * `votes` - Slice of critic votes
    ///
    /// # Returns
    ///
    /// Variance of confidence values.
    ///
    /// # Errors
    ///
    /// Returns an error if the votes slice is empty.
    pub fn compute_confidence_variance(&self, votes: &[NegotiationVote]) -> Result<f64> {
        if votes.is_empty() {
            return Err(Error::Config(
                "Cannot compute confidence variance of empty vote list".to_string(),
            ));
        }

        let confidences: Vec<f64> = votes.iter().map(|v| v.confidence).collect();
        let n = confidences.len() as f64;

        let mean_confidence = confidences.iter().sum::<f64>() / n;
        let variance = confidences
            .iter()
            .map(|c| (c - mean_confidence).powi(2))
            .sum::<f64>()
            / n;

        Ok(variance)
    }

    /// Get comprehensive summary of vote characteristics.
    ///
    /// Combines multiple analytical methods to provide a complete picture
    /// of the vote distribution and critic agreement.
    ///
    /// # Arguments
    ///
    /// * `votes` - Slice of critic votes
    ///
    /// # Returns
    ///
    /// `VoteSummary` with summary statistics.
    ///
    /// # Errors
    ///
    /// Returns an error if the votes slice is empty.
    pub fn get_vote_summary(&self, votes: &[NegotiationVote]) -> Result<VoteSummary> {
        if votes.is_empty() {
            return Err(Error::Config("Cannot summarize empty vote list".to_string()));
        }

        let passed_count = votes.iter().filter(|v| v.passed).count();

        Ok(VoteSummary {
            entropy: self.compute_entropy(votes)?,
            consensus: self.detect_consensus(votes, 0.8)?,
            polarization: self.detect_polarization(votes)?,
            confidence_variance: self.compute_confidence_variance(votes)?,
            pass_rate: passed_count as f64 / votes.len() as f64,
        })
    }
}

/// Summary of vote characteristics.
#[derive(Debug, Clone, Serialize)]
pub struct VoteSummary {
    /// Shannon entropy of score distribution
    pub entropy: f64,
    /// Whether consensus was detected
    pub consensus: bool,
    /// Whether polarization was detected
    pub polarization: bool,
    /// Variance of confidence levels
    pub confidence_variance: f64,
    /// Proportion of votes that passed
    pub pass_rate: f64,
}

/// Aggregate votes using confidence-weighted strategy.
///
/// This is a convenience function that uses the `ConfidenceWeightedAggregator`
/// to combine multiple critic votes into a single `AggregatedScore`.
///
/// This is the recommended default aggregation method as it weights each vote
/// by its confidence level, giving more influence to critics who are more
/// certain about their assessments.
///
/// # Arguments
///
/// * `votes` - Slice of `NegotiationVote` instances to aggregate
///
/// # Returns
///
/// An `AggregatedScore` containing:
/// - `mean`: Arithmetic mean of all scores
/// - `weighted_mean`: Confidence-weighted mean (recommended for decisions)
/// - `min_score`/`max_score`: Range of scores
/// - `std_dev`: Standard deviation (measure of consensus)
/// - `vote_count`: Number of votes aggregated
///
/// # Errors
///
/// Returns an error if the votes slice is empty.
///
/// # Example
///
/// ```rust
/// use sw4rm_sdk::voting::aggregate_votes;
/// use sw4rm_sdk::clients::negotiation_room::NegotiationVote;
///
/// let votes = vec![
///     NegotiationVote::new("art1".into(), "c1".into(), 8.0, 0.9, true, vec![], vec![], vec![], "room1".into()).unwrap(),
///     NegotiationVote::new("art1".into(), "c2".into(), 7.0, 0.7, true, vec![], vec![], vec![], "room1".into()).unwrap(),
/// ];
///
/// let aggregated = aggregate_votes(&votes).unwrap();
/// println!("Weighted score: {:.2}", aggregated.weighted_mean);
/// ```
pub fn aggregate_votes(votes: &[NegotiationVote]) -> Result<AggregatedScore> {
    ConfidenceWeightedAggregator::new().aggregate(votes)
}

/// Aggregate votes using a specified strategy.
///
/// Allows choosing a specific aggregation strategy for different use cases.
///
/// # Arguments
///
/// * `votes` - Slice of `NegotiationVote` instances to aggregate
/// * `strategy` - The aggregation strategy to use
///
/// # Returns
///
/// An `AggregatedScore` containing statistical summary of the votes.
///
/// # Errors
///
/// Returns an error if the votes slice is empty.
///
/// # Example
///
/// ```rust
/// use sw4rm_sdk::voting::{aggregate_votes_with_strategy, MajorityVoteAggregator};
/// use sw4rm_sdk::clients::negotiation_room::NegotiationVote;
///
/// let votes = vec![
///     NegotiationVote::new("art1".into(), "c1".into(), 8.0, 0.9, true, vec![], vec![], vec![], "room1".into()).unwrap(),
/// ];
/// let aggregated = aggregate_votes_with_strategy(&votes, &MajorityVoteAggregator::new()).unwrap();
/// ```
pub fn aggregate_votes_with_strategy<S: AggregationStrategy>(
    votes: &[NegotiationVote],
    strategy: &S,
) -> Result<AggregatedScore> {
    strategy.aggregate(votes)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_votes() -> Vec<NegotiationVote> {
        vec![
            NegotiationVote::new(
                "artifact".to_string(),
                "critic1".to_string(),
                8.0,
                0.9,
                true,
                vec![],
                vec![],
                vec![],
                "room".to_string(),
            )
            .unwrap(),
            NegotiationVote::new(
                "artifact".to_string(),
                "critic2".to_string(),
                7.0,
                0.8,
                true,
                vec![],
                vec![],
                vec![],
                "room".to_string(),
            )
            .unwrap(),
            NegotiationVote::new(
                "artifact".to_string(),
                "critic3".to_string(),
                9.0,
                0.95,
                true,
                vec![],
                vec![],
                vec![],
                "room".to_string(),
            )
            .unwrap(),
        ]
    }

    #[test]
    fn test_simple_average_aggregator() {
        let aggregator = SimpleAverageAggregator::new();
        let votes = create_test_votes();
        let result = aggregator.aggregate(&votes).unwrap();

        assert_eq!(result.vote_count, 3);
        assert!((result.mean - 8.0).abs() < 0.01);
        assert!((result.min_score - 7.0).abs() < 0.01);
        assert!((result.max_score - 9.0).abs() < 0.01);
        assert!((result.weighted_mean - 8.0).abs() < 0.01);
    }

    #[test]
    fn test_confidence_weighted_aggregator() {
        let aggregator = ConfidenceWeightedAggregator::new();
        let votes = create_test_votes();
        let result = aggregator.aggregate(&votes).unwrap();

        assert_eq!(result.vote_count, 3);
        // Weighted mean should be slightly higher than simple mean
        // because higher scores have higher confidence
        assert!(result.weighted_mean > result.mean - 0.5);
    }

    #[test]
    fn test_majority_vote_aggregator() {
        let aggregator = MajorityVoteAggregator::new();
        let votes = create_test_votes();
        let result = aggregator.aggregate(&votes).unwrap();

        // All votes passed, so weighted_mean should be 10.0
        assert!((result.weighted_mean - 10.0).abs() < 0.01);
    }

    #[test]
    fn test_borda_count_aggregator() {
        let aggregator = BordaCountAggregator::new();
        let votes = create_test_votes();
        let result = aggregator.aggregate(&votes).unwrap();

        assert_eq!(result.vote_count, 3);
        // Borda score should be between 0 and 10
        assert!(result.weighted_mean >= 0.0);
        assert!(result.weighted_mean <= 10.0);
    }

    #[test]
    fn test_empty_votes_error() {
        let aggregator = SimpleAverageAggregator::new();
        let empty: Vec<NegotiationVote> = vec![];
        let result = aggregator.aggregate(&empty);
        assert!(result.is_err());
    }

    #[test]
    fn test_voting_aggregator_entropy() {
        let aggregator = VotingAggregator::new(Box::new(SimpleAverageAggregator::new()));
        let votes = create_test_votes();
        let entropy = aggregator.compute_entropy(&votes).unwrap();

        // Entropy should be non-negative
        assert!(entropy >= 0.0);
    }

    #[test]
    fn test_voting_aggregator_consensus() {
        let aggregator = VotingAggregator::new(Box::new(SimpleAverageAggregator::new()));
        let votes = create_test_votes();

        // Votes are clustered and all passed, should be consensus
        let consensus = aggregator.detect_consensus(&votes, 0.8).unwrap();
        assert!(consensus);
    }

    #[test]
    fn test_voting_aggregator_polarization() {
        let aggregator = VotingAggregator::new(Box::new(SimpleAverageAggregator::new()));

        // Create polarized votes
        let votes = vec![
            NegotiationVote::new(
                "artifact".to_string(),
                "critic1".to_string(),
                1.0,
                0.9,
                false,
                vec![],
                vec![],
                vec![],
                "room".to_string(),
            )
            .unwrap(),
            NegotiationVote::new(
                "artifact".to_string(),
                "critic2".to_string(),
                2.0,
                0.8,
                false,
                vec![],
                vec![],
                vec![],
                "room".to_string(),
            )
            .unwrap(),
            NegotiationVote::new(
                "artifact".to_string(),
                "critic3".to_string(),
                9.0,
                0.95,
                true,
                vec![],
                vec![],
                vec![],
                "room".to_string(),
            )
            .unwrap(),
            NegotiationVote::new(
                "artifact".to_string(),
                "critic4".to_string(),
                10.0,
                0.9,
                true,
                vec![],
                vec![],
                vec![],
                "room".to_string(),
            )
            .unwrap(),
        ];

        let polarization = aggregator.detect_polarization(&votes).unwrap();
        assert!(polarization);
    }

    #[test]
    fn test_voting_aggregator_summary() {
        let aggregator = VotingAggregator::new(Box::new(SimpleAverageAggregator::new()));
        let votes = create_test_votes();
        let summary = aggregator.get_vote_summary(&votes).unwrap();

        assert!(summary.pass_rate > 0.0);
        assert!(summary.entropy >= 0.0);
    }

    #[test]
    fn test_confidence_variance() {
        let aggregator = VotingAggregator::new(Box::new(SimpleAverageAggregator::new()));
        let votes = create_test_votes();
        let variance = aggregator.compute_confidence_variance(&votes).unwrap();

        // Variance should be non-negative
        assert!(variance >= 0.0);
    }
}
