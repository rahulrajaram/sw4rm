from __future__ import annotations

import sys
from pathlib import Path

import pytest

HIVE_DIR = Path(__file__).resolve().parents[1] / "reference-services" / "hive"
if str(HIVE_DIR) not in sys.path:
    sys.path.insert(0, str(HIVE_DIR))

from reference_auth_middleware import (
    ReferenceAuthPolicy,
    ReferenceRateLimitInterceptor,
    ReferenceRateLimitPolicy,
    decode_reference_token,
    extract_subject_from_metadata,
    issue_reference_token,
    ReferenceTracingInterceptor,
    build_auth_interceptors,
)  # noqa: E402
from sw4rm.protos import common_pb2, registry_pb2, router_pb2, scheduler_pb2


def test_reference_jwt_roundtrip() -> None:
    now_fn = lambda: 1700000000
    token = issue_reference_token("agent-a", "secret", ttl_seconds=60, now_fn=now_fn)
    claims = decode_reference_token(token, "secret", now_fn=lambda: 1700000020)
    assert claims["sub"] == "agent-a"


def test_reference_jwt_rejects_expired_token() -> None:
    token = issue_reference_token("agent-a", "secret", ttl_seconds=1, now_fn=lambda: 1700000000)
    with pytest.raises(ValueError, match="expired"):
        decode_reference_token(token, "secret", now_fn=lambda: 1700000100)


def test_extract_subject_from_metadata_uses_bearer() -> None:
    token = issue_reference_token("agent-a", "secret", ttl_seconds=60, now_fn=lambda: 1700000000)
    metadata = [("authorization", f"Bearer {token}")]
    subject = extract_subject_from_metadata(metadata, "secret", now_fn=lambda: 1700000010)
    assert subject == "agent-a"


def test_auth_policy_rejects_impostor_sender() -> None:
    policy = ReferenceAuthPolicy.with_defaults(secret="secret")
    request = router_pb2.SendMessageRequest(
        msg=common_pb2.Envelope(
            producer_id="agent-alpha",
            message_type=common_pb2.MessageType.DATA,
            content_type="application/json",
            payload=b"{}",
        )
    )
    assert policy.authorize("SendMessage", "agent-alpha", request) is True
    assert policy.authorize("SendMessage", "agent-beta", request) is False


def test_auth_policy_restricts_admin_methods_to_admin_agents() -> None:
    policy = ReferenceAuthPolicy.with_defaults(secret="secret")
    request = scheduler_pb2.ShutdownAgentRequest(agent_id="agent-alpha")
    assert policy.authorize("ShutdownAgent", "scheduler", request) is True
    assert policy.authorize("ShutdownAgent", "agent-alpha", request) is False


def test_rate_limit_policy_enforces_send_message_qps() -> None:
    now_state = {"time": 0.0}

    def now() -> float:
        return now_state["time"]

    policy = ReferenceRateLimitPolicy(
        enabled=True,
        messages_per_second=2.0,
        burst_size=2,
        target_methods={"SendMessage"},
        now_fn=now,
    )

    assert policy.allow("SendMessage", "agent-a")[0] is True
    assert policy.allow("SendMessage", "agent-a")[0] is True
    assert policy.allow("SendMessage", "agent-a")[0] is False
    assert policy.allow("Heartbeat", "agent-a")[0] is True

    now_state["time"] = 1.0
    assert policy.allow("SendMessage", "agent-a")[0] is True


class _FakeContext:
    def __init__(self, metadata=None) -> None:
        self.aborts: list[tuple[object, str]] = []
        self._metadata = list(metadata or [])
        self.method = ""

    def invocation_metadata(self):
        return self._metadata

    def abort(self, code, details):
        self.aborts.append((code, details))
        raise RuntimeError(details)


class _FakeRequest:
    def __init__(self, msg=None, agent_id: str | None = None) -> None:
        self.msg = msg
        self.agent_id = agent_id


def test_rate_limit_interceptor_rejects_messages_over_limit() -> None:
    now_state = {"time": 0.0}

    def now() -> float:
        return now_state["time"]

    policy = ReferenceRateLimitPolicy(
        enabled=True,
        messages_per_second=1.0,
        burst_size=1,
        target_methods={"SendMessage"},
        now_fn=now,
    )
    interceptor = ReferenceRateLimitInterceptor(policy)
    request = router_pb2.SendMessageRequest(
        msg=common_pb2.Envelope(producer_id="agent-a", message_type=common_pb2.MessageType.DATA)
    )

    context = _FakeContext()
    interceptor._enforce("SendMessage", request, context)
    with pytest.raises(RuntimeError, match="message limit exceeded"):
        interceptor._enforce("SendMessage", request, context)


def test_tracing_interceptor_resolves_trace_from_metadata() -> None:
    interceptor = ReferenceTracingInterceptor(service_name="router")
    context = _FakeContext(
        metadata=[
            ("x-sw4rm-trace-id", "trace-1"),
            ("x-sw4rm-span-id", "span-1"),
        ]
    )
    trace = interceptor._resolve_trace_context(
        "SendMessage",
        _FakeRequest(agent_id="agent-a"),
        context,
    )
    assert trace is not None
    assert trace.trace_id == "trace-1"
    assert trace.parent_span_id == "span-1"


def test_tracing_interceptor_resolves_trace_from_envelope_metadata() -> None:
    interceptor = ReferenceTracingInterceptor(service_name="router")
    context = _FakeContext()
    request = _FakeRequest(
        msg={
            "_trace_context": {
                "trace_id": "trace-2",
                "span_id": "span-2",
            }
        }
    )
    trace = interceptor._resolve_trace_context("SendMessage", request, context)
    assert trace is not None
    assert trace.trace_id == "trace-2"
    assert trace.parent_span_id == "span-2"


def test_tracing_interceptor_wraps_handler_with_request_scope() -> None:
    interceptor = ReferenceTracingInterceptor(service_name="router")

    observed: dict[str, str] = {}

    def handler(request, context):
        from sw4rm import tracing
        active = tracing.get_current_trace()
        observed["trace_id"] = active.trace_id if active is not None else "none"
        observed["parent_span_id"] = active.parent_span_id or ""
        return "ok"

    handler_wrapper = interceptor._wrap_unary_unary(
        "SendMessage",
        handler,
    )
    response = handler_wrapper(
        _FakeRequest(
            msg={
                "_trace_context": {
                    "trace_id": "trace-3",
                    "span_id": "span-3",
                }
            }
        ),
        _FakeContext(),
    )

    assert response == "ok"
    assert observed["trace_id"] == "trace-3"
    assert observed["parent_span_id"] == "span-3"


def test_build_auth_interceptors_includes_reference_tracing() -> None:
    interceptors = build_auth_interceptors(service_name="router")
    assert any(interceptor.__class__.__name__ == "ReferenceTracingInterceptor" for interceptor in interceptors)
