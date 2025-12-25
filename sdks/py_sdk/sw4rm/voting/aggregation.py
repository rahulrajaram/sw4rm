"""Main voting aggregator with consensus and polarization detection.

This module provides the VotingAggregator class which combines a chosen
aggregation strategy with analytical methods for detecting consensus,
polarization, and measuring uncertainty through entropy.
"""
from __future__ import annotations

import math
from typing import TYPE_CHECKING

from sw4rm.negotiation_types import AggregatedScore, NegotiationVote

if TYPE_CHECKING:
    from sw4rm.voting.strategies import AggregationStrategy


class VotingAggregator:
    """Main aggregator for combining critic votes with analytical capabilities.

    Wraps an AggregationStrategy and provides additional methods for analyzing
    vote distributions, detecting consensus, and identifying polarization.

    Attributes:
        strategy: The aggregation strategy to use for combining votes
    """

    def __init__(self, strategy: AggregationStrategy) -> None:
        """Initialize aggregator with a strategy.

        Args:
            strategy: The aggregation strategy to use
        """
        self.strategy = strategy

    def aggregate(self, votes: list[NegotiationVote]) -> AggregatedScore:
        """Aggregate votes using the configured strategy.

        Args:
            votes: List of critic votes to aggregate

        Returns:
            AggregatedScore with aggregation results

        Raises:
            ValueError: If votes list is empty
        """
        return self.strategy.aggregate(votes)

    def compute_entropy(self, votes: list[NegotiationVote]) -> float:
        """Compute Shannon entropy of vote distribution.

        Entropy measures the uncertainty or disorder in the vote distribution.
        Higher entropy indicates more disagreement/uncertainty, lower entropy
        indicates more consensus.

        The score range [0, 10] is divided into bins, and entropy is computed
        over the probability distribution of votes across bins.

        Args:
            votes: List of critic votes

        Returns:
            Entropy value in bits (0 = perfect consensus, higher = more uncertainty)

        Raises:
            ValueError: If votes list is empty
        """
        if not votes:
            raise ValueError("Cannot compute entropy of empty vote list")

        # Create bins for score distribution (0-2, 2-4, 4-6, 6-8, 8-10)
        num_bins = 5
        bin_width = 10.0 / num_bins
        bin_counts = [0] * num_bins

        # Count votes in each bin
        for vote in votes:
            bin_idx = min(int(vote.score / bin_width), num_bins - 1)
            bin_counts[bin_idx] += 1

        # Compute Shannon entropy
        total = len(votes)
        entropy = 0.0
        for count in bin_counts:
            if count > 0:
                probability = count / total
                entropy -= probability * math.log2(probability)

        return entropy

    def detect_consensus(
        self, votes: list[NegotiationVote], threshold: float = 0.8
    ) -> bool:
        """Detect if votes show strong consensus.

        Consensus is detected when:
        1. Standard deviation of scores is low (< 2.0)
        2. A large proportion of critics agree on pass/fail (>= threshold)

        Args:
            votes: List of critic votes
            threshold: Minimum proportion of agreement required (default 0.8 = 80%)

        Returns:
            True if consensus is detected, False otherwise

        Raises:
            ValueError: If votes list is empty or threshold not in [0, 1]
        """
        if not votes:
            raise ValueError("Cannot detect consensus in empty vote list")
        if not 0.0 <= threshold <= 1.0:
            raise ValueError(f"Threshold must be in [0, 1], got {threshold}")

        # Compute standard deviation
        scores = [v.score for v in votes]
        mean = sum(scores) / len(scores)
        variance = sum((s - mean) ** 2 for s in scores) / len(scores)
        std_dev = variance ** 0.5

        # Check if scores are tightly clustered
        if std_dev >= 2.0:
            return False

        # Check if majority agrees on pass/fail
        passed_count = sum(1 for v in votes if v.passed)
        failed_count = len(votes) - passed_count

        agreement_ratio = max(passed_count, failed_count) / len(votes)
        return agreement_ratio >= threshold

    def detect_polarization(self, votes: list[NegotiationVote]) -> bool:
        """Detect if votes show polarization (bimodal distribution).

        Polarization is detected when votes cluster into two distinct groups,
        typically at opposite ends of the score spectrum. This is identified by:
        1. High standard deviation (>= 3.0)
        2. Low density in the middle range (4-6)
        3. High density in the extremes (0-3 or 7-10)

        Args:
            votes: List of critic votes

        Returns:
            True if polarization is detected, False otherwise

        Raises:
            ValueError: If votes list is empty
        """
        if not votes:
            raise ValueError("Cannot detect polarization in empty vote list")

        if len(votes) < 3:
            # Need at least 3 votes to meaningfully detect polarization
            return False

        # Compute standard deviation
        scores = [v.score for v in votes]
        mean = sum(scores) / len(scores)
        variance = sum((s - mean) ** 2 for s in scores) / len(scores)
        std_dev = variance ** 0.5

        # High standard deviation suggests spread
        if std_dev < 3.0:
            return False

        # Count votes in three regions: low (0-3), middle (4-6), high (7-10)
        low_count = sum(1 for s in scores if s <= 3.0)
        middle_count = sum(1 for s in scores if 3.0 < s < 7.0)
        high_count = sum(1 for s in scores if s >= 7.0)

        # Polarization: both extremes have votes, middle is sparse
        has_low_cluster = low_count >= len(votes) * 0.3
        has_high_cluster = high_count >= len(votes) * 0.3
        middle_sparse = middle_count <= len(votes) * 0.2

        return has_low_cluster and has_high_cluster and middle_sparse

    def compute_confidence_variance(self, votes: list[NegotiationVote]) -> float:
        """Compute variance of confidence levels across votes.

        High variance in confidence suggests critics have different levels of
        certainty about their evaluations, which may indicate the artifact is
        harder to assess or has ambiguous quality.

        Args:
            votes: List of critic votes

        Returns:
            Variance of confidence values

        Raises:
            ValueError: If votes list is empty
        """
        if not votes:
            raise ValueError("Cannot compute confidence variance of empty vote list")

        confidences = [v.confidence for v in votes]
        mean_confidence = sum(confidences) / len(confidences)
        variance = sum((c - mean_confidence) ** 2 for c in confidences) / len(confidences)
        return variance

    def get_vote_summary(self, votes: list[NegotiationVote]) -> dict[str, float]:
        """Get comprehensive summary of vote characteristics.

        Combines multiple analytical methods to provide a complete picture
        of the vote distribution and critic agreement.

        Args:
            votes: List of critic votes

        Returns:
            Dictionary with summary statistics:
            - entropy: Shannon entropy of score distribution
            - consensus: Boolean indicating consensus detection
            - polarization: Boolean indicating polarization detection
            - confidence_variance: Variance of confidence levels
            - pass_rate: Proportion of votes that passed

        Raises:
            ValueError: If votes list is empty
        """
        if not votes:
            raise ValueError("Cannot summarize empty vote list")

        passed_count = sum(1 for v in votes if v.passed)

        return {
            "entropy": self.compute_entropy(votes),
            "consensus": float(self.detect_consensus(votes)),
            "polarization": float(self.detect_polarization(votes)),
            "confidence_variance": self.compute_confidence_variance(votes),
            "pass_rate": passed_count / len(votes),
        }
