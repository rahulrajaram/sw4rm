import time
from typing import Optional

from sw4rm.gateway import GatewayAgent, MIN_GRACE_PERIOD_MS
from sw4rm.protos import common_pb2, handoff_pb2, registry_pb2


def _peer_descriptor(
    *,
    agent_id: str,
    capabilities: tuple[str, ...] = ("plan", "execute"),
    registration_type: int = registry_pb2.SWARM_GATEWAY,
) -> registry_pb2.AgentDescriptor:
    return registry_pb2.AgentDescriptor(
        agent_id=agent_id,
        registration_type=registration_type,
        capabilities=list(capabilities),
    )


def _make_request(
    request_id: str,
    *,
    to_agent: str = "gateway-1",
    depth: int = 0,
    max_depth: int = 3,
    deadline_ms: Optional[int] = None,
    allow_spillover: bool = False,
) -> handoff_pb2.HandoffRequest:
    deadline = deadline_ms if deadline_ms is not None else int(time.time() * 1000) + 60_000
    return handoff_pb2.HandoffRequest(
        request_id=request_id,
        from_agent="parent",
        to_agent=to_agent,
        reason="delegate",
        budget=handoff_pb2.BudgetEnvelope(
            token_budget_remaining=10_000,
            wall_time_remaining_ms=60_000,
            deadline_epoch_ms=deadline,
            current_depth=depth,
            max_delegation_depth=max_depth,
        ),
        delegation_policy=handoff_pb2.SwarmDelegationPolicy(
            allow_spillover_routing=allow_spillover
        ),
    )


def test_gateway_descriptor_registers_swarm_gateway():
    gateway = GatewayAgent(
        agent_id="gateway-1",
        name="Gateway One",
        max_concurrent_delegations=7,
        capabilities=["delegate", "route"],
    )

    descriptor = gateway.to_agent_descriptor()
    assert descriptor.agent_id == "gateway-1"
    assert descriptor.registration_type == registry_pb2.SWARM_GATEWAY
    assert descriptor.max_concurrent_delegations == 7
    assert list(descriptor.capabilities) == ["delegate", "route"]


def test_max_concurrent_delegations_enforced_with_overloaded():
    gateway = GatewayAgent(agent_id="gateway-1", max_concurrent_delegations=1, retry_after_ms=250)

    first = gateway.handle_handoff_request(_make_request("req-1"))
    second = gateway.handle_handoff_request(_make_request("req-2"))

    assert first.accepted
    assert not second.accepted
    assert second.rejection_code == common_pb2.OVERLOADED
    assert second.retry_after_ms == 250


def test_overloaded_gateway_emits_redirect_when_spillover_enabled_and_peer_available():
    gateway = GatewayAgent(
        agent_id="gateway-1",
        max_concurrent_delegations=1,
        capabilities=["plan", "execute"],
        peer_descriptors=[
            registry_pb2.AgentDescriptor(
                agent_id="worker-1",
                registration_type=registry_pb2.STANDARD_AGENT,
                capabilities=["plan", "execute"],
            ),
            registry_pb2.AgentDescriptor(
                agent_id="gateway-2",
                registration_type=registry_pb2.SWARM_GATEWAY,
                capabilities=["plan", "execute"],
            ),
        ],
    )

    first = gateway.handle_handoff_request(_make_request("req-1"))
    second = gateway.handle_handoff_request(
        _make_request("req-2", allow_spillover=True)
    )

    assert first.accepted
    assert not second.accepted
    assert second.rejection_code == common_pb2.REDIRECT
    assert second.redirect_to_agent_id == "gateway-2"
    assert second.retry_after_ms == 0


def test_overloaded_gateway_falls_back_to_overloaded_when_no_healthy_peer():
    gateway = GatewayAgent(
        agent_id="gateway-1",
        max_concurrent_delegations=1,
        capabilities=["plan", "execute"],
        peer_descriptors=[
            registry_pb2.AgentDescriptor(
                agent_id="gateway-2",
                registration_type=registry_pb2.SWARM_GATEWAY,
                capabilities=["plan", "execute"],
            )
        ],
        peer_health_fn=lambda _peer: False,
        retry_after_ms=333,
    )

    first = gateway.handle_handoff_request(_make_request("req-1"))
    second = gateway.handle_handoff_request(
        _make_request("req-2", allow_spillover=True)
    )

    assert first.accepted
    assert not second.accepted
    assert second.rejection_code == common_pb2.OVERLOADED
    assert second.retry_after_ms == 333


def test_overloaded_gateway_does_not_redirect_when_spillover_disabled():
    gateway = GatewayAgent(
        agent_id="gateway-1",
        max_concurrent_delegations=1,
        capabilities=["plan", "execute"],
        peer_descriptors=[
            registry_pb2.AgentDescriptor(
                agent_id="gateway-2",
                registration_type=registry_pb2.SWARM_GATEWAY,
                capabilities=["plan", "execute"],
            )
        ],
        retry_after_ms=200,
    )

    first = gateway.handle_handoff_request(_make_request("req-1"))
    second = gateway.handle_handoff_request(
        _make_request("req-2", allow_spillover=False)
    )

    assert first.accepted
    assert not second.accepted
    assert second.rejection_code == common_pb2.OVERLOADED
    assert second.retry_after_ms == 200


def test_independent_depth_validation_rejects_understated_depth():
    gateway = GatewayAgent(agent_id="gateway-1", max_delegation_depth=3)
    request = _make_request("req-1", depth=0, max_depth=3)
    gateway.register_verified_depth("req-1", 3)

    response = gateway.handle_handoff_request(request)

    assert not response.accepted
    assert response.rejection_code == common_pb2.VALIDATION_ERROR


def test_parent_lineage_depth_is_used_for_validation():
    gateway = GatewayAgent(agent_id="gateway-1", max_delegation_depth=3)
    gateway.register_verified_depth("parent-corr", 2)

    response = gateway.handle_handoff_request(
        _make_request("child-corr", depth=0, max_depth=3),
        parent_correlation_id="parent-corr",
    )

    assert not response.accepted
    assert response.rejection_code == common_pb2.VALIDATION_ERROR


def test_budget_propagation_is_monotonic_and_increments_depth():
    gateway = GatewayAgent(agent_id="gateway-1")
    parent_budget = handoff_pb2.BudgetEnvelope(
        token_budget_remaining=5000,
        wall_time_remaining_ms=10000,
        deadline_epoch_ms=123456789,
        current_depth=1,
        max_delegation_depth=3,
    )

    child_budget = gateway.propagate_budget(
        parent_budget, token_spent=450, wall_time_spent_ms=750
    )

    assert child_budget.token_budget_remaining == 4550
    assert child_budget.wall_time_remaining_ms == 9250
    assert child_budget.deadline_epoch_ms == parent_budget.deadline_epoch_ms
    assert child_budget.current_depth == 2
    assert child_budget.max_delegation_depth == 3


def test_cancel_delegation_sets_flags_and_cascades_to_children():
    gateway = GatewayAgent(agent_id="gateway-1")
    gateway.register_child_delegation("parent-corr", "child-corr")

    response = gateway.handle_cancel_delegation(
        handoff_pb2.CancelDelegation(
            correlation_id="parent-corr",
            reason="stop",
            grace_period_ms=1,
        )
    )

    assert response.acknowledged
    assert gateway.is_cancelled("parent-corr")
    assert gateway.is_cancelled("child-corr")
    assert (
        gateway.cancellation_flags["parent-corr"].grace_period_ms
        == MIN_GRACE_PERIOD_MS
    )


def test_cancelled_delegation_is_rejected_before_new_work():
    gateway = GatewayAgent(agent_id="gateway-1")
    gateway.handle_cancel_delegation(
        handoff_pb2.CancelDelegation(
            correlation_id="req-cancelled",
            reason="stop",
            grace_period_ms=5000,
        )
    )

    response = gateway.handle_handoff_request(_make_request("req-cancelled"))

    assert not response.accepted
    assert response.rejection_code == common_pb2.FORCED_PREEMPTION


def test_cancellation_safe_point_rechecks_before_accepting_work():
    class CancellationRaceGateway(GatewayAgent):
        def __init__(self) -> None:
            super().__init__(agent_id="gateway-race")
            self._cancel_checks = 0

        def is_cancelled(self, correlation_id: str) -> bool:
            self._cancel_checks += 1
            return self._cancel_checks >= 2

    gateway = CancellationRaceGateway()

    response = gateway.handle_handoff_request(_make_request("req-race"))

    assert not response.accepted
    assert response.rejection_code == common_pb2.FORCED_PREEMPTION
    assert gateway.active_delegation_count == 0


def test_force_preempt_expired_delegations_removes_active_work():
    now = {"ms": 10_000}
    gateway = GatewayAgent(agent_id="gateway-1", time_ms_fn=lambda: now["ms"])

    accepted = gateway.handle_handoff_request(_make_request("req-active", deadline_ms=60_000))
    assert accepted.accepted
    assert gateway.active_delegation_count == 1

    gateway.handle_cancel_delegation(
        handoff_pb2.CancelDelegation(
            correlation_id="req-active",
            reason="stop",
            grace_period_ms=5_000,
        )
    )
    now["ms"] = 15_000

    forced = gateway.force_preempt_expired_delegations(now_ms=now["ms"])

    assert forced == {"req-active"}
    assert gateway.active_delegation_count == 0


def test_health_aware_selector_filters_stale_non_serving_and_cooldown_peers():
    now = {"ms": 200_000}
    gateway = GatewayAgent(
        agent_id="gateway-1",
        max_concurrent_delegations=0,
        capabilities=["plan", "execute"],
        time_ms_fn=lambda: now["ms"],
        peer_descriptors=[
            _peer_descriptor(agent_id="peer-stale"),
            _peer_descriptor(agent_id="peer-initializing"),
            _peer_descriptor(agent_id="peer-cooldown"),
            _peer_descriptor(agent_id="peer-healthy"),
        ],
    )

    gateway.update_peer_runtime_state(
        "peer-stale",
        state=common_pb2.RUNNING,
        last_heartbeat_ms=now["ms"] - 120_000,
    )
    gateway.touch_peer_heartbeat("peer-initializing", state=common_pb2.INITIALIZING)
    gateway.touch_peer_heartbeat("peer-cooldown", state=common_pb2.RUNNING)
    gateway.record_peer_overloaded("peer-cooldown", retry_after_ms=15_000)
    gateway.touch_peer_heartbeat("peer-healthy", state=common_pb2.RUNNING)

    response = gateway.handle_handoff_request(
        _make_request("req-health-filter", allow_spillover=True)
    )

    assert not response.accepted
    assert response.rejection_code == common_pb2.REDIRECT
    assert response.redirect_to_agent_id == "peer-healthy"


def test_health_aware_selector_excludes_failed_and_shutting_down_peers():
    now = {"ms": 50_000}
    gateway = GatewayAgent(
        agent_id="gateway-1",
        max_concurrent_delegations=0,
        capabilities=["plan", "execute"],
        time_ms_fn=lambda: now["ms"],
        peer_descriptors=[
            _peer_descriptor(agent_id="peer-failed"),
            _peer_descriptor(agent_id="peer-shutting-down"),
            _peer_descriptor(agent_id="peer-healthy"),
        ],
    )

    gateway.touch_peer_heartbeat("peer-failed", state=common_pb2.FAILED_STATE)
    gateway.touch_peer_heartbeat(
        "peer-shutting-down", state=common_pb2.SHUTTING_DOWN
    )
    gateway.touch_peer_heartbeat("peer-healthy", state=common_pb2.RUNNING)

    response = gateway.handle_handoff_request(
        _make_request("req-non-serving-filter", allow_spillover=True)
    )

    assert not response.accepted
    assert response.rejection_code == common_pb2.REDIRECT
    assert response.redirect_to_agent_id == "peer-healthy"


def test_health_aware_selector_uses_round_robin_across_healthy_peers():
    now = {"ms": 10_000}
    gateway = GatewayAgent(
        agent_id="gateway-1",
        max_concurrent_delegations=0,
        capabilities=["plan", "execute"],
        time_ms_fn=lambda: now["ms"],
        peer_descriptors=[
            _peer_descriptor(agent_id="peer-1"),
            _peer_descriptor(agent_id="peer-2"),
            _peer_descriptor(agent_id="peer-3"),
        ],
    )
    gateway.touch_peer_heartbeat("peer-1", state=common_pb2.RUNNING)
    gateway.touch_peer_heartbeat("peer-2", state=common_pb2.RUNNING)
    gateway.touch_peer_heartbeat("peer-3", state=common_pb2.RUNNING)

    seen = []
    for idx in range(6):
        response = gateway.handle_handoff_request(
            _make_request(f"req-rr-{idx}", allow_spillover=True)
        )
        seen.append(response.redirect_to_agent_id)

    assert seen == ["peer-1", "peer-2", "peer-3", "peer-1", "peer-2", "peer-3"]


def test_overloaded_peer_rejoins_selection_after_cooldown_expires():
    now = {"ms": 10_000}
    gateway = GatewayAgent(
        agent_id="gateway-1",
        max_concurrent_delegations=0,
        capabilities=["plan", "execute"],
        time_ms_fn=lambda: now["ms"],
        peer_descriptors=[
            _peer_descriptor(agent_id="peer-a"),
            _peer_descriptor(agent_id="peer-b"),
        ],
    )
    gateway.touch_peer_heartbeat("peer-a", state=common_pb2.RUNNING)
    gateway.touch_peer_heartbeat("peer-b", state=common_pb2.RUNNING)
    gateway.record_peer_overloaded("peer-a", retry_after_ms=5_000)

    first = gateway.handle_handoff_request(
        _make_request("req-cooldown-1", allow_spillover=True)
    )
    assert first.redirect_to_agent_id == "peer-b"

    now["ms"] += 6_000
    next_targets = []
    for idx in range(2):
        response = gateway.handle_handoff_request(
            _make_request(f"req-cooldown-{idx + 2}", allow_spillover=True)
        )
        next_targets.append(response.redirect_to_agent_id)

    assert "peer-a" in next_targets
