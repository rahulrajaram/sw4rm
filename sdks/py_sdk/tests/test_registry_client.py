"""Unit tests for RegistryClient."""
import pytest
from unittest.mock import MagicMock, patch


class TestRegistryClientConstruction:
    """Tests for RegistryClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that RegistryClient initializes correctly with a valid channel."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_stores_channel(self):
        """Test that constructor stores the channel reference."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        # Arrange
        mock_channel = MagicMock()

        with patch.dict('sys.modules', {'sw4rm.protos': None}):
            # Act
            from sw4rm.clients.registry import RegistryClient
            client = RegistryClient(mock_channel)

            # Assert - stub should be None due to import failure
            assert client._channel == mock_channel
            assert client._stub is None
            assert client._pb2 is None


class TestRegistryClientRegister:
    """Tests for RegistryClient.register method."""

    def test_register_with_agent_descriptor(self):
        """Test register with a valid agent descriptor dictionary."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_agent_descriptor = MagicMock()

        mock_pb2.AgentDescriptor.return_value = mock_agent_descriptor
        mock_pb2.RegisterAgentRequest.return_value = mock_request
        mock_stub.RegisterAgent.return_value = mock_response

        agent_descriptor = {
            "agent_id": "agent-1",
            "name": "Test Agent",
            "capabilities": ["task_processing"],
            "communication_class": "SW4RM_STANDARD"
        }

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.register(agent_descriptor)

        # Assert
        mock_pb2.AgentDescriptor.assert_called_once_with(**agent_descriptor)
        mock_pb2.RegisterAgentRequest.assert_called_once_with(agent=mock_agent_descriptor)
        mock_stub.RegisterAgent.assert_called_once_with(mock_request, timeout=30.0)
        assert result == mock_response

    def test_register_with_minimal_descriptor(self):
        """Test register with minimal required fields."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_agent_descriptor = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.AgentDescriptor.return_value = mock_agent_descriptor
        mock_pb2.RegisterAgentRequest.return_value = mock_request
        mock_stub.RegisterAgent.return_value = mock_response

        agent_descriptor = {"agent_id": "agent-1"}

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.register(agent_descriptor)

        # Assert
        mock_pb2.AgentDescriptor.assert_called_once_with(**agent_descriptor)
        assert result == mock_response

    def test_register_with_stub_none_raises_runtime_error(self):
        """Test register raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = None

        agent_descriptor = {"agent_id": "agent-1"}

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.register(agent_descriptor)

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestRegistryClientHeartbeat:
    """Tests for RegistryClient.heartbeat method."""

    def test_heartbeat_with_agent_id_and_state(self):
        """Test heartbeat with agent_id and state."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.HeartbeatRequest.return_value = mock_request
        mock_stub.Heartbeat.return_value = mock_response

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.heartbeat(agent_id="agent-1", state=1)

        # Assert
        mock_pb2.HeartbeatRequest.assert_called_once_with(
            agent_id="agent-1",
            state=1,
            health={}
        )
        mock_stub.Heartbeat.assert_called_once_with(mock_request, timeout=30.0)
        assert result == mock_response

    def test_heartbeat_with_health_metrics(self):
        """Test heartbeat with health metrics."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.HeartbeatRequest.return_value = mock_request
        mock_stub.Heartbeat.return_value = mock_response

        health_metrics = {
            "cpu_usage": "45%",
            "memory_usage": "60%",
            "uptime": "3600s"
        }

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.heartbeat(agent_id="agent-1", state=1, health=health_metrics)

        # Assert
        mock_pb2.HeartbeatRequest.assert_called_once_with(
            agent_id="agent-1",
            state=1,
            health=health_metrics
        )
        mock_stub.Heartbeat.assert_called_once_with(mock_request, timeout=30.0)
        assert result == mock_response

    def test_heartbeat_with_none_health_defaults_to_empty_dict(self):
        """Test heartbeat with None health parameter defaults to empty dict."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.HeartbeatRequest.return_value = mock_request
        mock_stub.Heartbeat.return_value = mock_response

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.heartbeat(agent_id="agent-1", state=2, health=None)

        # Assert
        mock_pb2.HeartbeatRequest.assert_called_once_with(
            agent_id="agent-1",
            state=2,
            health={}
        )

    def test_heartbeat_with_stub_none_raises_runtime_error(self):
        """Test heartbeat raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.heartbeat(agent_id="agent-1", state=1)

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestRegistryClientDeregister:
    """Tests for RegistryClient.deregister method."""

    def test_deregister_with_agent_id_only(self):
        """Test deregister with only agent_id parameter."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.DeregisterAgentRequest.return_value = mock_request
        mock_stub.DeregisterAgent.return_value = mock_response

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.deregister(agent_id="agent-1")

        # Assert
        mock_pb2.DeregisterAgentRequest.assert_called_once_with(
            agent_id="agent-1",
            reason=""
        )
        mock_stub.DeregisterAgent.assert_called_once_with(mock_request, timeout=30.0)
        assert result == mock_response

    def test_deregister_with_reason(self):
        """Test deregister with a specified reason."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.DeregisterAgentRequest.return_value = mock_request
        mock_stub.DeregisterAgent.return_value = mock_response

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.deregister(agent_id="agent-1", reason="Agent shutdown")

        # Assert
        mock_pb2.DeregisterAgentRequest.assert_called_once_with(
            agent_id="agent-1",
            reason="Agent shutdown"
        )
        mock_stub.DeregisterAgent.assert_called_once_with(mock_request, timeout=30.0)
        assert result == mock_response

    def test_deregister_with_empty_reason_string(self):
        """Test deregister with explicit empty reason string."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.DeregisterAgentRequest.return_value = mock_request
        mock_stub.DeregisterAgent.return_value = mock_response

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.deregister(agent_id="agent-1", reason="")

        # Assert
        mock_pb2.DeregisterAgentRequest.assert_called_once_with(
            agent_id="agent-1",
            reason=""
        )

    def test_deregister_with_stub_none_raises_runtime_error(self):
        """Test deregister raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.deregister(agent_id="agent-1")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestRegistryClientIntegration:
    """Integration-style tests for RegistryClient."""

    def test_agent_lifecycle_operations(self):
        """Test complete agent lifecycle: register -> heartbeat -> deregister."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        agent_descriptor = {"agent_id": "agent-1", "name": "Test Agent"}

        # Act
        client.register(agent_descriptor)
        client.heartbeat(agent_id="agent-1", state=1)
        client.heartbeat(agent_id="agent-1", state=1, health={"status": "healthy"})
        client.deregister(agent_id="agent-1", reason="Normal shutdown")

        # Assert
        assert mock_stub.RegisterAgent.call_count == 1
        assert mock_stub.Heartbeat.call_count == 2
        assert mock_stub.DeregisterAgent.call_count == 1

    def test_multiple_heartbeats_in_sequence(self):
        """Test multiple heartbeat calls in sequence."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.registry import RegistryClient
        client = RegistryClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        for i in range(5):
            client.heartbeat(agent_id="agent-1", state=1)

        # Assert
        assert mock_stub.Heartbeat.call_count == 5
