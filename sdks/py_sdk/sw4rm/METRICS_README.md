# SW4RM Metrics Interface

This document describes the metrics collection interface for SW4RM, implementing specification §13 (Buffers and Back-Pressure).

## Overview

The metrics module provides a pluggable interface for collecting observability data from SW4RM agents and routers. It supports three metric types:

- **Gauges**: Point-in-time measurements (e.g., current queue depth)
- **Counters**: Monotonically increasing totals (e.g., total message rejects)
- **Histograms**: Value distributions (e.g., latency measurements)

## Quick Start

```python
from sw4rm.metrics import (
    MetricName,
    InMemoryMetricsCollector,
    NoOpMetricsCollector,
)

# For production (zero overhead)
collector = NoOpMetricsCollector()

# For testing/debugging
collector = InMemoryMetricsCollector()

# Record metrics
collector.record_gauge(
    MetricName.INBOUND_QUEUE_DEPTH,
    value=7,
    labels={"agent_id": "agent-frontend"}
)

collector.record_counter(
    MetricName.NACKS_TOTAL,
    increment=1,
    labels={"agent_id": "scheduler", "error_code": "ack_timeout"}
)

collector.record_histogram(
    MetricName.PROCESS_TIME_SECONDS,
    value=0.042,
    labels={"agent_id": "worker"}
)

# Retrieve metrics (InMemoryMetricsCollector only)
metrics = collector.get_metrics()
for metric in metrics:
    print(f"{metric.name.value} = {metric.value} {metric.labels}")
```

## Standard Metrics

All metric names are defined in `MetricName` enum and align with SW4RM spec §13:

### Router Queue Metrics

- **`INBOUND_QUEUE_DEPTH`** (gauge)
  - Current number of messages in agent's inbound queue
  - Labels: `agent_id`
  - Example: `router.inbound_queue_depth{agent_id="agent-42"} 7`

- **`INBOUND_QUEUE_CAPACITY`** (gauge)
  - Maximum queue capacity for agent
  - Labels: `agent_id`
  - Example: `router.inbound_queue_capacity{agent_id="agent-42"} 10`

### Rejection and Error Metrics

- **`ENQUEUE_REJECTS_TOTAL`** (counter)
  - Total messages rejected during enqueue
  - Labels: `agent_id`, `reason`
  - Reasons: `buffer_full`, `oversize_payload`, `validation_error`
  - Example: `router.enqueue_rejects_total{agent_id="agent-42",reason="buffer_full"} 5`

- **`NACKS_TOTAL`** (counter)
  - Total negative acknowledgments sent
  - Labels: `agent_id`, `error_code`
  - Error codes: `buffer_full`, `ack_timeout`, `permission_denied`, etc.
  - Example: `router.nacks_total{agent_id="scheduler",error_code="ack_timeout"} 3`

### Latency Metrics

- **`ENQUEUE_LATENCY_SECONDS`** (histogram)
  - Time from message receive to enqueue
  - Labels: `agent_id`
  - Example: `router.enqueue_latency_seconds{agent_id="agent-42"} 0.001`

- **`DEQUEUE_LATENCY_SECONDS`** (histogram)
  - Time from enqueue to agent fetch
  - Labels: `agent_id`
  - Example: `agent.dequeue_latency_seconds{agent_id="agent-42"} 0.005`

- **`PROCESS_TIME_SECONDS`** (histogram)
  - Service time per message
  - Labels: `agent_id`
  - Example: `agent.process_time_seconds{agent_id="agent-42"} 0.042`

### Age Metrics

- **`OLDEST_ENQUEUED_AGE_SECONDS`** (gauge)
  - Age of oldest message in queue
  - Labels: `agent_id`
  - Example: `router.oldest_enqueued_age_seconds{agent_id="agent-42"} 2.5`

## Standard Labels

As specified in the SW4RM spec, the following labels are commonly used:

- **`agent_id`**: Identifier of the agent (e.g., `"agent-frontend"`, `"scheduler"`)
- **`error_code`**: Error code for failure metrics (e.g., `"buffer_full"`, `"ack_timeout"`)
- **`reason`**: Human-readable reason for rejections (e.g., `"buffer_full"`, `"oversize_payload"`)

## Implementations

### NoOpMetricsCollector

The default implementation that discards all metrics. Use this in production when you don't need metrics or have external instrumentation.

**Characteristics:**
- Zero overhead
- No memory allocation
- All operations are no-op
- `get_metrics()` always returns empty list

**Use cases:**
- Production deployments without metrics
- Performance-critical paths
- When using external metrics systems (Prometheus, StatsD)

```python
from sw4rm.metrics import NoOpMetricsCollector

collector = NoOpMetricsCollector()
collector.record_gauge(MetricName.INBOUND_QUEUE_DEPTH, 10)  # No-op
assert collector.get_metrics() == []  # Always empty
```

### InMemoryMetricsCollector

A simple in-memory implementation for testing and debugging.

**Characteristics:**
- Stores all metrics in memory
- No aggregation or windowing
- Thread-safe reads (shallow copy on get_metrics)
- Manual cleanup required (call `clear()`)

**Use cases:**
- Unit testing metrics emission
- Local development and debugging
- Small-scale deployments
- Integration tests

**Warning:** This collector does not implement retention policies. Long-running processes should periodically call `get_metrics()` and `clear()` to prevent unbounded memory growth.

```python
from sw4rm.metrics import InMemoryMetricsCollector

collector = InMemoryMetricsCollector()

# Record metrics
collector.record_counter(MetricName.NACKS_TOTAL, labels={"agent_id": "test"})
collector.record_gauge(MetricName.INBOUND_QUEUE_DEPTH, 5)

# Retrieve and inspect
metrics = collector.get_metrics()
assert len(metrics) == 2

# Check memory usage
print(f"Stored metrics: {collector.get_metric_count()}")

# Clear to prevent memory growth
collector.clear()
assert collector.get_metric_count() == 0
```

## Custom Implementations

You can create custom collectors by implementing the `MetricsCollector` protocol:

```python
from typing import Optional
from sw4rm.metrics import MetricName, Metric, MetricsCollector


class PrometheusCollector:
    """Example: Export metrics to Prometheus."""

    def __init__(self, registry):
        self.registry = registry
        self._gauges = {}
        self._counters = {}
        self._histograms = {}

    def record_gauge(
        self,
        name: MetricName,
        value: float,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        # Get or create Prometheus gauge
        gauge = self._get_or_create_gauge(name)
        if labels:
            gauge.labels(**labels).set(value)
        else:
            gauge.set(value)

    def record_counter(
        self,
        name: MetricName,
        increment: float = 1.0,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        counter = self._get_or_create_counter(name)
        if labels:
            counter.labels(**labels).inc(increment)
        else:
            counter.inc(increment)

    def record_histogram(
        self,
        name: MetricName,
        value: float,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        histogram = self._get_or_create_histogram(name)
        if labels:
            histogram.labels(**labels).observe(value)
        else:
            histogram.observe(value)

    def get_metrics(self) -> list[Metric]:
        # Prometheus handles storage/export
        return []

    # Helper methods omitted for brevity...
```

## Integration Example

Here's how to integrate metrics into a SW4RM router:

```python
from sw4rm.metrics import MetricName, InMemoryMetricsCollector
import time


class MessageRouter:
    def __init__(self, metrics_collector):
        self.metrics = metrics_collector
        self.queues = {}  # agent_id -> queue

    def enqueue_message(self, agent_id: str, message: dict) -> bool:
        start_time = time.time()

        queue = self.queues.get(agent_id)
        if not queue:
            return False

        # Record current queue depth
        self.metrics.record_gauge(
            MetricName.INBOUND_QUEUE_DEPTH,
            value=len(queue),
            labels={"agent_id": agent_id}
        )

        # Check capacity
        capacity = 10  # from config
        if len(queue) >= capacity:
            # Record rejection
            self.metrics.record_counter(
                MetricName.ENQUEUE_REJECTS_TOTAL,
                labels={"agent_id": agent_id, "reason": "buffer_full"}
            )

            # Record NACK
            self.metrics.record_counter(
                MetricName.NACKS_TOTAL,
                labels={"agent_id": agent_id, "error_code": "buffer_full"}
            )
            return False

        # Enqueue message
        queue.append(message)

        # Record enqueue latency
        latency = time.time() - start_time
        self.metrics.record_histogram(
            MetricName.ENQUEUE_LATENCY_SECONDS,
            value=latency,
            labels={"agent_id": agent_id}
        )

        # Update queue depth after enqueue
        self.metrics.record_gauge(
            MetricName.INBOUND_QUEUE_DEPTH,
            value=len(queue),
            labels={"agent_id": agent_id}
        )

        return True

    def process_message(self, agent_id: str) -> None:
        queue = self.queues.get(agent_id, [])
        if not queue:
            return

        start_time = time.time()
        message = queue.pop(0)

        # Calculate dequeue latency
        enqueue_time = message.get("enqueue_timestamp", start_time)
        dequeue_latency = start_time - enqueue_time
        self.metrics.record_histogram(
            MetricName.DEQUEUE_LATENCY_SECONDS,
            value=dequeue_latency,
            labels={"agent_id": agent_id}
        )

        # Process message...
        # (processing code here)

        # Record processing time
        process_time = time.time() - start_time
        self.metrics.record_histogram(
            MetricName.PROCESS_TIME_SECONDS,
            value=process_time,
            labels={"agent_id": agent_id}
        )

        # Update queue depth
        self.metrics.record_gauge(
            MetricName.INBOUND_QUEUE_DEPTH,
            value=len(queue),
            labels={"agent_id": agent_id}
        )


# Usage
collector = InMemoryMetricsCollector()
router = MessageRouter(collector)

# Later, inspect metrics
metrics = collector.get_metrics()
for m in metrics:
    print(f"{m.name.value} = {m.value} @ {m.timestamp}")
```

## Testing

The module includes comprehensive validation tests:

```bash
cd sdks/py_sdk
python3 test_metrics_validation.py
```

Example output:
```
============================================================
SW4RM Metrics Module Validation
============================================================

Testing MetricName enum...
  ✓ INBOUND_QUEUE_DEPTH: router.inbound_queue_depth
  ✓ INBOUND_QUEUE_CAPACITY: router.inbound_queue_capacity
  ✓ ENQUEUE_REJECTS_TOTAL: router.enqueue_rejects_total
  ✓ NACKS_TOTAL: router.nacks_total
  ✓ ENQUEUE_LATENCY_SECONDS: router.enqueue_latency_seconds
  ✓ DEQUEUE_LATENCY_SECONDS: agent.dequeue_latency_seconds
  ✓ PROCESS_TIME_SECONDS: agent.process_time_seconds
  ✓ OLDEST_ENQUEUED_AGE_SECONDS: router.oldest_enqueued_age_seconds
  All 8 required metrics defined!

...

============================================================
✓ All validation tests passed!
============================================================
```

## Best Practices

1. **Choose the right collector**:
   - Use `NoOpMetricsCollector` in production unless you need metrics
   - Use `InMemoryMetricsCollector` for testing and debugging
   - Implement custom collectors for production observability (Prometheus, DataDog, etc.)

2. **Label discipline**:
   - Always include `agent_id` label
   - Use `error_code` for error metrics
   - Use `reason` for human-readable rejection reasons
   - Keep label cardinality low to avoid memory issues

3. **Memory management**:
   - With `InMemoryMetricsCollector`, periodically call `clear()`
   - Monitor `get_metric_count()` in long-running processes
   - Consider time-based or size-based retention policies

4. **Performance**:
   - Metrics recording should be fast (< 1ms)
   - Avoid expensive operations in metric recording paths
   - Use batching for high-volume metrics if needed

5. **Testing**:
   - Use `InMemoryMetricsCollector` in tests to verify metrics emission
   - Assert on metric counts, names, and label values
   - Clear collector between test cases

## See Also

- [SW4RM Specification §13: Buffers and Back-Pressure](../../documentation/protocol/spec.md#13-buffers-and-back-pressure)
- [SW4RM Python SDK Documentation](../README.md)
- [Activity Buffer Module](activity_buffer.py)
- [Error Mapping Module](error_mapping.py)
