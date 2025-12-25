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

/**
 * Voting and aggregation strategies for SW4RM.
 *
 * This module provides aggregation strategies for combining critic votes
 * in negotiation room workflows. Strategies include:
 * - SimpleAverageAggregator: Arithmetic mean of all scores
 * - ConfidenceWeightedAggregator: Weight votes by confidence (POMDP-based)
 * - MajorityVoteAggregator: Count passed vs failed votes
 * - BordaCountAggregator: Ranked voting with position-based points
 *
 * Based on Python SDK voting/strategies.py and voting/aggregation.py.
 */

import {
  NegotiationVote,
  AggregatedScore,
  NegotiationValidationError,
} from '../clients/negotiationRoom.js';

/**
 * Interface for vote aggregation strategies.
 *
 * Implementations must provide an aggregate method that takes a list of votes
 * and returns an AggregatedScore with statistical summary.
 */
export interface VotingAggregator {
  /**
   * Aggregate votes into statistical summary.
   *
   * @param votes - List of critic votes to aggregate
   * @returns AggregatedScore with aggregation results
   * @throws NegotiationValidationError if votes list is empty or invalid
   */
  aggregate(votes: NegotiationVote[]): AggregatedScore;
}

/**
 * Simple arithmetic mean aggregation strategy.
 *
 * Computes basic statistics without considering confidence levels.
 * All votes are weighted equally.
 */
export class SimpleAverageAggregator implements VotingAggregator {
  /**
   * Aggregate votes using simple arithmetic mean.
   *
   * @param votes - List of critic votes to aggregate
   * @returns AggregatedScore with simple mean in both mean and weightedMean fields
   * @throws NegotiationValidationError if votes list is empty
   */
  aggregate(votes: NegotiationVote[]): AggregatedScore {
    if (votes.length === 0) {
      throw new NegotiationValidationError(
        'Cannot aggregate empty list of votes'
      );
    }

    const scores = votes.map((v) => v.score);

    // Basic statistics
    const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
    const minScore = Math.min(...scores);
    const maxScore = Math.max(...scores);

    // Standard deviation
    const variance =
      scores.reduce((sum, s) => sum + Math.pow(s - mean, 2), 0) / scores.length;
    const stdDev = Math.sqrt(variance);

    // For simple average, weightedMean equals mean
    return {
      mean,
      minScore,
      maxScore,
      stdDev,
      weightedMean: mean,
      voteCount: votes.length,
    };
  }
}

/**
 * Confidence-weighted aggregation strategy based on POMDP research.
 *
 * Weights each vote's score by its confidence value, giving more influence
 * to votes from critics with higher certainty. This implements the approach
 * from POMDP research where agent confidence reflects belief state certainty.
 *
 * Formula: weighted_mean = sum(score_i * confidence_i) / sum(confidence_i)
 */
export class ConfidenceWeightedAggregator implements VotingAggregator {
  /**
   * Aggregate votes using confidence weighting.
   *
   * @param votes - List of critic votes to aggregate
   * @returns AggregatedScore with confidence-weighted mean
   * @throws NegotiationValidationError if votes list is empty
   */
  aggregate(votes: NegotiationVote[]): AggregatedScore {
    if (votes.length === 0) {
      throw new NegotiationValidationError(
        'Cannot aggregate empty list of votes'
      );
    }

    const scores = votes.map((v) => v.score);
    const confidences = votes.map((v) => v.confidence);

    // Basic statistics (unweighted)
    const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
    const minScore = Math.min(...scores);
    const maxScore = Math.max(...scores);

    // Standard deviation (unweighted)
    const variance =
      scores.reduce((sum, s) => sum + Math.pow(s - mean, 2), 0) / scores.length;
    const stdDev = Math.sqrt(variance);

    // Confidence-weighted mean
    const totalConfidence = confidences.reduce((a, b) => a + b, 0);
    let weightedMean: number;
    if (totalConfidence > 0) {
      weightedMean =
        scores.reduce((sum, s, i) => sum + s * confidences[i], 0) /
        totalConfidence;
    } else {
      // Fallback to simple mean if all confidences are zero
      weightedMean = mean;
    }

    return {
      mean,
      minScore,
      maxScore,
      stdDev,
      weightedMean,
      voteCount: votes.length,
    };
  }
}

/**
 * Majority voting aggregation strategy.
 *
 * Counts the number of passed vs failed votes and returns a score based on
 * the majority outcome. This is a binary approach that ignores the numerical
 * score values and focuses on the pass/fail decision.
 *
 * Score mapping:
 * - All passed: 10.0
 * - Majority passed (>50%): 7.5
 * - Tie: 5.0
 * - Majority failed (>50%): 2.5
 * - All failed: 0.0
 */
export class MajorityVoteAggregator implements VotingAggregator {
  /**
   * Aggregate votes using majority voting.
   *
   * @param votes - List of critic votes to aggregate
   * @returns AggregatedScore with score based on majority outcome
   * @throws NegotiationValidationError if votes list is empty
   */
  aggregate(votes: NegotiationVote[]): AggregatedScore {
    if (votes.length === 0) {
      throw new NegotiationValidationError(
        'Cannot aggregate empty list of votes'
      );
    }

    const scores = votes.map((v) => v.score);
    const passedCount = votes.filter((v) => v.passed).length;
    const failedCount = votes.length - passedCount;

    // Determine majority outcome and assign score
    let majorityScore: number;
    if (passedCount === votes.length) {
      // All passed
      majorityScore = 10.0;
    } else if (failedCount === votes.length) {
      // All failed
      majorityScore = 0.0;
    } else if (passedCount > failedCount) {
      // Majority passed
      majorityScore = 7.5;
    } else if (failedCount > passedCount) {
      // Majority failed
      majorityScore = 2.5;
    } else {
      // Tie
      majorityScore = 5.0;
    }

    // Basic statistics on original scores
    const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
    const minScore = Math.min(...scores);
    const maxScore = Math.max(...scores);
    const variance =
      scores.reduce((sum, s) => sum + Math.pow(s - mean, 2), 0) / scores.length;
    const stdDev = Math.sqrt(variance);

    return {
      mean,
      minScore,
      maxScore,
      stdDev,
      weightedMean: majorityScore,
      voteCount: votes.length,
    };
  }
}

/**
 * Borda count aggregation strategy.
 *
 * Implements ranked voting where each vote receives points based on its
 * rank position. Higher scored votes receive more points.
 *
 * Ranking system:
 * - Votes are sorted by score (highest to lowest)
 * - Highest score receives n points (where n = number of votes)
 * - Second highest receives n-1 points
 * - Lowest score receives 1 point
 * - Points are summed and normalized to 0-10 scale
 *
 * This method is resistant to strategic voting and reduces impact of outliers.
 */
export class BordaCountAggregator implements VotingAggregator {
  /**
   * Aggregate votes using Borda count.
   *
   * @param votes - List of critic votes to aggregate
   * @returns AggregatedScore with Borda count normalized score
   * @throws NegotiationValidationError if votes list is empty
   */
  aggregate(votes: NegotiationVote[]): AggregatedScore {
    if (votes.length === 0) {
      throw new NegotiationValidationError(
        'Cannot aggregate empty list of votes'
      );
    }

    const scores = votes.map((v) => v.score);
    const n = votes.length;

    // Basic statistics
    const mean = scores.reduce((a, b) => a + b, 0) / n;
    const minScore = Math.min(...scores);
    const maxScore = Math.max(...scores);
    const variance =
      scores.reduce((sum, s) => sum + Math.pow(s - mean, 2), 0) / n;
    const stdDev = Math.sqrt(variance);

    // Borda count calculation
    // Sort scores with their indices to handle ties
    const indexedScores = scores.map((score, idx) => ({ score, idx }));
    indexedScores.sort((a, b) => b.score - a.score);

    // Assign points based on rank (highest gets n points, lowest gets 1)
    let totalPoints = 0;
    for (let rank = 0; rank < indexedScores.length; rank++) {
      const points = n - rank;
      totalPoints += points;
    }

    // Normalize to 0-10 scale
    // Average points per position
    const avgPoints = totalPoints / n;
    // Normalize: avgPoints / n * 10 gives us the normalized score
    const bordaScore = (avgPoints / n) * 10.0;

    return {
      mean,
      minScore,
      maxScore,
      stdDev,
      weightedMean: bordaScore,
      voteCount: n,
    };
  }
}

/**
 * Main aggregator class with consensus and polarization detection.
 *
 * Wraps a VotingAggregator strategy and provides additional methods for
 * analyzing vote distributions, detecting consensus, and identifying
 * polarization.
 */
export class VotingAnalyzer {
  private strategy: VotingAggregator;

  /**
   * Initialize analyzer with a strategy.
   *
   * @param strategy - The aggregation strategy to use
   */
  constructor(strategy: VotingAggregator) {
    this.strategy = strategy;
  }

  /**
   * Aggregate votes using the configured strategy.
   *
   * @param votes - List of critic votes to aggregate
   * @returns AggregatedScore with aggregation results
   * @throws NegotiationValidationError if votes list is empty
   */
  aggregate(votes: NegotiationVote[]): AggregatedScore {
    return this.strategy.aggregate(votes);
  }

  /**
   * Compute Shannon entropy of vote distribution.
   *
   * Entropy measures the uncertainty or disorder in the vote distribution.
   * Higher entropy indicates more disagreement/uncertainty, lower entropy
   * indicates more consensus.
   *
   * The score range [0, 10] is divided into bins, and entropy is computed
   * over the probability distribution of votes across bins.
   *
   * @param votes - List of critic votes
   * @returns Entropy value in bits (0 = perfect consensus, higher = more uncertainty)
   * @throws NegotiationValidationError if votes list is empty
   */
  computeEntropy(votes: NegotiationVote[]): number {
    if (votes.length === 0) {
      throw new NegotiationValidationError(
        'Cannot compute entropy of empty vote list'
      );
    }

    // Create bins for score distribution (0-2, 2-4, 4-6, 6-8, 8-10)
    const numBins = 5;
    const binWidth = 10.0 / numBins;
    const binCounts = new Array(numBins).fill(0);

    // Count votes in each bin
    for (const vote of votes) {
      const binIdx = Math.min(Math.floor(vote.score / binWidth), numBins - 1);
      binCounts[binIdx]++;
    }

    // Compute Shannon entropy
    const total = votes.length;
    let entropy = 0.0;
    for (const count of binCounts) {
      if (count > 0) {
        const probability = count / total;
        entropy -= probability * Math.log2(probability);
      }
    }

    return entropy;
  }

  /**
   * Detect if votes show strong consensus.
   *
   * Consensus is detected when:
   * 1. Standard deviation of scores is low (< 2.0)
   * 2. A large proportion of critics agree on pass/fail (>= threshold)
   *
   * @param votes - List of critic votes
   * @param threshold - Minimum proportion of agreement required (default 0.8 = 80%)
   * @returns True if consensus is detected, false otherwise
   * @throws NegotiationValidationError if votes list is empty or threshold not in [0, 1]
   */
  detectConsensus(votes: NegotiationVote[], threshold: number = 0.8): boolean {
    if (votes.length === 0) {
      throw new NegotiationValidationError(
        'Cannot detect consensus in empty vote list'
      );
    }
    if (threshold < 0.0 || threshold > 1.0) {
      throw new NegotiationValidationError(
        `Threshold must be in [0, 1], got ${threshold}`
      );
    }

    // Compute standard deviation
    const scores = votes.map((v) => v.score);
    const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
    const variance =
      scores.reduce((sum, s) => sum + Math.pow(s - mean, 2), 0) / scores.length;
    const stdDev = Math.sqrt(variance);

    // Check if scores are tightly clustered
    if (stdDev >= 2.0) {
      return false;
    }

    // Check if majority agrees on pass/fail
    const passedCount = votes.filter((v) => v.passed).length;
    const failedCount = votes.length - passedCount;

    const agreementRatio = Math.max(passedCount, failedCount) / votes.length;
    return agreementRatio >= threshold;
  }

  /**
   * Detect if votes show polarization (bimodal distribution).
   *
   * Polarization is detected when votes cluster into two distinct groups,
   * typically at opposite ends of the score spectrum. This is identified by:
   * 1. High standard deviation (>= 3.0)
   * 2. Low density in the middle range (4-6)
   * 3. High density in the extremes (0-3 or 7-10)
   *
   * @param votes - List of critic votes
   * @returns True if polarization is detected, false otherwise
   * @throws NegotiationValidationError if votes list is empty
   */
  detectPolarization(votes: NegotiationVote[]): boolean {
    if (votes.length === 0) {
      throw new NegotiationValidationError(
        'Cannot detect polarization in empty vote list'
      );
    }

    if (votes.length < 3) {
      // Need at least 3 votes to meaningfully detect polarization
      return false;
    }

    // Compute standard deviation
    const scores = votes.map((v) => v.score);
    const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
    const variance =
      scores.reduce((sum, s) => sum + Math.pow(s - mean, 2), 0) / scores.length;
    const stdDev = Math.sqrt(variance);

    // High standard deviation suggests spread
    if (stdDev < 3.0) {
      return false;
    }

    // Count votes in three regions: low (0-3), middle (4-6), high (7-10)
    const lowCount = scores.filter((s) => s <= 3.0).length;
    const middleCount = scores.filter((s) => s > 3.0 && s < 7.0).length;
    const highCount = scores.filter((s) => s >= 7.0).length;

    // Polarization: both extremes have votes, middle is sparse
    const hasLowCluster = lowCount >= votes.length * 0.3;
    const hasHighCluster = highCount >= votes.length * 0.3;
    const middleSparse = middleCount <= votes.length * 0.2;

    return hasLowCluster && hasHighCluster && middleSparse;
  }

  /**
   * Compute variance of confidence levels across votes.
   *
   * High variance in confidence suggests critics have different levels of
   * certainty about their evaluations, which may indicate the artifact is
   * harder to assess or has ambiguous quality.
   *
   * @param votes - List of critic votes
   * @returns Variance of confidence values
   * @throws NegotiationValidationError if votes list is empty
   */
  computeConfidenceVariance(votes: NegotiationVote[]): number {
    if (votes.length === 0) {
      throw new NegotiationValidationError(
        'Cannot compute confidence variance of empty vote list'
      );
    }

    const confidences = votes.map((v) => v.confidence);
    const meanConfidence =
      confidences.reduce((a, b) => a + b, 0) / confidences.length;
    const variance =
      confidences.reduce(
        (sum, c) => sum + Math.pow(c - meanConfidence, 2),
        0
      ) / confidences.length;

    return variance;
  }

  /**
   * Get comprehensive summary of vote characteristics.
   *
   * Combines multiple analytical methods to provide a complete picture
   * of the vote distribution and critic agreement.
   *
   * @param votes - List of critic votes
   * @returns Object with summary statistics
   * @throws NegotiationValidationError if votes list is empty
   */
  getVoteSummary(votes: NegotiationVote[]): {
    entropy: number;
    consensus: boolean;
    polarization: boolean;
    confidenceVariance: number;
    passRate: number;
  } {
    if (votes.length === 0) {
      throw new NegotiationValidationError('Cannot summarize empty vote list');
    }

    const passedCount = votes.filter((v) => v.passed).length;

    return {
      entropy: this.computeEntropy(votes),
      consensus: this.detectConsensus(votes),
      polarization: this.detectPolarization(votes),
      confidenceVariance: this.computeConfidenceVariance(votes),
      passRate: passedCount / votes.length,
    };
  }
}
