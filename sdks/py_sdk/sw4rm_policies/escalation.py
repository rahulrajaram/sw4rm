# Copyright 2025 Rahul Rajaram
# Licensed under the Apache License, Version 2.0.
"""Runtime-neutral negotiation decision and escalation primitives."""
from dataclasses import dataclass
from enum import Enum
from collections.abc import Mapping
from typing import Any, Sequence, Tuple

from .aggregation import _population_stddev


class PolicyDecision(Enum):
    """Possible policy outcomes for a negotiation."""

    APPROVED = "APPROVED"
    REVISION_REQUESTED = "REVISION_REQUESTED"
    ESCALATED_TO_HITL = "ESCALATED_TO_HITL"


@dataclass(frozen=True)
class ThresholdPolicy:
    """Score and disagreement thresholds used by decision helpers."""

    score_threshold: float
    diff_tolerance: float


def apply_policy(
    weighted_mean: float, std_dev: float, policy: ThresholdPolicy
) -> PolicyDecision:
    """Map aggregate scores to approval, revision, or HITL escalation."""
    if std_dev > policy.diff_tolerance * 10.0:
        return PolicyDecision.ESCALATED_TO_HITL
    if weighted_mean >= policy.score_threshold * 10.0:
        return PolicyDecision.APPROVED
    return PolicyDecision.REVISION_REQUESTED


def should_auto_approve(score: float, policy: ThresholdPolicy) -> bool:
    """Return whether one score meets the configured approval threshold."""
    return score >= policy.score_threshold * 10.0


def _value(vote: Any, name: str) -> Any:
    return vote[name] if isinstance(vote, Mapping) else getattr(vote, name)


def should_escalate(votes: Sequence[Any], policy: ThresholdPolicy) -> bool:
    """Return whether failed, uncertain, or conflicting votes need HITL."""
    if not votes:
        return False
    if any(not _value(v, "passed") for v in votes):
        return True
    confidence = sum(_value(v, "confidence") for v in votes) / len(votes)
    if confidence < 0.5:
        return True
    if len(votes) >= 2:
        scores = [_value(v, "score") for v in votes]
        if _population_stddev(scores) > policy.diff_tolerance * 10.0:
            return True
    return False


def escalation_reasons(
    std_dev: float, diff_tolerance: float, votes: Sequence[Any]
) -> Tuple[str, ...]:
    """Return stable human-readable reasons explaining escalation signals."""
    failed = [v for v in votes if not _value(v, "passed")]
    average = sum(_value(v, "confidence") for v in votes) / len(votes) if votes else 0.0
    reasons = []
    if std_dev > diff_tolerance * 10.0:
        reasons.append("high variance (std_dev={:.2f})".format(std_dev))
    if failed:
        reasons.append("{} failed votes".format(len(failed)))
    if average < 0.5:
        reasons.append("low confidence (avg={:.2f})".format(average))
    return tuple(reasons)


__all__ = [
    "PolicyDecision",
    "ThresholdPolicy",
    "apply_policy",
    "should_auto_approve",
    "should_escalate",
    "escalation_reasons",
]
