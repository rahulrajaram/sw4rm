import json
from pathlib import Path

import pytest

from sw4rm.cancellation import CancellationManager
from sw4rm.delegation import delegate_to_swarm
from sw4rm.protos import common_pb2, handoff_pb2


VECTORS_DIR = Path(__file__).resolve().parents[3] / "tests" / "conformance_vectors"
DELEGATION_VECTORS_PATH = VECTORS_DIR / "sw4_005_delegation_vectors.json"
CANCELLATION_VECTORS_PATH = VECTORS_DIR / "sw4_004_cancellation_vectors.json"

with DELEGATION_VECTORS_PATH.open("r", encoding="utf-8") as handle:
    DELEGATION_VECTOR_SUITE = json.load(handle)

with CANCELLATION_VECTORS_PATH.open("r", encoding="utf-8") as handle:
    CANCELLATION_VECTOR_SUITE = json.load(handle)


DELEGATION_REJECTION_CODE_BY_NAME = {
    "VALIDATION_ERROR": common_pb2.VALIDATION_ERROR,
    "REDIRECT": common_pb2.REDIRECT,
}

CANCELLATION_ERROR_CODE_BY_NAME = {
    "ERROR_CODE_UNSPECIFIED": common_pb2.ERROR_CODE_UNSPECIFIED,
    "FORCED_PREEMPTION": common_pb2.FORCED_PREEMPTION,
}


@pytest.mark.parametrize(
    "vector",
    DELEGATION_VECTOR_SUITE["vectors"],
    ids=lambda vector: vector["id"],
)
def test_delegate_to_swarm_shared_conformance_vectors(vector):
    attempts = []
    redirect_map = vector["redirect_map"]

    def send_handoff(request: handoff_pb2.HandoffRequest) -> handoff_pb2.HandoffResponse:
        attempts.append(request.to_agent)
        return handoff_pb2.HandoffResponse(
            request_id=request.request_id,
            accepted=False,
            rejection_code=common_pb2.REDIRECT,
            redirect_to_agent_id=redirect_map[request.to_agent],
        )

    budget = vector["budget"]
    policy = vector["policy"]
    response = delegate_to_swarm(
        send_handoff,
        from_agent=vector["from_agent"],
        to_agent=vector["to_agent"],
        reason=vector["reason"],
        request_id=vector["request_id"],
        budget=handoff_pb2.BudgetEnvelope(
            token_budget_remaining=5_000,
            wall_time_remaining_ms=budget["wall_time_remaining_ms"],
            deadline_epoch_ms=budget["deadline_epoch_ms"],
            current_depth=1,
            max_delegation_depth=3,
        ),
        delegation_policy=handoff_pb2.SwarmDelegationPolicy(
            allow_spillover_routing=policy["allow_spillover_routing"],
            max_redirects=policy["max_redirects"],
        ),
        now_ms_fn=lambda: budget["deadline_epoch_ms"] - 1_000,
    )

    expected = vector["expected"]
    assert response.accepted == expected["accepted"]
    assert (
        response.rejection_code
        == DELEGATION_REJECTION_CODE_BY_NAME[expected["rejection_code"]]
    )
    assert attempts == expected["attempts"]

    reason_contains = expected.get("reason_contains")
    if reason_contains:
        assert reason_contains.lower() in response.rejection_reason.lower()

    expected_redirect = expected.get("redirect_to_agent_id")
    if expected_redirect is not None:
        assert response.redirect_to_agent_id == expected_redirect


@pytest.mark.parametrize(
    "vector",
    CANCELLATION_VECTOR_SUITE["vectors"],
    ids=lambda vector: vector["id"],
)
def test_cancellation_shared_conformance_vectors(vector):
    manager = CancellationManager(time_ms_fn=lambda: 1_000)

    for child_link in vector.get("children", []):
        manager.register_child_delegation(child_link["parent"], child_link["child"])

    request = vector["request"]
    response = manager.handle_cancel_delegation(
        handoff_pb2.CancelDelegation(
            correlation_id=request["correlation_id"],
            reason=request["reason"],
            grace_period_ms=request["grace_period_ms"],
        )
    )

    expected = vector["expected"]
    assert response.acknowledged == expected["acknowledged"]

    root_id = request["correlation_id"]
    root_flag = manager.cancellation_flags[root_id]
    assert root_flag.grace_period_ms == expected["effective_grace_period_ms"]

    for correlation_id in expected.get("cancelled", []):
        assert manager.is_cancelled(correlation_id)

    for check in expected.get("grace_expiry_checks", []):
        correlation_id = check["correlation_id"]
        flag = manager.cancellation_flags[correlation_id]
        check_now = int(flag.cancel_time_ms + flag.grace_period_ms + check["offset_ms"])
        assert (
            manager.is_grace_expired(correlation_id, now_ms=check_now)
            == check["expired"]
        )

    for check in expected.get("forced_preemption_checks", []):
        correlation_id = check["correlation_id"]
        flag = manager.cancellation_flags[correlation_id]
        check_now = int(flag.cancel_time_ms + flag.grace_period_ms + check["offset_ms"])
        assert manager.forced_preemption_error_code(
            correlation_id, now_ms=check_now
        ) == CANCELLATION_ERROR_CODE_BY_NAME[check["error_code"]]

    collect_forced = expected.get("collect_forced")
    if collect_forced:
        collect_now = int(
            root_flag.cancel_time_ms
            + root_flag.grace_period_ms
            + collect_forced["offset_ms"]
        )
        forced = manager.collect_forced_preemptions(
            set(collect_forced["active_correlations"]),
            now_ms=collect_now,
        )
        assert forced == set(collect_forced["expected"])
