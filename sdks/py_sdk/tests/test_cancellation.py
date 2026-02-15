from sw4rm.cancellation import MIN_GRACE_PERIOD_MS, CancellationManager
from sw4rm.protos import common_pb2, handoff_pb2


def test_cancel_delegation_acknowledges_and_enforces_minimum_grace():
    clock = {"now_ms": 1000}
    manager = CancellationManager(time_ms_fn=lambda: clock["now_ms"])

    response = manager.handle_cancel_delegation(
        handoff_pb2.CancelDelegation(
            correlation_id="corr-1",
            reason="stop",
            grace_period_ms=0,
        )
    )

    assert response.acknowledged
    assert manager.is_cancelled("corr-1")
    flag = manager.cancellation_flags["corr-1"]
    assert flag.grace_period_ms == MIN_GRACE_PERIOD_MS
    assert flag.cancel_time_ms == 1000


def test_cancel_delegation_cascades_to_registered_children():
    clock = {"now_ms": 42_000}
    manager = CancellationManager(time_ms_fn=lambda: clock["now_ms"])
    manager.register_child_delegation("parent-corr", "child-a")
    manager.register_child_delegation("parent-corr", "child-b")

    manager.handle_cancel_delegation(
        handoff_pb2.CancelDelegation(
            correlation_id="parent-corr",
            reason="stop",
            grace_period_ms=10_000,
        )
    )

    assert manager.is_cancelled("parent-corr")
    assert manager.is_cancelled("child-a")
    assert manager.is_cancelled("child-b")
    assert manager.cancellation_flags["child-a"].grace_period_ms == 10_000
    assert manager.cancellation_flags["child-b"].cancel_time_ms == 42_000


def test_is_grace_expired_uses_optional_now_override():
    manager = CancellationManager(time_ms_fn=lambda: 5_000)
    manager.handle_cancel_delegation(
        handoff_pb2.CancelDelegation(
            correlation_id="corr-grace",
            reason="stop",
            grace_period_ms=6_000,
        )
    )

    assert not manager.is_grace_expired("corr-grace", now_ms=10_999)
    assert manager.is_grace_expired("corr-grace", now_ms=11_000)


def test_forced_preemption_error_code_only_after_grace_expiry():
    manager = CancellationManager(time_ms_fn=lambda: 1_000)
    manager.handle_cancel_delegation(
        handoff_pb2.CancelDelegation(
            correlation_id="corr-preempt",
            reason="stop",
            grace_period_ms=5_000,
        )
    )

    assert (
        manager.forced_preemption_error_code("corr-preempt", now_ms=5_999)
        == common_pb2.ERROR_CODE_UNSPECIFIED
    )
    assert (
        manager.forced_preemption_error_code("corr-preempt", now_ms=6_000)
        == common_pb2.FORCED_PREEMPTION
    )


def test_collect_forced_preemptions_returns_only_expired_active_correlations():
    clock = {"now_ms": 10_000}
    manager = CancellationManager(time_ms_fn=lambda: clock["now_ms"])

    manager.handle_cancel_delegation(
        handoff_pb2.CancelDelegation(
            correlation_id="expired-corr",
            reason="stop",
            grace_period_ms=5_000,
        )
    )
    clock["now_ms"] = 13_000
    manager.handle_cancel_delegation(
        handoff_pb2.CancelDelegation(
            correlation_id="within-grace",
            reason="stop",
            grace_period_ms=8_000,
        )
    )

    forced = manager.collect_forced_preemptions(
        {"expired-corr", "within-grace", "not-cancelled"},
        now_ms=16_000,
    )

    assert forced == {"expired-corr"}
