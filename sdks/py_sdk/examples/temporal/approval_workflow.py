# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0

"""Optional Temporal approval-workflow reference skeleton.

This file is intentionally outside the SDK package's runtime surface.  It is
an illustrative adapter: policy evaluation stays in ``sw4rm_policies`` and
Temporal supplies durable signals and timers.
"""

from __future__ import annotations

import asyncio
from dataclasses import dataclass

from temporalio import workflow

from sw4rm_policies.aggregation import aggregate_votes
from sw4rm_policies.escalation import (
    PolicyDecision,
    ThresholdPolicy,
    apply_policy,
    should_escalate,
)
from sw4rm_policies.quorum import MinimumVotes, QuorumPolicy, evaluate


@dataclass(frozen=True)
class ApprovalVote:
    critic_id: str
    score: float
    confidence: float
    passed: bool


@dataclass(frozen=True)
class ApprovalRequest:
    requested_critics: tuple[str, ...]
    quorum_threshold: int = 1
    score_threshold: float = 0.5
    diff_tolerance: float = 0.2
    timeout_seconds: float = 300.0


@dataclass(frozen=True)
class ApprovalResult:
    status: str
    votes_received: int
    timed_out: bool = False


@workflow.defn
class ApprovalWorkflow:
    """Wait for quorum votes or a durable approval timeout."""

    def __init__(self) -> None:
        self._votes: dict[str, ApprovalVote] = {}

    @workflow.signal
    def submit_vote(self, vote: ApprovalVote) -> None:
        """Record one vote per critic; retries deterministically replace it."""
        self._votes = {**self._votes, vote.critic_id: vote}

    @workflow.run
    async def run(self, request: ApprovalRequest) -> ApprovalResult:
        try:
            await workflow.wait_condition(
                lambda: _quorum_reached(self._votes, request),
                timeout=request.timeout_seconds,
            )
            status = _decision_for(self._votes, request).value
            timed_out = False
        except asyncio.TimeoutError:
            status = PolicyDecision.ESCALATED_TO_HITL.value
            timed_out = True

        await workflow.wait_condition(workflow.all_handlers_finished)
        return ApprovalResult(
            status=status,
            votes_received=_requested_vote_count(self._votes, request),
            timed_out=timed_out,
        )


def _quorum_reached(votes: dict[str, ApprovalVote], request: ApprovalRequest) -> bool:
    """Delegate the deterministic decision to the neutral policy package."""
    policy = QuorumPolicy(
        rule=MinimumVotes(request.quorum_threshold), on_failure="fail_closed"
    )
    return evaluate(list(votes.values()), request.requested_critics, policy).met


def _requested_votes(
    votes: dict[str, ApprovalVote], request: ApprovalRequest
) -> list[ApprovalVote]:
    seen: set[str] = set()
    requested: list[ApprovalVote] = []
    for critic in request.requested_critics:
        if critic in seen:
            continue
        seen.add(critic)
        vote = votes.get(critic)
        if vote is not None:
            requested.append(vote)
    return requested


def _requested_vote_count(
    votes: dict[str, ApprovalVote], request: ApprovalRequest
) -> int:
    return len(_requested_votes(votes, request))


def _decision_for(
    votes: dict[str, ApprovalVote], request: ApprovalRequest
) -> PolicyDecision:
    requested = _requested_votes(votes, request)
    summary = aggregate_votes(requested)
    policy = ThresholdPolicy(request.score_threshold, request.diff_tolerance)
    if should_escalate(requested, policy):
        return PolicyDecision.ESCALATED_TO_HITL
    return apply_policy(summary.weighted_mean, summary.std_dev, policy)
