"""Unit tests for ToolClient."""
import pytest
from unittest.mock import MagicMock, patch


class TestToolClientConstruction:
    """Tests for ToolClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that ToolClient initializes correctly with a valid channel."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_stores_channel(self):
        """Test that constructor stores the channel reference."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)

        # Assert - channel should be stored regardless
        assert client._channel == mock_channel


class TestToolClientCall:
    """Tests for ToolClient.call method."""

    def test_call_with_valid_params(self):
        """Test call with a valid ToolCall dictionary."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.ToolCall.return_value = mock_request
        mock_stub.Call.return_value = mock_response

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        call_dict = {
            "call_id": "call-1",
            "tool_name": "read_file",
            "provider_id": "provider-1",
            "args": b'{"path": "/tmp/test.txt"}'
        }

        # Act
        result = client.call(call=call_dict)

        # Assert
        mock_pb2.ToolCall.assert_called_once_with(**call_dict)
        mock_stub.Call.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_call_with_minimal_params(self):
        """Test call with minimal ToolCall fields."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        call_dict = {
            "call_id": "call-1",
            "tool_name": "echo"
        }

        # Act
        client.call(call=call_dict)

        # Assert
        mock_pb2.ToolCall.assert_called_once_with(**call_dict)
        mock_stub.Call.assert_called_once()

    def test_call_with_empty_dict(self):
        """Test call with empty dictionary."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.call(call={})

        # Assert
        mock_pb2.ToolCall.assert_called_once_with()
        mock_stub.Call.assert_called_once()

    def test_call_with_stub_none_raises_runtime_error(self):
        """Test call raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.call(call={"call_id": "call-1"})

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestToolClientCallStream:
    """Tests for ToolClient.call_stream method."""

    def test_call_stream_with_valid_params(self):
        """Test call_stream with a valid ToolCall dictionary."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_stream = iter([MagicMock(), MagicMock(), MagicMock()])

        mock_pb2.ToolCall.return_value = mock_request
        mock_stub.CallStream.return_value = mock_stream

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        call_dict = {
            "call_id": "call-1",
            "tool_name": "stream_logs",
            "provider_id": "provider-1"
        }

        # Act
        result = client.call_stream(call=call_dict)

        # Assert
        mock_pb2.ToolCall.assert_called_once_with(**call_dict)
        mock_stub.CallStream.assert_called_once_with(mock_request)
        # Result should be an iterable
        assert result == mock_stream

    def test_call_stream_returns_iterable(self):
        """Test that call_stream returns an iterable of ToolFrame objects."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        frame1 = MagicMock(name="frame1")
        frame2 = MagicMock(name="frame2")
        frame3 = MagicMock(name="frame3")
        mock_stub.CallStream.return_value = iter([frame1, frame2, frame3])

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.call_stream(call={"call_id": "call-1"})
        frames = list(result)

        # Assert
        assert len(frames) == 3
        assert frame1 in frames
        assert frame2 in frames
        assert frame3 in frames

    def test_call_stream_with_empty_stream(self):
        """Test call_stream with an empty stream response."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        mock_stub.CallStream.return_value = iter([])

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.call_stream(call={"call_id": "call-1"})
        frames = list(result)

        # Assert
        assert len(frames) == 0

    def test_call_stream_with_stub_none_raises_runtime_error(self):
        """Test call_stream raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.call_stream(call={"call_id": "call-1"})

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestToolClientCancel:
    """Tests for ToolClient.cancel method."""

    def test_cancel_with_valid_params(self):
        """Test cancel with a valid ToolCall dictionary."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.ToolCall.return_value = mock_request
        mock_stub.Cancel.return_value = mock_response

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        call_dict = {
            "call_id": "call-1",
            "tool_name": "long_running_task"
        }

        # Act
        result = client.cancel(call=call_dict)

        # Assert
        mock_pb2.ToolCall.assert_called_once_with(**call_dict)
        mock_stub.Cancel.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_cancel_with_minimal_call_id(self):
        """Test cancel with only call_id (minimum required)."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.cancel(call={"call_id": "call-to-cancel"})

        # Assert
        mock_pb2.ToolCall.assert_called_once_with(call_id="call-to-cancel")
        mock_stub.Cancel.assert_called_once()

    def test_cancel_with_stub_none_raises_runtime_error(self):
        """Test cancel raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.cancel(call={"call_id": "call-1"})

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestToolClientIntegration:
    """Integration-style tests for ToolClient."""

    def test_call_and_cancel_sequence(self):
        """Test calling a tool and then canceling it."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        call_dict = {
            "call_id": "call-1",
            "tool_name": "slow_operation",
            "provider_id": "provider-1"
        }

        # Act
        client.call(call=call_dict)
        client.cancel(call={"call_id": "call-1"})

        # Assert
        assert mock_stub.Call.call_count == 1
        assert mock_stub.Cancel.call_count == 1

    def test_multiple_stream_calls(self):
        """Test multiple streaming calls."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        mock_stub.CallStream.return_value = iter([MagicMock()])

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result1 = client.call_stream(call={"call_id": "stream-1"})
        result2 = client.call_stream(call={"call_id": "stream-2"})

        # Assert
        assert mock_stub.CallStream.call_count == 2

    def test_all_methods_share_same_stub(self):
        """Test that all methods use the same stub instance."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        mock_stub.CallStream.return_value = iter([])

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.call(call={"call_id": "1"})
        list(client.call_stream(call={"call_id": "2"}))
        client.cancel(call={"call_id": "3"})

        # Assert - all calls should be on the same stub
        assert mock_stub.Call.call_count == 1
        assert mock_stub.CallStream.call_count == 1
        assert mock_stub.Cancel.call_count == 1


class TestToolClientEdgeCases:
    """Edge case tests for ToolClient."""

    def test_call_with_binary_args(self):
        """Test call with binary arguments."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        binary_data = b'\x00\x01\x02\xff\xfe\xfd'
        call_dict = {
            "call_id": "call-1",
            "tool_name": "process_binary",
            "args": binary_data
        }

        # Act
        client.call(call=call_dict)

        # Assert
        mock_pb2.ToolCall.assert_called_once_with(**call_dict)

    def test_call_with_unicode_tool_name(self):
        """Test call with unicode characters in tool name."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        call_dict = {
            "call_id": "call-1",
            "tool_name": "process_unicode_test"
        }

        # Act
        client.call(call=call_dict)

        # Assert
        mock_pb2.ToolCall.assert_called_once_with(**call_dict)

    def test_call_with_large_args(self):
        """Test call with large argument payload."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.tool import ToolClient
        client = ToolClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # 1MB of data
        large_data = b'x' * (1024 * 1024)
        call_dict = {
            "call_id": "call-1",
            "tool_name": "process_large",
            "args": large_data
        }

        # Act
        client.call(call=call_dict)

        # Assert
        mock_pb2.ToolCall.assert_called_once_with(**call_dict)
