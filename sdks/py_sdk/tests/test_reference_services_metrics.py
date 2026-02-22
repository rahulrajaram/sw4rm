from __future__ import annotations

import sys
from pathlib import Path

import pytest

HIVE_DIR = Path(__file__).resolve().parents[1] / "reference-services" / "hive"
if str(HIVE_DIR) not in sys.path:
    sys.path.insert(0, str(HIVE_DIR))

from reference_metrics import (  # noqa: E402
    ReferenceMetricsInterceptor,
    _canonical_service_name,
    build_reference_metrics_interceptor,
)  # type: ignore


class _FakeCollector:
    def __init__(self) -> None:
        self.started = []
        self.completed = []
        self.failed = []

    def request_started(self, service_name: str, method_name: str, is_message: bool) -> None:
        self.started.append((service_name, method_name, is_message))

    def request_completed(
        self,
        service_name: str,
        method_name: str,
        duration_seconds: float,
        is_message: bool,
    ) -> None:
        self.completed.append((service_name, method_name, round(duration_seconds, 6), is_message))

    def request_failed(
        self,
        service_name: str,
        method_name: str,
        status: str,
        duration_seconds: float,
        is_message: bool,
    ) -> None:
        self.failed.append((service_name, method_name, status, round(duration_seconds, 6), is_message))


def test_canonical_service_name_is_normalized() -> None:
    assert _canonical_service_name("registry") == "registry"
    assert _canonical_service_name("registry-service") == "registry"
    assert _canonical_service_name("router") == "router"
    assert _canonical_service_name("scheduler") == "scheduler"
    assert _canonical_service_name("reference-service") == "reference-service"


def test_unary_unary_success_and_failure_metric_counts() -> None:
    collector = _FakeCollector()
    interceptor = ReferenceMetricsInterceptor("registry", collector=collector)

    def _ok_handler(_request, _context):
        return "ok"

    result = interceptor._wrap_unary_unary("SendMessage", _ok_handler)("payload", None)
    assert result == "ok"

    assert collector.started == [("registry", "SendMessage", True)]
    assert len(collector.completed) == 1
    assert not collector.failed

    def _fail_handler(_request, _context):
        raise RuntimeError("request failed")

    with pytest.raises(RuntimeError, match="request failed"):
        interceptor._wrap_unary_unary("SendMessage", _fail_handler)("payload", None)

    assert len(collector.failed) == 1
    assert collector.failed[0][:3] == ("registry", "SendMessage", "runtime_error")


def test_streaming_success_and_failure_paths_for_all_stream_variants() -> None:
    collector = _FakeCollector()
    interceptor = ReferenceMetricsInterceptor("scheduler", collector=collector)

    def _unary_stream_handler(_request, _context):
        yield "ok-1"
        yield "ok-2"

    assert list(interceptor._wrap_unary_stream("StreamIncoming", _unary_stream_handler)(None, None)) == [
        "ok-1",
        "ok-2",
    ]

    assert len(collector.completed) >= 1
    assert not collector.failed

    def _failing_stream(_request, _context):
        yield "before"
        raise RuntimeError("stream failed")

    with pytest.raises(RuntimeError, match="stream failed"):
        list(interceptor._wrap_stream_stream("StreamIncoming", _failing_stream)(iter(("msg",)), None))

    assert any(entry[2] == "runtime_error" for entry in collector.failed)
    assert len(collector.failed) >= 1

    def _stream_unary_handler(_request_iter, _context):
        consumed = list(_request_iter)
        return str(consumed)

    assert interceptor._wrap_stream_unary("SubmitTasks", _stream_unary_handler)(iter(("a", "b")), None) == "['a', 'b']"
    assert collector.completed[-1][1] == "SubmitTasks"

    def _failing_stream_unary(_request_iter, _context):
        raise RuntimeError("stream unary failed")

    with pytest.raises(RuntimeError, match="stream unary failed"):
        interceptor._wrap_stream_unary("SubmitTasks", _failing_stream_unary)(iter(("a", "b")), None)

    assert any(entry[2] == "runtime_error" for entry in collector.failed)


def test_metrics_interceptor_can_be_disabled_with_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("REFERENCE_METRICS_ENABLED", "0")
    try:
        interceptor = build_reference_metrics_interceptor("registry")
    finally:
        monkeypatch.delenv("REFERENCE_METRICS_ENABLED", raising=False)
    assert interceptor is None
