#!/usr/bin/env python3
"""Tests for reference-service logging and correlation utilities."""

from __future__ import annotations

import io
import json
import logging
import sys
from pathlib import Path

from sw4rm import logging as sw4rm_logging

HIVE_DIR = Path(__file__).resolve().parents[1] / "reference-services" / "hive"
if str(HIVE_DIR) not in sys.path:
    sys.path.insert(0, str(HIVE_DIR))

from reference_logging import (
    ReferenceLoggingInterceptor,
    configure_reference_service_logging,
    extract_request_correlation_id,
    request_logging_context,
)


class _Context:
    def __init__(self, metadata):
        self._metadata = metadata

    def invocation_metadata(self):
        return self._metadata


def test_extract_request_correlation_id_prefers_payload_then_metadata_then_fallback() -> None:
    envelope = type("Envelope", (), {"correlation_id": "env-corr"})()
    request = type("Request", (), {"msg": envelope, "correlation_id": "request-corr"})()
    context = _Context([("x-correlation-id", "header-corr")])

    assert (
        extract_request_correlation_id(
            method_name="SendMessage",
            request=request,
            context=context,
            fallback="fallback-corr",
        )
        == "env-corr"
    )

    request = type("Request", (), {"msg": type("Envelope", (), {})(), "correlation_id": "request-corr"})()
    assert (
        extract_request_correlation_id(
            method_name="SendMessage",
            request=request,
            context=context,
            fallback="fallback-corr",
        )
        == "header-corr"
    )

    request = type("Request", (), {"msg": type("Envelope", (), {})()})()
    assert (
        extract_request_correlation_id(
            method_name="SendMessage",
            request=request,
            context=_Context(None),
            fallback="fallback-corr",
        )
        == "fallback-corr"
    )


def test_request_logging_context_restores_correlation(monkeypatch) -> None:
    sw4rm_logging.set_correlation_id("previous-corr")
    with request_logging_context(
        request=type("Request", (), {})(),
        context=_Context(None),
        method_name="SendMessage",
        fallback_correlation_id="stream-corr",
    ):
        assert sw4rm_logging.get_correlation_id() == "stream-corr"
    assert sw4rm_logging.get_correlation_id() == "previous-corr"


def test_reference_logging_interceptor_sets_request_correlation(monkeypatch) -> None:
    sw4rm_logging.set_correlation_id("outer-corr")
    seen: list[str | None] = []

    def handler(request, context):
        seen.append(sw4rm_logging.get_correlation_id())
        return "ok"

    interceptor = ReferenceLoggingInterceptor()
    wrapped = interceptor._wrap_unary_unary("SendMessage", handler)
    wrapped(
        type("Request", (), {"msg": type("Envelope", (), {"correlation_id": "rpc-corr"})()})(),
        _Context([("x-request-id", "header-corr")]),
    )

    assert seen == ["rpc-corr"]
    assert sw4rm_logging.get_correlation_id() == "outer-corr"


def test_configure_reference_service_logging_emits_json_when_json_format(monkeypatch) -> None:
    root = logging.getLogger()
    original_handlers = list(root.handlers)
    original_level = root.level
    original_propagate = root.propagate

    stream = io.StringIO()
    try:
        configure_reference_service_logging(
            service_name="test-registry",
            level="INFO",
            stream=stream,
            use_json=True,
        )
        logging.info("hello")
        line = stream.getvalue().strip().splitlines()[-1]
        payload = json.loads(line)
        assert payload["agent_id"] == "test-registry"
        assert payload["level"] == "INFO"
    finally:
        root.setLevel(original_level)
        root.handlers.clear()
        root.handlers.extend(original_handlers)
        root.propagate = original_propagate
        sw4rm_logging.set_correlation_id(None)


def test_configure_reference_service_logging_respects_plain_mode(monkeypatch) -> None:
    root = logging.getLogger()
    original_handlers = list(root.handlers)
    original_level = root.level
    original_propagate = root.propagate
    stream = io.StringIO()
    monkeypatch.setenv("REFERENCE_LOG_FORMAT", "plain")

    try:
        configure_reference_service_logging(
            service_name="test-registry",
            level="INFO",
            stream=stream,
        )
        logging.info("hello")
        line = stream.getvalue().strip().splitlines()[-1]
        assert line and line[0] != "{"
    finally:
        root.setLevel(original_level)
        root.handlers.clear()
        root.handlers.extend(original_handlers)
        root.propagate = original_propagate
        sw4rm_logging.set_correlation_id(None)
