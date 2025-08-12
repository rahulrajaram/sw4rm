from __future__ import annotations

from typing import Any


class ReasoningClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import reasoning_pb2, reasoning_pb2_grpc  # type: ignore
            self._pb2 = reasoning_pb2
            self._stub = reasoning_pb2_grpc.ReasoningServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def check_parallelism(self, agent_id: str) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.CheckParallelismRequest(agent_id=agent_id)
        return self._stub.CheckParallelism(req)

    def evaluate_debate(self, prompt: str, intensity: int) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.EvaluateDebateRequest(prompt=prompt, intensity=intensity)
        return self._stub.EvaluateDebate(req)

