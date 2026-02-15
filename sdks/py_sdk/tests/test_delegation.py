from sw4rm.delegation import delegate_to_swarm
from sw4rm.protos import common_pb2, handoff_pb2


def _budget(*, deadline_ms: int, wall_time_ms: int = 10_000) -> handoff_pb2.BudgetEnvelope:
    return handoff_pb2.BudgetEnvelope(
        token_budget_remaining=5_000,
        wall_time_remaining_ms=wall_time_ms,
        deadline_epoch_ms=deadline_ms,
        current_depth=1,
        max_delegation_depth=3,
    )


def test_delegate_to_swarm_builds_request_with_budget_and_policy():
    captured_requests = []

    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        copied = handoff_pb2.HandoffRequest()
        copied.CopyFrom(request)
        captured_requests.append(copied)
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=True,
            accepting_agent="gateway-1",
        )

    policy = handoff_pb2.SwarmDelegationPolicy(
        max_retries_on_overloaded=3,
        initial_backoff_ms=400,
        backoff_multiplier=2.5,
        max_backoff_ms=2_000,
        allow_spillover_routing=True,
    )
    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-1",
        reason="delegate work",
        budget=_budget(deadline_ms=999_999),
        delegation_policy=policy,
        request_id="req-1",
        capabilities_required=["codegen", "verify"],
        priority=7,
        timeout_seconds=1.25,
        now_ms_fn=lambda: 100_000,
    )

    assert response.accepted
    assert len(captured_requests) == 1
    request = captured_requests[0]
    assert request.request_id == "req-1"
    assert request.from_agent == "parent"
    assert request.to_agent == "gateway-1"
    assert request.reason == "delegate work"
    assert list(request.capabilities_required) == ["codegen", "verify"]
    assert request.priority == 7
    assert request.timeout.seconds == 1
    assert request.timeout.nanos == 250_000_000
    assert request.budget.deadline_epoch_ms == 999_999
    assert request.delegation_policy.max_retries_on_overloaded == 3
    assert request.delegation_policy.allow_spillover_routing


def test_delegate_to_swarm_retries_overloaded_with_retry_after_jitter():
    call_count = {"value": 0}
    captured_requests = []
    current_ms = {"value": 1_000_000}
    sleeps_ms = []

    def now_ms() -> int:
        return current_ms["value"]

    def sleep(seconds: float) -> None:
        delay_ms = int(seconds * 1000)
        sleeps_ms.append(delay_ms)
        current_ms["value"] += delay_ms

    def rand_uniform(low: float, high: float) -> float:
        assert low == 0.0
        return high

    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        copied = handoff_pb2.HandoffRequest()
        copied.CopyFrom(request)
        captured_requests.append(copied)

        call_count["value"] += 1
        if call_count["value"] == 1:
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_code=common_pb2.OVERLOADED,
                retry_after_ms=1_000,
            )
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=True,
            accepting_agent="gateway-1",
        )

    policy = handoff_pb2.SwarmDelegationPolicy(max_retries_on_overloaded=2)
    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-1",
        reason="delegate",
        budget=_budget(deadline_ms=1_005_000, wall_time_ms=10_000),
        delegation_policy=policy,
        request_id="req-jitter",
        now_ms_fn=now_ms,
        sleep_fn=sleep,
        rand_uniform_fn=rand_uniform,
    )

    assert response.accepted
    assert len(captured_requests) == 2
    # 1000 + 20% max jitter when retry_after_ms is present.
    assert sleeps_ms == [1200]
    assert captured_requests[1].budget.wall_time_remaining_ms == 8_800


def test_delegate_to_swarm_uses_bounded_exponential_full_jitter_without_retry_after():
    call_count = {"value": 0}
    current_ms = {"value": 500_000}
    sleeps_ms = []
    random_ranges = []

    def now_ms() -> int:
        return current_ms["value"]

    def sleep(seconds: float) -> None:
        delay_ms = int(seconds * 1000)
        sleeps_ms.append(delay_ms)
        current_ms["value"] += delay_ms

    def rand_uniform(low: float, high: float) -> float:
        random_ranges.append((low, high))
        return high

    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        call_count["value"] += 1
        if call_count["value"] < 3:
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_code=common_pb2.OVERLOADED,
            )
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=True,
            accepting_agent="gateway-1",
        )

    policy = handoff_pb2.SwarmDelegationPolicy(
        max_retries_on_overloaded=2,
        initial_backoff_ms=500,
        backoff_multiplier=2.0,
        max_backoff_ms=2_000,
    )
    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-1",
        reason="delegate",
        budget=_budget(deadline_ms=510_000, wall_time_ms=10_000),
        delegation_policy=policy,
        request_id="req-backoff",
        now_ms_fn=now_ms,
        sleep_fn=sleep,
        rand_uniform_fn=rand_uniform,
    )

    assert response.accepted
    assert sleeps_ms == [500, 1000]
    assert random_ranges == [(0.0, 500.0), (0.0, 1000.0)]


def test_delegate_to_swarm_follows_redirect_chain_and_preserves_request_metadata():
    captured_requests = []
    current_ms = {"value": 10_000}

    def now_ms() -> int:
        return current_ms["value"]

    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        copied = handoff_pb2.HandoffRequest()
        copied.CopyFrom(request)
        captured_requests.append(copied)

        if request.to_agent == "gateway-a":
            current_ms["value"] += 30
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_code=common_pb2.REDIRECT,
                redirect_to_agent_id="gateway-b",
            )
        if request.to_agent == "gateway-b":
            current_ms["value"] += 20
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_code=common_pb2.REDIRECT,
                redirect_to_agent_id="gateway-c",
            )
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=True,
            accepting_agent="gateway-c",
        )

    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-a",
        reason="delegate",
        budget=_budget(deadline_ms=20_000, wall_time_ms=100),
        delegation_policy=handoff_pb2.SwarmDelegationPolicy(
            allow_spillover_routing=True,
            max_redirects=3,
        ),
        request_id="req-redirect-meta",
        context_snapshot=b"context-bytes",
        capabilities_required=["plan", "execute"],
        priority=5,
        now_ms_fn=now_ms,
    )

    assert response.accepted
    assert [req.to_agent for req in captured_requests] == [
        "gateway-a",
        "gateway-b",
        "gateway-c",
    ]
    assert all(req.request_id == "req-redirect-meta" for req in captured_requests)
    assert all(req.context_snapshot == b"context-bytes" for req in captured_requests)
    assert all(list(req.capabilities_required) == ["plan", "execute"] for req in captured_requests)
    assert all(req.priority == 5 for req in captured_requests)
    assert captured_requests[1].budget.wall_time_remaining_ms == 70
    assert captured_requests[2].budget.wall_time_remaining_ms == 50


def test_delegate_to_swarm_enforces_default_effective_max_redirects_of_two():
    attempts = []

    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        attempts.append(request.to_agent)
        routing = {
            "gateway-a": "gateway-b",
            "gateway-b": "gateway-c",
            "gateway-c": "gateway-d",
        }
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=False,
            rejection_code=common_pb2.REDIRECT,
            redirect_to_agent_id=routing[request.to_agent],
        )

    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-a",
        reason="delegate",
        budget=_budget(deadline_ms=500_000, wall_time_ms=10_000),
        delegation_policy=handoff_pb2.SwarmDelegationPolicy(
            allow_spillover_routing=True,
            max_redirects=0,
        ),
        request_id="req-default-max-redirects",
        now_ms_fn=lambda: 100_000,
    )

    assert not response.accepted
    assert response.rejection_code == common_pb2.REDIRECT
    assert attempts == ["gateway-a", "gateway-b", "gateway-c"]


def test_delegate_to_swarm_rejects_redirect_loops():
    attempts = []

    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        attempts.append(request.to_agent)
        if request.to_agent == "gateway-a":
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_code=common_pb2.REDIRECT,
                redirect_to_agent_id="gateway-b",
            )
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=False,
            rejection_code=common_pb2.REDIRECT,
            redirect_to_agent_id="gateway-a",
        )

    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-a",
        reason="delegate",
        budget=_budget(deadline_ms=100_000, wall_time_ms=10_000),
        delegation_policy=handoff_pb2.SwarmDelegationPolicy(
            allow_spillover_routing=True,
            max_redirects=4,
        ),
        request_id="req-loop",
        now_ms_fn=lambda: 1_000,
    )

    assert not response.accepted
    assert response.rejection_code == common_pb2.VALIDATION_ERROR
    assert "loop" in response.rejection_reason.lower()
    assert attempts == ["gateway-a", "gateway-b"]


def test_delegate_to_swarm_rejects_redirect_loops_even_after_redirect_budget_spent():
    attempts = []

    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        attempts.append(request.to_agent)
        if request.to_agent == "gateway-a":
            return handoff_pb2.HandoffResponse(
                request_id=request.request_id,
                accepted=False,
                rejection_code=common_pb2.REDIRECT,
                redirect_to_agent_id="gateway-b",
            )
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=False,
            rejection_code=common_pb2.REDIRECT,
            redirect_to_agent_id="gateway-a",
        )

    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-a",
        reason="delegate",
        budget=_budget(deadline_ms=100_000, wall_time_ms=10_000),
        delegation_policy=handoff_pb2.SwarmDelegationPolicy(
            allow_spillover_routing=True,
            max_redirects=1,
        ),
        request_id="req-loop-after-budget",
        now_ms_fn=lambda: 1_000,
    )

    assert not response.accepted
    assert response.rejection_code == common_pb2.VALIDATION_ERROR
    assert "loop" in response.rejection_reason.lower()
    assert attempts == ["gateway-a", "gateway-b"]


def test_delegate_to_swarm_rejects_blank_redirect_targets():
    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=False,
            rejection_code=common_pb2.REDIRECT,
            redirect_to_agent_id="   ",
        )

    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-a",
        reason="delegate",
        budget=_budget(deadline_ms=100_000, wall_time_ms=10_000),
        delegation_policy=handoff_pb2.SwarmDelegationPolicy(
            allow_spillover_routing=True,
            max_redirects=3,
        ),
        request_id="req-blank-redirect-target",
        now_ms_fn=lambda: 1_000,
    )

    assert not response.accepted
    assert response.rejection_code == common_pb2.VALIDATION_ERROR
    assert "non-empty" in response.rejection_reason.lower()


def test_delegate_to_swarm_stops_retry_when_deadline_precludes_wait():
    call_count = {"value": 0}
    current_ms = {"value": 2_000}

    def now_ms() -> int:
        return current_ms["value"]

    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        call_count["value"] += 1
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=False,
            rejection_code=common_pb2.OVERLOADED,
            retry_after_ms=1000,
        )

    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-1",
        reason="delegate",
        budget=_budget(deadline_ms=2_500, wall_time_ms=5_000),
        delegation_policy=handoff_pb2.SwarmDelegationPolicy(max_retries_on_overloaded=3),
        request_id="req-deadline-stop",
        now_ms_fn=now_ms,
        sleep_fn=lambda _: (_ for _ in ()).throw(AssertionError("sleep must not run")),
        rand_uniform_fn=lambda _a, _b: 200.0,
    )

    assert call_count["value"] == 1
    assert not response.accepted
    assert response.rejection_code == common_pb2.OVERLOADED


def test_delegate_to_swarm_times_out_when_single_attempt_exhausts_wall_time():
    now = {"ms": 10_000}

    def now_ms() -> int:
        return now["ms"]

    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        now["ms"] += 150
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=False,
            rejection_code=common_pb2.OVERLOADED,
            retry_after_ms=1,
        )

    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-1",
        reason="delegate",
        budget=_budget(deadline_ms=20_000, wall_time_ms=100),
        delegation_policy=handoff_pb2.SwarmDelegationPolicy(max_retries_on_overloaded=3),
        request_id="req-attempt-exhausts-wall-time",
        now_ms_fn=now_ms,
        sleep_fn=lambda _seconds: (_ for _ in ()).throw(
            AssertionError("sleep must not run after budget exhaustion")
        ),
    )

    assert not response.accepted
    assert response.rejection_code == common_pb2.ACK_TIMEOUT


def test_delegate_to_swarm_fails_fast_when_deadline_already_expired():
    def send_handoff(_request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        raise AssertionError("send_handoff_fn should not be called after deadline expiry")

    response = delegate_to_swarm(
        send_handoff,
        from_agent="parent",
        to_agent="gateway-1",
        reason="delegate",
        budget=_budget(deadline_ms=900, wall_time_ms=1_000),
        request_id="req-expired",
        now_ms_fn=lambda: 1_000,
    )

    assert not response.accepted
    assert response.rejection_code == common_pb2.ACK_TIMEOUT


def test_delegate_to_swarm_requires_deadline_in_budget():
    try:
        delegate_to_swarm(
            lambda _request: handoff_pb2.HandoffResponse(accepted=True),
            from_agent="parent",
            to_agent="gateway-1",
            reason="delegate",
            budget=handoff_pb2.BudgetEnvelope(
                token_budget_remaining=1,
                wall_time_remaining_ms=1000,
                deadline_epoch_ms=0,
            ),
        )
    except ValueError as exc:
        assert "deadline_epoch_ms" in str(exc)
    else:
        raise AssertionError("ValueError expected when deadline_epoch_ms is missing")
