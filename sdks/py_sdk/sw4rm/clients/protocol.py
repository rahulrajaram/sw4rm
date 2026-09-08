"""Canonical wire RPCs, distinct from local workflow and handoff helpers."""
from __future__ import annotations

from importlib import import_module
from typing import Any

from sw4rm.clients.protocol_methods import PROTOCOL_METHODS


class ProtocolClient:
    """Call any canonical RPC with generated protobuf request/response objects.

    The caller owns the supplied grpc.Channel and closes it when finished.
    Calls are dispatched once: this layer never retries an uncertain effect.
    """

    def __init__(self, channel: Any) -> None:
        self._channel = channel

    @staticmethod
    def rpc_paths() -> tuple[str, ...]:
        return tuple(PROTOCOL_METHODS)

    def _method(self, path: str, request: Any, *, streaming: bool):
        try:
            module_name, request_type, server_streaming = PROTOCOL_METHODS[path]
        except KeyError as error:
            raise ValueError(f"Unknown canonical SW4RM RPC: {path}") from error
        if server_streaming != streaming:
            raise ValueError(f"{path} requires {'stream' if server_streaming else 'call'}")
        if getattr(getattr(request, "DESCRIPTOR", None), "full_name", None) != request_type:
            raise TypeError(f"{path} requires {request_type}")
        module = import_module(f"sw4rm.protos.{module_name}_pb2_grpc")
        _, service, method = path.split("/")
        stub = getattr(module, service.rsplit(".", 1)[1] + "Stub")(self._channel)
        return getattr(stub, method)

    def call(self, path: str, request: Any, *, timeout: float = 30.0, metadata=None):
        """Execute a unary RPC, preserving grpc errors and full response fields."""
        return self._method(path, request, streaming=False)(request, timeout=timeout, metadata=metadata)

    def stream(self, path: str, request: Any, *, timeout: float = 30.0, metadata=None):
        """Return the generated cancellable iterator for a server-streaming RPC."""
        return self._method(path, request, streaming=True)(request, timeout=timeout, metadata=metadata)
