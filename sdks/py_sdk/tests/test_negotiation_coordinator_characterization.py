"""Characterization tests for legacy negotiation-coordinator behavior."""

from __future__ import annotations

from sw4rm.negotiation_coordinator import NegotiationCoordinator
from sw4rm.negotiation_types import (
    AggregatedScore,
    DecisionOutcome,
    NegotiationVote,
)
from sw4rm.policy_types import NegotiationPolicy


def _policy() -> NegotiationPolicy:
    return NegotiationPolicy(score_threshold=0.8, diff_tolerance=0.1)


def _scores(*, weighted_mean: float = 8.0, std_dev: float = 1.0) -> AggregatedScore:
    return AggregatedScore(
        mean=weighted_mean,
        min_score=3.0,
        max_score=9.0,
        std_dev=std_dev,
        weighted_mean=weighted_mean,
        vote_count=2,
    )


def _vote(
    *,
    score: float = 8.0,
    confidence: float = 0.9,
    passed: bool = True,
    recommendations: list[str] | None = None,
) -> NegotiationVote:
    return NegotiationVote(
        artifact_id="artifact-1",
        critic_id=f"critic-{score}-{confidence}",
        score=score,
        confidence=confidence,
        passed=passed,
        strengths=[],
        weaknesses=[],
        recommendations=recommendations or [],
        negotiation_room_id="room-1",
    )


def test_apply_policy_threshold_boundaries_and_precedence():
    coordinator = NegotiationCoordinator()
    policy = _policy()
    assert (
        coordinator.apply_policy(_scores(weighted_mean=8.0), policy)
        is DecisionOutcome.APPROVED
    )
    assert (
        coordinator.apply_policy(_scores(weighted_mean=7.99), policy)
        is DecisionOutcome.REVISION_REQUESTED
    )
    assert (
        coordinator.apply_policy(_scores(weighted_mean=9.0, std_dev=1.0), policy)
        is DecisionOutcome.APPROVED
    )
    assert (
        coordinator.apply_policy(_scores(weighted_mean=9.0, std_dev=1.01), policy)
        is DecisionOutcome.ESCALATED_TO_HITL
    )


def test_auto_approve_uses_inclusive_normalized_threshold():
    coordinator = NegotiationCoordinator()
    policy = _policy()
    assert coordinator.should_auto_approve(8.0, policy) is True
    assert coordinator.should_auto_approve(7.999, policy) is False


def test_should_escalate_empty_and_single_vote_behavior():
    coordinator = NegotiationCoordinator()
    policy = _policy()
    assert coordinator.should_escalate([], policy) is False
    assert (
        coordinator.should_escalate([_vote(score=0.0, confidence=0.9)], policy) is False
    )


def test_should_escalate_fixed_confidence_boundary_and_failure_precedence():
    coordinator = NegotiationCoordinator()
    policy = _policy()
    assert coordinator.should_escalate([_vote(confidence=0.5)], policy) is False
    assert coordinator.should_escalate([_vote(confidence=0.499)], policy) is True
    assert (
        coordinator.should_escalate([_vote(confidence=0.99, passed=False)], policy)
        is True
    )


def test_should_escalate_variance_and_recommendation_behavior():
    coordinator = NegotiationCoordinator()
    policy = _policy()
    assert (
        coordinator.should_escalate([_vote(score=8.0), _vote(score=9.0)], policy)
        is False
    )
    assert (
        coordinator.should_escalate([_vote(score=2.0), _vote(score=8.0)], policy)
        is True
    )
    # Recommendations are not inspected by the current implementation.
    assert (
        coordinator.should_escalate([_vote(recommendations=["escalate"])], policy)
        is False
    )


def test_decision_reason_strings_and_escalation_reason_order():
    coordinator = NegotiationCoordinator()
    policy = _policy()
    scores = _scores(weighted_mean=9.0, std_dev=2.5)
    failed_low_confidence = [_vote(score=9.0, confidence=0.2, passed=False)]
    assert coordinator.generate_decision_reason(
        DecisionOutcome.APPROVED, _scores(weighted_mean=9.0, std_dev=0.5), [], policy
    ) == (
        "APPROVED: Weighted mean score (9.00) meets or exceeds threshold (8.00). "
        "Received 2 votes with standard deviation of 0.50."
    )
    assert coordinator.generate_decision_reason(
        DecisionOutcome.REVISION_REQUESTED,
        _scores(weighted_mean=6.0),
        failed_low_confidence,
        policy,
    ) == (
        "REVISION_REQUESTED: Weighted mean score (6.00) below threshold (8.00). "
        "1 of 2 critics marked as failed. Score range: 3.00 to 9.00."
    )
    assert coordinator.generate_decision_reason(
        DecisionOutcome.ESCALATED_TO_HITL, scores, failed_low_confidence, policy
    ) == (
        "ESCALATED_TO_HITL: high variance (std_dev=2.50), 1 failed votes, "
        "low confidence (avg=0.20). Score range: 3.00 to 9.00. "
        "Human review required for final decision."
    )


def test_empty_vote_escalation_reason_and_unknown_outcome_format():
    coordinator = NegotiationCoordinator()
    policy = _policy()
    reason = coordinator.generate_decision_reason(
        DecisionOutcome.ESCALATED_TO_HITL, _scores(std_dev=0.0), [], policy
    )
    assert reason == (
        "ESCALATED_TO_HITL: low confidence (avg=0.00). Score range: 3.00 to 9.00. "
        "Human review required for final decision."
    )
    assert (
        coordinator.generate_decision_reason(
            DecisionOutcome.DECISION_OUTCOME_UNSPECIFIED, _scores(), [], policy
        )
        == "Decision outcome: DECISION_OUTCOME_UNSPECIFIED"
    )
