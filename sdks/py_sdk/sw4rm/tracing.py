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

import functools
import uuid
from contextvars import ContextVar
from dataclasses import dataclass, field
from typing import Any, Callable, Optional, TypeVar

# Import for correlation ID integration
try:
    from . import logging as sw4rm_logging
except ImportError:
    sw4rm_logging = None  # type: ignore

# Context variable for current trace context
_current_trace: ContextVar[Optional["TraceContext"]] = ContextVar(
    "current_trace", default=None
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
