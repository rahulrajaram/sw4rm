from __future__ import annotations

import contextlib
import sys
import threading
from pathlib import Path
from typing import List, Optional

import pytest

HIVE_DIR = Path(__file__).resolve().parents[1] / "reference-services" / "hive"
if str(HIVE_DIR) not in sys.path:
    sys.path.insert(0, str(HIVE_DIR))

from graceful_shutdown import ReferenceServiceShutdownCoordinator
from registry_service import RegistryServiceImpl
from router_service import RouterServiceImpl
from scheduler_service import SchedulerServiceImpl

try:
    from sw4rm.protos import common_pb2, registry_pb2, router_pb2, scheduler_pb2
except Exception:
    import common_pb2, registry_pb2, router_pb2, scheduler_pb2


def _db_path(tmp_path: Path, filename: str) -> str:
    return str(tmp_path / filename)


class _FakeStopper:
    def __init__(self, outer: "_FakeServer") -> None:
        self.outer = outer

    def wait(self, timeout: Optional[float] = None) -> None:
        self.outer.wait_calls.append(timeout)


class _FakeServer:
    def __init__(self) -> None:
        self.stop_calls: list[float] = []
        self.wait_calls: list[Optional[float]] = []

    def stop(self, grace: float) -> _FakeStopper:
        self.stop_calls.append(grace)
        return _FakeStopper(self)


def test_shutdown_coordinator_tracks_inflight_workloads_and_waits_for_completion() -> None:
    manager = ReferenceServiceShutdownCoordinator("test-service", grace_period_seconds=0.2)
    in_request = threading.Event()
    complete = threading.Event()

    def request_handler() -> None:
        with manager.track_request("LongLivedRpc"):
            in_request.set()
            complete.wait(timeout=1.0)

    worker = threading.Thread(target=request_handler)
    worker.start()

    try:
        assert in_request.wait(timeout=1.0)
        manager.request_shutdown()

        # The request is still running, so completion should timeout briefly.
        assert manager.wait_for_inflight(0.05) is False

        complete.set()
        worker.join(timeout=1.0)
        assert manager.wait_for_inflight(1.0) is True
    finally:
        complete.set()
        worker.join(timeout=1.0)


def test_stop_server_invokes_grpc_stop_and_wait() -> None:
    manager = ReferenceServiceShutdownCoordinator("test-service", grace_period_seconds=0.05)
    grpc_server = _FakeServer()

    manager.stop_server(
        grpc_server,
        stop_wait_seconds=0.01,
        pre_stop_hook=lambda: None,
    )

    assert grpc_server.stop_calls == [0.05]
    assert grpc_server.wait_calls == [1.05]


def test_reference_services_track_shutdown_for_key_rpcs(tmp_path: Path) -> None:
    registry = RegistryServiceImpl(db_path=_db_path(tmp_path, "registry.sqlite3"))
    router = RouterServiceImpl(db_path=_db_path(tmp_path, "router.sqlite3"))
    scheduler = SchedulerServiceImpl(db_path=_db_path(tmp_path, "scheduler.sqlite3"))

    registry_calls: List[str] = []
    router_calls: List[str] = []
    scheduler_calls: List[str] = []

    @contextlib.contextmanager
    def probe_registry(method: str):
        registry_calls.append(method)
        yield

    @contextlib.contextmanager
    def probe_router(method: str):
        router_calls.append(method)
        yield

    @contextlib.contextmanager
    def probe_scheduler(method: str):
        scheduler_calls.append(method)
        yield

    registry._shutdown_manager.track_request = probe_registry
    router._shutdown_manager.track_request = probe_router
    scheduler._shutdown_manager.track_request = probe_scheduler

    register_request = registry_pb2.RegisterAgentRequest(
        agent=registry_pb2.AgentDescriptor(
            agent_id="agent-a",
            name="Agent A",
            description="drain test",
        )
    )
    registry.RegisterAgent(register_request, None)

    envelope = common_pb2.Envelope(
        producer_id="scheduler",
        message_type=common_pb2.MessageType.DATA,
        content_type="application/json",
        payload=b"{}",
    )
    router.SendMessage(router_pb2.SendMessageRequest(msg=envelope), None)

    submit_request = scheduler_pb2.SubmitTaskRequest(
        agent_id="scheduler",
        task_id="task-1",
        scope="build",
        content_type="application/json",
        priority=1,
        params=b"{}",
    )
    scheduler.SubmitTask(submit_request, None)

    assert registry_calls == ["RegisterAgent"]
    assert router_calls == ["SendMessage"]
    assert scheduler_calls == ["SubmitTask"]


def test_reference_services_reject_new_requests_after_draining(tmp_path: Path) -> None:
    shutdown_manager = ReferenceServiceShutdownCoordinator("reference-services", grace_period_seconds=0.05)
    registry = RegistryServiceImpl(
        db_path=_db_path(tmp_path, "registry.sqlite3"),
        shutdown_manager=shutdown_manager,
    )
    router = RouterServiceImpl(db_path=_db_path(tmp_path, "router.sqlite3"))
    router._shutdown_manager = shutdown_manager
    scheduler = SchedulerServiceImpl(
        db_path=_db_path(tmp_path, "scheduler.sqlite3"),
        shutdown_manager=shutdown_manager,
    )

    scheduler.SubmitTask(
        scheduler_pb2.SubmitTaskRequest(
            agent_id="scheduler",
            task_id="task-1",
            scope="build",
            content_type="application/json",
            priority=1,
            params=b"{}",
        ),
        None,
    )

    shutdown_manager.request_shutdown()

    register_response = registry.RegisterAgent(
        registry_pb2.RegisterAgentRequest(
            agent=registry_pb2.AgentDescriptor(agent_id="agent-a", name="Agent A")
        ),
        None,
    )
    assert register_response.accepted is False
    assert register_response.reason == "Registry service is shutting down"

    heartbeat_response = registry.Heartbeat(
        registry_pb2.HeartbeatRequest(agent_id="agent-a", state=0, health={}),
        None,
    )
    assert heartbeat_response.ok is False

    deregister_response = registry.DeregisterAgent(
        registry_pb2.DeregisterAgentRequest(agent_id="agent-a", reason="test"),
        None,
    )
    assert deregister_response.ok is False

    send_response = router.SendMessage(
        router_pb2.SendMessageRequest(
            msg=common_pb2.Envelope(
                producer_id="scheduler",
                message_type=common_pb2.MessageType.DATA,
                content_type="application/json",
                payload=b"{}",
            )
        ),
        None,
    )
    assert send_response.accepted is False
    assert send_response.reason == "Router service is shutting down"
    stream = router.StreamIncoming(router_pb2.StreamRequest(agent_id="agent-a"), None)
    with pytest.raises(StopIteration):
        next(stream)

    preempt_response = scheduler.RequestPreemption(
        scheduler_pb2.PreemptRequest(agent_id="scheduler", task_id="task-1", reason="test"),
        None,
    )
    assert preempt_response.enqueued is False

    submit_response = scheduler.SubmitTask(
        scheduler_pb2.SubmitTaskRequest(
            agent_id="scheduler",
            task_id="task-2",
            scope="build",
            content_type="application/json",
            priority=1,
            params=b"{}",
        ),
        None,
    )
    assert submit_response.accepted is False
    assert submit_response.reason == "Scheduler service is shutting down"

    purge_response = scheduler.PurgeActivity(
        scheduler_pb2.PurgeActivityRequest(agent_id="scheduler", task_ids=[]),
        None,
    )
    assert purge_response.purged == 0

    scheduler_response = scheduler.PollActivityBuffer(
        scheduler_pb2.PollActivityBufferRequest(agent_id="scheduler"),
        None,
    )
    assert len(scheduler_response.entries) == 0

    shutdown_response = scheduler.ShutdownAgent(
        scheduler_pb2.ShutdownAgentRequest(agent_id="scheduler"),
        None,
    )
    assert shutdown_response.ok is False
