"""Tests for runtime-neutral policy primitives."""

from dataclasses import FrozenInstanceError, dataclass

import pytest

from sw4rm_policies.aggregation import ScoreSummary, aggregate_votes
from sw4rm_policies.escalation import (
    PolicyDecision,
    ThresholdPolicy,
    apply_policy,
    escalation_reasons,
    should_auto_approve,
    should_escalate,
)


@dataclass(frozen=True)
class Vote:
    score: float
    confidence: float
    passed: bool = True


def test_aggregate_attributes_mapping_and_zero_fallback():
    votes = [Vote(2.0, 0.0), {"score": 8.0, "confidence": 0.0, "passed": True}]
    assert aggregate_votes(votes) == ScoreSummary(5.0, 2.0, 8.0, 3.0, 5.0, 2)
    assert (
        aggregate_votes(
            [{"score": 2.0, "confidence": 1.0}, {"score": 8.0, "confidence": 3.0}]
        ).weighted_mean
        == 6.5
    )


def test_aggregate_empty_error_and_frozen_summary_policy():
    with pytest.raises(ValueError, match="Cannot aggregate empty list of votes"):
        aggregate_votes([])
    with pytest.raises(FrozenInstanceError):
        ScoreSummary(1, 1, 1, 0, 1, 1).mean = 2
    with pytest.raises(FrozenInstanceError):
        ThresholdPolicy(0.8, 0.1).score_threshold = 0.9


def test_decision_boundaries():
    policy = ThresholdPolicy(0.8, 0.1)
    assert apply_policy(8.0, 1.0, policy) is PolicyDecision.APPROVED
    assert apply_policy(7.99, 1.0, policy) is PolicyDecision.REVISION_REQUESTED
    assert apply_policy(9.0, 1.01, policy) is PolicyDecision.ESCALATED_TO_HITL
    assert should_auto_approve(8.0, policy) is True
    assert should_auto_approve(7.99, policy) is False


def test_escalation_predicate_and_ordered_reasons():
    policy = ThresholdPolicy(0.8, 0.1)
    assert should_escalate([], policy) is False
    assert should_escalate([Vote(8.0, 0.9)], policy) is False
    assert should_escalate([Vote(8.0, 0.5)], policy) is False
    assert should_escalate([Vote(8.0, 0.49)], policy) is True
    assert should_escalate([Vote(8.0, 0.9, False)], policy) is True
    assert should_escalate([Vote(2.0, 0.9), Vote(8.0, 0.9)], policy) is True
    reasons = escalation_reasons(2.5, 0.1, [Vote(8.0, 0.2, False)])
    assert reasons == (
        "high variance (std_dev=2.50)",
        "1 failed votes",
        "low confidence (avg=0.20)",
    )
