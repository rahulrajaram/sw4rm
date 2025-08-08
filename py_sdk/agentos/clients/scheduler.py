from __future__ import annotations

from typing import Any


class SchedulerClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from agentos.protos import scheduler_pb2, scheduler_pb2_grpc  # type: ignore
            self._pb2 = scheduler_pb2
            self._stub = scheduler_pb2_grpc.SchedulerServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def submit_task(self, agent_id: str, task_id: str, priority: int, params: bytes, content_type: str, scope: str = "") -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`." )
        req = self._pb2.SubmitTaskRequest(
            agent_id=agent_id,
            task_id=task_id,
            priority=priority,
            params=params,
            content_type=content_type,
            scope=scope,
        )
        return self._stub.SubmitTask(req)

    def request_preemption(self, agent_id: str, task_id: str, reason: str = "") -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`." )
        req = self._pb2.PreemptRequest(agent_id=agent_id, task_id=task_id, reason=reason)
        return self._stub.RequestPreemption(req)

