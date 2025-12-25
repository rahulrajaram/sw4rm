#!/usr/bin/env python3
"""Example demonstrating the voting aggregation system.

This example shows how to use different aggregation strategies to combine
critic votes in a negotiation room scenario.
"""
from sw4rm.negotiation_types import NegotiationVote
from sw4rm.voting import (
    BordaCountAggregator,
    ConfidenceWeightedAggregator,
    MajorityVoteAggregator,
    SimpleAverageAggregator,
    VotingAggregator,
)


def create_example_votes() -> list[NegotiationVote]:
    """Create a realistic set of votes for demonstration."""
    return [
        NegotiationVote(
            artifact_id="artifact_123",
            critic_id="security_critic",
            score=8.5,
            confidence=0.9,
            passed=True,
            strengths=["Strong authentication", "Good input validation"],
            weaknesses=["Missing rate limiting"],
            recommendations=["Add rate limiting to API endpoints"],
            negotiation_room_id="room_001",
        ),
        NegotiationVote(
            artifact_id="artifact_123",
            critic_id="performance_critic",
            score=7.0,
            confidence=0.75,
            passed=True,
            strengths=["Efficient database queries"],
            weaknesses=["No caching strategy"],
            recommendations=["Consider adding Redis cache"],
            negotiation_room_id="room_001",
        ),
        NegotiationVote(
            artifact_id="artifact_123",
            critic_id="code_quality_critic",
            score=6.5,
            confidence=0.8,
            passed=True,
            strengths=["Clean code structure", "Good documentation"],
            weaknesses=["Some functions are too long"],
            recommendations=["Refactor large functions into smaller ones"],
            negotiation_room_id="room_001",
        ),
        NegotiationVote(
            artifact_id="artifact_123",
            critic_id="testing_critic",
            score=9.0,
            confidence=0.95,
            passed=True,
            strengths=["Excellent test coverage", "Good edge case handling"],
            weaknesses=[],
            recommendations=["Add more integration tests"],
            negotiation_room_id="room_001",
        ),
    ]


def demonstrate_strategies():
    """Demonstrate different aggregation strategies."""
    votes = create_example_votes()

    print("=" * 70)
    print("Voting Aggregation Strategies Demonstration")
    print("=" * 70)
    print(f"\nNumber of votes: {len(votes)}")
    print("\nIndividual votes:")
    for vote in votes:
        print(f"  {vote.critic_id:25s}: score={vote.score:.1f}, "
              f"confidence={vote.confidence:.2f}, passed={vote.passed}")

    print("\n" + "=" * 70)
    print("Strategy Comparison")
    print("=" * 70)

    # 1. Simple Average
    print("\n1. Simple Average Strategy:")
    print("   Treats all votes equally")
    simple_agg = VotingAggregator(SimpleAverageAggregator())
    simple_result = simple_agg.aggregate(votes)
    print(f"   Mean score: {simple_result.mean:.2f}")
    print(f"   Weighted mean: {simple_result.weighted_mean:.2f}")
    print(f"   Std deviation: {simple_result.std_dev:.2f}")

    # 2. Confidence Weighted
    print("\n2. Confidence-Weighted Strategy:")
    print("   Weights votes by critic confidence (POMDP-based)")
    conf_agg = VotingAggregator(ConfidenceWeightedAggregator())
    conf_result = conf_agg.aggregate(votes)
    print(f"   Mean score: {conf_result.mean:.2f}")
    print(f"   Weighted mean: {conf_result.weighted_mean:.2f}")
    print(f"   → Testing critic (0.95 conf, 9.0 score) has more influence")

    # 3. Majority Vote
    print("\n3. Majority Vote Strategy:")
    print("   Based on pass/fail count (ignores numerical scores)")
    majority_agg = VotingAggregator(MajorityVoteAggregator())
    majority_result = majority_agg.aggregate(votes)
    print(f"   Mean score: {majority_result.mean:.2f}")
    print(f"   Majority outcome: {majority_result.weighted_mean:.2f}")
    print(f"   → All critics passed, so score is 10.0")

    # 4. Borda Count
    print("\n4. Borda Count Strategy:")
    print("   Ranked voting with position-based points")
    borda_agg = VotingAggregator(BordaCountAggregator())
    borda_result = borda_agg.aggregate(votes)
    print(f"   Mean score: {borda_result.mean:.2f}")
    print(f"   Borda score: {borda_result.weighted_mean:.2f}")
    print(f"   → Ranks: testing(9.0)→security(8.5)→performance(7.0)→quality(6.5)")

    # Analytical methods
    print("\n" + "=" * 70)
    print("Vote Analysis")
    print("=" * 70)

    print(f"\nEntropy: {conf_agg.compute_entropy(votes):.3f} bits")
    print("  (Low entropy = high agreement, High entropy = high disagreement)")

    print(f"\nConsensus detected: {conf_agg.detect_consensus(votes)}")
    print("  (Low std dev + high pass/fail agreement)")

    print(f"\nPolarization detected: {conf_agg.detect_polarization(votes)}")
    print("  (Bimodal distribution with votes at extremes)")

    print(f"\nConfidence variance: {conf_agg.compute_confidence_variance(votes):.4f}")
    print("  (How much critics' confidence levels vary)")

    # Comprehensive summary
    print("\n" + "=" * 70)
    print("Comprehensive Summary")
    print("=" * 70)
    summary = conf_agg.get_vote_summary(votes)
    print(f"\nPass rate: {summary['pass_rate']:.1%}")
    print(f"Entropy: {summary['entropy']:.3f} bits")
    print(f"Consensus: {'Yes' if summary['consensus'] else 'No'}")
    print(f"Polarization: {'Yes' if summary['polarization'] else 'No'}")
    print(f"Confidence variance: {summary['confidence_variance']:.4f}")

    print("\n" + "=" * 70)


def demonstrate_polarization():
    """Demonstrate polarization detection with a polarized vote set."""
    print("\n" + "=" * 70)
    print("Polarization Example")
    print("=" * 70)

    polarized_votes = [
        NegotiationVote(
            artifact_id="artifact_456",
            critic_id="critic_1",
            score=9.0,
            confidence=0.85,
            passed=True,
            strengths=["Excellent"],
            weaknesses=[],
            recommendations=[],
            negotiation_room_id="room_002",
        ),
        NegotiationVote(
            artifact_id="artifact_456",
            critic_id="critic_2",
            score=8.5,
            confidence=0.90,
            passed=True,
            strengths=["Very good"],
            weaknesses=[],
            recommendations=[],
            negotiation_room_id="room_002",
        ),
        NegotiationVote(
            artifact_id="artifact_456",
            critic_id="critic_3",
            score=2.0,
            confidence=0.80,
            passed=False,
            strengths=[],
            weaknesses=["Major issues"],
            recommendations=["Complete rewrite"],
            negotiation_room_id="room_002",
        ),
        NegotiationVote(
            artifact_id="artifact_456",
            critic_id="critic_4",
            score=1.5,
            confidence=0.75,
            passed=False,
            strengths=[],
            weaknesses=["Critical flaws"],
            recommendations=["Start over"],
            negotiation_room_id="room_002",
        ),
    ]

    print("\nPolarized votes (critics strongly disagree):")
    for vote in polarized_votes:
        print(f"  {vote.critic_id}: score={vote.score:.1f}, passed={vote.passed}")

    aggregator = VotingAggregator(ConfidenceWeightedAggregator())
    result = aggregator.aggregate(polarized_votes)

    print(f"\nSimple mean: {result.mean:.2f}")
    print(f"Std deviation: {result.std_dev:.2f} (high variance)")
    print(f"Entropy: {aggregator.compute_entropy(polarized_votes):.3f} bits")
    print(f"Consensus: {aggregator.detect_consensus(polarized_votes)}")
    print(f"Polarization: {aggregator.detect_polarization(polarized_votes)} ← Detected!")

    print("\n→ This indicates the artifact needs human review (HITL escalation)")


if __name__ == "__main__":
    demonstrate_strategies()
    demonstrate_polarization()
    print("\n" + "=" * 70)
    print("Example completed successfully!")
    print("=" * 70)
