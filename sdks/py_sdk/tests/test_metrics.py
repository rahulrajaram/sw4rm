"""Tests for Python SDK metrics collector implementations."""

from __future__ import annotations

from sw4rm import config as config_module
from sw4rm.metrics import (
    InMemoryMetricsCollector,
    MetricName,
    NoOpMetricsCollector,
    StatsDMetricsCollector,
    build_metrics_collector,
    build_metrics_collector_from_config,
)


class _CapturingSocket:
    def __init__(self) -> None:
        self.sent: list[tuple[bytes, tuple[str, int]]] = []

    def settimeout(self, *_args, **_kwargs) -> None:
        """No-op for tests."""

    def sendto(self, payload: bytes, destination: tuple[str, int]) -> int:
        self.sent.append((payload, destination))
        return len(payload)

    def close(self) -> None:
        """No-op close."""


def test_build_metrics_collector_falls_back_to_noop_for_unknown_backend() -> None:
    """Unknown backend values should fall back to no-op collector."""
    collector = build_metrics_collector(enable_metrics=True, backend="mystery")
    assert isinstance(collector, NoOpMetricsCollector)


def test_build_metrics_collector_can_disable_with_flag() -> None:
    """Disabling metrics should return no-op collector."""
    collector = build_metrics_collector(enable_metrics=False, backend="statsd")
    assert isinstance(collector, NoOpMetricsCollector)


def test_statsd_collector_formats_payload_with_namespace_and_tags() -> None:
    """StatsD collector should emit datagram payloads with namespace and labels."""
    fake_socket = _CapturingSocket()

    collector = StatsDMetricsCollector(
        host="statsd.internal",
        port=8126,
        namespace="team.alpha",
        tags=["global:prod"],
        socket_factory=lambda *_args, **_kwargs: fake_socket,
    )

    collector.record_gauge(
        MetricName.INBOUND_QUEUE_DEPTH,
        value=7,
        labels={"agent_id": "agent-1", "error_code": "none"},
    )

    collector.record_counter(
        MetricName.ENQUEUE_REJECTS_TOTAL,
        increment=3,
        labels={"reason": "buffer_full"},
    )

    collector.record_histogram(
        MetricName.DEQUEUE_LATENCY_SECONDS,
        value=0.125,
        labels={"agent_id": "agent-2"},
    )

    assert len(fake_socket.sent) == 3
    assert fake_socket.sent[0][1] == ("statsd.internal", 8126)
    assert fake_socket.sent[0][0].decode() == (
        "team.alpha.router.inbound_queue_depth:7.0|g|#global:prod,"
        "agent_id:agent-1,error_code:none"
    )
    assert fake_socket.sent[1][0].decode() == (
        "team.alpha.router.enqueue_rejects_total:3.0|c|#global:prod,reason:buffer_full"
    )
    assert fake_socket.sent[2][0].decode() == (
        "team.alpha.agent.dequeue_latency_seconds:0.125|h|#global:prod,agent_id:agent-2"
    )


def test_statsd_collector_appends_sample_rate_when_configured() -> None:
    """Sample rate should be appended to emitted metrics packets."""
    fake_socket = _CapturingSocket()

    collector = StatsDMetricsCollector(
        sample_rate=0.25,
        socket_factory=lambda *_args, **_kwargs: fake_socket,
    )

    collector.record_counter(MetricName.NACKS_TOTAL, increment=1)
    assert fake_socket.sent == [
        (
            b"sw4rm.router.nacks_total:1.0|c|@0.25",
            ("localhost", 8125),
        )
    ]


def test_build_metrics_collector_from_config_supports_memory_backend() -> None:
    """Config-backed factory should honor in-memory backend."""
    cfg = config_module.SW4RMConfig(
        enable_metrics=True,
        metrics_backend="memory",
    )
    collector = build_metrics_collector_from_config(cfg)
    assert isinstance(collector, InMemoryMetricsCollector)


def test_memory_backend_config_still_supported() -> None:
    """Memory backend should produce in-memory collector."""
    collector = build_metrics_collector(
        enable_metrics=True,
        backend="memory",
    )
    assert isinstance(collector, InMemoryMetricsCollector)

    collector.record_gauge(MetricName.INBOUND_QUEUE_CAPACITY, value=10)
    assert collector.get_metric_count() == 1
