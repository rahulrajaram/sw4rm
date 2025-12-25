"""Negotiation Coordinator for SW4RM.

This module provides the NegotiationCoordinator class for making decisions
based on critic votes and negotiation policies. The coordinator implements
the decision-making logic for the Negotiation Room pattern:
- Applying policies to aggregated scores
- Determining auto-approval based on thresholds
- Detecting escalation conditions

Based on SPEC_REQUESTS.md section 6.1.
"""
from __future__ import annotations

from sw4rm.negotiation_types import (
    AggregatedScore,
    DecisionOutcome,
    NegotiationVote,
)
from sw4rm.policy_types import NegotiationPolicy


class NegotiationCoordinator:
    """Coordinator for making decisions in negotiation rooms.

    The coordinator applies policy rules to critic votes and aggregated
    scores to determine the final decision outcome. It implements the
    three key decision paths:
    1. Auto-approval when scores exceed thresholds
    2. Revision request when scores are below thresholds
    3. Escalation to HITL when votes are conflicting or uncertain

    This is a stateless coordinator that makes decisions based on the
    provided inputs without maintaining session state.
    """

    def __init__(self) -> None:
        """Initialize the negotiation coordinator."""
        pass

    def apply_policy(
        self,
        scores: AggregatedScore,
        policy: NegotiationPolicy,
    ) -> DecisionOutcome:
        """Apply negotiation policy to aggregated scores to determine outcome.

        Evaluates the aggregated scores against the policy thresholds to
        determine whether to approve, request revisions, or escalate.

        Decision logic:
        1. If weighted_mean >= score_threshold: APPROVED
        2. If weighted_mean < score_threshold: REVISION_REQUESTED
        3. If std_dev > diff_tolerance: ESCALATED_TO_HITL (high variance indicates conflict)

        Note: Escalation check takes precedence over approval/revision to ensure
        conflicting votes are reviewed by humans.

        Args:
            scores: Aggregated voting statistics
            policy: Negotiation policy with thresholds

        Returns:
            The decision outcome based on policy evaluation

        Example:
            >>> coordinator = NegotiationCoordinator()
            >>> scores = AggregatedScore(
            ...     mean=8.5,
            ...     min_score=8.0,
            ...     max_score=9.0,
            ...     std_dev=0.5,
            ...     weighted_mean=8.6,
            ...     vote_count=3
            ... )
            >>> policy = NegotiationPolicy(
            ...     score_threshold=0.8,  # 8.0 on 0-10 scale
            ...     diff_tolerance=0.1     # std_dev threshold
            ... )
            >>> # Note: score_threshold is 0-1 scale, but scores are 0-10
            >>> # We normalize scores to 0-1 for comparison
            >>> outcome = coordinator.apply_policy(scores, policy)
        """
        # Normalize score_threshold from 0-1 to 0-10 scale to match scores
        # Policy uses 0-1 scale, but NegotiationVote uses 0-10 scale
        normalized_threshold = policy.score_threshold * 10.0

        # Check for high variance indicating conflict
        # diff_tolerance is in 0-1 scale, std_dev is in 0-10 scale
        normalized_diff_tolerance = policy.diff_tolerance * 10.0

        if scores.std_dev > normalized_diff_tolerance:
            # High variance indicates disagreement among critics
            return DecisionOutcome.ESCALATED_TO_HITL

        # Check if scores meet approval threshold
        if scores.weighted_mean >= normalized_threshold:
            return DecisionOutcome.APPROVED

        # Scores below threshold require revision
        return DecisionOutcome.REVISION_REQUESTED

    def should_auto_approve(
        self,
        score: float,
        policy: NegotiationPolicy,
    ) -> bool:
        """Check if a score meets the auto-approval threshold.

        Determines whether a single score (or weighted mean) is high enough
        to automatically approve without further review.

        Args:
            score: The score to evaluate (0-10 scale)
            policy: Negotiation policy with score threshold

        Returns:
            True if score meets or exceeds the approval threshold, False otherwise

        Example:
            >>> coordinator = NegotiationCoordinator()
            >>> policy = NegotiationPolicy(score_threshold=0.8)
            >>> coordinator.should_auto_approve(9.0, policy)
            True
            >>> coordinator.should_auto_approve(7.0, policy)
            False
        """
        # Normalize policy threshold from 0-1 to 0-10 scale
        normalized_threshold = policy.score_threshold * 10.0
        return score >= normalized_threshold

    def should_escalate(
        self,
        votes: list[NegotiationVote],
        policy: NegotiationPolicy,
    ) -> bool:
        """Determine if votes should be escalated to human review.

        Checks for conditions that indicate votes need human-in-the-loop
        review:
        1. Any critic explicitly marked the artifact as failed
        2. High variance in scores (indicates disagreement)
        3. Low confidence across critics (indicates uncertainty)

        Args:
            votes: List of critic votes to evaluate
            policy: Negotiation policy with escalation thresholds

        Returns:
            True if votes should be escalated, False otherwise

        Example:
            >>> coordinator = NegotiationCoordinator()
            >>> votes = [
            ...     NegotiationVote(
            ...         artifact_id="code-123",
            ...         critic_id="critic-1",
            ...         score=9.0,
            ...         confidence=0.9,
            ...         passed=True,
            ...         strengths=["Good"],
            ...         weaknesses=[],
            ...         recommendations=[],
            ...         negotiation_room_id="room-1"
            ...     ),
            ...     NegotiationVote(
            ...         artifact_id="code-123",
            ...         critic_id="critic-2",
            ...         score=3.0,  # Very different score
            ...         confidence=0.9,
            ...         passed=False,  # Failed
            ...         strengths=[],
            ...         weaknesses=["Poor"],
            ...         recommendations=["Rewrite"],
            ...         negotiation_room_id="room-1"
            ...     )
            ... ]
            >>> policy = NegotiationPolicy(diff_tolerance=0.1)
            >>> coordinator.should_escalate(votes, policy)
            True
        """
        if not votes:
            # No votes yet, no escalation needed
            return False

        # Check if any critic explicitly failed the artifact
        for vote in votes:
            if not vote.passed:
                return True

        # Check for low confidence across all critics
        avg_confidence = sum(v.confidence for v in votes) / len(votes)
        if avg_confidence < 0.5:
            # Low confidence threshold
            return True

        # Check for high variance in scores
        if len(votes) >= 2:
            scores = [v.score for v in votes]
            mean_score = sum(scores) / len(scores)
            variance = sum((s - mean_score) ** 2 for s in scores) / len(scores)
            std_dev = variance ** 0.5

            # Normalize diff_tolerance from 0-1 to 0-10 scale
            normalized_diff_tolerance = policy.diff_tolerance * 10.0

            if std_dev > normalized_diff_tolerance:
                return True

        return False

    def generate_decision_reason(
        self,
        outcome: DecisionOutcome,
        scores: AggregatedScore,
        votes: list[NegotiationVote],
        policy: NegotiationPolicy,
    ) -> str:
        """Generate a human-readable explanation for a decision.

        Creates a detailed rationale explaining why a particular outcome
        was chosen based on the votes and policy thresholds.

        Args:
            outcome: The decision outcome
            scores: Aggregated voting statistics
            votes: All critic votes
            policy: The policy that was applied

        Returns:
            A human-readable explanation of the decision

        Example:
            >>> coordinator = NegotiationCoordinator()
            >>> outcome = DecisionOutcome.APPROVED
            >>> scores = AggregatedScore(
            ...     mean=8.5, min_score=8.0, max_score=9.0,
            ...     std_dev=0.5, weighted_mean=8.6, vote_count=3
            ... )
            >>> votes = []  # Simplified for example
            >>> policy = NegotiationPolicy(score_threshold=0.8)
            >>> reason = coordinator.generate_decision_reason(
            ...     outcome, scores, votes, policy
            ... )
            >>> "APPROVED" in reason
            True
        """
        normalized_threshold = policy.score_threshold * 10.0

        if outcome == DecisionOutcome.APPROVED:
            return (
                f"APPROVED: Weighted mean score ({scores.weighted_mean:.2f}) "
                f"meets or exceeds threshold ({normalized_threshold:.2f}). "
                f"Received {scores.vote_count} votes with standard deviation "
                f"of {scores.std_dev:.2f}."
            )

        elif outcome == DecisionOutcome.REVISION_REQUESTED:
            failed_votes = [v for v in votes if not v.passed]
            return (
                f"REVISION_REQUESTED: Weighted mean score ({scores.weighted_mean:.2f}) "
                f"below threshold ({normalized_threshold:.2f}). "
                f"{len(failed_votes)} of {scores.vote_count} critics marked as failed. "
                f"Score range: {scores.min_score:.2f} to {scores.max_score:.2f}."
            )

        elif outcome == DecisionOutcome.ESCALATED_TO_HITL:
            failed_votes = [v for v in votes if not v.passed]
            avg_confidence = sum(v.confidence for v in votes) / len(votes) if votes else 0.0

            reasons = []
            if scores.std_dev > policy.diff_tolerance * 10.0:
                reasons.append(f"high variance (std_dev={scores.std_dev:.2f})")
            if failed_votes:
                reasons.append(f"{len(failed_votes)} failed votes")
            if avg_confidence < 0.5:
                reasons.append(f"low confidence (avg={avg_confidence:.2f})")

            reason_str = ", ".join(reasons) if reasons else "policy requirements"

            return (
                f"ESCALATED_TO_HITL: {reason_str}. "
                f"Score range: {scores.min_score:.2f} to {scores.max_score:.2f}. "
                f"Human review required for final decision."
            )

        else:
            return f"Decision outcome: {outcome.name}"
