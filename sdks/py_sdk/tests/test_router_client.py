"""Unit tests for RouterClient."""
import pytest
from unittest.mock import MagicMock, patch


class TestRouterClientConstruction:
    """Tests for RouterClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that RouterClient initializes correctly with a valid channel."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.router import RouterClient
        client = RouterClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_stores_channel(self):
        """Test that constructor stores the channel reference."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.router import RouterClient
        client = RouterClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        # Arrange
        mock_channel = MagicMock()

        with patch.dict('sys.modules', {'sw4rm.protos': None}):
            # Act
            from sw4rm.clients.router import RouterClient
            client = RouterClient(mock_channel)

            # Assert - stub should be None due to import failure
            assert client._channel == mock_channel
            assert client._stub is None
            assert client._pb2 is None


class TestRouterClientSendMessage:
    """Tests for RouterClient.send_message method."""

    def test_send_message_with_envelope_dict(self):
        """Test send_message with a valid envelope dictionary."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_envelope_msg = MagicMock()

        mock_pb2.SendMessageRequest.return_value = mock_request
        mock_stub.SendMessage.return_value = mock_response

        envelope_dict = {
            "producer_id": "agent-1",
            "message_type": 2,  # DATA enum value
            "payload": b"test_content"
        }

        from sw4rm.clients.router import RouterClient
        client = RouterClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        with patch('sw4rm.protos.common_pb2.Envelope', return_value=mock_envelope_msg):
            # Act
            result = client.send_message(envelope_dict)

        # Assert
        mock_pb2.SendMessageRequest.assert_called_once_with(msg=mock_envelope_msg)
        mock_stub.SendMessage.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_send_message_with_stub_none_raises_runtime_error(self):
        """Test send_message raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.router import RouterClient
        client = RouterClient(mock_channel)
        client._stub = None

        envelope_dict = {"producer_id": "agent-1", "message_type": 2}  # DATA enum value

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.send_message(envelope_dict)

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestRouterClientStreamIncoming:
    """Tests for RouterClient.stream_incoming method."""

    def test_stream_incoming_with_agent_id(self):
        """Test stream_incoming returns an iterator of responses."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_stream = MagicMock()

        mock_pb2.StreamRequest.return_value = mock_request
        mock_stub.StreamIncoming.return_value = mock_stream

        from sw4rm.clients.router import RouterClient
        client = RouterClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.stream_incoming(agent_id="agent-1")

        # Assert
        mock_pb2.StreamRequest.assert_called_once_with(agent_id="agent-1")
        mock_stub.StreamIncoming.assert_called_once_with(mock_request)
        assert result == mock_stream

    def test_stream_incoming_with_different_agent_ids(self):
        """Test stream_incoming with multiple different agent IDs."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_stream = MagicMock()

        mock_pb2.StreamRequest.return_value = mock_request
        mock_stub.StreamIncoming.return_value = mock_stream

        from sw4rm.clients.router import RouterClient
        client = RouterClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        agent_ids = ["agent-1", "agent-2", "agent-3"]

        # Act & Assert
        for agent_id in agent_ids:
            result = client.stream_incoming(agent_id=agent_id)
            assert result == mock_stream

        assert mock_pb2.StreamRequest.call_count == 3
        assert mock_stub.StreamIncoming.call_count == 3

    def test_stream_incoming_with_stub_none_raises_runtime_error(self):
        """Test stream_incoming raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.router import RouterClient
        client = RouterClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.stream_incoming(agent_id="agent-1")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestRouterClientIntegration:
    """Integration-style tests for RouterClient."""

    def test_multiple_operations_in_sequence(self):
        """Test multiple operations can be performed in sequence."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_stream = MagicMock()
        mock_envelope_msg = MagicMock()

        from sw4rm.clients.router import RouterClient
        client = RouterClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        envelope_dict = {"producer_id": "agent-1", "message_type": 2}  # DATA enum value

        with patch('sw4rm.protos.common_pb2.Envelope', return_value=mock_envelope_msg):
            # Act
            client.send_message(envelope_dict)
            mock_stub.StreamIncoming.return_value = mock_stream
            stream_result = client.stream_incoming(agent_id="agent-1")

        # Assert
        assert mock_stub.SendMessage.call_count == 1
        assert mock_stub.StreamIncoming.call_count == 1
        assert stream_result == mock_stream
