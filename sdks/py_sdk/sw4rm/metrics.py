# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Metrics collection interface for SW4RM.

This module provides abstractions for collecting and reporting metrics as defined
in SW4RM specification §13 (Buffers and Back-Pressure).

The metrics system supports three types of metrics:
- Gauges: Point-in-time values (e.g., queue depth)
- Counters: Monotonically increasing values (e.g., total rejects)
- Histograms: Distribution of values (e.g., latency measurements)

Implementations can choose between NoOpMetricsCollector (default, no overhead),
InMemoryMetricsCollector (testing/debugging), and now StatsDMetricsCollector
for production metrics backends (StatsD/Datadog-compatible).
"""

from __future__ import annotations

import logging
import socket
import time
from dataclasses import dataclass, field
from enum import Enum
from typing import Protocol, Optional


_DEFAULT_STATSD_HOST = "localhost"
_DEFAULT_STATSD_PORT = 8125
_DEFAULT_METRICS_NAMESPACE = "sw4rm"


def _safe_tag_value(value: object) -> str:
    """Return a value suitable for a Datadog tag."""
    return str(value).replace(":", "\\:").replace("|", "\\|")


def _normalize_namespace(namespace: str) -> str:
    return namespace.strip().strip(".")


def _normalize_backend_name(backend: str) -> str:
    return backend.strip().lower()


class MetricName(Enum):
    """Standard metric names from SW4RM spec §13.

    These metric names align with the recommended back-pressure metrics
    for monitoring router and agent health.
    """

    # Router queue metrics
    INBOUND_QUEUE_DEPTH = "router.inbound_queue_depth"
    INBOUND_QUEUE_CAPACITY = "router.inbound_queue_capacity"

    # Rejection and error metrics
    ENQUEUE_REJECTS_TOTAL = "router.enqueue_rejects_total"
    NACKS_TOTAL = "router.nacks_total"

    # Latency metrics
    ENQUEUE_LATENCY_SECONDS = "router.enqueue_latency_seconds"
    DEQUEUE_LATENCY_SECONDS = "agent.dequeue_latency_seconds"
    PROCESS_TIME_SECONDS = "agent.process_time_seconds"

    # Age metrics
    OLDEST_ENQUEUED_AGE_SECONDS = "router.oldest_enqueued_age_seconds"


@dataclass
class Metric:
    """Represents a single metric observation.

    Attributes:
        name: The metric identifier (from MetricName enum)
        value: The numeric value of this observation
        labels: Key-value pairs for metric dimensions (e.g., agent_id, error_code)
        timestamp: Unix timestamp (seconds since epoch) when metric was recorded
    """

    name: MetricName
    value: float
    labels: dict[str, str] = field(default_factory=dict)
    timestamp: float = field(default_factory=time.time)

    def __post_init__(self) -> None:
        """Validate metric fields after initialization."""
        if not isinstance(self.name, MetricName):
            raise TypeError(f"name must be a MetricName enum, got {type(self.name)}")
        if not isinstance(self.value, (int, float)):
            raise TypeError(f"value must be numeric, got {type(self.value)}")


def _build_statsd_tags(
    labels: Optional[dict[str, str]],
    *,
    global_tags: Optional[list[str]] = None,
) -> str:
    """Build a stable, deterministic Datadog/StatsD tag string."""
    tags: list[str] = []
    if global_tags:
        tags.extend(global_tags)
    if labels:
        for key in sorted(labels):
            tags.append(f"{_safe_tag_value(key)}:{_safe_tag_value(labels[key])}")
    return f"|#{','.join(tags)}" if tags else ""


def _format_metric_name(name: MetricName, namespace: str = "") -> str:
    """Build metric name with optional namespace."""
    metric_name = name.value
    normalized_namespace = _normalize_namespace(namespace)
    return f"{normalized_namespace}.{metric_name}" if normalized_namespace else metric_name


class MetricsCollector(Protocol):
    """Protocol defining the interface for metrics collection.

    Implementations of this protocol handle the recording and storage of metrics.
    The protocol supports three metric types commonly used in observability systems:

    - Gauges: Current value measurements (use record_gauge)
    - Counters: Cumulative totals (use record_counter)
    - Histograms: Value distributions (use record_histogram)

    Standard labels from spec:
        - agent_id: Identifier of the agent producing the metric
        - error_code: Error code for failure metrics (e.g., buffer_full)
        - reason: Human-readable reason for rejections or errors
    """

    def record_gauge(
        self,
        name: MetricName,
        value: float,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Record a gauge metric (point-in-time value).

        Gauges represent instantaneous measurements like queue depth or capacity.
        Each call sets the current value, overwriting previous observations.

        Args:
            name: The metric to record
            value: Current measurement value
            labels: Optional dimensional labels (e.g., {"agent_id": "agent-42"})

        Example:
            collector.record_gauge(
                MetricName.INBOUND_QUEUE_DEPTH,
                value=7,
                labels={"agent_id": "agent-frontend"}
            )
        """
        ...

    def record_counter(
        self,
        name: MetricName,
        increment: float = 1.0,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Record a counter metric (cumulative total).

        Counters track monotonically increasing values like total requests or errors.
        Each call adds the increment to the running total.

        Args:
            name: The metric to increment
            increment: Amount to add to counter (default: 1.0)
            labels: Optional dimensional labels (e.g., {"error_code": "buffer_full"})

        Example:
            collector.record_counter(
                MetricName.ENQUEUE_REJECTS_TOTAL,
                increment=1,
                labels={"agent_id": "agent-backend", "reason": "buffer_full"}
            )
        """
        ...

    def record_histogram(
        self,
        name: MetricName,
        value: float,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Record a histogram metric (value distribution).

        Histograms track the distribution of values like latencies or message sizes.
        Implementations typically calculate percentiles, averages, and other statistics.

        Args:
            name: The metric to observe
            value: Measurement value to record
            labels: Optional dimensional labels (e.g., {"agent_id": "agent-scheduler"})

        Example:
            collector.record_histogram(
                MetricName.PROCESS_TIME_SECONDS,
                value=0.042,
                labels={"agent_id": "agent-worker"}
            )
        """
        ...

    def get_metrics(self) -> list[Metric]:
        """Retrieve all recorded metrics.

        Returns:
            List of all Metric instances recorded since the last retrieval or reset.
            The exact semantics (windowed vs. cumulative) depend on the implementation.

        Note:
            Some implementations may clear metrics after retrieval (snapshot behavior),
            while others maintain cumulative state. Check implementation documentation.
        """
        ...


class NoOpMetricsCollector:
    """A no-op metrics collector that discards all metrics.

    This is the default collector for production use when external metrics
    systems (Prometheus, StatsD, etc.) are not configured. It provides zero
    overhead by doing nothing.

    Example:
        collector = NoOpMetricsCollector()
        collector.record_gauge(MetricName.INBOUND_QUEUE_DEPTH, 5)  # No-op
    """

    def record_gauge(
        self,
        name: MetricName,
        value: float,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Discard gauge metric (no-op)."""
        pass

    def record_counter(
        self,
        name: MetricName,
        increment: float = 1.0,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Discard counter metric (no-op)."""
        pass

    def record_histogram(
        self,
        name: MetricName,
        value: float,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Discard histogram metric (no-op)."""
        pass

    def get_metrics(self) -> list[Metric]:
        """Return empty list (no metrics stored)."""
        return []


class InMemoryMetricsCollector:
    """In-memory metrics collector for testing and debugging.

    This collector stores all metrics in memory and is useful for:
    - Unit testing metrics emission
    - Local debugging and development
    - Small-scale deployments without external metrics infrastructure

    Warning:
        This collector does not implement windowing or retention policies.
        Long-running processes should periodically call get_metrics() and
        clear the buffer to prevent unbounded memory growth.

    Example:
        collector = InMemoryMetricsCollector()
        collector.record_counter(
            MetricName.NACKS_TOTAL,
            labels={"agent_id": "test-agent", "error_code": "ack_timeout"}
        )

        metrics = collector.get_metrics()
        assert len(metrics) == 1
        assert metrics[0].name == MetricName.NACKS_TOTAL
    """

    def __init__(self) -> None:
        """Initialize an empty in-memory metrics store."""
        self._metrics: list[Metric] = []

    def record_gauge(
        self,
        name: MetricName,
        value: float,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Record a gauge metric in memory.

        Note: This implementation stores each observation independently.
        For true gauge semantics (last value wins), consider using a
        production metrics backend.
        """
        metric = Metric(
            name=name,
            value=value,
            labels=labels or {},
        )
        self._metrics.append(metric)

    def record_counter(
        self,
        name: MetricName,
        increment: float = 1.0,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Record a counter increment in memory.

        Note: This implementation stores each increment independently.
        Aggregation must be performed by the consumer of get_metrics().
        """
        metric = Metric(
            name=name,
            value=increment,
            labels=labels or {},
        )
        self._metrics.append(metric)

    def record_histogram(
        self,
        name: MetricName,
        value: float,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Record a histogram observation in memory.

        Note: This implementation stores raw observations.
        Percentile calculation and bucketing must be performed by the
        consumer of get_metrics().
        """
        metric = Metric(
            name=name,
            value=value,
            labels=labels or {},
        )
        self._metrics.append(metric)

    def get_metrics(self) -> list[Metric]:
        """Return all recorded metrics.

        Returns a shallow copy of the metrics list to prevent external
        mutation of internal state.
        """
        return self._metrics.copy()

    def clear(self) -> None:
        """Clear all stored metrics.

        This method is useful for preventing unbounded memory growth
        in long-running processes or for resetting state between tests.
        """
        self._metrics.clear()

    def get_metric_count(self) -> int:
        """Return the number of metrics currently stored.

        Useful for monitoring memory usage and testing.
        """
        return len(self._metrics)


class StatsDMetricsCollector:
    """Datadog/StatsD-compatible metrics collector.

    This collector streams metrics to a local or remote StatsD UDP endpoint.
    It is safe by design: metric send failures are swallowed and do not interrupt
    control flow.

    Example:
        collector = StatsDMetricsCollector(
            host="127.0.0.1",
            port=8125,
            namespace="sw4rm",
            tags=["env:prod"],
        )
        collector.record_counter(MetricName.ENQUEUE_REJECTS_TOTAL, labels={"reason": "buffer_full"})
    """

    def __init__(
        self,
        host: str = _DEFAULT_STATSD_HOST,
        port: int = _DEFAULT_STATSD_PORT,
        namespace: str = _DEFAULT_METRICS_NAMESPACE,
        tags: Optional[list[str]] = None,
        sample_rate: float = 1.0,
        *,
        socket_factory=socket.socket,
    ) -> None:
        """Create a datagram-based metrics collector.

        Args:
            host: StatsD host
            port: StatsD port
            namespace: Optional metric namespace prefix
            tags: Global tags appended to every metric
            sample_rate: Optional DogStatsD sample rate (0.0 < rate <= 1.0)
            socket_factory: Optional injection point for testing
        """
        self.host = host
        self.port = port
        self.namespace = _normalize_namespace(namespace) or _DEFAULT_METRICS_NAMESPACE
        self.tags = tags or []
        self.sample_rate = sample_rate

        try:
            self._socket = socket_factory(socket.AF_INET, socket.SOCK_DGRAM)
            self._socket.settimeout(0.1)
        except Exception:
            logging.debug(
                "Failed to create metrics socket, metrics emission will be disabled",
                exc_info=True,
            )
            self._socket = None

    def _emit(self, name: MetricName, value: float, metric_type: str, labels: Optional[dict[str, str]]) -> None:
        """Emit one metric packet."""
        if self._socket is None:
            return

        metric = _format_metric_name(name, namespace=self.namespace)
        payload = f"{metric}:{value}|{metric_type}{_build_statsd_tags(labels, global_tags=self.tags)}"
        if self.sample_rate and 0 < self.sample_rate < 1:
            payload += f"|@{self.sample_rate}"
        try:
            self._socket.sendto(payload.encode("utf-8"), (self.host, self.port))
        except Exception:
            logging.debug(
                "Failed to send metrics packet to %s:%s",
                self.host,
                self.port,
                exc_info=True,
            )

    def record_gauge(
        self,
        name: MetricName,
        value: float,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Emit a gauge metric."""
        self._emit(name, float(value), "g", labels)

    def record_counter(
        self,
        name: MetricName,
        increment: float = 1.0,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Emit a counter metric."""
        self._emit(name, float(increment), "c", labels)

    def record_histogram(
        self,
        name: MetricName,
        value: float,
        labels: Optional[dict[str, str]] = None,
    ) -> None:
        """Emit a histogram metric."""
        self._emit(name, float(value), "h", labels)

    def get_metrics(self) -> list[Metric]:
        """Return empty list (StatsD stores metrics externally)."""
        return []

    def close(self) -> None:
        """Close underlying socket when no longer needed."""
        if self._socket is not None:
            self._socket.close()
            self._socket = None


def build_metrics_collector(
    *,
    enable_metrics: bool = True,
    backend: str = "noop",
    host: str = _DEFAULT_STATSD_HOST,
    port: int = _DEFAULT_STATSD_PORT,
    namespace: str = _DEFAULT_METRICS_NAMESPACE,
    tags: Optional[list[str]] = None,
    sample_rate: float = 1.0,
) -> MetricsCollector:
    """Build a metrics collector from explicit configuration.

    Supported backends:
    - noop / off / false / disabled
    - memory / inmemory
    - statsd / datadog / dogstatsd
    """
    if not enable_metrics:
        return NoOpMetricsCollector()

    backend_name = _normalize_backend_name(backend)
    if backend_name in {"noop", "off", "false", "disabled"}:
        return NoOpMetricsCollector()
    if backend_name in {"memory", "inmemory"}:
        return InMemoryMetricsCollector()
    if backend_name in {"statsd", "datadog", "dogstatsd"}:
        return StatsDMetricsCollector(
            host=host,
            port=port,
            namespace=namespace,
            tags=tags,
            sample_rate=sample_rate,
        )

    logging.warning("Unknown metrics backend '%s'; defaulting to noop", backend)
    return NoOpMetricsCollector()


def build_metrics_collector_from_config(config: Optional["SW4RMConfig"] = None) -> MetricsCollector:
    """Build a collector from SW4RMConfig."""
    if config is None:
        from . import config as _config

        config = _config.get_config()

    return build_metrics_collector(
        enable_metrics=config.enable_metrics,
        backend=config.metrics_backend,
        host=config.metrics_host,
        port=config.metrics_port,
        namespace=config.metrics_namespace,
        tags=config.metrics_tags,
        sample_rate=config.metrics_sample_rate,
    )
