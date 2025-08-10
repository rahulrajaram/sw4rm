from __future__ import annotations

from typing import Any, Iterable, Tuple


def _grpc_required():
    raise RuntimeError("grpc is required for interceptors. Install grpcio.")


try:
    import grpc  # type: ignore
except Exception:  # pragma: no cover - optional import
    grpc = None  # type: ignore


class CorrelationIdClientInterceptor:  # type: ignore[misc]
    """Adds correlation-id and user-agent metadata to outgoing calls."""

    def __init__(self, *, correlation_id: str | None = None, user_agent: str | None = None) -> None:
        if grpc is None:
            _grpc_required()
        self._correlation_id = correlation_id
        self._user_agent = user_agent or "sw4rm-protocol-sdk/0.1"

    def _append_metadata(self, client_call_details: Any) -> Any:
        metadata = [] if client_call_details.metadata is None else list(client_call_details.metadata)
        if self._correlation_id:
            metadata.append(("x-correlation-id", self._correlation_id))
        if self._user_agent:
            metadata.append(("user-agent", self._user_agent))
        return _ClientCallDetails(
            method=client_call_details.method,
            timeout=client_call_details.timeout,
            metadata=tuple(metadata),
            credentials=client_call_details.credentials,
            wait_for_ready=getattr(client_call_details, "wait_for_ready", None),
            compression=getattr(client_call_details, "compression", None),
        )

    def intercept_unary_unary(self, continuation, client_call_details, request):  # type: ignore
        return continuation(self._append_metadata(client_call_details), request)

    def intercept_unary_stream(self, continuation, client_call_details, request):  # type: ignore
        return continuation(self._append_metadata(client_call_details), request)

    def intercept_stream_unary(self, continuation, client_call_details, request_iterator):  # type: ignore
        return continuation(self._append_metadata(client_call_details), request_iterator)

    def intercept_stream_stream(self, continuation, client_call_details, request_iterator):  # type: ignore
        return continuation(self._append_metadata(client_call_details), request_iterator)


class _ClientCallDetails(grpc.ClientCallDetails):  # type: ignore
    def __init__(self, method, timeout, metadata, credentials, wait_for_ready, compression):
        self.method = method
        self.timeout = timeout
        self.metadata = metadata
        self.credentials = credentials
        self.wait_for_ready = wait_for_ready
        self.compression = compression


def channel_with_interceptors(target: str, *interceptors: Any, secure: bool = False) -> Any:
    """Create a channel with the provided client interceptors attached.

    Example:
        ch = channel_with_interceptors(
            "localhost:50051",
            CorrelationIdClientInterceptor(correlation_id="abc-123"),
        )
    """
    if grpc is None:
        _grpc_required()
    base = grpc.secure_channel(target, grpc.ssl_channel_credentials()) if secure else grpc.insecure_channel(target)
    if not interceptors:
        return base
    return grpc.intercept_channel(base, *interceptors)
