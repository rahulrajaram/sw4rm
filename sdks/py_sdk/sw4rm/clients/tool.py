from __future__ import annotations

from typing import Any, Iterable


class ToolClient:
    """Client for the SW4RM Tool Service.

    Provides methods for executing tool calls with support for both unary
    and streaming responses. Tools are executed by registered providers
    and may operate within worktree contexts.

    Attributes:
        _channel: gRPC channel for service communication
        _stub: Generated gRPC stub for ToolService
    """

    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import tool_pb2, tool_pb2_grpc  # type: ignore
            self._pb2 = tool_pb2
            self._stub = tool_pb2_grpc.ToolServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def call(self, call: dict) -> Any:
        """Execute a unary tool call.

        Args:
            call: Dictionary with ToolCall fields (call_id, tool_name, provider_id, args, etc.)

        Returns:
            ToolFrame with result
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.ToolCall(**call)
        return self._stub.Call(req)

    def call_stream(self, call: dict) -> Iterable[Any]:
        """Execute a streaming tool call.

        Args:
            call: Dictionary with ToolCall fields (call_id, tool_name, provider_id, args, etc.)

        Returns:
            Iterator of ToolFrame objects
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.ToolCall(**call)
        return self._stub.CallStream(req)

    def cancel(self, call: dict) -> Any:
        """Cancel a tool call (best effort).

        Args:
            call: Dictionary with ToolCall fields (at minimum call_id)

        Returns:
            ToolError with cancellation status
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.ToolCall(**call)
        return self._stub.Cancel(req)

