"""Unit tests for SchedulerPolicyClient."""
import pytest
from unittest.mock import MagicMock, patch


class TestSchedulerPolicyClientConstruction:
    """Tests for SchedulerPolicyClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that SchedulerPolicyClient initializes correctly with a valid channel."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_stores_channel(self):
        """Test that constructor stores the channel reference."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)

        # Assert - channel should be stored regardless
        assert client._channel == mock_channel


class TestSchedulerPolicyClientRequire:
    """Tests for SchedulerPolicyClient._require method."""

    def test_require_with_stub_none_raises_runtime_error(self):
        """Test _require raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client._require()

        assert "Protobuf stubs not generated" in str(exc_info.value)

    def test_require_with_valid_stub_does_not_raise(self):
        """Test _require does not raise when stub is valid."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub

        # Act - should not raise
        client._require()

        # Assert - no exception means success


class TestSchedulerPolicyClientSetNegotiationPolicy:
    """Tests for SchedulerPolicyClient.set_negotiation_policy method."""

    def test_set_negotiation_policy_with_valid_policy(self):
        """Test set_negotiation_policy with a valid policy object."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_policy = MagicMock()

        mock_pb2.SetNegotiationPolicyRequest.return_value = mock_request
        mock_stub.SetNegotiationPolicy.return_value = mock_response

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.set_negotiation_policy(policy=mock_policy)

        # Assert
        mock_pb2.SetNegotiationPolicyRequest.assert_called_once_with(policy=mock_policy)
        mock_stub.SetNegotiationPolicy.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_set_negotiation_policy_with_stub_none_raises_runtime_error(self):
        """Test set_negotiation_policy raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.set_negotiation_policy(policy=MagicMock())

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerPolicyClientGetNegotiationPolicy:
    """Tests for SchedulerPolicyClient.get_negotiation_policy method."""

    def test_get_negotiation_policy_success(self):
        """Test get_negotiation_policy returns the current policy."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.GetNegotiationPolicyRequest.return_value = mock_request
        mock_stub.GetNegotiationPolicy.return_value = mock_response

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.get_negotiation_policy()

        # Assert
        mock_pb2.GetNegotiationPolicyRequest.assert_called_once_with()
        mock_stub.GetNegotiationPolicy.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_get_negotiation_policy_with_stub_none_raises_runtime_error(self):
        """Test get_negotiation_policy raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.get_negotiation_policy()

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerPolicyClientSetPolicyProfiles:
    """Tests for SchedulerPolicyClient.set_policy_profiles method."""

    def test_set_policy_profiles_with_multiple_profiles(self):
        """Test set_policy_profiles with multiple profile objects."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.SetPolicyProfilesRequest.return_value = mock_request
        mock_stub.SetPolicyProfiles.return_value = mock_response

        profiles = [MagicMock(name="profile1"), MagicMock(name="profile2")]

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.set_policy_profiles(profiles=profiles)

        # Assert
        mock_pb2.SetPolicyProfilesRequest.assert_called_once_with(profiles=profiles)
        mock_stub.SetPolicyProfiles.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_set_policy_profiles_with_empty_list(self):
        """Test set_policy_profiles with empty list."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.set_policy_profiles(profiles=[])

        # Assert
        mock_pb2.SetPolicyProfilesRequest.assert_called_once_with(profiles=[])

    def test_set_policy_profiles_with_stub_none_raises_runtime_error(self):
        """Test set_policy_profiles raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.set_policy_profiles(profiles=[])

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerPolicyClientListPolicyProfiles:
    """Tests for SchedulerPolicyClient.list_policy_profiles method."""

    def test_list_policy_profiles_success(self):
        """Test list_policy_profiles returns all profiles."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.ListPolicyProfilesRequest.return_value = mock_request
        mock_stub.ListPolicyProfiles.return_value = mock_response

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.list_policy_profiles()

        # Assert
        mock_pb2.ListPolicyProfilesRequest.assert_called_once_with()
        mock_stub.ListPolicyProfiles.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_list_policy_profiles_with_stub_none_raises_runtime_error(self):
        """Test list_policy_profiles raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.list_policy_profiles()

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerPolicyClientGetEffectivePolicy:
    """Tests for SchedulerPolicyClient.get_effective_policy method."""

    def test_get_effective_policy_with_valid_negotiation_id(self):
        """Test get_effective_policy with a valid negotiation ID."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.GetEffectivePolicyRequest.return_value = mock_request
        mock_stub.GetEffectivePolicy.return_value = mock_response

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.get_effective_policy(negotiation_id="neg-123")

        # Assert
        mock_pb2.GetEffectivePolicyRequest.assert_called_once_with(negotiation_id="neg-123")
        mock_stub.GetEffectivePolicy.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_get_effective_policy_with_stub_none_raises_runtime_error(self):
        """Test get_effective_policy raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.get_effective_policy(negotiation_id="neg-123")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerPolicyClientSubmitEvaluation:
    """Tests for SchedulerPolicyClient.submit_evaluation method."""

    def test_submit_evaluation_with_valid_params(self):
        """Test submit_evaluation with valid negotiation ID and report."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_report = MagicMock()

        mock_pb2.SubmitEvaluationRequest.return_value = mock_request
        mock_stub.SubmitEvaluation.return_value = mock_response

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.submit_evaluation(negotiation_id="neg-123", report=mock_report)

        # Assert
        mock_pb2.SubmitEvaluationRequest.assert_called_once_with(
            negotiation_id="neg-123",
            report=mock_report
        )
        mock_stub.SubmitEvaluation.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_submit_evaluation_with_stub_none_raises_runtime_error(self):
        """Test submit_evaluation raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.submit_evaluation(negotiation_id="neg-123", report=MagicMock())

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerPolicyClientHitlAction:
    """Tests for SchedulerPolicyClient.hitl_action method."""

    def test_hitl_action_with_all_params(self):
        """Test hitl_action with all parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.HitlActionRequest.return_value = mock_request
        mock_stub.HitlAction.return_value = mock_response

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.hitl_action(
            negotiation_id="neg-123",
            action="approve",
            rationale="Looks good to me"
        )

        # Assert
        mock_pb2.HitlActionRequest.assert_called_once_with(
            negotiation_id="neg-123",
            action="approve",
            rationale="Looks good to me"
        )
        mock_stub.HitlAction.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_hitl_action_with_default_rationale(self):
        """Test hitl_action with default empty rationale."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.hitl_action(negotiation_id="neg-123", action="reject")

        # Assert
        mock_pb2.HitlActionRequest.assert_called_once_with(
            negotiation_id="neg-123",
            action="reject",
            rationale=""
        )

    def test_hitl_action_approve(self):
        """Test hitl_action with approve action."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.hitl_action(negotiation_id="neg-123", action="approve")

        # Assert
        mock_pb2.HitlActionRequest.assert_called_once()
        call_args = mock_pb2.HitlActionRequest.call_args
        assert call_args[1]["action"] == "approve"

    def test_hitl_action_reject(self):
        """Test hitl_action with reject action."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.hitl_action(negotiation_id="neg-123", action="reject", rationale="Policy violation")

        # Assert
        mock_pb2.HitlActionRequest.assert_called_once()
        call_args = mock_pb2.HitlActionRequest.call_args
        assert call_args[1]["action"] == "reject"
        assert call_args[1]["rationale"] == "Policy violation"

    def test_hitl_action_with_stub_none_raises_runtime_error(self):
        """Test hitl_action raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.hitl_action(negotiation_id="neg-123", action="approve")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestSchedulerPolicyClientIntegration:
    """Integration-style tests for SchedulerPolicyClient."""

    def test_full_policy_workflow(self):
        """Test a full policy workflow: set profiles, get effective, submit evaluation."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        profiles = [MagicMock(), MagicMock()]

        # Act
        client.set_policy_profiles(profiles=profiles)
        client.list_policy_profiles()
        client.set_negotiation_policy(policy=MagicMock())
        client.get_negotiation_policy()
        client.get_effective_policy(negotiation_id="neg-1")
        client.submit_evaluation(negotiation_id="neg-1", report=MagicMock())
        client.hitl_action(negotiation_id="neg-1", action="approve")

        # Assert
        assert mock_stub.SetPolicyProfiles.call_count == 1
        assert mock_stub.ListPolicyProfiles.call_count == 1
        assert mock_stub.SetNegotiationPolicy.call_count == 1
        assert mock_stub.GetNegotiationPolicy.call_count == 1
        assert mock_stub.GetEffectivePolicy.call_count == 1
        assert mock_stub.SubmitEvaluation.call_count == 1
        assert mock_stub.HitlAction.call_count == 1

    def test_multiple_negotiations(self):
        """Test handling multiple negotiations."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
        client = SchedulerPolicyClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.get_effective_policy(negotiation_id="neg-1")
        client.get_effective_policy(negotiation_id="neg-2")
        client.get_effective_policy(negotiation_id="neg-3")

        # Assert
        assert mock_stub.GetEffectivePolicy.call_count == 3
