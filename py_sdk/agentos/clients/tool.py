from __future__ import annotations

from typing import Any, Dict, Iterable, Optional


class ToolClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from agentos.protos import tool_pb2, tool_pb2_grpc  # type: ignore
            self._pb2 = tool_pb2
            self._stub = tool_pb2_grpc.ToolServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def _build_policy(self, policy: Optional[Dict[str, Any]]):
        if not policy:
            return None
        # The pb2 message will ignore unknown keys; callers should match field names.
        return self._pb2.ExecutionPolicy(**policy)

    def call(
        self,
        call_id: str,
        tool_name: str,
        provider_id: str,
        content_type: str,
        args: bytes,
        policy: Optional[Dict[str, Any]] = None,
        stream: bool = False,
    ) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.ToolCall(
            call_id=call_id,
            tool_name=tool_name,
            provider_id=provider_id,
            content_type=content_type,
            args=args,
            policy=self._build_policy(policy),
            stream=stream,
        )
        return self._stub.Call(req)

    def call_stream(
        self,
        call_id: str,
        tool_name: str,
        provider_id: str,
        content_type: str,
        args: bytes,
        policy: Optional[Dict[str, Any]] = None,
    ) -> Iterable[Any]:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.ToolCall(
            call_id=call_id,
            tool_name=tool_name,
            provider_id=provider_id,
            content_type=content_type,
            args=args,
            policy=self._build_policy(policy),
            stream=True,
        )
        return self._stub.CallStream(req)

    def cancel(self, call_id: str, tool_name: str = "", provider_id: str = "") -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.ToolCall(
            call_id=call_id,
            tool_name=tool_name,
            provider_id=provider_id,
        )
        return self._stub.Cancel(req)

