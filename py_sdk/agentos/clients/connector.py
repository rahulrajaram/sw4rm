from __future__ import annotations

from typing import Any, Dict, List, Optional


class ConnectorClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from agentos.protos import connector_pb2, connector_pb2_grpc  # type: ignore
            self._pb2 = connector_pb2
            self._stub = connector_pb2_grpc.ConnectorServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def register_provider(self, provider_id: str, tools: List[Dict[str, Any]]) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        tool_msgs = [self._pb2.ToolDescriptor(**t) for t in tools]
        req = self._pb2.ProviderRegisterRequest(provider_id=provider_id, tools=tool_msgs)
        return self._stub.RegisterProvider(req)

    def describe_tools(self, provider_id: str) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.DescribeToolsRequest(provider_id=provider_id)
        return self._stub.DescribeTools(req)

