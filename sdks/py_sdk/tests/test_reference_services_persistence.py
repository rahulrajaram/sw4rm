from __future__ import annotations

import sys
from pathlib import Path

HIVE_DIR = Path(__file__).resolve().parents[1] / "reference-services" / "hive"
if str(HIVE_DIR) not in sys.path:
    sys.path.insert(0, str(HIVE_DIR))

from sw4rm.protos import common_pb2, registry_pb2, router_pb2, scheduler_pb2
from registry_service import RegistryServiceImpl
from router_service import RouterServiceImpl
from scheduler_service import SchedulerServiceImpl


def _state_db(tmp_path: Path, name: str) -> str:
    return str(tmp_path / name)


def test_registry_service_persists_agents(tmp_path: Path) -> None:
    db_path = _state_db(tmp_path, "registry.sqlite3")

    first = RegistryServiceImpl(db_path=db_path)
    register = registry_pb2.RegisterAgentRequest(
        agent=registry_pb2.AgentDescriptor(
            agent_id="agent-1",
            name="Agent One",
            description="persistent agent",
        )
    )
    first.RegisterAgent(register, None)
    assert "agent-1" in first.agents

    second = RegistryServiceImpl(db_path=db_path)
    assert "agent-1" in second.agents
    assert second.agents["agent-1"]["name"] == "Agent One"

    second.Heartbeat(
        registry_pb2.HeartbeatRequest(agent_id="agent-1", health={"mode": "ready"}, state=0),
        None,
    )
    third = RegistryServiceImpl(db_path=db_path)
    assert third.agents["agent-1"].get("health", {}).get("mode") == "ready"


def test_router_service_persists_pending_messages(tmp_path: Path) -> None:
    db_path = _state_db(tmp_path, "router.sqlite3")

    first = RouterServiceImpl(db_path=db_path)
    first._ensure_agent_queue("worker-a")
    first._ensure_agent_queue("worker-b")

    payload = common_pb2.Envelope(
        message_id="msg-1",
        producer_id="scheduler",
        message_type=common_pb2.MessageType.DATA,
        content_type="application/json",
        payload=b'{"ok":true}',
        correlation_id="corr-1",
        sequence_number=1,
        idempotency_token="id-1",
    )
    first.SendMessage(router_pb2.SendMessageRequest(msg=payload), None)

    second = RouterServiceImpl(db_path=db_path)
    assert "worker-a" in second.agent_queues
    assert "worker-b" in second.agent_queues
    assert not second.agent_queues["worker-a"].empty()
    _, first_item = second.agent_queues["worker-a"].get_nowait()
    assert first_item.message_id == "msg-1"


def test_scheduler_service_persists_tasks_and_activity(tmp_path: Path) -> None:
    db_path = _state_db(tmp_path, "scheduler.sqlite3")

    submitter = SchedulerServiceImpl(db_path=db_path)
    submit_res = submitter.SubmitTask(
        scheduler_pb2.SubmitTaskRequest(
            agent_id="agent-1",
            task_id="task-1",
            priority=5,
            scope="analysis",
            params=b'{"goal":"run"}',
            content_type="application/json",
        ),
        None,
    )
    assert submit_res.accepted is True
    assert "task-1" in submitter.tasks

    pollter = SchedulerServiceImpl(db_path=db_path)
    poll = pollter.PollActivityBuffer(scheduler_pb2.PollActivityBufferRequest(agent_id="agent-1"), None)
    assert len(poll.entries) == 1
    assert poll.entries[0].task_id == "task-1"

    request = scheduler_pb2.PreemptRequest(agent_id="agent-1", task_id="task-1", reason="manual stop")
    preempt = pollter.RequestPreemption(request, None)
    assert preempt.enqueued is True

    purger = SchedulerServiceImpl(db_path=db_path)
    assert purger.tasks["task-1"]["status"] == "preempted"
    purged = purger.PurgeActivity(scheduler_pb2.PurgeActivityRequest(agent_id="agent-1", task_ids=["task-1"]), None)
    assert purged.purged == 1
