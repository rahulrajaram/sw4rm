# Copyright 2025 Rahul Rajaram
# Licensed under the Apache License, Version 2.0.

"""Runtime-neutral, pure quorum policy evaluation."""

from __future__ import annotations

import math
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any, List, Sequence, Union, TypeVar

Vote = TypeVar("Vote")


@dataclass(frozen=True)
class MinimumVotes:
    """Require at least ``n`` distinct requested critics."""

    n: int


@dataclass(frozen=True)
class MinimumFraction:
    """Require the ceiling of expected critics times ``fraction``."""

    fraction: float


@dataclass(frozen=True)
class RequireAll:
    """Require every requested critic when enabled."""

    enabled: bool = True


QuorumRule = Union[MinimumVotes, MinimumFraction, RequireAll]


@dataclass(frozen=True)
class EscalateHitl:
    """Represent fail-closed escalation to human review."""

    reason: str


@dataclass(frozen=True)
class DecidedWithAbstains:
    """Represent a decision with generated abstain records."""

    injected_votes: List[dict] = field(default_factory=list)


@dataclass(frozen=True)
class DecidedWithAvailable:
    """Represent a decision using only received votes."""


FailureAction = Union[EscalateHitl, DecidedWithAbstains, DecidedWithAvailable]

# Valid on_failure action names (validated at construction, R44).
VALID_FAILURE_ACTIONS = frozenset(
    {"fail_closed", "fail_with_abstain", "fail_with_available"}
)


@dataclass(frozen=True)
class QuorumPolicy:
    """Pair a quorum rule with its failure action name."""

    rule: QuorumRule
    on_failure: Any

    def __post_init__(self) -> None:
        """Validate the failure action eagerly (fp-refine finding 2 / R44)."""
        if self.on_failure not in VALID_FAILURE_ACTIONS:
            raise ValueError(
                f"Unknown failure action: {self.on_failure!r}"
                f" (expected one of {sorted(VALID_FAILURE_ACTIONS)})"
            )


@dataclass(frozen=True)
class QuorumOutcome:
    """Describe quorum status and the votes available downstream."""

    met: bool
    votes_received: int
    votes_expected: int
    threshold: int
    action: Any = None
    all_votes: List[Union[Vote, dict]] = field(default_factory=list)


def default_policy() -> QuorumPolicy:
    """Return the at-least-half, fail-closed default policy."""

    return QuorumPolicy(rule=MinimumFraction(0.5), on_failure="fail_closed")


def _critic_id(vote: Vote) -> str:
    if isinstance(vote, Mapping):
        return vote["critic_id"]
    return vote.critic_id  # type: ignore[attr-defined]


def _compute_threshold(rule: QuorumRule, expected: int) -> int:
    if isinstance(rule, MinimumVotes):
        return rule.n
    if isinstance(rule, MinimumFraction):
        return math.ceil(expected * rule.fraction)
    if isinstance(rule, RequireAll):
        return expected if rule.enabled else 0
    raise ValueError(f"Unknown quorum rule: {rule!r}")


def evaluate(
    votes: List[Vote], requested_critics: Sequence[str], policy: QuorumPolicy
) -> QuorumOutcome:
    """Evaluate collected votes against a policy without runtime dependencies."""

    voted_ids = {_critic_id(vote) for vote in votes}
    expected = len(requested_critics)
    received = len(voted_ids & set(requested_critics))
    threshold = _compute_threshold(policy.rule, expected)
    if received >= threshold:
        return QuorumOutcome(True, received, expected, threshold, all_votes=list(votes))
    if policy.on_failure == "fail_closed":
        action = EscalateHitl("Quorum not met — escalating to HITL")
    elif policy.on_failure == "fail_with_abstain":
        missing = [critic for critic in requested_critics if critic not in voted_ids]
        injected = [
            {
                "critic_id": critic,
                "score": 0.0,
                "confidence": 0.0,
                "passed": False,
                "abstain": True,
            }
            for critic in missing
        ]
        action = DecidedWithAbstains(injected)
    elif policy.on_failure == "fail_with_available":
        action = DecidedWithAvailable()
    else:  # pragma: no cover - unreachable, validated in QuorumPolicy.__post_init__
        raise ValueError(f"Unknown failure action: {policy.on_failure!r}")
    all_votes = list(votes) + (action.injected_votes if isinstance(action, DecidedWithAbstains) else [])
    return QuorumOutcome(False, received, expected, threshold, action, all_votes)
