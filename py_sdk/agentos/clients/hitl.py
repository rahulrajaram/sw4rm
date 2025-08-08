from __future__ import annotations

from typing import Any


class HitlClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from agentos.protos import hitl_pb2, hitl_pb2_grpc  # type: ignore
            self._pb2 = hitl_pb2
            self._stub = hitl_pb2_grpc.HitlServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def decide(self, reason_type: int, context: bytes = b"", proposed_actions: list[str] | None = None, priority: int = 0) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`." )
        req = self._pb2.HitlInvocation(
            reason_type=reason_type,
            context=context,
            proposed_actions=proposed_actions or [],
            priority=priority,
        )
        return self._stub.Decide(req)

