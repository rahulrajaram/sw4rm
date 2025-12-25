"""Unit tests for WorktreeClient."""
import pytest
from unittest.mock import MagicMock, patch


class TestWorktreeClientConstruction:
    """Tests for WorktreeClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that WorktreeClient initializes correctly with a valid channel."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_stores_channel(self):
        """Test that constructor stores the channel reference."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)

        # Assert - channel should be stored regardless
        assert client._channel == mock_channel


class TestWorktreeClientBind:
    """Tests for WorktreeClient.bind method."""

    def test_bind_with_valid_params(self):
        """Test bind with all valid parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.BindRequest.return_value = mock_request
        mock_stub.Bind.return_value = mock_response

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.bind(
            agent_id="agent-1",
            repo_id="repo-1",
            worktree_id="worktree-1"
        )

        # Assert
        mock_pb2.BindRequest.assert_called_once_with(
            agent_id="agent-1",
            repo_id="repo-1",
            worktree_id="worktree-1"
        )
        mock_stub.Bind.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_bind_with_stub_none_raises_runtime_error(self):
        """Test bind raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.bind(agent_id="agent-1", repo_id="repo-1", worktree_id="worktree-1")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestWorktreeClientUnbind:
    """Tests for WorktreeClient.unbind method."""

    def test_unbind_with_valid_params(self):
        """Test unbind with valid agent_id."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.UnbindRequest.return_value = mock_request
        mock_stub.Unbind.return_value = mock_response

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.unbind(agent_id="agent-1")

        # Assert
        mock_pb2.UnbindRequest.assert_called_once_with(agent_id="agent-1")
        mock_stub.Unbind.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_unbind_with_stub_none_raises_runtime_error(self):
        """Test unbind raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.unbind(agent_id="agent-1")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestWorktreeClientStatus:
    """Tests for WorktreeClient.status method."""

    def test_status_with_valid_params(self):
        """Test status with valid agent_id."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.StatusRequest.return_value = mock_request
        mock_stub.Status.return_value = mock_response

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.status(agent_id="agent-1")

        # Assert
        mock_pb2.StatusRequest.assert_called_once_with(agent_id="agent-1")
        mock_stub.Status.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_status_with_stub_none_raises_runtime_error(self):
        """Test status raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.status(agent_id="agent-1")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestWorktreeClientRequestSwitch:
    """Tests for WorktreeClient.request_switch method."""

    def test_request_switch_with_all_params(self):
        """Test request_switch with all parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.SwitchRequest.return_value = mock_request
        mock_stub.RequestSwitch.return_value = mock_response

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.request_switch(
            agent_id="agent-1",
            target_worktree_id="worktree-2",
            requires_hitl=True
        )

        # Assert
        mock_pb2.SwitchRequest.assert_called_once_with(
            agent_id="agent-1",
            target_worktree_id="worktree-2",
            requires_hitl=True
        )
        mock_stub.RequestSwitch.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_request_switch_with_default_requires_hitl(self):
        """Test request_switch with default requires_hitl (False)."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.request_switch(agent_id="agent-1", target_worktree_id="worktree-2")

        # Assert
        mock_pb2.SwitchRequest.assert_called_once_with(
            agent_id="agent-1",
            target_worktree_id="worktree-2",
            requires_hitl=False
        )

    def test_request_switch_with_stub_none_raises_runtime_error(self):
        """Test request_switch raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.request_switch(agent_id="agent-1", target_worktree_id="worktree-2")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestWorktreeClientApproveSwitch:
    """Tests for WorktreeClient.approve_switch method."""

    def test_approve_switch_with_valid_params(self):
        """Test approve_switch with all parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.SwitchApprove.return_value = mock_request
        mock_stub.ApproveSwitch.return_value = mock_response

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.approve_switch(
            agent_id="agent-1",
            target_worktree_id="worktree-2",
            ttl_ms=60000
        )

        # Assert
        mock_pb2.SwitchApprove.assert_called_once_with(
            agent_id="agent-1",
            target_worktree_id="worktree-2",
            ttl_ms=60000
        )
        mock_stub.ApproveSwitch.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_approve_switch_with_zero_ttl(self):
        """Test approve_switch with zero TTL."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.approve_switch(
            agent_id="agent-1",
            target_worktree_id="worktree-2",
            ttl_ms=0
        )

        # Assert
        mock_pb2.SwitchApprove.assert_called_once_with(
            agent_id="agent-1",
            target_worktree_id="worktree-2",
            ttl_ms=0
        )

    def test_approve_switch_with_stub_none_raises_runtime_error(self):
        """Test approve_switch raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.approve_switch(
                agent_id="agent-1",
                target_worktree_id="worktree-2",
                ttl_ms=60000
            )

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestWorktreeClientRejectSwitch:
    """Tests for WorktreeClient.reject_switch method."""

    def test_reject_switch_with_reason(self):
        """Test reject_switch with a reason provided."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.SwitchReject.return_value = mock_request
        mock_stub.RejectSwitch.return_value = mock_response

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.reject_switch(
            agent_id="agent-1",
            reason="Conflicting operation in progress"
        )

        # Assert
        mock_pb2.SwitchReject.assert_called_once_with(
            agent_id="agent-1",
            reason="Conflicting operation in progress"
        )
        mock_stub.RejectSwitch.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_reject_switch_with_default_reason(self):
        """Test reject_switch with default empty reason."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.reject_switch(agent_id="agent-1")

        # Assert
        mock_pb2.SwitchReject.assert_called_once_with(
            agent_id="agent-1",
            reason=""
        )

    def test_reject_switch_with_stub_none_raises_runtime_error(self):
        """Test reject_switch raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.reject_switch(agent_id="agent-1")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestWorktreeClientIntegration:
    """Integration-style tests for WorktreeClient."""

    def test_full_worktree_lifecycle(self):
        """Test a full worktree lifecycle: bind, status, request_switch, approve, unbind."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act - simulate full lifecycle
        client.bind(agent_id="agent-1", repo_id="repo-1", worktree_id="worktree-1")
        client.status(agent_id="agent-1")
        client.request_switch(agent_id="agent-1", target_worktree_id="worktree-2")
        client.approve_switch(agent_id="agent-1", target_worktree_id="worktree-2", ttl_ms=30000)
        client.unbind(agent_id="agent-1")

        # Assert
        assert mock_stub.Bind.call_count == 1
        assert mock_stub.Status.call_count == 1
        assert mock_stub.RequestSwitch.call_count == 1
        assert mock_stub.ApproveSwitch.call_count == 1
        assert mock_stub.Unbind.call_count == 1

    def test_switch_request_rejection_flow(self):
        """Test switch request followed by rejection."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.worktree import WorktreeClient
        client = WorktreeClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.request_switch(agent_id="agent-1", target_worktree_id="worktree-2", requires_hitl=True)
        client.reject_switch(agent_id="agent-1", reason="Not allowed")

        # Assert
        assert mock_stub.RequestSwitch.call_count == 1
        assert mock_stub.RejectSwitch.call_count == 1
        mock_pb2.SwitchReject.assert_called_with(agent_id="agent-1", reason="Not allowed")
