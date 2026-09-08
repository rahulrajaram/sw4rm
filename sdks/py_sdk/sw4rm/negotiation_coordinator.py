"""Decision coordination for the SW4RM negotiation room."""

from __future__ import annotations

from typing import List

from sw4rm.negotiation_types import AggregatedScore, DecisionOutcome, NegotiationVote
from sw4rm.policy_types import NegotiationPolicy
from sw4rm_policies.escalation import (
    PolicyDecision,
    ThresholdPolicy,
    apply_policy,
    escalation_reasons,
    should_auto_approve,
    should_escalate,
)

_DECISION_MAP = {
    PolicyDecision.APPROVED: DecisionOutcome.APPROVED,
    PolicyDecision.REVISION_REQUESTED: DecisionOutcome.REVISION_REQUESTED,
    PolicyDecision.ESCALATED_TO_HITL: DecisionOutcome.ESCALATED_TO_HITL,
}


def _sdk_decision(decision: PolicyDecision) -> DecisionOutcome:
    """Map every neutral decision to its SDK enum counterpart."""
    try:
        return _DECISION_MAP[decision]
    except KeyError as error:
        raise AssertionError("Unhandled neutral policy decision") from error


def _thresholds(policy: NegotiationPolicy) -> ThresholdPolicy:
    return ThresholdPolicy(policy.score_threshold, policy.diff_tolerance)


class NegotiationCoordinator:
    """Stateless coordinator retaining the historical SDK API."""

    def apply_policy(
        self, scores: AggregatedScore, policy: NegotiationPolicy
    ) -> DecisionOutcome:
        """Apply score and variance thresholds to aggregated scores."""
        return _sdk_decision(
            apply_policy(scores.weighted_mean, scores.std_dev, _thresholds(policy))
        )

    def should_auto_approve(self, score: float, policy: NegotiationPolicy) -> bool:
        """Return whether a score meets the normalized approval threshold."""
        return should_auto_approve(score, _thresholds(policy))

    def should_escalate(
        self, votes: List[NegotiationVote], policy: NegotiationPolicy
    ) -> bool:
        """Return whether votes require human review."""
        return should_escalate(votes, _thresholds(policy))

    def generate_decision_reason(
        self,
        outcome: DecisionOutcome,
        scores: AggregatedScore,
        votes: List[NegotiationVote],
        policy: NegotiationPolicy,
    ) -> str:
        """Generate the historical human-readable decision rationale."""
        threshold = policy.score_threshold * 10.0
        if outcome == DecisionOutcome.APPROVED:
            return (
                f"APPROVED: Weighted mean score ({scores.weighted_mean:.2f}) meets or exceeds "
                f"threshold ({threshold:.2f}). Received {scores.vote_count} votes with "
                f"standard deviation of {scores.std_dev:.2f}."
            )
        if outcome == DecisionOutcome.REVISION_REQUESTED:
            failed = sum(not vote.passed for vote in votes)
            return (
                f"REVISION_REQUESTED: Weighted mean score ({scores.weighted_mean:.2f}) below "
                f"threshold ({threshold:.2f}). {failed} of {scores.vote_count} critics "
                f"marked as failed. Score range: {scores.min_score:.2f} to {scores.max_score:.2f}."
            )
        if outcome == DecisionOutcome.ESCALATED_TO_HITL:
            reasons = escalation_reasons(scores.std_dev, policy.diff_tolerance, votes)
            reason = ", ".join(reasons) if reasons else "policy requirements"
            return (
                f"ESCALATED_TO_HITL: {reason}. Score range: {scores.min_score:.2f} to "
                f"{scores.max_score:.2f}. Human review required for final decision."
            )
        return f"Decision outcome: {outcome.name}"


__all__ = ["NegotiationCoordinator"]
