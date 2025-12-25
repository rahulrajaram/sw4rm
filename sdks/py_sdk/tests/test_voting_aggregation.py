"""Tests for voting aggregation strategies and VotingAggregator.

Tests cover:
- All aggregation strategies (SimpleAverage, ConfidenceWeighted, MajorityVote, BordaCount)
- Edge cases (empty votes, single vote, all same score, ties)
- Entropy calculation
- Consensus detection
- Polarization detection
- Confidence variance
"""
import math

import pytest

from sw4rm.negotiation_types import NegotiationVote
from sw4rm.voting import (
    BordaCountAggregator,
    ConfidenceWeightedAggregator,
    MajorityVoteAggregator,
    SimpleAverageAggregator,
    VotingAggregator,
)


def create_vote(
    score: float,
    confidence: float = 0.8,
    passed: bool = True,
    critic_id: str = "critic_1",
) -> NegotiationVote:
    """Helper to create a test vote."""
    return NegotiationVote(
        artifact_id="test_artifact",
        critic_id=critic_id,
        score=score,
        confidence=confidence,
        passed=passed,
        strengths=["good"],
        weaknesses=["bad"],
        recommendations=["improve"],
        negotiation_room_id="room_1",
    )


class TestSimpleAverageAggregator:
    """Tests for SimpleAverageAggregator."""

    def test_simple_average_basic(self):
        """Test basic arithmetic mean aggregation."""
        votes = [
            create_vote(8.0, critic_id="c1"),
            create_vote(6.0, critic_id="c2"),
            create_vote(7.0, critic_id="c3"),
        ]

        aggregator = SimpleAverageAggregator()
        result = aggregator.aggregate(votes)

        assert result.mean == 7.0
        assert result.weighted_mean == 7.0  # Same as mean for simple average
        assert result.min_score == 6.0
        assert result.max_score == 8.0
        assert result.vote_count == 3
        assert result.std_dev > 0  # Should have some variance

    def test_simple_average_all_same(self):
        """Test aggregation when all scores are identical."""
        votes = [
            create_vote(5.0, critic_id=f"c{i}")
            for i in range(5)
        ]

        aggregator = SimpleAverageAggregator()
        result = aggregator.aggregate(votes)

        assert result.mean == 5.0
        assert result.weighted_mean == 5.0
        assert result.min_score == 5.0
        assert result.max_score == 5.0
        assert result.std_dev == 0.0
        assert result.vote_count == 5

    def test_simple_average_single_vote(self):
        """Test aggregation with single vote."""
        votes = [create_vote(7.5)]

        aggregator = SimpleAverageAggregator()
        result = aggregator.aggregate(votes)

        assert result.mean == 7.5
        assert result.weighted_mean == 7.5
        assert result.min_score == 7.5
        assert result.max_score == 7.5
        assert result.std_dev == 0.0
        assert result.vote_count == 1

    def test_simple_average_empty_votes(self):
        """Test that empty vote list raises ValueError."""
        aggregator = SimpleAverageAggregator()
        with pytest.raises(ValueError, match="Cannot aggregate empty list"):
            aggregator.aggregate([])


class TestConfidenceWeightedAggregator:
    """Tests for ConfidenceWeightedAggregator."""

    def test_confidence_weighted_basic(self):
        """Test confidence-weighted aggregation."""
        votes = [
            create_vote(8.0, confidence=0.9, critic_id="c1"),
            create_vote(4.0, confidence=0.5, critic_id="c2"),
            create_vote(6.0, confidence=0.7, critic_id="c3"),
        ]

        aggregator = ConfidenceWeightedAggregator()
        result = aggregator.aggregate(votes)

        # Mean should be simple average
        assert result.mean == 6.0

        # Weighted mean should favor high-confidence votes
        # (8*0.9 + 4*0.5 + 6*0.7) / (0.9 + 0.5 + 0.7)
        # = (7.2 + 2.0 + 4.2) / 2.1 = 13.4 / 2.1 ≈ 6.38
        expected_weighted = (8.0 * 0.9 + 4.0 * 0.5 + 6.0 * 0.7) / (0.9 + 0.5 + 0.7)
        assert abs(result.weighted_mean - expected_weighted) < 0.01

        assert result.min_score == 4.0
        assert result.max_score == 8.0
        assert result.vote_count == 3

    def test_confidence_weighted_high_confidence_dominates(self):
        """Test that high confidence votes dominate the weighted mean."""
        votes = [
            create_vote(9.0, confidence=0.95, critic_id="c1"),
            create_vote(2.0, confidence=0.1, critic_id="c2"),
            create_vote(3.0, confidence=0.1, critic_id="c3"),
        ]

        aggregator = ConfidenceWeightedAggregator()
        result = aggregator.aggregate(votes)

        # Simple mean should be around 4.67
        assert abs(result.mean - 4.67) < 0.1

        # Weighted mean should be much closer to 9.0 (high confidence vote)
        assert result.weighted_mean > 7.0

    def test_confidence_weighted_zero_confidence(self):
        """Test handling of zero confidence votes."""
        votes = [
            create_vote(8.0, confidence=0.0, critic_id="c1"),
            create_vote(6.0, confidence=0.0, critic_id="c2"),
        ]

        aggregator = ConfidenceWeightedAggregator()
        result = aggregator.aggregate(votes)

        # Should fall back to simple mean when all confidences are zero
        assert result.weighted_mean == 7.0

    def test_confidence_weighted_empty_votes(self):
        """Test that empty vote list raises ValueError."""
        aggregator = ConfidenceWeightedAggregator()
        with pytest.raises(ValueError, match="Cannot aggregate empty list"):
            aggregator.aggregate([])


class TestMajorityVoteAggregator:
    """Tests for MajorityVoteAggregator."""

    def test_majority_vote_all_passed(self):
        """Test when all votes passed."""
        votes = [
            create_vote(8.0, passed=True, critic_id=f"c{i}")
            for i in range(5)
        ]

        aggregator = MajorityVoteAggregator()
        result = aggregator.aggregate(votes)

        # All passed should give 10.0
        assert result.weighted_mean == 10.0
        assert result.vote_count == 5

    def test_majority_vote_all_failed(self):
        """Test when all votes failed."""
        votes = [
            create_vote(3.0, passed=False, critic_id=f"c{i}")
            for i in range(5)
        ]

        aggregator = MajorityVoteAggregator()
        result = aggregator.aggregate(votes)

        # All failed should give 0.0
        assert result.weighted_mean == 0.0

    def test_majority_vote_majority_passed(self):
        """Test when majority passed."""
        votes = [
            create_vote(8.0, passed=True, critic_id="c1"),
            create_vote(7.0, passed=True, critic_id="c2"),
            create_vote(6.5, passed=True, critic_id="c3"),
            create_vote(4.0, passed=False, critic_id="c4"),
        ]

        aggregator = MajorityVoteAggregator()
        result = aggregator.aggregate(votes)

        # Majority passed should give 7.5
        assert result.weighted_mean == 7.5

    def test_majority_vote_majority_failed(self):
        """Test when majority failed."""
        votes = [
            create_vote(5.0, passed=False, critic_id="c1"),
            create_vote(4.0, passed=False, critic_id="c2"),
            create_vote(3.0, passed=False, critic_id="c3"),
            create_vote(7.0, passed=True, critic_id="c4"),
        ]

        aggregator = MajorityVoteAggregator()
        result = aggregator.aggregate(votes)

        # Majority failed should give 2.5
        assert result.weighted_mean == 2.5

    def test_majority_vote_tie(self):
        """Test when votes are tied."""
        votes = [
            create_vote(8.0, passed=True, critic_id="c1"),
            create_vote(7.0, passed=True, critic_id="c2"),
            create_vote(4.0, passed=False, critic_id="c3"),
            create_vote(3.0, passed=False, critic_id="c4"),
        ]

        aggregator = MajorityVoteAggregator()
        result = aggregator.aggregate(votes)

        # Tie should give 5.0
        assert result.weighted_mean == 5.0

    def test_majority_vote_empty_votes(self):
        """Test that empty vote list raises ValueError."""
        aggregator = MajorityVoteAggregator()
        with pytest.raises(ValueError, match="Cannot aggregate empty list"):
            aggregator.aggregate([])


class TestBordaCountAggregator:
    """Tests for BordaCountAggregator."""

    def test_borda_count_basic(self):
        """Test basic Borda count aggregation."""
        votes = [
            create_vote(9.0, critic_id="c1"),  # Rank 1: 3 points
            create_vote(7.0, critic_id="c2"),  # Rank 2: 2 points
            create_vote(5.0, critic_id="c3"),  # Rank 3: 1 point
        ]

        aggregator = BordaCountAggregator()
        result = aggregator.aggregate(votes)

        # Total points: 3 + 2 + 1 = 6
        # Average points: 6 / 3 = 2
        # Normalized: (2 / 3) * 10 = 6.67
        assert abs(result.weighted_mean - 6.67) < 0.1
        assert result.vote_count == 3

    def test_borda_count_all_same(self):
        """Test Borda count with identical scores."""
        votes = [
            create_vote(7.0, critic_id=f"c{i}")
            for i in range(4)
        ]

        aggregator = BordaCountAggregator()
        result = aggregator.aggregate(votes)

        # All same scores should give middle value
        # With 4 votes: points are 4,3,2,1 = 10 total, avg = 2.5
        # Normalized: (2.5 / 4) * 10 = 6.25
        assert abs(result.weighted_mean - 6.25) < 0.1

    def test_borda_count_extremes(self):
        """Test Borda count with extreme scores."""
        votes = [
            create_vote(10.0, critic_id="c1"),
            create_vote(0.0, critic_id="c2"),
        ]

        aggregator = BordaCountAggregator()
        result = aggregator.aggregate(votes)

        # 2 votes: 2 points + 1 point = 3 total, avg = 1.5
        # Normalized: (1.5 / 2) * 10 = 7.5
        assert abs(result.weighted_mean - 7.5) < 0.1

    def test_borda_count_single_vote(self):
        """Test Borda count with single vote."""
        votes = [create_vote(7.0)]

        aggregator = BordaCountAggregator()
        result = aggregator.aggregate(votes)

        # Single vote gets 1 point, normalized: (1/1) * 10 = 10.0
        assert result.weighted_mean == 10.0

    def test_borda_count_empty_votes(self):
        """Test that empty vote list raises ValueError."""
        aggregator = BordaCountAggregator()
        with pytest.raises(ValueError, match="Cannot aggregate empty list"):
            aggregator.aggregate([])


class TestVotingAggregator:
    """Tests for VotingAggregator main class."""

    def test_voting_aggregator_uses_strategy(self):
        """Test that VotingAggregator delegates to strategy."""
        votes = [
            create_vote(8.0, critic_id="c1"),
            create_vote(6.0, critic_id="c2"),
        ]

        # Test with SimpleAverageAggregator
        aggregator = VotingAggregator(SimpleAverageAggregator())
        result = aggregator.aggregate(votes)
        assert result.mean == 7.0
        assert result.weighted_mean == 7.0

        # Test with ConfidenceWeightedAggregator
        aggregator = VotingAggregator(ConfidenceWeightedAggregator())
        result = aggregator.aggregate(votes)
        assert result.mean == 7.0
        # weighted_mean might differ based on confidence

    def test_compute_entropy_uniform_distribution(self):
        """Test entropy with uniform score distribution."""
        # One vote in each bin (0-2, 2-4, 4-6, 6-8, 8-10)
        votes = [
            create_vote(1.0, critic_id="c1"),
            create_vote(3.0, critic_id="c2"),
            create_vote(5.0, critic_id="c3"),
            create_vote(7.0, critic_id="c4"),
            create_vote(9.0, critic_id="c5"),
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        entropy = aggregator.compute_entropy(votes)

        # Uniform distribution over 5 bins: log2(5) ≈ 2.32
        assert abs(entropy - math.log2(5)) < 0.01

    def test_compute_entropy_perfect_consensus(self):
        """Test entropy with perfect consensus (all same score)."""
        votes = [
            create_vote(7.0, critic_id=f"c{i}")
            for i in range(5)
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        entropy = aggregator.compute_entropy(votes)

        # Perfect consensus: entropy should be 0
        assert entropy == 0.0

    def test_compute_entropy_empty_votes(self):
        """Test that entropy computation fails on empty votes."""
        aggregator = VotingAggregator(SimpleAverageAggregator())
        with pytest.raises(ValueError, match="Cannot compute entropy"):
            aggregator.compute_entropy([])

    def test_detect_consensus_strong(self):
        """Test consensus detection with strong agreement."""
        votes = [
            create_vote(7.5, passed=True, critic_id="c1"),
            create_vote(7.8, passed=True, critic_id="c2"),
            create_vote(7.2, passed=True, critic_id="c3"),
            create_vote(7.6, passed=True, critic_id="c4"),
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        consensus = aggregator.detect_consensus(votes)

        assert consensus is True

    def test_detect_consensus_high_variance(self):
        """Test that high variance prevents consensus detection."""
        votes = [
            create_vote(9.0, passed=True, critic_id="c1"),
            create_vote(8.0, passed=True, critic_id="c2"),
            create_vote(2.0, passed=False, critic_id="c3"),
            create_vote(3.0, passed=False, critic_id="c4"),
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        consensus = aggregator.detect_consensus(votes)

        # High variance should prevent consensus
        assert consensus is False

    def test_detect_consensus_low_agreement(self):
        """Test that low agreement prevents consensus."""
        votes = [
            create_vote(7.1, passed=True, critic_id="c1"),
            create_vote(7.2, passed=True, critic_id="c2"),
            create_vote(7.0, passed=False, critic_id="c3"),
            create_vote(6.9, passed=False, critic_id="c4"),
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        consensus = aggregator.detect_consensus(votes, threshold=0.8)

        # Only 50% agreement, below 80% threshold
        assert consensus is False

    def test_detect_consensus_custom_threshold(self):
        """Test consensus with custom threshold."""
        votes = [
            create_vote(7.0, passed=True, critic_id="c1"),
            create_vote(7.0, passed=True, critic_id="c2"),
            create_vote(7.0, passed=False, critic_id="c3"),
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())

        # With 67% threshold, should detect consensus (2/3 = 66.7%)
        assert aggregator.detect_consensus(votes, threshold=0.66) is True

        # With 70% threshold, should not detect consensus
        assert aggregator.detect_consensus(votes, threshold=0.70) is False

    def test_detect_consensus_invalid_threshold(self):
        """Test that invalid threshold raises ValueError."""
        votes = [create_vote(7.0)]
        aggregator = VotingAggregator(SimpleAverageAggregator())

        with pytest.raises(ValueError, match="Threshold must be in"):
            aggregator.detect_consensus(votes, threshold=1.5)

    def test_detect_consensus_empty_votes(self):
        """Test that consensus detection fails on empty votes."""
        aggregator = VotingAggregator(SimpleAverageAggregator())
        with pytest.raises(ValueError, match="Cannot detect consensus"):
            aggregator.detect_consensus([])

    def test_detect_polarization_clear_case(self):
        """Test polarization detection with clear bimodal distribution."""
        votes = [
            create_vote(9.0, passed=True, critic_id="c1"),
            create_vote(9.5, passed=True, critic_id="c2"),
            create_vote(8.5, passed=True, critic_id="c3"),
            create_vote(2.0, passed=False, critic_id="c4"),
            create_vote(1.5, passed=False, critic_id="c5"),
            create_vote(2.5, passed=False, critic_id="c6"),
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        polarization = aggregator.detect_polarization(votes)

        assert polarization is True

    def test_detect_polarization_no_polarization(self):
        """Test that normal distribution is not detected as polarized."""
        votes = [
            create_vote(6.0, critic_id="c1"),
            create_vote(6.5, critic_id="c2"),
            create_vote(7.0, critic_id="c3"),
            create_vote(6.8, critic_id="c4"),
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        polarization = aggregator.detect_polarization(votes)

        assert polarization is False

    def test_detect_polarization_too_few_votes(self):
        """Test that polarization cannot be detected with very few votes."""
        votes = [
            create_vote(9.0, critic_id="c1"),
            create_vote(1.0, critic_id="c2"),
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        polarization = aggregator.detect_polarization(votes)

        # Less than 3 votes cannot show polarization
        assert polarization is False

    def test_detect_polarization_empty_votes(self):
        """Test that polarization detection fails on empty votes."""
        aggregator = VotingAggregator(SimpleAverageAggregator())
        with pytest.raises(ValueError, match="Cannot detect polarization"):
            aggregator.detect_polarization([])

    def test_compute_confidence_variance_uniform(self):
        """Test confidence variance with uniform confidence."""
        votes = [
            create_vote(7.0, confidence=0.8, critic_id=f"c{i}")
            for i in range(5)
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        variance = aggregator.compute_confidence_variance(votes)

        # All same confidence: variance should be 0
        assert variance == 0.0

    def test_compute_confidence_variance_varied(self):
        """Test confidence variance with varied confidence."""
        votes = [
            create_vote(7.0, confidence=0.9, critic_id="c1"),
            create_vote(7.0, confidence=0.5, critic_id="c2"),
            create_vote(7.0, confidence=0.7, critic_id="c3"),
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        variance = aggregator.compute_confidence_variance(votes)

        # Should have non-zero variance
        assert variance > 0

    def test_compute_confidence_variance_empty_votes(self):
        """Test that confidence variance fails on empty votes."""
        aggregator = VotingAggregator(SimpleAverageAggregator())
        with pytest.raises(ValueError, match="Cannot compute confidence variance"):
            aggregator.compute_confidence_variance([])

    def test_get_vote_summary_comprehensive(self):
        """Test comprehensive vote summary."""
        votes = [
            create_vote(8.0, confidence=0.9, passed=True, critic_id="c1"),
            create_vote(7.5, confidence=0.8, passed=True, critic_id="c2"),
            create_vote(7.8, confidence=0.85, passed=True, critic_id="c3"),
        ]

        aggregator = VotingAggregator(SimpleAverageAggregator())
        summary = aggregator.get_vote_summary(votes)

        assert "entropy" in summary
        assert "consensus" in summary
        assert "polarization" in summary
        assert "confidence_variance" in summary
        assert "pass_rate" in summary

        assert summary["pass_rate"] == 1.0  # All passed
        assert summary["consensus"] == 1.0  # Should detect consensus
        assert summary["polarization"] == 0.0  # No polarization
        assert summary["entropy"] >= 0  # Valid entropy
        assert summary["confidence_variance"] >= 0  # Valid variance

    def test_get_vote_summary_empty_votes(self):
        """Test that vote summary fails on empty votes."""
        aggregator = VotingAggregator(SimpleAverageAggregator())
        with pytest.raises(ValueError, match="Cannot summarize empty vote list"):
            aggregator.get_vote_summary([])


class TestEdgeCases:
    """Tests for edge cases across all aggregators."""

    def test_extreme_scores(self):
        """Test all aggregators handle extreme scores (0 and 10)."""
        votes = [
            create_vote(0.0, critic_id="c1"),
            create_vote(10.0, critic_id="c2"),
        ]

        strategies = [
            SimpleAverageAggregator(),
            ConfidenceWeightedAggregator(),
            MajorityVoteAggregator(),
            BordaCountAggregator(),
        ]

        for strategy in strategies:
            result = strategy.aggregate(votes)
            assert result.min_score == 0.0
            assert result.max_score == 10.0
            assert result.vote_count == 2
            assert 0.0 <= result.weighted_mean <= 10.0

    def test_many_votes(self):
        """Test all aggregators handle large number of votes."""
        votes = [
            create_vote(float(i % 10), critic_id=f"c{i}")
            for i in range(100)
        ]

        strategies = [
            SimpleAverageAggregator(),
            ConfidenceWeightedAggregator(),
            MajorityVoteAggregator(),
            BordaCountAggregator(),
        ]

        for strategy in strategies:
            result = strategy.aggregate(votes)
            assert result.vote_count == 100
            assert 0.0 <= result.weighted_mean <= 10.0

    def test_varying_confidence_levels(self):
        """Test that confidence weighting works with varied levels."""
        votes = [
            create_vote(9.0, confidence=1.0, critic_id="c1"),
            create_vote(1.0, confidence=0.0, critic_id="c2"),
            create_vote(5.0, confidence=0.5, critic_id="c3"),
        ]

        # Confidence weighted should be heavily influenced by high confidence vote
        weighted_agg = ConfidenceWeightedAggregator()
        weighted_result = weighted_agg.aggregate(votes)

        # Simple average should be (9 + 1 + 5) / 3 = 5.0
        simple_agg = SimpleAverageAggregator()
        simple_result = simple_agg.aggregate(votes)

        assert simple_result.weighted_mean == 5.0
        # Weighted should be closer to 9.0 due to high confidence
        # (9*1.0 + 1*0.0 + 5*0.5) / (1.0 + 0.0 + 0.5) = 11.5 / 1.5 ≈ 7.67
        assert weighted_result.weighted_mean > 7.0
