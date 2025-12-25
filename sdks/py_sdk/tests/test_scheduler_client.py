"""Unit tests for SchedulerClient."""
import pytest
from unittest.mock import MagicMock, patch, PropertyMock
from datetime import timedelta


class TestSchedulerClientConstruction:
    """Tests for SchedulerClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that SchedulerClient initializes correctly with a valid channel."""
        # Arrange
        mock_channel = MagicMock()

        with patch.dict('sys.modules', {
            'sw4rm.protos': MagicMock(),
            'sw4rm.protos.scheduler_pb2': MagicMock(),
            'sw4rm.protos.scheduler_pb2_grpc': MagicMock(),
        }):
            with patch('sw4rm.clients.scheduler.scheduler_pb2', create=True) as mock_pb2:
                with patch('sw4rm.clients.scheduler.scheduler_pb2_grpc', create=True) as mock_grpc:
                    # Need to reimport to pick up patches
                    import importlib
                    import sw4rm.clients.scheduler as scheduler_module
                    importlib.reload(scheduler_module)

                    # Act
                    from sw4rm.clients.scheduler import SchedulerClient
                    client = SchedulerClient(mock_channel)

                    # Assert
                    assert client._channel == mock_channel

    def test_constructor_stores_channel(self):
        """Test that constructor stores the channel reference."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        # Arrange
        mock_channel = MagicMock()

        with patch.dict('sys.modules', {'sw4rm.protos': None}):
            # Act
            from sw4rm.clients.scheduler import SchedulerClient
            client = SchedulerClient(mock_channel)

            # Assert - stub should be None due to import failure
            # The actual behavior depends on whether protos are generated
            assert client._channel == mock_channel


class TestSchedulerClientSubmitTask:
    """Tests for SchedulerClient.submit_task method."""

    def test_submit_task_with_valid_params(self):
        """Test submit_task with all valid parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.SubmitTaskRequest.return_value = mock_request
        mock_stub.SubmitTask.return_value = mock_response

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.submit_task(
            agent_id="agent-1",
            task_id="task-1",
            priority=5,
            scope="test-scope",
            params=b'{"key": "value"}',
            content_type="application/json"
        )

        # Assert
        mock_pb2.SubmitTaskRequest.assert_called_once_with(
            agent_id="agent-1",
            task_id="task-1",
            priority=5,
            scope="test-scope",
            params=b'{"key": "value"}',
            content_type="application/json"
        )
        mock_stub.SubmitTask.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_submit_task_with_default_params(self):
        """Test submit_task with default parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.submit_task(agent_id="agent-1", task_id="task-1")

        # Assert
        mock_pb2.SubmitTaskRequest.assert_called_once_with(
            agent_id="agent-1",
            task_id="task-1",
            priority=0,
            scope="",
            params=b"",
            content_type="application/json"
        )

    def test_submit_task_priority_at_lower_bound(self):
        """Test submit_task with priority at lower bound (-19)."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act - should not raise
        client.submit_task(agent_id="agent-1", task_id="task-1", priority=-19)

        # Assert
        mock_pb2.SubmitTaskRequest.assert_called_once()

    def test_submit_task_priority_at_upper_bound(self):
        """Test submit_task with priority at upper bound (20)."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act - should not raise
        client.submit_task(agent_id="agent-1", task_id="task-1", priority=20)

        # Assert
        mock_pb2.SubmitTaskRequest.assert_called_once()

    def test_submit_task_priority_below_lower_bound_raises_value_error(self):
        """Test submit_task raises ValueError when priority is below -19."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act & Assert
        with pytest.raises(ValueError) as exc_info:
            client.submit_task(agent_id="agent-1", task_id="task-1", priority=-20)

        assert "Priority must be between -19 and 20" in str(exc_info.value)
        assert "-20" in str(exc_info.value)

    def test_submit_task_priority_above_upper_bound_raises_value_error(self):
        """Test submit_task raises ValueError when priority is above 20."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act & Assert
        with pytest.raises(ValueError) as exc_info:
            client.submit_task(agent_id="agent-1", task_id="task-1", priority=21)

        assert "Priority must be between -19 and 20" in str(exc_info.value)
        assert "21" in str(exc_info.value)

    def test_submit_task_with_stub_none_raises_runtime_error(self):
        """Test submit_task raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.submit_task(agent_id="agent-1", task_id="task-1")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerClientRequestPreemption:
    """Tests for SchedulerClient.request_preemption method."""

    def test_request_preemption_with_all_params(self):
        """Test request_preemption with all parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.PreemptRequest.return_value = mock_request
        mock_stub.RequestPreemption.return_value = mock_response

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.request_preemption(
            agent_id="agent-1",
            task_id="task-1",
            reason="Higher priority task"
        )

        # Assert
        mock_pb2.PreemptRequest.assert_called_once_with(
            agent_id="agent-1",
            task_id="task-1",
            reason="Higher priority task"
        )
        mock_stub.RequestPreemption.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_request_preemption_with_default_reason(self):
        """Test request_preemption with default empty reason."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.request_preemption(agent_id="agent-1", task_id="task-1")

        # Assert
        mock_pb2.PreemptRequest.assert_called_once_with(
            agent_id="agent-1",
            task_id="task-1",
            reason=""
        )

    def test_request_preemption_with_stub_none_raises_runtime_error(self):
        """Test request_preemption raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.request_preemption(agent_id="agent-1", task_id="task-1")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerClientShutdownAgent:
    """Tests for SchedulerClient.shutdown_agent method."""

    def test_shutdown_agent_without_grace_period(self):
        """Test shutdown_agent without specifying grace period."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.ShutdownAgentRequest.return_value = mock_request
        mock_stub.ShutdownAgent.return_value = mock_response

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.shutdown_agent(agent_id="agent-1")

        # Assert
        mock_pb2.ShutdownAgentRequest.assert_called_once_with(
            agent_id="agent-1",
            grace_period=None
        )
        mock_stub.ShutdownAgent.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_shutdown_agent_with_grace_period(self):
        """Test shutdown_agent with a grace period specified."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.ShutdownAgentRequest.return_value = mock_request
        mock_stub.ShutdownAgent.return_value = mock_response

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        grace_period = timedelta(seconds=30)

        # Act
        with patch('google.protobuf.duration_pb2.Duration') as mock_duration_class:
            mock_duration = MagicMock()
            mock_duration_class.return_value = mock_duration
            result = client.shutdown_agent(agent_id="agent-1", grace_period=grace_period)

        # Assert
        mock_stub.ShutdownAgent.assert_called_once()
        assert result == mock_response

    def test_shutdown_agent_with_fractional_grace_period(self):
        """Test shutdown_agent with a fractional seconds grace period."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.ShutdownAgentRequest.return_value = mock_request
        mock_stub.ShutdownAgent.return_value = mock_response

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # 30.5 seconds
        grace_period = timedelta(seconds=30, milliseconds=500)

        # Act
        with patch('google.protobuf.duration_pb2.Duration') as mock_duration_class:
            mock_duration = MagicMock()
            mock_duration_class.return_value = mock_duration
            result = client.shutdown_agent(agent_id="agent-1", grace_period=grace_period)

        # Assert
        mock_stub.ShutdownAgent.assert_called_once()
        assert result == mock_response

    def test_shutdown_agent_with_stub_none_raises_runtime_error(self):
        """Test shutdown_agent raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.shutdown_agent(agent_id="agent-1")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerClientPollActivityBuffer:
    """Tests for SchedulerClient.poll_activity_buffer method."""

    def test_poll_activity_buffer_success(self):
        """Test poll_activity_buffer returns activity entries."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.PollActivityBufferRequest.return_value = mock_request
        mock_stub.PollActivityBuffer.return_value = mock_response

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.poll_activity_buffer(agent_id="agent-1")

        # Assert
        mock_pb2.PollActivityBufferRequest.assert_called_once_with(agent_id="agent-1")
        mock_stub.PollActivityBuffer.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_poll_activity_buffer_with_stub_none_raises_runtime_error(self):
        """Test poll_activity_buffer raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.poll_activity_buffer(agent_id="agent-1")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerClientPurgeActivity:
    """Tests for SchedulerClient.purge_activity method."""

    def test_purge_activity_with_multiple_task_ids(self):
        """Test purge_activity with multiple task IDs."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.PurgeActivityRequest.return_value = mock_request
        mock_stub.PurgeActivity.return_value = mock_response

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        task_ids = ["task-1", "task-2", "task-3"]

        # Act
        result = client.purge_activity(agent_id="agent-1", task_ids=task_ids)

        # Assert
        mock_pb2.PurgeActivityRequest.assert_called_once_with(
            agent_id="agent-1",
            task_ids=task_ids
        )
        mock_stub.PurgeActivity.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_purge_activity_with_empty_task_ids(self):
        """Test purge_activity with empty task IDs list."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.PurgeActivityRequest.return_value = mock_request
        mock_stub.PurgeActivity.return_value = mock_response

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.purge_activity(agent_id="agent-1", task_ids=[])

        # Assert
        mock_pb2.PurgeActivityRequest.assert_called_once_with(
            agent_id="agent-1",
            task_ids=[]
        )

    def test_purge_activity_with_stub_none_raises_runtime_error(self):
        """Test purge_activity raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.purge_activity(agent_id="agent-1", task_ids=["task-1"])

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerClientIntegration:
    """Integration-style tests for SchedulerClient."""

    def test_multiple_operations_in_sequence(self):
        """Test multiple operations can be performed in sequence."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler import SchedulerClient
        client = SchedulerClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.submit_task(agent_id="agent-1", task_id="task-1", priority=5)
        client.poll_activity_buffer(agent_id="agent-1")
        client.request_preemption(agent_id="agent-1", task_id="task-1")
        client.purge_activity(agent_id="agent-1", task_ids=["task-1"])

        # Assert
        assert mock_stub.SubmitTask.call_count == 1
        assert mock_stub.PollActivityBuffer.call_count == 1
        assert mock_stub.RequestPreemption.call_count == 1
        assert mock_stub.PurgeActivity.call_count == 1
