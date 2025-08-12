from __future__ import annotations

from typing import Any, Iterable


class ToolClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import tool_pb2, tool_pb2_grpc  # type: ignore
            self._pb2 = tool_pb2
            self._stub = tool_pb2_grpc.ToolServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def execute(self, call: dict) -> Iterable[Any]:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.ExecuteRequest(call=self._pb2.ToolCall(**call))
        return self._stub.Execute(req)

