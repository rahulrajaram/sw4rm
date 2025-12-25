"""Unit tests for LoggingClient."""
import pytest
from unittest.mock import MagicMock, patch


class TestLoggingClientConstruction:
    """Tests for LoggingClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that LoggingClient initializes correctly with a valid channel."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_stores_channel(self):
        """Test that constructor stores the channel reference."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        # Arrange
        mock_channel = MagicMock()

        with patch.dict('sys.modules', {'sw4rm.protos': None}):
            # Act
            from sw4rm.clients.logging import LoggingClient
            client = LoggingClient(mock_channel)

            # Assert - stub should be None due to import failure
            assert client._channel == mock_channel
            assert client._stub is None
            assert client._pb2 is None


class TestLoggingClientIngest:
    """Tests for LoggingClient.ingest method."""

    def test_ingest_with_log_event_dict(self):
        """Test ingest with a valid log event dictionary."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_log_event = MagicMock()

        mock_pb2.LogEvent.return_value = mock_log_event
        mock_pb2.IngestRequest.return_value = mock_request
        mock_stub.Ingest.return_value = mock_response

        event_dict = {
            "timestamp": "2024-01-01T00:00:00Z",
            "level": "INFO",
            "message": "Agent started successfully",
            "correlation_id": "corr-1",
            "agent_id": "agent-1",
            "metadata": {"component": "scheduler"}
        }

        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.ingest(event_dict)

        # Assert
        mock_pb2.LogEvent.assert_called_once_with(**event_dict)
        mock_pb2.IngestRequest.assert_called_once_with(event=mock_log_event)
        mock_stub.Ingest.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_ingest_with_minimal_event(self):
        """Test ingest with minimal required fields."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_log_event = MagicMock()

        mock_pb2.LogEvent.return_value = mock_log_event
        mock_pb2.IngestRequest.return_value = mock_request
        mock_stub.Ingest.return_value = mock_response

        event_dict = {
            "timestamp": "2024-01-01T00:00:00Z",
            "level": "INFO",
            "message": "Test log"
        }

        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.ingest(event_dict)

        # Assert
        mock_pb2.LogEvent.assert_called_once_with(**event_dict)
        assert result == mock_response

    def test_ingest_with_different_log_levels(self):
        """Test ingest with different log levels."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_log_event = MagicMock()

        mock_pb2.LogEvent.return_value = mock_log_event
        mock_pb2.IngestRequest.return_value = mock_request
        mock_stub.Ingest.return_value = mock_response

        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        log_levels = ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]

        # Act & Assert
        for i, level in enumerate(log_levels):
            event_dict = {
                "timestamp": "2024-01-01T00:00:00Z",
                "level": level,
                "message": f"Test log at {level} level"
            }
            result = client.ingest(event_dict)
            assert result == mock_response

        assert mock_stub.Ingest.call_count == 5
        assert mock_pb2.LogEvent.call_count == 5

    def test_ingest_with_error_event(self):
        """Test ingest with an error log event."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_log_event = MagicMock()

        mock_pb2.LogEvent.return_value = mock_log_event
        mock_pb2.IngestRequest.return_value = mock_request
        mock_stub.Ingest.return_value = mock_response

        event_dict = {
            "timestamp": "2024-01-01T00:00:00Z",
            "level": "ERROR",
            "message": "Task execution failed",
            "correlation_id": "corr-1",
            "agent_id": "agent-1",
            "metadata": {
                "error_code": "TASK_TIMEOUT",
                "stack_trace": "...",
                "task_id": "task-1"
            }
        }

        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.ingest(event_dict)

        # Assert
        mock_pb2.LogEvent.assert_called_once_with(**event_dict)
        assert result == mock_response

    def test_ingest_with_structured_metadata(self):
        """Test ingest with structured metadata."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_log_event = MagicMock()

        mock_pb2.LogEvent.return_value = mock_log_event
        mock_pb2.IngestRequest.return_value = mock_request
        mock_stub.Ingest.return_value = mock_response

        event_dict = {
            "timestamp": "2024-01-01T00:00:00Z",
            "level": "INFO",
            "message": "Task completed",
            "correlation_id": "corr-1",
            "agent_id": "agent-1",
            "metadata": {
                "task_id": "task-1",
                "duration_ms": 5000,
                "success": True,
                "output": {"result": "completed"},
                "tags": ["production", "critical"]
            }
        }

        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.ingest(event_dict)

        # Assert
        mock_pb2.LogEvent.assert_called_once_with(**event_dict)
        assert result == mock_response

    def test_ingest_with_stub_none_raises_runtime_error(self):
        """Test ingest raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)
        client._stub = None

        event_dict = {
            "timestamp": "2024-01-01T00:00:00Z",
            "level": "INFO",
            "message": "Test log"
        }

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.ingest(event_dict)

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestLoggingClientIntegration:
    """Integration-style tests for LoggingClient."""

    def test_multiple_log_events_in_sequence(self):
        """Test ingesting multiple log events in sequence."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        events = [
            {
                "timestamp": f"2024-01-01T00:00:{i:02d}Z",
                "level": "INFO",
                "message": f"Event {i}"
            }
            for i in range(5)
        ]

        # Act
        for event in events:
            client.ingest(event)

        # Assert
        assert mock_stub.Ingest.call_count == 5
        assert mock_pb2.LogEvent.call_count == 5

    def test_log_event_lifecycle_for_task(self):
        """Test logging lifecycle events for a task execution."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        task_id = "task-1"
        correlation_id = "corr-1"

        # Act
        # Task started
        client.ingest({
            "timestamp": "2024-01-01T00:00:00Z",
            "level": "INFO",
            "message": f"Task {task_id} started",
            "correlation_id": correlation_id,
            "metadata": {"task_id": task_id, "event_type": "started"}
        })

        # Task progress
        client.ingest({
            "timestamp": "2024-01-01T00:00:05Z",
            "level": "INFO",
            "message": f"Task {task_id} in progress",
            "correlation_id": correlation_id,
            "metadata": {"task_id": task_id, "event_type": "progress", "percent": 50}
        })

        # Task completed
        client.ingest({
            "timestamp": "2024-01-01T00:00:10Z",
            "level": "INFO",
            "message": f"Task {task_id} completed",
            "correlation_id": correlation_id,
            "metadata": {"task_id": task_id, "event_type": "completed"}
        })

        # Assert
        assert mock_stub.Ingest.call_count == 3
        assert mock_pb2.LogEvent.call_count == 3
        assert mock_pb2.IngestRequest.call_count == 3

    def test_concurrent_agent_logging(self):
        """Test logging from multiple agents."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.logging import LoggingClient
        client = LoggingClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        agent_ids = ["agent-1", "agent-2", "agent-3"]

        # Act
        for i, agent_id in enumerate(agent_ids):
            event = {
                "timestamp": "2024-01-01T00:00:00Z",
                "level": "INFO",
                "message": f"Log from {agent_id}",
                "agent_id": agent_id,
                "correlation_id": f"corr-{i}"
            }
            client.ingest(event)

        # Assert
        assert mock_stub.Ingest.call_count == 3
        assert mock_pb2.LogEvent.call_count == 3
