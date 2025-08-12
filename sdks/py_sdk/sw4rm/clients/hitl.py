from __future__ import annotations

from typing import Any


class HitlClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import hitl_pb2, hitl_pb2_grpc  # type: ignore
            self._pb2 = hitl_pb2
            self._stub = hitl_pb2_grpc.HitlServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def decide(self, invocation: dict) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.DecideRequest(invocation=self._pb2.HitlInvocation(**invocation))
        return self._stub.Decide(req)

