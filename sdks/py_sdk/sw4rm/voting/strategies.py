"""Aggregation strategies for combining critic votes.

This module defines the AggregationStrategy protocol and provides multiple
implementations for aggregating NegotiationVote instances into AggregatedScore.

Strategies:
- SimpleAverageAggregator: Arithmetic mean of all scores
- ConfidenceWeightedAggregator: Weight votes by confidence (POMDP-based)
- MajorityVoteAggregator: Count passed vs failed votes
- BordaCountAggregator: Ranked voting with position-based points
"""
from __future__ import annotations

from typing import Protocol

from sw4rm.negotiation_types import AggregatedScore, NegotiationVote


class AggregationStrategy(Protocol):
    """Protocol for vote aggregation strategies.

    Implementations must provide an aggregate method that takes a list of votes
    and returns an AggregatedScore with statistical summary.
    """

    def aggregate(self, votes: list[NegotiationVote]) -> AggregatedScore:
        """Aggregate votes into statistical summary.

        Args:
            votes: List of critic votes to aggregate

        Returns:
            AggregatedScore with aggregation results

        Raises:
            ValueError: If votes list is empty or invalid
        """
        ...


class SimpleAverageAggregator:
    """Simple arithmetic mean aggregation strategy.

    Computes basic statistics without considering confidence levels.
    All votes are weighted equally.
    """

    def aggregate(self, votes: list[NegotiationVote]) -> AggregatedScore:
        """Aggregate votes using simple arithmetic mean.

        Args:
            votes: List of critic votes to aggregate

        Returns:
            AggregatedScore with simple mean in both mean and weighted_mean fields

        Raises:
            ValueError: If votes list is empty
        """
        if not votes:
            raise ValueError("Cannot aggregate empty list of votes")

        scores = [v.score for v in votes]

        # Basic statistics
        mean = sum(scores) / len(scores)
        min_score = min(scores)
        max_score = max(scores)

        # Standard deviation
        variance = sum((s - mean) ** 2 for s in scores) / len(scores)
        std_dev = variance ** 0.5

        # For simple average, weighted_mean equals mean
        return AggregatedScore(
            mean=mean,
            min_score=min_score,
            max_score=max_score,
            std_dev=std_dev,
            weighted_mean=mean,
            vote_count=len(votes),
        )


class ConfidenceWeightedAggregator:
    """Confidence-weighted aggregation strategy based on POMDP research.

    Weights each vote's score by its confidence value, giving more influence
    to votes from critics with higher certainty. This implements the approach
    from POMDP research where agent confidence reflects belief state certainty.

    Formula: weighted_mean = sum(score_i * confidence_i) / sum(confidence_i)
    """

    def aggregate(self, votes: list[NegotiationVote]) -> AggregatedScore:
        """Aggregate votes using confidence weighting.

        Args:
            votes: List of critic votes to aggregate

        Returns:
            AggregatedScore with confidence-weighted mean

        Raises:
            ValueError: If votes list is empty
        """
        if not votes:
            raise ValueError("Cannot aggregate empty list of votes")

        scores = [v.score for v in votes]
        confidences = [v.confidence for v in votes]

        # Basic statistics (unweighted)
        mean = sum(scores) / len(scores)
        min_score = min(scores)
        max_score = max(scores)

        # Standard deviation (unweighted)
        variance = sum((s - mean) ** 2 for s in scores) / len(scores)
        std_dev = variance ** 0.5

        # Confidence-weighted mean
        total_confidence = sum(confidences)
        if total_confidence > 0:
            weighted_mean = sum(s * c for s, c in zip(scores, confidences)) / total_confidence
        else:
            # Fallback to simple mean if all confidences are zero
            weighted_mean = mean

        return AggregatedScore(
            mean=mean,
            min_score=min_score,
            max_score=max_score,
            std_dev=std_dev,
            weighted_mean=weighted_mean,
            vote_count=len(votes),
        )


class MajorityVoteAggregator:
    """Majority voting aggregation strategy.

    Counts the number of passed vs failed votes and returns a score based on
    the majority outcome. This is a binary approach that ignores the numerical
    score values and focuses on the pass/fail decision.

    Score mapping:
    - All passed: 10.0
    - Majority passed (>50%): 7.5
    - Tie: 5.0
    - Majority failed (>50%): 2.5
    - All failed: 0.0
    """

    def aggregate(self, votes: list[NegotiationVote]) -> AggregatedScore:
        """Aggregate votes using majority voting.

        Args:
            votes: List of critic votes to aggregate

        Returns:
            AggregatedScore with score based on majority outcome

        Raises:
            ValueError: If votes list is empty
        """
        if not votes:
            raise ValueError("Cannot aggregate empty list of votes")

        scores = [v.score for v in votes]
        passed_count = sum(1 for v in votes if v.passed)
        failed_count = len(votes) - passed_count

        # Determine majority outcome and assign score
        if passed_count == len(votes):
            # All passed
            majority_score = 10.0
        elif failed_count == len(votes):
            # All failed
            majority_score = 0.0
        elif passed_count > failed_count:
            # Majority passed
            majority_score = 7.5
        elif failed_count > passed_count:
            # Majority failed
            majority_score = 2.5
        else:
            # Tie
            majority_score = 5.0

        # Basic statistics on original scores
        mean = sum(scores) / len(scores)
        min_score = min(scores)
        max_score = max(scores)
        variance = sum((s - mean) ** 2 for s in scores) / len(scores)
        std_dev = variance ** 0.5

        return AggregatedScore(
            mean=mean,
            min_score=min_score,
            max_score=max_score,
            std_dev=std_dev,
            weighted_mean=majority_score,
            vote_count=len(votes),
        )


class BordaCountAggregator:
    """Borda count aggregation strategy (score-derived ranks).

    Votes are ranked by score (highest first, stable for ties) and each vote
    receives Borda points by rank: the highest scored vote receives ``n``
    points, the second ``n - 1``, and the lowest ``1``.  The aggregate
    ``weighted_mean`` is the Borda-points-weighted mean of the actual scores,
    so the result depends on the vote scores, not just the vote count:

        weighted_mean = sum(points_i * score_i) / sum(points_i)

    This method is resistant to strategic voting and reduces impact of
    outliers while remaining score-sensitive.

    Note: the Lisp and Elixir SDKs implement classic Borda over ranked
    preference lists (``vote.choice``) — a distinct input format producing
    per-choice winners, not a scored-vote aggregate.
    """

    def aggregate(self, votes: list[NegotiationVote]) -> AggregatedScore:
        """Aggregate votes using score-derived Borda count.

        Args:
            votes: List of critic votes to aggregate

        Returns:
            AggregatedScore with the Borda-weighted mean score

        Raises:
            ValueError: If votes list is empty
        """
        if not votes:
            raise ValueError("Cannot aggregate empty list of votes")

        scores = [v.score for v in votes]
        n = len(votes)

        # Basic statistics
        mean = sum(scores) / n
        min_score = min(scores)
        max_score = max(scores)
        variance = sum((s - mean) ** 2 for s in scores) / n
        std_dev = variance ** 0.5

        # Borda count calculation: points by score-derived rank (stable sort
        # keeps tied scores in input order).
        indexed_scores = [(score, idx) for idx, score in enumerate(scores)]
        indexed_scores.sort(key=lambda x: x[0], reverse=True)

        weighted = 0.0
        total_points = 0
        for rank, (score, _idx) in enumerate(indexed_scores):
            points = n - rank
            weighted += points * score
            total_points += points

        borda_score = weighted / total_points

        return AggregatedScore(
            mean=mean,
            min_score=min_score,
            max_score=max_score,
            std_dev=std_dev,
            weighted_mean=borda_score,
            vote_count=n,
        )
