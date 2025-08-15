from __future__ import annotations

from typing import Any


class ReasoningClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import reasoning_pb2, reasoning_pb2_grpc  # type: ignore
            self._pb2 = reasoning_pb2
            self._stub = reasoning_pb2_grpc.ReasoningProxyStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def check_parallelism(self, scope_a: str, scope_b: str) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.ParallelismCheckRequest(scope_a=scope_a, scope_b=scope_b)
        return self._stub.CheckParallelism(req)

    def evaluate_debate(self, negotiation_id: str, proposal_a: str, proposal_b: str, intensity: str = "low") -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.DebateEvaluateRequest(negotiation_id=negotiation_id, proposal_a=proposal_a, proposal_b=proposal_b, intensity=intensity)
        return self._stub.EvaluateDebate(req)



    def summarize(self, session_id: str, segments: list[dict], max_tokens: int = 256, mode: str = "rolling") -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        pb_segments = [self._pb2.TextSegment(kind=s.get("kind",""), content=s.get("content",""), seq=int(s.get("seq",0)), at=s.get("at","")) for s in segments]
        req = self._pb2.SummarizeRequest(session_id=session_id, segments=pb_segments, max_tokens=max_tokens, mode=mode)
        return self._stub.Summarize(req)
