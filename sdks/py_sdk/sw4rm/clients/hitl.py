from __future__ import annotations

from typing import Any


class HitlClient:
    """Client for the SW4RM Human-in-the-Loop (HITL) Service.

    Handles escalation of decisions to human operators when agent confidence
    is low, risks are high, or policy requires human approval. The service
    manages invocation requests and captures human decisions.

    Attributes:
        _channel: gRPC channel for service communication
        _stub: Generated gRPC stub for HitlService
    """

    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import hitl_pb2, hitl_pb2_grpc  # type: ignore
            self._pb2 = hitl_pb2
            self._stub = hitl_pb2_grpc.HitlServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def decide(self, invocation: Any) -> Any:
        """Submit a HITL invocation for human decision.

        Args:
            invocation: A ``HitlInvocation`` message, or a dict with
                ``HitlInvocation`` fields (``reason_type`` — a
                ``HitlReasonType`` value, ``context`` — bytes,
                ``proposed_actions`` — repeated string, ``priority`` — int).

        Returns:
            HitlDecision with the human's decision (action,
            decision_payload, rationale).
        """
        self._require()
        if not isinstance(invocation, self._pb2.HitlInvocation):
            invocation = self._pb2.HitlInvocation(**invocation)
        return self._stub.Decide(invocation)

    def _require(self) -> None:
        if not self._stub:
            raise RuntimeError(
                "Protobuf stubs not generated for hitl. Run protoc to generate sw4rm/protos/*_pb2.py"
            )
