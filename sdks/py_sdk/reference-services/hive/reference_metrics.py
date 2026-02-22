#!/usr/bin/env python3
"""Prometheus instrumentation for reference services.

The reference services share the same gRPC transport interceptor chain as
authentication and rate limiting. This module plugs into that chain so every
incoming RPC contributes to Prometheus metrics for:

* Message counts
* Request latency histograms
* Error counters
* Active connection gauges (includes streaming RPCs)

The exporter can be disabled with ``REFERENCE_METRICS_ENABLED=0``. If
``prometheus_client`` is unavailable, the interceptor still returns a
no-op implementation so service startup remains functional.
"""

from __future__ import annotations

import logging
import os
import threading
import time
from typing import Dict, Optional

import grpc


logger = logging.getLogger(__name__)

_DEFAULT_METRICS_HOST = "0.0.0.0"
_DEFAULT_METRICS_ENABLED = True
_DEFAULT_SERVICE_PORTS: Dict[str, int] = {
    "registry": 9100,
    "router": 9101,
    "scheduler": 9102,
}

_STARTED_METRICS_PORTS: set[int] = set()
_METRICS_LOCK = threading.Lock()


def _coerce_bool(value: Optional[str], default: bool) -> bool:
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on", "enabled"}


def _coerce_int(value: Optional[str], default: int, minimum: int = 1) -> int:
    if value is None:
        return default
    try:
        parsed = int(str(value).strip())
    except (TypeError, ValueError):
        return default
    return parsed if parsed >= minimum else default


def _canonical_service_name(service_name: Optional[str]) -> str:
    if not service_name:
        return "reference-service"
    normalized = service_name.strip().lower()
    for service in ("registry", "router", "scheduler"):
        if normalized == service or normalized.startswith(service + "-"):
            return service
    return normalized


class _NoopMetricsCollector:
    """Fallback metrics collector used when Prometheus is unavailable."""

    def request_started(self, service_name: str, method_name: str, is_message: bool) -> None:
        return None

    def request_completed(
        self,
        service_name: str,
        method_name: str,
        duration_seconds: float,
        is_message: bool,
    ) -> None:
        return None

    def request_failed(
        self,
        service_name: str,
        method_name: str,
        status: str,
        duration_seconds: float,
        is_message: bool,
    ) -> None:
        return None


try:
    from prometheus_client import Counter, Gauge, Histogram, start_http_server
except Exception:  # pragma: no cover - optional runtime dependency
    Counter = Gauge = Histogram = None  # type: ignore[assignment]
    start_http_server = None


class _PrometheusMetricsCollector:
    """Prometheus-backed metrics collector for reference services."""

    def __init__(self) -> None:
        if Counter is None or Gauge is None or Histogram is None or start_http_server is None:
            raise RuntimeError("prometheus_client is unavailable")

        self._message_count = Counter(
            "sw4rm_reference_messages_total",
            "Total number of reference-service messages/RPCs observed by method",
            ["service", "method", "is_message"],
        )
        self._request_latency = Histogram(
            "sw4rm_reference_request_latency_seconds",
            "Reference-service request processing latency in seconds",
            ["service", "method"],
            buckets=(
                0.001,
                0.005,
                0.01,
                0.025,
                0.05,
                0.1,
                0.25,
                0.5,
                1.0,
                2.5,
                5.0,
                10.0,
            ),
        )
        self._errors = Counter(
            "sw4rm_reference_rpc_errors_total",
            "Reference-service RPC error count by status",
            ["service", "method", "status"],
        )
        self._active = Gauge(
            "sw4rm_reference_active_connections",
            "Active in-flight reference-service requests/streams",
            ["service", "method"],
        )

    @staticmethod
    def _is_message_rpc(method_name: str) -> str:
        return "true" if method_name in {"SendMessage", "StreamIncoming"} else "false"

    def request_started(self, service_name: str, method_name: str, is_message: bool) -> None:
        self._active.labels(service=service_name, method=method_name).inc()
        is_message_label = self._is_message_rpc(method_name) if is_message else "false"
        self._message_count.labels(
            service=service_name,
            method=method_name,
            is_message=is_message_label,
        ).inc()

    def request_completed(
        self,
        service_name: str,
        method_name: str,
        duration_seconds: float,
        is_message: bool,
    ) -> None:
        self._active.labels(service=service_name, method=method_name).dec()
        self._request_latency.labels(service=service_name, method=method_name).observe(
            max(0.0, float(duration_seconds)),
        )

    def request_failed(
        self,
        service_name: str,
        method_name: str,
        status: str,
        duration_seconds: float,
        is_message: bool,
    ) -> None:
        self._active.labels(service=service_name, method=method_name).dec()
        self._errors.labels(
            service=service_name,
            method=method_name,
            status=status,
        ).inc()
        self._request_latency.labels(service=service_name, method=method_name).observe(
            max(0.0, float(duration_seconds)),
        )


_COLLECTOR = None


def _get_collector() -> _NoopMetricsCollector | _PrometheusMetricsCollector:
    global _COLLECTOR
    if _COLLECTOR is not None:
        return _COLLECTOR

    if Counter is None or Gauge is None or Histogram is None or start_http_server is None:
        logger.warning(
            "prometheus_client is unavailable; reference service metrics exporter disabled",
        )
        _COLLECTOR = _NoopMetricsCollector()
        return _COLLECTOR

    _COLLECTOR = _PrometheusMetricsCollector()
    return _COLLECTOR


def _status_from_exception(exc: BaseException) -> str:
    if isinstance(exc, grpc.RpcError):
        code = exc.code()
        return code.name if code is not None else "grpc_error"
    if isinstance(exc, RuntimeError):
        return "runtime_error"
    return exc.__class__.__name__


def _is_message_rpc(method_name: str) -> bool:
    return method_name in {"SendMessage", "StreamIncoming"}


class ReferenceMetricsInterceptor(grpc.ServerInterceptor):
    """gRPC interceptor that emits Prometheus metrics for each RPC."""

    def __init__(self, service_name: str, collector: Optional[object] = None) -> None:
        self._service_name = _canonical_service_name(service_name)
        self._collector = collector or _get_collector()

    def intercept_service(self, continuation, handler_call_details):
        handler = continuation(handler_call_details)
        if handler is None:
            return None

        method_name = handler_call_details.method.split("/")[-1]

        if handler.unary_unary is not None:
            return grpc.unary_unary_rpc_method_handler(
                self._wrap_unary_unary(method_name, handler.unary_unary),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.unary_stream is not None:
            return grpc.unary_stream_rpc_method_handler(
                self._wrap_unary_stream(method_name, handler.unary_stream),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.stream_unary is not None:
            return grpc.stream_unary_rpc_method_handler(
                self._wrap_stream_unary(method_name, handler.stream_unary),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        if handler.stream_stream is not None:
            return grpc.stream_stream_rpc_method_handler(
                self._wrap_stream_stream(method_name, handler.stream_stream),
                request_deserializer=handler.request_deserializer,
                response_serializer=handler.response_serializer,
            )
        return handler

    def _wrap_unary_unary(self, method_name: str, continuation_fn):
        def _handler(request, context):
            start = time.perf_counter()
            is_message = _is_message_rpc(method_name)
            self._collector.request_started(
                self._service_name,
                method_name,
                is_message=is_message,
            )
            failed_status = None
            try:
                return continuation_fn(request, context)
            except BaseException as exc:  # noqa: BLE001
                failed_status = _status_from_exception(exc)
                raise
            finally:
                duration = time.perf_counter() - start
                if failed_status is None:
                    self._collector.request_completed(
                        self._service_name,
                        method_name,
                        duration,
                        is_message=is_message,
                    )
                else:
                    self._collector.request_failed(
                        self._service_name,
                        method_name,
                        failed_status,
                        duration,
                        is_message=is_message,
                    )

        return _handler

    def _wrap_unary_stream(self, method_name: str, continuation_fn):
        def _iter_messages(request, context):
            status = "ok"
            start = time.perf_counter()
            is_message = _is_message_rpc(method_name)
            self._collector.request_started(self._service_name, method_name, is_message=is_message)
            try:
                for item in continuation_fn(request, context):
                    yield item
            except BaseException as exc:  # noqa: BLE001
                status = _status_from_exception(exc)
                raise
            finally:
                duration = time.perf_counter() - start
                if status == "ok":
                    self._collector.request_completed(self._service_name, method_name, duration, is_message=is_message)
                else:
                    self._collector.request_failed(
                        self._service_name,
                        method_name,
                        status,
                        duration,
                        is_message=is_message,
                    )

        return _iter_messages

    def _wrap_stream_unary(self, method_name: str, continuation_fn):
        def _handler(request_iterator, context):
            start = time.perf_counter()
            is_message = _is_message_rpc(method_name)
            self._collector.request_started(self._service_name, method_name, is_message=is_message)
            failed_status = None
            try:
                return continuation_fn(request_iterator, context)
            except BaseException as exc:  # noqa: BLE001
                failed_status = _status_from_exception(exc)
                raise
            finally:
                duration = time.perf_counter() - start
                if failed_status is None:
                    self._collector.request_completed(
                        self._service_name,
                        method_name,
                        duration,
                        is_message=is_message,
                    )
                else:
                    self._collector.request_failed(
                        self._service_name,
                        method_name,
                        failed_status,
                        duration,
                        is_message=is_message,
                    )

        return _handler

    def _wrap_stream_stream(self, method_name: str, continuation_fn):
        def _iter_messages(request_iterator, context):
            status = "ok"
            start = time.perf_counter()
            is_message = _is_message_rpc(method_name)
            self._collector.request_started(self._service_name, method_name, is_message=is_message)
            try:
                for item in continuation_fn(request_iterator, context):
                    yield item
            except BaseException as exc:  # noqa: BLE001
                status = _status_from_exception(exc)
                raise
            finally:
                duration = time.perf_counter() - start
                if status == "ok":
                    self._collector.request_completed(self._service_name, method_name, duration, is_message=is_message)
                else:
                    self._collector.request_failed(
                        self._service_name,
                        method_name,
                        status,
                        duration,
                        is_message=is_message,
                    )

        return _iter_messages


def build_reference_metrics_interceptor(
    service_name: str,
    *,
    metrics_enabled: Optional[bool] = None,
    metrics_port: Optional[int] = None,
    metrics_host: Optional[str] = None,
) -> Optional[ReferenceMetricsInterceptor]:
    """Return a metrics interceptor when Prometheus metrics are enabled."""

    if metrics_enabled is None:
        metrics_enabled = _coerce_bool(
            os.getenv("REFERENCE_METRICS_ENABLED"),
            _DEFAULT_METRICS_ENABLED,
        )
    if not metrics_enabled:
        return None

    if Counter is None or Gauge is None or Histogram is None or start_http_server is None:
        logger.debug("metrics enabled but Prometheus client is unavailable")
        return ReferenceMetricsInterceptor(service_name, collector=_NoopMetricsCollector())

    canonical_service = _canonical_service_name(service_name)
    host = metrics_host or os.getenv("REFERENCE_METRICS_HOST", _DEFAULT_METRICS_HOST)
    default_port = _DEFAULT_SERVICE_PORTS.get(canonical_service, 9100)
    if metrics_port is None:
        metrics_port = _coerce_int(
            os.getenv(f"{canonical_service.upper()}_METRICS_PORT"),
            _coerce_int(os.getenv("REFERENCE_METRICS_PORT"), default=default_port),
            minimum=1,
        )

    _ensure_metrics_server(port=metrics_port, host=host)
    return ReferenceMetricsInterceptor(canonical_service)


def _ensure_metrics_server(*, host: str, port: int) -> None:
    if not host:
        host = _DEFAULT_METRICS_HOST
    if port <= 0:
        return

    with _METRICS_LOCK:
        if port in _STARTED_METRICS_PORTS:
            return
        if start_http_server is None:
            return
        start_http_server(port=port, addr=host)
        _STARTED_METRICS_PORTS.add(port)
