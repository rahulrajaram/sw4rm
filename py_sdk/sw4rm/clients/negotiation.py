from __future__ import annotations

from typing import Any, Iterable


class NegotiationClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import negotiation_pb2, negotiation_pb2_grpc  # type: ignore
            self._pb2 = negotiation_pb2
            self._stub = negotiation_pb2_grpc.NegotiationServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def open(
        self,
        negotiation_id: str,
        correlation_id: str,
        topic: str,
        participants: list[str],
        intensity: int = 0,
        debate_timeout_seconds: int | None = None,
    ) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        duration = None
        if debate_timeout_seconds is not None:
            duration = self._pb2.google_dot_protobuf_dot_duration__pb2.Duration(
                seconds=debate_timeout_seconds
            )
        req = self._pb2.NegotiationOpen(
            negotiation_id=negotiation_id,
            correlation_id=correlation_id,
            topic=topic,
            participants=participants,
            intensity=intensity,
            debate_timeout=duration,
        )
        return self._stub.Open(req)

    def propose(
        self,
        negotiation_id: str,
        from_agent: str,
        content_type: str,
        payload: bytes,
    ) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.Proposal(
            negotiation_id=negotiation_id,
            from_agent=from_agent,
            content_type=content_type,
            payload=payload,
        )
        return self._stub.Propose(req)

    def counter(
        self,
        negotiation_id: str,
        from_agent: str,
        content_type: str,
        payload: bytes,
    ) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.CounterProposal(
            negotiation_id=negotiation_id,
            from_agent=from_agent,
            content_type=content_type,
            payload=payload,
        )
        return self._stub.Counter(req)

    def evaluate(
        self,
        negotiation_id: str,
        from_agent: str,
        confidence_score: float | None = None,
        notes: str = "",
    ) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.Evaluation(
            negotiation_id=negotiation_id,
            from_agent=from_agent,
            confidence_score=confidence_score or 0.0,
            notes=notes,
        )
        return self._stub.Evaluate(req)

    def decide(
        self,
        negotiation_id: str,
        decided_by: str,
        content_type: str,
        result: bytes,
    ) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.Decision(
            negotiation_id=negotiation_id,
            decided_by=decided_by,
            content_type=content_type,
            result=result,
        )
        return self._stub.Decide(req)

    def abort(self, negotiation_id: str, reason: str = "") -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        # Updated to match proto rename: AbortRequest
        req = self._pb2.AbortRequest(negotiation_id=negotiation_id, reason=reason)
        return self._stub.Abort(req)

