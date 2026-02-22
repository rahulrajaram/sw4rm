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

"""Distributed tracing and correlation ID propagation for SW4RM.

This module provides distributed tracing capabilities for SW4RM agents, including:
- Trace context with trace_id, span_id, parent_span_id, and correlation_id
- Automatic span creation and propagation
- Context-aware tracing using contextvars
- Decorator for automatic span creation
- Integration with structured logging

Traces follow a hierarchical structure where each operation creates a span
with a unique span_id that chains back to its parent via parent_span_id.
The correlation_id is propagated across the entire trace for log correlation.
"""

from __future__ import annotations

import json
import functools
import uuid
from contextvars import ContextVar
from dataclasses import dataclass, field
from typing import Any, Callable, Mapping, Optional, TypeVar

try:
    from opentelemetry.context import get_current as _otel_get_context
    from opentelemetry.propagate import extract as _otel_extract, inject as _otel_inject
    from opentelemetry.trace import (
        NonRecordingSpan,
        SpanContext,
        SpanKind,
        TraceFlags,
        TraceState,
        get_current_span,
        get_tracer,
        set_span_in_context,
    )
    from opentelemetry.trace.span import INVALID_SPAN
    from opentelemetry.util.types import AttributeValue

    _HAS_OTEL = True
except Exception:  # pragma: no cover - optional OpenTelemetry dependency
    _HAS_OTEL = False

# Import for correlation ID integration
try:
    from . import logging as sw4rm_logging
except ImportError:
    sw4rm_logging = None  # type: ignore

# Context variable for current trace context
_current_trace: ContextVar[Optional["TraceContext"]] = ContextVar(
    "current_trace", default=None
)

TRACE_PARENT_HEADER = "traceparent"
TRACE_STATE_HEADER = "tracestate"
SW4RM_TRACE_ID_HEADER = "x-sw4rm-trace-id"
SW4RM_SPAN_ID_HEADER = "x-sw4rm-span-id"
SW4RM_PARENT_SPAN_ID_HEADER = "x-sw4rm-parent-span-id"
SW4RM_CORRELATION_ID_HEADER = "x-sw4rm-correlation-id"
TRACE_ENVELOPE_KEY = "_trace_context"


def _normalize_metadata(metadata: Any) -> dict[str, str]:
    normalized: dict[str, str] = {}
    if metadata is None:
        return normalized
    for item in metadata:
        key = str(getattr(item, "key", item[0] if isinstance(item, tuple) else "")).lower()
        value = str(getattr(item, "value", item[1] if isinstance(item, tuple) else ""))
        normalized[key] = value
    return normalized


def _trace_id_to_hex(value: int) -> str:
    if value <= 0:
        return uuid.uuid4().hex
    return f"{value:032x}"


def _span_id_to_hex(value: int) -> str:
    if value <= 0:
        return uuid.uuid4().hex[:16]
    return f"{value:016x}"


def _build_opentelemetry_context(trace: "TraceContext") -> dict[str, str]:
    if not _HAS_OTEL:
        return {}
    span_context = SpanContext(
        trace_id=int(trace.trace_id, 16),
        span_id=int(trace.span_id, 16),
        is_remote=False,
        trace_flags=TraceFlags(TraceFlags.SAMPLED),
        trace_state=TraceState(),
    )
    carrier: dict[str, str] = {}
    _otel_inject(carrier, context=set_span_in_context(NonRecordingSpan(span_context)))
    return carrier


def _serialize_custom_trace_context(trace: "TraceContext") -> dict[str, str]:
    headers: dict[str, str] = {
        SW4RM_TRACE_ID_HEADER: trace.trace_id,
        SW4RM_SPAN_ID_HEADER: trace.span_id,
        SW4RM_CORRELATION_ID_HEADER: trace.correlation_id or trace.trace_id,
    }
    if trace.parent_span_id:
        headers[SW4RM_PARENT_SPAN_ID_HEADER] = trace.parent_span_id
    return headers


def trace_context_to_metadata(trace: Optional["TraceContext"]) -> dict[str, str]:
    """Serialize trace context into metadata headers suitable for gRPC propagation."""
    if trace is None:
        return {}

    headers: dict[str, str] = {}
    try:
        if _HAS_OTEL:
            headers.update(_build_opentelemetry_context(trace))
    except Exception:
        headers = {}

    # Always include SW4RM-specific headers as a portable fallback.
    fallback = _serialize_custom_trace_context(trace)
    for key, value in fallback.items():
        headers[key] = value

    # Use W3C parent/child semantics even when OTEL is unavailable.
    headers[TRACE_PARENT_HEADER] = f"00-{trace.trace_id}-{trace.span_id}-01"
    return headers


def trace_context_to_envelope_metadata(trace: Optional["TraceContext"]) -> dict[str, Any]:
    """Serialize trace context into a sidecar envelope payload field."""
    if trace is None:
        return {}

    metadata: dict[str, Any] = {
        "trace_id": trace.trace_id,
        "span_id": trace.span_id,
        "correlation_id": trace.correlation_id,
    }
    if trace.parent_span_id:
        metadata["parent_span_id"] = trace.parent_span_id
    if trace.metadata:
        metadata["metadata"] = dict(trace.metadata)
    return metadata


def add_trace_context_to_envelope(
    envelope: Mapping[str, Any],
    trace: Optional["TraceContext"],
) -> dict[str, Any]:
    """Return a copy of *envelope* with trace metadata inserted."""
    payload = dict(envelope)
    if trace is not None:
        payload[TRACE_ENVELOPE_KEY] = trace_context_to_envelope_metadata(trace)
    return payload


def strip_trace_context_from_envelope(envelope: Mapping[str, Any]) -> tuple[dict[str, Any], Optional["TraceContext"]]:
    """Return envelope payload without trace metadata and parsed trace context."""
    payload = dict(envelope)
    trace = trace_context_from_envelope_metadata(payload.pop(TRACE_ENVELOPE_KEY, None))
    return payload, trace


def trace_context_from_metadata(metadata: Any) -> Optional["TraceContext"]:
    """Parse trace context from normalized metadata mapping.

    Supported forms:

    1. W3C / OpenTelemetry headers (preferred): ``traceparent`` / ``tracestate``
    2. SW4RM fallback headers:
       ``x-sw4rm-trace-id`` / ``x-sw4rm-span-id`` / optional parent + correlation
    """
    if metadata is None:
        return None

    normalized = _normalize_metadata(metadata)
    if not normalized:
        return None

    otel_trace = _trace_context_from_opentelemetry_metadata(normalized)
    if otel_trace is not None:
        return otel_trace

    trace_id = normalized.get(SW4RM_TRACE_ID_HEADER)
    span_id = normalized.get(SW4RM_SPAN_ID_HEADER)
    if not trace_id or not span_id:
        return None

    parent_span_id = normalized.get(SW4RM_PARENT_SPAN_ID_HEADER)
    correlation_id = normalized.get(SW4RM_CORRELATION_ID_HEADER)
    return TraceContext(
        trace_id=trace_id,
        span_id=span_id,
        parent_span_id=parent_span_id if parent_span_id else None,
        correlation_id=correlation_id,
    )


def trace_context_from_envelope_metadata(envelope: Any) -> Optional["TraceContext"]:
    """Extract trace context from SW4RM envelope metadata payload."""
    if envelope is None:
        return None

    payload = None
    if isinstance(envelope, Mapping):
        payload = envelope.get(TRACE_ENVELOPE_KEY)
    elif hasattr(envelope, "get") and callable(envelope.get):
        try:
            payload = envelope.get(TRACE_ENVELOPE_KEY)  # type: ignore[assignment]
        except Exception:
            payload = None
    elif hasattr(envelope, TRACE_ENVELOPE_KEY):
        payload = getattr(envelope, TRACE_ENVELOPE_KEY)

    if payload is None:
        return None

    if isinstance(payload, TraceContext):
        return payload

    if isinstance(payload, str):
        try:
            parsed = json.loads(payload)
        except Exception:
            return None
        payload = parsed

    if not isinstance(payload, Mapping):
        return None

    try:
        return TraceContext.from_dict(dict(payload))
    except Exception:
        return None


def _trace_context_from_opentelemetry_metadata(metadata: dict[str, str]) -> Optional["TraceContext"]:
    if not _HAS_OTEL:
        return None
    context = _otel_extract(metadata)
    span = get_current_span(context)
    if span is None or span == INVALID_SPAN:
        return None
    span_context = span.get_span_context()
    if not span_context.is_valid:
        return None
    return TraceContext(
        trace_id=_trace_id_to_hex(int(span_context.trace_id)),
        span_id=_span_id_to_hex(int(span_context.span_id)),
        parent_span_id=None,
        correlation_id=metadata.get("x-correlation-id") or metadata.get("correlation-id")
        or metadata.get("x-request-id")
        or None,
        metadata={},
    )


@dataclass
class TraceContext:
    """Context for distributed tracing.

    A trace context represents a single span in a distributed trace. Each
    span has a unique span_id and may have a parent_span_id linking it to
    its parent span. The trace_id is shared across all spans in a trace,
    and the correlation_id is used for log correlation.

    Attributes:
        trace_id: Unique identifier for the entire trace (shared by all spans)
        span_id: Unique identifier for this specific span
        parent_span_id: Identifier of the parent span, or None for root spans
        correlation_id: Correlation ID for log aggregation (typically same as trace_id)
        metadata: Additional metadata for this span (e.g., agent_id, operation)
    """

    trace_id: str
    span_id: str
    parent_span_id: Optional[str] = None
    correlation_id: Optional[str] = None
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        """Initialize correlation_id to trace_id if not provided."""
        if self.correlation_id is None:
            self.correlation_id = self.trace_id

    def to_dict(self) -> dict[str, Any]:
        """Convert trace context to dictionary for serialization.

        Returns:
            Dictionary representation of the trace context
        """
        return {
            "trace_id": self.trace_id,
            "span_id": self.span_id,
            "parent_span_id": self.parent_span_id,
            "correlation_id": self.correlation_id,
            "metadata": self.metadata,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "TraceContext":
        """Create a TraceContext from a dictionary.

        Args:
            data: Dictionary containing trace context fields

        Returns:
            TraceContext instance
        """
        return cls(
            trace_id=data["trace_id"],
            span_id=data["span_id"],
            parent_span_id=data.get("parent_span_id"),
            correlation_id=data.get("correlation_id"),
            metadata=data.get("metadata", {}),
        )


def _generate_id() -> str:
    """Generate a unique ID for trace or span.

    Returns:
        UUID string (without hyphens for compactness)
    """
    return uuid.uuid4().hex


def create_trace(metadata: Optional[dict[str, Any]] = None) -> TraceContext:
    """Create a new root trace context.

    This creates a new trace with a unique trace_id and span_id.
    Use this to start a new distributed trace.

    Args:
        metadata: Optional metadata to attach to the trace (e.g., agent_id, operation)

    Returns:
        New TraceContext for the root span

    Example:
        trace = create_trace(metadata={"agent_id": "agent-42", "operation": "process"})
        with_trace_context(trace):
            # All operations in this context will be part of this trace
            logger.info("Processing started")
    """
    trace_id = _generate_id()
    span_id = _generate_id()

    return TraceContext(
        trace_id=trace_id,
        span_id=span_id,
        parent_span_id=None,
        correlation_id=trace_id,
        metadata=metadata or {},
    )


def create_child_span(
    parent: TraceContext,
    metadata: Optional[dict[str, Any]] = None,
) -> TraceContext:
    """Create a child span from a parent trace context.

    This creates a new span that is a child of the provided parent span.
    The child inherits the trace_id and correlation_id from the parent.

    Args:
        parent: Parent trace context
        metadata: Optional metadata to attach to the child span

    Returns:
        New TraceContext for the child span

    Example:
        parent_trace = get_current_trace()
        if parent_trace:
            child_trace = create_child_span(
                parent_trace,
                metadata={"operation": "sub_task"}
            )
            with_trace_context(child_trace):
                # This operation is traced as a child span
                perform_sub_task()
    """
    span_id = _generate_id()

    # Merge parent metadata with new metadata
    merged_metadata = {**parent.metadata}
    if metadata:
        merged_metadata.update(metadata)

    return TraceContext(
        trace_id=parent.trace_id,
        span_id=span_id,
        parent_span_id=parent.span_id,
        correlation_id=parent.correlation_id,
        metadata=merged_metadata,
    )


def get_current_trace() -> Optional[TraceContext]:
    """Get the current trace context from the async context.

    Returns:
        Current TraceContext, or None if no trace is active
    """
    return _current_trace.get()


def set_current_trace(trace: Optional[TraceContext]) -> None:
    """Set the current trace context.

    This updates the trace context for the current async context and
    automatically propagates the correlation_id to the logging module.

    Args:
        trace: TraceContext to set, or None to clear
    """
    _current_trace.set(trace)

    # Propagate correlation_id to logging module
    if sw4rm_logging is not None:
        correlation_id = trace.correlation_id if trace else None
        sw4rm_logging.set_correlation_id(correlation_id)


class with_trace_context:
    """Context manager for trace context propagation.

    Sets the trace context for the duration of the context and automatically
    restores the previous context on exit.

    Example:
        trace = create_trace(metadata={"agent_id": "agent-42"})
        with with_trace_context(trace):
            logger.info("This log will have the correlation_id")
            # ... perform traced operations ...
    """

    def __init__(self, trace: Optional[TraceContext]) -> None:
        """Initialize the context manager.

        Args:
            trace: TraceContext to set
        """
        self.trace = trace
        self.previous_trace: Optional[TraceContext] = None

    def __enter__(self) -> TraceContext:
        """Enter the context and set the trace.

        Returns:
            The trace context
        """
        self.previous_trace = get_current_trace()
        set_current_trace(self.trace)
        return self.trace  # type: ignore

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        """Exit the context and restore the previous trace.

        Args:
            exc_type: Exception type if an exception occurred
            exc_val: Exception value if an exception occurred
            exc_tb: Exception traceback if an exception occurred
        """
        set_current_trace(self.previous_trace)


# Type variable for generic function return types
F = TypeVar("F", bound=Callable[..., Any])


def traced(
    operation: Optional[str] = None,
    metadata: Optional[dict[str, Any]] = None,
) -> Callable[[F], F]:
    """Decorator for automatic span creation.

    Wraps a function or method to automatically create a child span when called.
    If no parent trace exists, creates a new root trace. The span is active
    for the duration of the function call.

    Args:
        operation: Name of the operation (defaults to function name)
        metadata: Additional metadata to attach to the span

    Returns:
        Decorated function with automatic tracing

    Example:
        @traced(operation="process_message", metadata={"component": "router"})
        def process_message(msg):
            # This function is automatically traced
            logger.info("Processing message")  # Log includes correlation_id
            return msg

        @traced()  # Uses function name as operation
        async def handle_request(request):
            # Works with async functions too
            await process_async_operation()
    """

    def decorator(func: F) -> F:
        # Determine operation name
        op_name = operation or func.__name__

        @functools.wraps(func)
        def sync_wrapper(*args: Any, **kwargs: Any) -> Any:
            # Get current trace context
            current = get_current_trace()

            # Create new trace or child span
            span_metadata = {"operation": op_name}
            if metadata:
                span_metadata.update(metadata)

            if current is None:
                # No parent trace, create new root trace
                trace = create_trace(metadata=span_metadata)
            else:
                # Create child span
                trace = create_child_span(current, metadata=span_metadata)

            # Execute function with trace context
            with with_trace_context(trace):
                return func(*args, **kwargs)

        @functools.wraps(func)
        async def async_wrapper(*args: Any, **kwargs: Any) -> Any:
            # Get current trace context
            current = get_current_trace()

            # Create new trace or child span
            span_metadata = {"operation": op_name}
            if metadata:
                span_metadata.update(metadata)

            if current is None:
                # No parent trace, create new root trace
                trace = create_trace(metadata=span_metadata)
            else:
                # Create child span
                trace = create_child_span(current, metadata=span_metadata)

            # Execute async function with trace context
            with with_trace_context(trace):
                return await func(*args, **kwargs)

        # Return appropriate wrapper based on function type
        import inspect
        if inspect.iscoroutinefunction(func):
            return async_wrapper  # type: ignore
        else:
            return sync_wrapper  # type: ignore

    return decorator
