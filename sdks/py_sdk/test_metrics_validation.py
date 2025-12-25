#!/usr/bin/env python3
"""Quick validation test for metrics.py implementation."""

from sw4rm.metrics import (
    MetricName,
    Metric,
    MetricsCollector,
    NoOpMetricsCollector,
    InMemoryMetricsCollector,
)


def test_metric_names():
    """Verify all required metric names are defined."""
    print("Testing MetricName enum...")
    required_metrics = [
        "INBOUND_QUEUE_DEPTH",
        "INBOUND_QUEUE_CAPACITY",
        "ENQUEUE_REJECTS_TOTAL",
        "NACKS_TOTAL",
        "ENQUEUE_LATENCY_SECONDS",
        "DEQUEUE_LATENCY_SECONDS",
        "PROCESS_TIME_SECONDS",
        "OLDEST_ENQUEUED_AGE_SECONDS",
    ]

    for metric_name in required_metrics:
        assert hasattr(MetricName, metric_name), f"Missing metric: {metric_name}"
        print(f"  ✓ {metric_name}: {getattr(MetricName, metric_name).value}")

    print(f"  All {len(required_metrics)} required metrics defined!\n")


def test_metric_dataclass():
    """Test Metric dataclass creation."""
    print("Testing Metric dataclass...")

    metric = Metric(
        name=MetricName.INBOUND_QUEUE_DEPTH,
        value=42.0,
        labels={"agent_id": "test-agent"},
    )

    assert metric.name == MetricName.INBOUND_QUEUE_DEPTH
    assert metric.value == 42.0
    assert metric.labels == {"agent_id": "test-agent"}
    assert isinstance(metric.timestamp, float)
    print(f"  ✓ Created metric: {metric.name.value} = {metric.value}")
    print(f"  ✓ Labels: {metric.labels}")
    print(f"  ✓ Timestamp: {metric.timestamp}\n")


def test_noop_collector():
    """Test NoOpMetricsCollector."""
    print("Testing NoOpMetricsCollector...")

    collector = NoOpMetricsCollector()

    # All operations should be no-op
    collector.record_gauge(MetricName.INBOUND_QUEUE_DEPTH, 10)
    collector.record_counter(MetricName.NACKS_TOTAL, 1)
    collector.record_histogram(MetricName.PROCESS_TIME_SECONDS, 0.5)

    metrics = collector.get_metrics()
    assert len(metrics) == 0, "NoOpCollector should return empty list"
    print("  ✓ All operations are no-op")
    print(f"  ✓ get_metrics() returns empty list: {metrics}\n")


def test_inmemory_collector():
    """Test InMemoryMetricsCollector."""
    print("Testing InMemoryMetricsCollector...")

    collector = InMemoryMetricsCollector()

    # Record different metric types
    collector.record_gauge(
        MetricName.INBOUND_QUEUE_DEPTH,
        value=7,
        labels={"agent_id": "agent-frontend"}
    )

    collector.record_counter(
        MetricName.ENQUEUE_REJECTS_TOTAL,
        increment=1,
        labels={"agent_id": "agent-backend", "reason": "buffer_full"}
    )

    collector.record_histogram(
        MetricName.PROCESS_TIME_SECONDS,
        value=0.042,
        labels={"agent_id": "agent-worker"}
    )

    metrics = collector.get_metrics()
    assert len(metrics) == 3, f"Expected 3 metrics, got {len(metrics)}"

    print(f"  ✓ Recorded 3 metrics")
    for i, m in enumerate(metrics, 1):
        print(f"    {i}. {m.name.value} = {m.value} {m.labels}")

    # Test clear
    assert collector.get_metric_count() == 3
    collector.clear()
    assert collector.get_metric_count() == 0
    print("  ✓ clear() removes all metrics\n")


def test_protocol_compliance():
    """Test that implementations satisfy the Protocol."""
    print("Testing Protocol compliance...")

    # Both implementations should satisfy MetricsCollector protocol
    noop: MetricsCollector = NoOpMetricsCollector()
    inmem: MetricsCollector = InMemoryMetricsCollector()

    # Both should have required methods
    for collector in [noop, inmem]:
        assert callable(collector.record_gauge)
        assert callable(collector.record_counter)
        assert callable(collector.record_histogram)
        assert callable(collector.get_metrics)

    print("  ✓ NoOpMetricsCollector satisfies Protocol")
    print("  ✓ InMemoryMetricsCollector satisfies Protocol\n")


def test_standard_labels():
    """Test standard labels from spec."""
    print("Testing standard labels...")

    collector = InMemoryMetricsCollector()

    # Test with standard labels: agent_id, error_code, reason
    collector.record_counter(
        MetricName.NACKS_TOTAL,
        labels={
            "agent_id": "scheduler",
            "error_code": "ack_timeout",
        }
    )

    collector.record_counter(
        MetricName.ENQUEUE_REJECTS_TOTAL,
        labels={
            "agent_id": "agent-42",
            "reason": "buffer_full",
        }
    )

    metrics = collector.get_metrics()
    assert len(metrics) == 2

    # Verify labels are preserved
    assert "agent_id" in metrics[0].labels
    assert "error_code" in metrics[0].labels
    assert "agent_id" in metrics[1].labels
    assert "reason" in metrics[1].labels

    print("  ✓ Standard labels work correctly")
    print(f"    - agent_id: {metrics[0].labels['agent_id']}")
    print(f"    - error_code: {metrics[0].labels['error_code']}")
    print(f"    - reason: {metrics[1].labels['reason']}\n")


if __name__ == "__main__":
    print("=" * 60)
    print("SW4RM Metrics Module Validation")
    print("=" * 60 + "\n")

    test_metric_names()
    test_metric_dataclass()
    test_noop_collector()
    test_inmemory_collector()
    test_protocol_compliance()
    test_standard_labels()

    print("=" * 60)
    print("✓ All validation tests passed!")
    print("=" * 60)
