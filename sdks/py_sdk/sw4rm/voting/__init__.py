"""Voting and aggregation strategies for SW4RM Negotiation Rooms.

This module provides multiple aggregation strategies for combining critic votes,
implementing confidence-weighted voting based on POMDP research.

Key components:
- AggregationStrategy: Protocol for vote aggregation implementations
- VotingAggregator: Main aggregator class with consensus/polarization detection
- Multiple strategy implementations: SimpleAverage, ConfidenceWeighted, MajorityVote, BordaCount

Based on SPEC_REQUESTS.md Phase 3.4: Confidence-Weighted Voting.
"""
from sw4rm.voting.aggregation import VotingAggregator
from sw4rm.voting.strategies import (
    AggregationStrategy,
    BordaCountAggregator,
    ConfidenceWeightedAggregator,
    MajorityVoteAggregator,
    SimpleAverageAggregator,
)

__all__ = [
    "VotingAggregator",
    "AggregationStrategy",
    "SimpleAverageAggregator",
    "ConfidenceWeightedAggregator",
    "MajorityVoteAggregator",
    "BordaCountAggregator",
]
