#!/usr/bin/env python3
"""Structured logging and request correlation utilities for reference services."""

from __future__ import annotations

import logging
import os
import sys
from contextlib import contextmanager
from typing import Any, Iterator, Optional, Sequence

from sw4rm import logging as sw4rm_logging

try:
    import grpc  # type: ignore
except Exception:  # pragma: no cover - optional import in tests
    grpc = None  # type: ignore


_LOG_ENV_TRUE = {"1", "true", "yes", "on", "y", "enable", "enabled"}
_LOG_ENV_FALSE = {"0", "false", "no", "off", "n", "disable", "disabled", "plain", "text"}
_CORRELATION_HEADER_KEYS = (
    "x-correlation-id",
    "correlation-id",
    "x-request-id",
    "request-id",
)


def _as_bool(raw: Optional[str], default: bool = False) -> bool:
    if raw is None:
        return default
    normalized = str(raw).strip().lower()
    if normalized in _LOG_ENV_TRUE:
        return True
    if normalized in _LOG_ENV_FALSE:
        return False
    return default


def _resolve_log_json_mode(raw: Optional[str], default: bool = True) -> bool:
    if raw is None:
        return default
    normalized = str(raw).strip().lower()
    if normalized in {"json", "jsonl", "structured"}:
        return True
    if normalized in {"plain", "plain/text", "text", "human", "txt"}:
        return False
    return _as_bool(normalized, default=default)


def _metadata_to_dict(metadata: Sequence[Any]) -> dict[str, str]:
    normalized: dict[str, str] = {}
    for item in metadata or []:
        key = str(getattr(item, "key", item[0] if isinstance(item, tuple) else "")).lower()
        value = str(getattr(item, "value", item[1] if isinstance(item, tuple) else ""))
        normalized[key] = value
    return normalized


def _extract_correlation_id_from_request(request: Any) -> Optional[str]:
    if request is None:
        return None

    envelope = getattr(request, "msg", None)
    envelope_corr = getattr(envelope, "correlation_id", None)
    if isinstance(envelope_corr, str) and envelope_corr.strip():
        return envelope_corr

    return None


def _extract_correlation_id_from_metadata(context: Any) -> Optional[str]:
    getter = getattr(context, "invocation_metadata", None)
    if getter is None:
        return None
    metadata = getter()
    normalized = _metadata_to_dict(metadata)
    for key in _CORRELATION_HEADER_KEYS:
        value = normalized.get(key)
        if isinstance(value, str) and value.strip():
            return value
    return None


def extract_request_correlation_id(
    method_name: str,
    request: Any,
    context: Any,
    fallback: Optional[str] = None,
) -> Optional[str]:
    """Extract correlation id for a request.

    Preference is envelope correlation id, then metadata headers, then request
    correlation id, then optional explicit fallback.
    """
    _ = method_name
    corr = _extract_correlation_id_from_request(request)
    if corr:
        return corr

    corr = _extract_correlation_id_from_metadata(context)
    if corr:
        return corr

    direct_corr = getattr(request, "correlation_id", None)
    if isinstance(direct_corr, str) and direct_corr.strip():
        return direct_corr

    if isinstance(fallback, str) and fallback.strip():
        return fallback

    return None


@contextmanager
def request_logging_context(
    *,
    request: Any = None,
    context: Any = None,
    method_name: str = "",
    fallback_correlation_id: Optional[str] = None,
) -> Iterator[None]:
    """Set correlation ID for the duration of the context."""
    correlation_id = extract_request_correlation_id(
        method_name=method_name,
        request=request,
        context=context,
        fallback=fallback_correlation_id,
    )

    previous_correlation = sw4rm_logging.get_correlation_id()
    try:
        if correlation_id:
            sw4rm_logging.set_correlation_id(correlation_id)
        yield
    finally:
        sw4rm_logging.set_correlation_id(previous_correlation)


def configure_reference_service_logging(
    *,
    service_name: str,
    level: int | str = "INFO",
    use_json: Optional[bool] = None,
    stream: Any = None,
) -> None:
    """Configure root logging for reference services.

    Reference services keep default JSON log output for aggregation. Plain text can
    be enabled with REFERENCE_LOG_FORMAT=plain.
    """
    if use_json is None:
        use_json = _resolve_log_json_mode(
            os.getenv("REFERENCE_LOG_FORMAT", "json"),
            default=True,
        )

    if isinstance(level, str):
        level_value = getattr(logging, level.upper(), logging.INFO)
    else:
        level_value = level

    if isinstance(level_value, int):
        resolved_level = level_value
    else:  # pragma: no cover - fallback guard
        resolved_level = logging.INFO

    sw4rm_logging.configure_logging(level=resolved_level, use_json=use_json)

    # Replace root handlers for consistent JSON output in all reference services.
    handler_stream = stream if stream is not None else sys.stdout
    handler = logging.StreamHandler(handler_stream)
    handler.setFormatter(sw4rm_logging.StructuredFormatter(agent_id=service_name, use_json=bool(use_json)))

    root = logging.getLogger()
    root.handlers.clear()
    root.setLevel(resolved_level)
    root.addHandler(handler)
    root.propagate = False


if grpc is not None:

    class ReferenceLoggingInterceptor(grpc.ServerInterceptor):  # type: ignore[misc]
        """Sets correlation-id context for request logs."""

        def intercept_service(self, continuation, handler_call_details):
            handler = continuation(handler_call_details)
            if handler is None:
                return None

            method_name = str(getattr(handler_call_details, "method", "")).rsplit("/", 1)[-1]

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
            def handler(request, context):
                with request_logging_context(
                    request=request,
                    context=context,
                    method_name=method_name,
                ):
                    return continuation_fn(request, context)

            return handler

        def _wrap_unary_stream(self, method_name: str, continuation_fn):
            def handler(request, context):
                with request_logging_context(
                    request=request,
                    context=context,
                    method_name=method_name,
                ):
                    return continuation_fn(request, context)

            return handler

        def _wrap_stream_unary(self, method_name: str, continuation_fn):
            def handler(request_iterator, context):
                with request_logging_context(context=context, method_name=method_name):
                    return continuation_fn(request_iterator, context)

            return handler

        def _wrap_stream_stream(self, method_name: str, continuation_fn):
            def handler(request_iterator, context):
                with request_logging_context(context=context, method_name=method_name):
                    return continuation_fn(request_iterator, context)

            return handler
else:

    class ReferenceLoggingInterceptor:  # type: ignore[misc]
        """Fallback interceptor used when grpc is unavailable."""

        def __init__(self):
            pass

        def intercept_service(self, continuation, handler_call_details):
            return continuation(handler_call_details)

        def _wrap_unary_unary(self, method_name: str, continuation_fn):
            def handler(request, context):
                return continuation_fn(request, context)

            return handler

        def _wrap_unary_stream(self, method_name: str, continuation_fn):
            def handler(request, context):
                return continuation_fn(request, context)

            return handler

        def _wrap_stream_unary(self, method_name: str, continuation_fn):
            def handler(request_iterator, context):
                return continuation_fn(request_iterator, context)

            return handler

        def _wrap_stream_stream(self, method_name: str, continuation_fn):
            def handler(request_iterator, context):
                return continuation_fn(request_iterator, context)

            return handler


__all__ = [
    "configure_reference_service_logging",
    "extract_request_correlation_id",
    "request_logging_context",
    "ReferenceLoggingInterceptor",
]
