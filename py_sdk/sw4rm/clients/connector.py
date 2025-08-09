from __future__ import annotations

from typing import Any


class ConnectorClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import connector_pb2, connector_pb2_grpc  # type: ignore
            self._pb2 = connector_pb2
            self._stub = connector_pb2_grpc.ConnectorServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def register_provider(self, descriptor: dict) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.RegisterProviderRequest(descriptor=self._pb2.ToolDescriptor(**descriptor))
        return self._stub.RegisterProvider(req)

    def describe_provider(self, provider_id: str) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.DescribeProviderRequest(provider_id=provider_id)
        return self._stub.DescribeProvider(req)

