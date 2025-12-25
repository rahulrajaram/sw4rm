from __future__ import annotations

from typing import Any, Optional
from datetime import timedelta


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

    def submit_task(
        self,
        agent_id: str,
        task_id: str,
        priority: int = 0,
        scope: str = "",
        params: bytes = b"",
        content_type: str = "application/json"
    ) -> Any:
        """Submit a task to the scheduler.

        Args:
            agent_id: Target agent identifier
            task_id: Unique task identifier
            priority: Task priority (-19 to 20, default 0)
            scope: Resource scope descriptor for conflict detection
            params: Task parameters as bytes
            content_type: MIME type of params (default: application/json)

        Returns:
            SubmitTaskResponse
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        if not -19 <= priority <= 20:
            raise ValueError(f"Priority must be between -19 and 20, got {priority}")
        req = self._pb2.SubmitTaskRequest(
            agent_id=agent_id,
            task_id=task_id,
            priority=priority,
            scope=scope,
            params=params,
            content_type=content_type
        )
        return self._stub.SubmitTask(req)

    def request_preemption(self, agent_id: str, task_id: str, reason: str = "") -> Any:
        """Request preemption of a running task.

        Args:
            agent_id: Agent running the task
            task_id: Task to preempt
            reason: Optional reason for preemption

        Returns:
            PreemptResponse
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.PreemptRequest(agent_id=agent_id, task_id=task_id, reason=reason)
        return self._stub.RequestPreemption(req)

    def shutdown_agent(self, agent_id: str, grace_period: Optional[timedelta] = None) -> Any:
        """Request graceful agent shutdown.

        Args:
            agent_id: Agent to shutdown
            grace_period: Optional grace period for cleanup (None = use default)

        Returns:
            ShutdownAgentResponse
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")

        from google.protobuf.duration_pb2 import Duration
        grace_duration = None
        if grace_period is not None:
            grace_duration = Duration()
            grace_duration.seconds = int(grace_period.total_seconds())
            grace_duration.nanos = int((grace_period.total_seconds() % 1) * 1e9)

        req = self._pb2.ShutdownAgentRequest(agent_id=agent_id, grace_period=grace_duration)
        return self._stub.ShutdownAgent(req)

    def poll_activity_buffer(self, agent_id: str) -> Any:
        """Poll the activity buffer for an agent.

        Args:
            agent_id: Agent whose activity to poll

        Returns:
            PollActivityBufferResponse with list of ActivityEntry
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.PollActivityBufferRequest(agent_id=agent_id)
        return self._stub.PollActivityBuffer(req)

    def purge_activity(self, agent_id: str, task_ids: list[str]) -> Any:
        """Purge completed/failed tasks from activity buffer.

        Args:
            agent_id: Agent whose activity to purge
            task_ids: List of task IDs to purge

        Returns:
            PurgeActivityResponse with count of purged entries
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.PurgeActivityRequest(agent_id=agent_id, task_ids=task_ids)
        return self._stub.PurgeActivity(req)

