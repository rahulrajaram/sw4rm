"""Client-side SW4-004 delegation helpers."""

from __future__ import annotations

import random
import time
import uuid
from typing import Callable, Optional, Sequence

from sw4rm.protos import common_pb2, handoff_pb2


RETRY_AFTER_JITTER_RATIO = 0.2
DEFAULT_MAX_RETRIES_ON_OVERLOADED = 2
DEFAULT_MAX_REDIRECTS = 2
DEFAULT_INITIAL_BACKOFF_MS = 250
DEFAULT_BACKOFF_MULTIPLIER = 2.0
DEFAULT_MAX_BACKOFF_MS = 2000


def _now_ms() -> int:
    return int(time.time() * 1000)


def _sleep_seconds(seconds: float) -> None:
    time.sleep(seconds)


def _uniform(low: float, high: float) -> float:
    return random.uniform(low, high)


def _default_policy() -> handoff_pb2.SwarmDelegationPolicy:
    return handoff_pb2.SwarmDelegationPolicy(
        max_retries_on_overloaded=DEFAULT_MAX_RETRIES_ON_OVERLOADED,
        initial_backoff_ms=DEFAULT_INITIAL_BACKOFF_MS,
        backoff_multiplier=DEFAULT_BACKOFF_MULTIPLIER,
        max_backoff_ms=DEFAULT_MAX_BACKOFF_MS,
        allow_spillover_routing=False,
        max_redirects=0,
    )


def _normalize_policy(
    policy: Optional[handoff_pb2.SwarmDelegationPolicy],
) -> handoff_pb2.SwarmDelegationPolicy:
    if policy is None:
        return _default_policy()

    normalized = handoff_pb2.SwarmDelegationPolicy()
    normalized.CopyFrom(policy)
    if normalized.initial_backoff_ms == 0:
        normalized.initial_backoff_ms = DEFAULT_INITIAL_BACKOFF_MS
    if normalized.backoff_multiplier <= 0:
        normalized.backoff_multiplier = DEFAULT_BACKOFF_MULTIPLIER
    if normalized.max_backoff_ms == 0:
        normalized.max_backoff_ms = DEFAULT_MAX_BACKOFF_MS
    return normalized


def _deadline_exhausted_response(request_id: str) -> handoff_pb2.HandoffResponse:
    return handoff_pb2.HandoffResponse(
        request_id=request_id,
        accepted=False,
        rejection_reason="Delegation deadline exhausted before handoff acceptance",
        rejection_code=common_pb2.ACK_TIMEOUT,
    )


def _next_retry_wait_ms(
    response: handoff_pb2.HandoffResponse,
    *,
    retry_index: int,
    policy: handoff_pb2.SwarmDelegationPolicy,
    rand_uniform_fn: Callable[[float, float], float],
) -> int:
    if response.retry_after_ms > 0:
        retry_after = float(response.retry_after_ms)
        jitter = rand_uniform_fn(0.0, retry_after * RETRY_AFTER_JITTER_RATIO)
        return int(retry_after + jitter)

    exponential = float(policy.initial_backoff_ms) * (
        float(policy.backoff_multiplier) ** retry_index
    )
    bounded = min(exponential, float(policy.max_backoff_ms))
    return int(rand_uniform_fn(0.0, bounded))


def _effective_max_redirects(policy: handoff_pb2.SwarmDelegationPolicy) -> int:
    configured = int(policy.max_redirects)
    return configured if configured > 0 else DEFAULT_MAX_REDIRECTS


def _invalid_redirect_response(
    request_id: str,
    reason: str,
) -> handoff_pb2.HandoffResponse:
    return handoff_pb2.HandoffResponse(
        request_id=request_id,
        accepted=False,
        rejection_reason=reason,
        rejection_code=common_pb2.VALIDATION_ERROR,
    )


def _budget_exhausted(
    budget: handoff_pb2.BudgetEnvelope,
    *,
    now_ms: int,
) -> bool:
    return (
        int(budget.wall_time_remaining_ms) <= 0
        or now_ms > int(budget.deadline_epoch_ms)
    )


def _consume_wall_time(budget: handoff_pb2.BudgetEnvelope, *, elapsed_ms: int) -> None:
    budget.wall_time_remaining_ms = max(
        int(budget.wall_time_remaining_ms) - max(int(elapsed_ms), 0),
        0,
    )


def delegate_to_swarm(
    send_handoff_fn: Callable[[handoff_pb2.HandoffRequest], handoff_pb2.HandoffResponse],
    *,
    from_agent: str,
    to_agent: str,
    reason: str,
    budget: handoff_pb2.BudgetEnvelope,
    delegation_policy: Optional[handoff_pb2.SwarmDelegationPolicy] = None,
    request_id: Optional[str] = None,
    context_snapshot: bytes = b"",
    capabilities_required: Optional[Sequence[str]] = None,
    priority: int = 0,
    timeout_seconds: Optional[float] = None,
    now_ms_fn: Optional[Callable[[], int]] = None,
    sleep_fn: Optional[Callable[[float], None]] = None,
    rand_uniform_fn: Optional[Callable[[float, float], float]] = None,
) -> handoff_pb2.HandoffResponse:
    """Construct and dispatch a cross-swarm delegation request.

    Implements SW4-004/SW4-005 caller-side behavior:
    - uses BudgetEnvelope + SwarmDelegationPolicy on HandoffRequest
    - follows REDIRECT responses when spillover routing is enabled
    - enforces redirect chain limits (default effective value 2)
    - stops early for invalid/looping redirects
    - retries OVERLOADED responses with bounded backoff + jitter
    - stops retrying when deadline or wall-time budget is exhausted
    """
    if budget.deadline_epoch_ms == 0:
        raise ValueError("budget.deadline_epoch_ms is required for cross-swarm delegation")
    if timeout_seconds is not None and timeout_seconds < 0:
        raise ValueError("timeout_seconds must be >= 0")

    now = now_ms_fn or _now_ms
    sleep = sleep_fn or _sleep_seconds
    rand = rand_uniform_fn or _uniform
    policy = _normalize_policy(delegation_policy)

    request_budget = handoff_pb2.BudgetEnvelope()
    request_budget.CopyFrom(budget)

    request = handoff_pb2.HandoffRequest(
        request_id=request_id or str(uuid.uuid4()),
        from_agent=from_agent,
        to_agent=to_agent,
        reason=reason,
        context_snapshot=context_snapshot,
        capabilities_required=list(capabilities_required or []),
        priority=priority,
        budget=request_budget,
        delegation_policy=policy,
    )
    if timeout_seconds is not None:
        timeout_ms = int(timeout_seconds * 1000)
        request.timeout.seconds = timeout_ms // 1000
        request.timeout.nanos = (timeout_ms % 1000) * 1_000_000

    redirect_hops = 0
    effective_max_redirects = _effective_max_redirects(policy)
    visited_agents = {request.to_agent}
    retry_index = 0
    while True:
        start_ms = now()
        if _budget_exhausted(request.budget, now_ms=start_ms):
            return _deadline_exhausted_response(request.request_id)

        response = send_handoff_fn(request)

        end_ms = now()
        elapsed_ms = max(end_ms - start_ms, 0)
        _consume_wall_time(request.budget, elapsed_ms=elapsed_ms)

        if response.accepted:
            return response
        if _budget_exhausted(request.budget, now_ms=end_ms):
            return _deadline_exhausted_response(request.request_id)

        if response.rejection_code != common_pb2.OVERLOADED:
            if response.rejection_code != common_pb2.REDIRECT:
                return response

            if not policy.allow_spillover_routing:
                return response

            target_agent = response.redirect_to_agent_id.strip()
            if not target_agent:
                return _invalid_redirect_response(
                    request.request_id,
                    "Redirect response missing non-empty redirect_to_agent_id",
                )
            if target_agent in visited_agents:
                return _invalid_redirect_response(
                    request.request_id,
                    f"Redirect loop detected for agent '{target_agent}'",
                )
            if redirect_hops >= effective_max_redirects:
                return response

            request.to_agent = target_agent
            visited_agents.add(target_agent)
            redirect_hops += 1
            continue

        if retry_index >= int(policy.max_retries_on_overloaded):
            return response

        wait_ms = _next_retry_wait_ms(
            response,
            retry_index=retry_index,
            policy=policy,
            rand_uniform_fn=rand,
        )
        retry_index += 1

        remaining_deadline_ms = request.budget.deadline_epoch_ms - end_ms
        if (
            wait_ms <= 0
            or wait_ms > int(request.budget.wall_time_remaining_ms)
            or wait_ms > remaining_deadline_ms
        ):
            return response

        before_sleep_ms = now()
        sleep(wait_ms / 1000.0)
        after_sleep_ms = now()
        slept_ms = max(after_sleep_ms - before_sleep_ms, 0)
        _consume_wall_time(request.budget, elapsed_ms=slept_ms)
