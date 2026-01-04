"""Tests for the agent handoff protocol.

This module tests the handoff functionality including request/response flow,
context serialization, and agent integration.
"""

import pytest

from sw4rm.handoff import (
    HandoffRequest,
    HandoffResponse,
    HandoffStatus,
    HandoffContext,
    serialize_context,
    deserialize_context,
)
from sw4rm.clients import HandoffClient
from sw4rm.runtime.agent import Agent


class TestHandoffTypes:
    """Tests for handoff data types."""

    def test_handoff_request_creation(self):
        """Test creating a HandoffRequest."""
        request = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Need specialist knowledge",
            preserve_history=True,
            capabilities_required=["database", "analytics"],
        )

        assert request.from_agent == "agent-1"
        assert request.to_agent == "agent-2"
        assert request.reason == "Need specialist knowledge"
        assert request.preserve_history is True
        assert request.capabilities_required == ["database", "analytics"]
        assert request.context_snapshot is None
        assert isinstance(request.metadata, dict)

    def test_handoff_response_creation(self):
        """Test creating a HandoffResponse."""
        response = HandoffResponse(
            accepted=True,
            handoff_id="handoff-123",
            status=HandoffStatus.PENDING,
        )

        assert response.accepted is True
        assert response.handoff_id == "handoff-123"
        assert response.status == HandoffStatus.PENDING
        assert response.rejection_reason is None
        assert isinstance(response.metadata, dict)

    def test_handoff_response_rejection(self):
        """Test creating a HandoffResponse with rejection."""
        response = HandoffResponse(
            accepted=False,
            handoff_id="handoff-456",
            rejection_reason="Agent is at capacity",
            status=HandoffStatus.REJECTED,
        )

        assert response.accepted is False
        assert response.rejection_reason == "Agent is at capacity"
        assert response.status == HandoffStatus.REJECTED

    def test_handoff_status_enum(self):
        """Test HandoffStatus enum values."""
        assert HandoffStatus.PENDING.value == "PENDING"
        assert HandoffStatus.ACCEPTED.value == "ACCEPTED"
        assert HandoffStatus.REJECTED.value == "REJECTED"
        assert HandoffStatus.COMPLETED.value == "COMPLETED"


class TestHandoffContext:
    """Tests for HandoffContext and serialization."""

    def test_empty_context_creation(self):
        """Test creating an empty HandoffContext."""
        context = HandoffContext()

        assert context.conversation_history == []
        assert context.tool_state == {}
        assert context.metadata == {}

    def test_context_with_data(self):
        """Test creating a HandoffContext with data."""
        context = HandoffContext(
            conversation_history=[
                {"role": "user", "content": "Hello"},
                {"role": "assistant", "content": "Hi there!"},
            ],
            tool_state={"active_tools": ["search", "calculator"]},
            metadata={"session_id": "sess-123"},
        )

        assert len(context.conversation_history) == 2
        assert context.conversation_history[0]["role"] == "user"
        assert context.tool_state["active_tools"] == ["search", "calculator"]
        assert context.metadata["session_id"] == "sess-123"

    def test_context_to_dict(self):
        """Test converting HandoffContext to dictionary."""
        context = HandoffContext(
            conversation_history=[{"role": "user", "content": "Test"}],
            tool_state={"tool1": "active"},
            metadata={"key": "value"},
        )

        data = context.to_dict()

        assert isinstance(data, dict)
        assert "conversation_history" in data
        assert "tool_state" in data
        assert "metadata" in data
        assert data["conversation_history"] == [{"role": "user", "content": "Test"}]
        assert data["tool_state"] == {"tool1": "active"}
        assert data["metadata"] == {"key": "value"}

    def test_context_from_dict(self):
        """Test creating HandoffContext from dictionary."""
        data = {
            "conversation_history": [{"role": "system", "content": "You are helpful"}],
            "tool_state": {"cache": {"key": "value"}},
            "metadata": {"timestamp": "2024-01-01T00:00:00Z"},
        }

        context = HandoffContext.from_dict(data)

        assert len(context.conversation_history) == 1
        assert context.conversation_history[0]["role"] == "system"
        assert context.tool_state["cache"]["key"] == "value"
        assert context.metadata["timestamp"] == "2024-01-01T00:00:00Z"

    def test_serialize_context(self):
        """Test serializing a HandoffContext to bytes."""
        context = HandoffContext(
            conversation_history=[{"role": "user", "content": "Hello"}],
            tool_state={"active": True},
            metadata={"version": "1.0"},
        )

        serialized = serialize_context(context)

        assert isinstance(serialized, bytes)
        assert len(serialized) > 0

    def test_deserialize_context(self):
        """Test deserializing bytes to a HandoffContext."""
        context = HandoffContext(
            conversation_history=[{"role": "assistant", "content": "Response"}],
            tool_state={"tools": ["tool1", "tool2"]},
            metadata={"agent": "agent-1"},
        )

        serialized = serialize_context(context)
        deserialized = deserialize_context(serialized)

        assert isinstance(deserialized, HandoffContext)
        assert deserialized.conversation_history == context.conversation_history
        assert deserialized.tool_state == context.tool_state
        assert deserialized.metadata == context.metadata

    def test_serialize_deserialize_round_trip(self):
        """Test that serialization round-trip preserves data."""
        original = HandoffContext(
            conversation_history=[
                {"role": "user", "content": "Question 1"},
                {"role": "assistant", "content": "Answer 1"},
                {"role": "user", "content": "Question 2"},
            ],
            tool_state={
                "active_tools": ["search", "calculator"],
                "cache": {"search_results": [1, 2, 3]},
            },
            metadata={
                "session_id": "sess-456",
                "start_time": "2024-01-01T12:00:00Z",
                "agent_version": "1.2.3",
            },
        )

        # Serialize and deserialize
        serialized = serialize_context(original)
        restored = deserialize_context(serialized)

        # Verify all data is preserved
        assert restored.conversation_history == original.conversation_history
        assert restored.tool_state == original.tool_state
        assert restored.metadata == original.metadata

    def test_deserialize_invalid_data(self):
        """Test that deserializing invalid data raises ValueError."""
        with pytest.raises(ValueError, match="Failed to deserialize"):
            deserialize_context(b"invalid json data")

    def test_serialize_empty_context(self):
        """Test serializing an empty context."""
        context = HandoffContext()
        serialized = serialize_context(context)
        deserialized = deserialize_context(serialized)

        assert deserialized.conversation_history == []
        assert deserialized.tool_state == {}
        assert deserialized.metadata == {}


class TestHandoffClient:
    """Tests for HandoffClient."""

    @pytest.fixture(autouse=True)
    def clear_storage(self):
        """Clear shared handoff storage before each test."""
        HandoffClient.clear_all_handoffs()
        yield
        HandoffClient.clear_all_handoffs()

    @pytest.fixture
    def client(self):
        """Create a HandoffClient for testing."""
        return HandoffClient()

    def test_client_initialization(self, client):
        """Test HandoffClient initialization."""
        assert client is not None
        assert client._channel is None
        assert client._stub is None

    def test_request_handoff(self, client):
        """Test requesting a handoff."""
        request = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Task delegation",
        )

        response = client.request_handoff(request)

        assert isinstance(response, HandoffResponse)
        assert response.accepted is True
        assert response.handoff_id is not None
        assert response.status == HandoffStatus.PENDING
        assert "created_at" in response.metadata

    def test_accept_handoff(self, client):
        """Test accepting a handoff request."""
        # First create a handoff
        request = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Test handoff",
        )
        initial_response = client.request_handoff(request)
        handoff_id = initial_response.handoff_id

        # Accept the handoff
        response = client.accept_handoff(handoff_id)

        assert response.accepted is True
        assert response.status == HandoffStatus.ACCEPTED
        assert "accepted_at" in response.metadata

    def test_reject_handoff(self, client):
        """Test rejecting a handoff request."""
        # First create a handoff
        request = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Test handoff",
        )
        initial_response = client.request_handoff(request)
        handoff_id = initial_response.handoff_id

        # Reject the handoff
        rejection_reason = "Agent is busy with other tasks"
        response = client.reject_handoff(handoff_id, rejection_reason)

        assert response.accepted is False
        assert response.status == HandoffStatus.REJECTED
        assert response.rejection_reason == rejection_reason
        assert "rejected_at" in response.metadata

    def test_complete_handoff(self, client):
        """Test completing a handoff."""
        # Create and accept a handoff
        request = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Test handoff",
        )
        initial_response = client.request_handoff(request)
        handoff_id = initial_response.handoff_id
        client.accept_handoff(handoff_id)

        # Complete the handoff
        response = client.complete_handoff(handoff_id)

        assert response.status == HandoffStatus.COMPLETED
        assert "completed_at" in response.metadata

    def test_get_pending_handoffs(self, client):
        """Test getting pending handoffs for an agent."""
        # Create multiple handoffs for agent-2
        request1 = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Handoff 1",
        )
        request2 = HandoffRequest(
            from_agent="agent-3",
            to_agent="agent-2",
            reason="Handoff 2",
        )
        request3 = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-4",
            reason="Handoff 3 (different target)",
        )

        client.request_handoff(request1)
        client.request_handoff(request2)
        client.request_handoff(request3)

        # Get pending handoffs for agent-2
        pending = client.get_pending_handoffs("agent-2")

        assert len(pending) == 2
        assert all(req.to_agent == "agent-2" for req in pending)
        assert any(req.reason == "Handoff 1" for req in pending)
        assert any(req.reason == "Handoff 2" for req in pending)

    def test_get_pending_handoffs_after_acceptance(self, client):
        """Test that accepted handoffs are removed from pending list."""
        request = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Test",
        )
        response = client.request_handoff(request)

        # Initially should be pending
        pending = client.get_pending_handoffs("agent-2")
        assert len(pending) == 1

        # After acceptance, should be removed from pending
        client.accept_handoff(response.handoff_id)
        pending = client.get_pending_handoffs("agent-2")
        assert len(pending) == 0

    def test_get_handoff_status(self, client):
        """Test getting handoff status."""
        request = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Test",
        )
        response = client.request_handoff(request)
        handoff_id = response.handoff_id

        # Get status
        status = client.get_handoff_status(handoff_id)

        assert status is not None
        assert status.handoff_id == handoff_id
        assert status.status == HandoffStatus.PENDING

    def test_get_handoff_status_not_found(self, client):
        """Test getting status for non-existent handoff."""
        status = client.get_handoff_status("non-existent-id")
        assert status is None

    def test_accept_non_existent_handoff(self, client):
        """Test accepting a non-existent handoff raises ValueError."""
        with pytest.raises(ValueError, match="not found"):
            client.accept_handoff("non-existent-id")

    def test_reject_non_existent_handoff(self, client):
        """Test rejecting a non-existent handoff raises ValueError."""
        with pytest.raises(ValueError, match="not found"):
            client.reject_handoff("non-existent-id", "reason")

    def test_accept_already_accepted_handoff(self, client):
        """Test accepting an already accepted handoff raises ValueError."""
        request = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Test",
        )
        response = client.request_handoff(request)
        handoff_id = response.handoff_id

        # Accept once
        client.accept_handoff(handoff_id)

        # Try to accept again
        with pytest.raises(ValueError, match="not in PENDING status"):
            client.accept_handoff(handoff_id)


class TestAgentHandoffIntegration:
    """Tests for agent handoff integration."""

    @pytest.fixture(autouse=True)
    def clear_storage(self):
        """Clear shared handoff storage before each test."""
        HandoffClient.clear_all_handoffs()
        yield
        HandoffClient.clear_all_handoffs()

    def test_agent_has_handoff_methods(self):
        """Test that Agent class has handoff methods."""
        agent = Agent("agent-1", "Test Agent")

        assert hasattr(agent, "initiate_handoff")
        assert hasattr(agent, "get_handoff_context")
        assert hasattr(agent, "on_handoff_request")
        assert hasattr(agent, "on_handoff_received")

    def test_agent_initiate_handoff(self):
        """Test agent initiating a handoff."""
        agent = Agent("agent-1", "Test Agent")

        response = agent.initiate_handoff(
            to_agent="agent-2",
            reason="Need specialized processing"
        )

        assert isinstance(response, HandoffResponse)
        assert response.accepted is True
        assert response.handoff_id is not None
        assert response.status == HandoffStatus.PENDING

    def test_agent_get_handoff_context(self):
        """Test agent getting handoff context."""
        agent = Agent("agent-1", "Test Agent")
        agent.start()

        context = agent.get_handoff_context()

        assert isinstance(context, HandoffContext)
        assert context.metadata["agent_id"] == "agent-1"
        assert context.metadata["agent_name"] == "Test Agent"
        assert context.metadata["state"] == "RUNNABLE"

    def test_agent_handoff_context_includes_state(self):
        """Test that handoff context includes agent state."""
        agent = Agent("agent-1", "Test Agent")
        agent.start()
        agent.schedule("task-123")

        context = agent.get_handoff_context()

        assert context.metadata["state"] == "SCHEDULED"
        assert context.metadata["task_id"] == "task-123"

    def test_custom_agent_with_handoff_hooks(self):
        """Test custom agent implementing handoff hooks."""
        class CustomAgent(Agent):
            def __init__(self, *args, **kwargs):
                super().__init__(*args, **kwargs)
                self.handoff_request_received = None
                self.handoff_context_received = None

            def on_handoff_request(self, request):
                self.handoff_request_received = request

            def on_handoff_received(self, context):
                self.handoff_context_received = context

        agent = CustomAgent("agent-1", "Custom Agent")

        # Create a handoff request
        request = HandoffRequest(
            from_agent="agent-0",
            to_agent="agent-1",
            reason="Test",
        )

        # Simulate receiving handoff request
        agent.on_handoff_request(request)
        assert agent.handoff_request_received == request

        # Simulate receiving handoff context
        context = HandoffContext(
            conversation_history=[{"role": "user", "content": "Hello"}],
        )
        agent.on_handoff_received(context)
        assert agent.handoff_context_received == context

    def test_handoff_request_includes_context(self):
        """Test that handoff request includes serialized context."""
        agent = Agent("agent-1", "Test Agent")
        agent.start()

        response = agent.initiate_handoff("agent-2", "Test handoff")

        # Get the handoff request from the client
        client = HandoffClient()
        pending = client.get_pending_handoffs("agent-2")

        assert len(pending) > 0
        request = pending[0]
        assert request.context_snapshot is not None

        # Verify context can be deserialized
        context = deserialize_context(request.context_snapshot)
        assert isinstance(context, HandoffContext)
        assert context.metadata["agent_id"] == "agent-1"


class TestHandoffWorkflow:
    """Tests for complete handoff workflows."""

    @pytest.fixture(autouse=True)
    def clear_storage(self):
        """Clear shared handoff storage before each test."""
        HandoffClient.clear_all_handoffs()
        yield
        HandoffClient.clear_all_handoffs()

    def test_request_accept_complete_flow(self):
        """Test complete handoff flow: request -> accept -> complete."""
        client = HandoffClient()

        # Request handoff
        request = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Workflow test",
        )
        response1 = client.request_handoff(request)
        assert response1.status == HandoffStatus.PENDING

        # Accept handoff
        response2 = client.accept_handoff(response1.handoff_id)
        assert response2.status == HandoffStatus.ACCEPTED

        # Complete handoff
        response3 = client.complete_handoff(response1.handoff_id)
        assert response3.status == HandoffStatus.COMPLETED

    def test_request_reject_flow(self):
        """Test handoff rejection flow: request -> reject."""
        client = HandoffClient()

        # Request handoff
        request = HandoffRequest(
            from_agent="agent-1",
            to_agent="agent-2",
            reason="Workflow test",
        )
        response1 = client.request_handoff(request)
        assert response1.status == HandoffStatus.PENDING

        # Reject handoff
        response2 = client.reject_handoff(
            response1.handoff_id,
            "Not equipped to handle this task"
        )
        assert response2.status == HandoffStatus.REJECTED
        assert response2.accepted is False
        assert response2.rejection_reason is not None

    def test_end_to_end_agent_handoff(self):
        """Test end-to-end handoff between two agents."""
        # Create two agents
        agent1 = Agent("agent-1", "Generalist")
        agent2 = Agent("agent-2", "Specialist")

        agent1.start()
        agent2.start()

        # Agent 1 initiates handoff to Agent 2
        response = agent1.initiate_handoff(
            to_agent=agent2.agent_id,
            reason="Need specialist knowledge"
        )

        assert response.accepted is True
        assert response.status == HandoffStatus.PENDING

        # Agent 2 can see the pending handoff
        client = HandoffClient()
        pending = client.get_pending_handoffs(agent2.agent_id)
        assert len(pending) > 0
        assert pending[0].from_agent == agent1.agent_id

        # Agent 2 accepts the handoff
        accepted_response = client.accept_handoff(response.handoff_id)
        assert accepted_response.status == HandoffStatus.ACCEPTED

        # Agent 2 can deserialize and use the context
        handoff_request = pending[0]
        context = deserialize_context(handoff_request.context_snapshot)
        assert context.metadata["agent_id"] == agent1.agent_id
