from __future__ import annotations

from typing import Any


class SchedulerClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import scheduler_pb2, scheduler_pb2_grpc  # type: ignore
            self._pb2 = scheduler_pb2
            self._stub = scheduler_pb2_grpc.SchedulerServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def submit_task(self, agent_id: str, priority: int = 0, notes: str = "") -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.SubmitTaskRequest(agent_id=agent_id, priority=priority, notes=notes)
        return self._stub.SubmitTask(req)

    def request_preemption(self, agent_id: str, reason: str = "") -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.RequestPreemptionRequest(agent_id=agent_id, reason=reason)
        return self._stub.RequestPreemption(req)

    def shutdown_agent(self, agent_id: str, reason: str = "") -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.ShutdownAgentRequest(agent_id=agent_id, reason=reason)
        return self._stub.ShutdownAgent(req)

