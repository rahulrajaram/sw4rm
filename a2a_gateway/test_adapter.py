"""Tests for A2A-to-SW4RM adapter."""
import json
import pytest
from unittest.mock import MagicMock

from a2a_gateway.agent_card import agent_descriptor_to_card, make_gateway_card
from a2a_gateway.adapter import (
    A2AToSW4RMAdapter,
    TaskState,
    TaskStore,
    a2a_message_to_sw4rm_envelope,
    sw4rm_envelope_to_a2a_message,
    sw4rm_agent_state_to_a2a_task_state,
)


class TestAgentCard:
    """Tests for A2A Agent Card generation."""

    def test_descriptor_to_card_basic(self):
        descriptor = {
            "agent_id": "code-writer",
            "name": "Code Writer Agent",
            "description": "Writes Python code",
            "capabilities": ["code-generation", "refactoring"],
        }
        card = agent_descriptor_to_card(descriptor)

        assert card["name"] == "Code Writer Agent"
        assert card["description"] == "Writes Python code"
        assert card["protocolVersion"] == "0.3"
        assert card["capabilities"]["streaming"] is True
        assert len(card["skills"]) == 2
        assert card["skills"][0]["tags"] == ["code-generation"]

    def test_descriptor_to_card_defaults(self):
        card = agent_descriptor_to_card({"agent_id": "minimal"})

        assert card["name"] == "minimal"
        assert "SW4RM agent" in card["description"]
        assert "text/plain" in card["supportedContentTypes"]

    def test_descriptor_to_card_modalities(self):
        descriptor = {
            "agent_id": "media",
            "modalities_supported": ["image/png", "text/html"],
        }
        card = agent_descriptor_to_card(descriptor)

        assert card["supportedContentTypes"] == ["image/png", "text/html"]

    def test_gateway_card(self):
        card = make_gateway_card(gateway_url="http://myhost:9999")

        assert card["name"] == "SW4RM Gateway"
        assert "http://myhost:9999" in card["url"]
        assert card["capabilities"]["streaming"] is True

    def test_gateway_card_with_agents(self):
        agents = [
            {"agent_id": "a1", "name": "Agent One", "capabilities": ["chat"]},
            {"agent_id": "a2", "name": "Agent Two", "capabilities": ["code"]},
        ]
        card = make_gateway_card(agents=agents)

        assert len(card["skills"]) == 2
        assert card["skills"][0]["name"] == "Agent One"


class TestMessageTranslation:
    """Tests for A2A Message <-> SW4RM Envelope translation."""

    def test_message_to_envelope(self):
        message = {
            "role": "user",
            "parts": [{"text": {"text": "Write a hello world program"}}],
            "message_id": "msg-123",
            "metadata": {"sw4rm.sender": "user-42"},
        }

        envelope = a2a_message_to_sw4rm_envelope(
            message=message,
            target_agent_id="code-writer",
            task_id="task-456",
        )

        assert envelope["producer_id"] == "user-42"
        assert envelope["consumer_id"] == "code-writer"
        assert envelope["message_type"] == 2  # DATA
        assert envelope["correlation_id"] == "task-456"
        assert envelope["content_type"] == "application/json"

        # Payload should be JSON-parseable
        payload = json.loads(envelope["payload"])
        assert payload["a2a_task_id"] == "task-456"
        assert payload["role"] == "user"
        assert len(payload["parts"]) == 1

    def test_message_to_envelope_default_sender(self):
        message = {"role": "user", "parts": []}
        envelope = a2a_message_to_sw4rm_envelope(message, "agent-x", "t1")

        assert envelope["producer_id"] == "a2a-gateway"

    def test_envelope_to_message_json(self):
        payload = json.dumps({
            "a2a_task_id": "task-1",
            "parts": [{"text": {"text": "Result: 42"}}],
        }).encode()

        envelope = {
            "producer_id": "code-writer",
            "message_id": "env-789",
            "correlation_id": "task-1",
            "message_type": 2,
            "payload": payload,
        }

        message = sw4rm_envelope_to_a2a_message(envelope)

        assert message["role"] == "agent"
        assert message["task_id"] == "task-1"
        assert len(message["parts"]) == 1
        assert message["metadata"]["sw4rm.producer_id"] == "code-writer"

    def test_envelope_to_message_binary(self):
        envelope = {
            "producer_id": "binary-agent",
            "payload": b"\x89PNG\r\n\x1a\n",
            "message_type": 2,
        }

        message = sw4rm_envelope_to_a2a_message(envelope)

        assert message["role"] == "agent"
        assert len(message["parts"]) == 1
        # Binary content should be wrapped as file part
        assert "file" in message["parts"][0]


class TestTaskStore:
    """Tests for in-memory task store."""

    def test_create_and_get(self):
        store = TaskStore()
        task = store.create_task("agent-1", {"role": "user", "parts": []})

        assert task["id"]
        assert task["status"]["state"] == TaskState.SUBMITTED
        assert task["metadata"]["sw4rm.target_agent"] == "agent-1"

        fetched = store.get_task(task["id"])
        assert fetched == task

    def test_update_state(self):
        store = TaskStore()
        task = store.create_task("agent-1", {"role": "user", "parts": []})

        store.update_state(task["id"], TaskState.WORKING)
        updated = store.get_task(task["id"])
        assert updated["status"]["state"] == TaskState.WORKING

    def test_add_artifact(self):
        store = TaskStore()
        task = store.create_task("agent-1", {"role": "user", "parts": []})

        artifact = {"artifact_id": "art-1", "name": "result.py"}
        store.add_artifact(task["id"], artifact)

        updated = store.get_task(task["id"])
        assert len(updated["artifacts"]) == 1

    def test_get_nonexistent(self):
        store = TaskStore()
        assert store.get_task("nonexistent") is None

    def test_list_tasks(self):
        store = TaskStore()
        store.create_task("a1", {"role": "user"}, context_id="ctx-1")
        store.create_task("a2", {"role": "user"}, context_id="ctx-1")
        store.create_task("a3", {"role": "user"}, context_id="ctx-2")

        all_tasks = store.list_tasks()
        assert len(all_tasks) == 3

        ctx1_tasks = store.list_tasks(context_id="ctx-1")
        assert len(ctx1_tasks) == 2


class TestStateMapping:
    """Tests for SW4RM AgentState → A2A TaskState mapping."""

    def test_running_maps_to_working(self):
        assert sw4rm_agent_state_to_a2a_task_state(4) == TaskState.WORKING

    def test_completed_maps_to_completed(self):
        assert sw4rm_agent_state_to_a2a_task_state(9) == TaskState.COMPLETED

    def test_failed_maps_to_failed(self):
        assert sw4rm_agent_state_to_a2a_task_state(10) == TaskState.FAILED

    def test_waiting_maps_to_input_required(self):
        assert sw4rm_agent_state_to_a2a_task_state(5) == TaskState.INPUT_REQUIRED

    def test_shutting_down_maps_to_canceled(self):
        assert sw4rm_agent_state_to_a2a_task_state(11) == TaskState.CANCELED

    def test_unknown_maps_to_working(self):
        assert sw4rm_agent_state_to_a2a_task_state(999) == TaskState.WORKING


class TestAdapter:
    """Tests for A2AToSW4RMAdapter end-to-end."""

    def test_send_message_creates_task(self):
        mock_router = MagicMock()
        adapter = A2AToSW4RMAdapter(router_client=mock_router)

        message = {
            "role": "user",
            "parts": [{"text": {"text": "Hello"}}],
        }
        task = adapter.send_message(message, target_agent_id="agent-1")

        assert task["id"]
        assert task["status"]["state"] == TaskState.WORKING
        mock_router.send_message.assert_called_once()

    def test_send_message_handles_routing_failure(self):
        mock_router = MagicMock()
        mock_router.send_message.side_effect = Exception("connection refused")
        adapter = A2AToSW4RMAdapter(router_client=mock_router)

        message = {"role": "user", "parts": []}
        task = adapter.send_message(message, target_agent_id="dead-agent")

        assert task["status"]["state"] == TaskState.FAILED

    def test_get_task(self):
        adapter = A2AToSW4RMAdapter()
        message = {"role": "user", "parts": []}
        task = adapter.send_message(message, target_agent_id="agent-1")

        fetched = adapter.get_task(task["id"])
        assert fetched["id"] == task["id"]

    def test_cancel_task(self):
        mock_scheduler = MagicMock()
        adapter = A2AToSW4RMAdapter(scheduler_client=mock_scheduler)

        message = {"role": "user", "parts": []}
        task = adapter.send_message(message, target_agent_id="agent-1")

        canceled = adapter.cancel_task(task["id"])
        assert canceled["status"]["state"] == TaskState.CANCELED
        mock_scheduler.request_preemption.assert_called_once()

    def test_cancel_nonexistent_task(self):
        adapter = A2AToSW4RMAdapter()
        assert adapter.cancel_task("nonexistent") is None

    def test_get_agent_card_gateway(self):
        adapter = A2AToSW4RMAdapter(gateway_url="http://test:1234")
        card = adapter.get_agent_card()

        assert card["name"] == "SW4RM Gateway"
        assert "http://test:1234" in card["url"]
