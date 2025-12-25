"""Unit tests for HitlClient."""
import pytest
from unittest.mock import MagicMock, patch


class TestHitlClientConstruction:
    """Tests for HitlClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that HitlClient initializes correctly with a valid channel."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.hitl import HitlClient
        client = HitlClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_stores_channel(self):
        """Test that constructor stores the channel reference."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.hitl import HitlClient
        client = HitlClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        # Arrange
        mock_channel = MagicMock()

        with patch.dict('sys.modules', {'sw4rm.protos': None}):
            # Act
            from sw4rm.clients.hitl import HitlClient
            client = HitlClient(mock_channel)

            # Assert - stub should be None due to import failure
            assert client._channel == mock_channel
            assert client._stub is None
            assert client._pb2 is None


class TestHitlClientDecide:
    """Tests for HitlClient.decide method."""

    def test_decide_with_invocation_dict(self):
        """Test decide with a valid invocation dictionary."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_invocation = MagicMock()

        mock_pb2.HitlInvocation.return_value = mock_invocation
        mock_pb2.DecideRequest.return_value = mock_request
        mock_stub.Decide.return_value = mock_response

        invocation_dict = {
            "correlation_id": "corr-1",
            "reason_type": "LOW_CONFIDENCE",
            "context": "Need human review",
            "options": ["approve", "reject"]
        }

        from sw4rm.clients.hitl import HitlClient
        client = HitlClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.decide(invocation_dict)

        # Assert
        mock_pb2.HitlInvocation.assert_called_once_with(**invocation_dict)
        mock_pb2.DecideRequest.assert_called_once_with(invocation=mock_invocation)
        mock_stub.Decide.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_decide_with_minimal_invocation(self):
        """Test decide with minimal required fields."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_invocation = MagicMock()

        mock_pb2.HitlInvocation.return_value = mock_invocation
        mock_pb2.DecideRequest.return_value = mock_request
        mock_stub.Decide.return_value = mock_response

        invocation_dict = {"correlation_id": "corr-1"}

        from sw4rm.clients.hitl import HitlClient
        client = HitlClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.decide(invocation_dict)

        # Assert
        mock_pb2.HitlInvocation.assert_called_once_with(**invocation_dict)
        assert result == mock_response

    def test_decide_with_multiple_options(self):
        """Test decide with multiple decision options."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_invocation = MagicMock()

        mock_pb2.HitlInvocation.return_value = mock_invocation
        mock_pb2.DecideRequest.return_value = mock_request
        mock_stub.Decide.return_value = mock_response

        invocation_dict = {
            "correlation_id": "corr-1",
            "reason_type": "HIGH_RISK_OPERATION",
            "context": "Risky transaction",
            "options": ["approve", "reject", "modify", "escalate_to_manager"]
        }

        from sw4rm.clients.hitl import HitlClient
        client = HitlClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.decide(invocation_dict)

        # Assert
        mock_pb2.HitlInvocation.assert_called_once_with(**invocation_dict)
        assert result == mock_response

    def test_decide_with_rich_context(self):
        """Test decide with detailed context information."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_invocation = MagicMock()

        mock_pb2.HitlInvocation.return_value = mock_invocation
        mock_pb2.DecideRequest.return_value = mock_request
        mock_stub.Decide.return_value = mock_response

        invocation_dict = {
            "correlation_id": "corr-1",
            "reason_type": "POLICY_REQUIRES_HUMAN_APPROVAL",
            "context": "Transaction exceeds approval threshold",
            "options": ["approve", "reject"],
            "metadata": {
                "amount": 10000,
                "currency": "USD",
                "requester": "user-123"
            }
        }

        from sw4rm.clients.hitl import HitlClient
        client = HitlClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.decide(invocation_dict)

        # Assert
        mock_pb2.HitlInvocation.assert_called_once_with(**invocation_dict)
        assert result == mock_response

    def test_decide_with_stub_none_raises_runtime_error(self):
        """Test decide raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.hitl import HitlClient
        client = HitlClient(mock_channel)
        client._stub = None

        invocation_dict = {"correlation_id": "corr-1"}

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.decide(invocation_dict)

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestHitlClientIntegration:
    """Integration-style tests for HitlClient."""

    def test_multiple_hitl_invocations_in_sequence(self):
        """Test multiple HITL invocations in sequence."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.hitl import HitlClient
        client = HitlClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        invocations = [
            {"correlation_id": f"corr-{i}", "reason_type": "LOW_CONFIDENCE"}
            for i in range(3)
        ]

        # Act
        for invocation in invocations:
            client.decide(invocation)

        # Assert
        assert mock_stub.Decide.call_count == 3
        assert mock_pb2.HitlInvocation.call_count == 3

    def test_different_reason_types(self):
        """Test HITL invocations with different reason types."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.hitl import HitlClient
        client = HitlClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        reason_types = [
            "LOW_CONFIDENCE",
            "HIGH_RISK_OPERATION",
            "POLICY_REQUIRES_HUMAN_APPROVAL",
            "ANOMALY_DETECTED"
        ]

        # Act
        for i, reason_type in enumerate(reason_types):
            invocation = {
                "correlation_id": f"corr-{i}",
                "reason_type": reason_type
            }
            client.decide(invocation)

        # Assert
        assert mock_stub.Decide.call_count == 4
        assert mock_pb2.HitlInvocation.call_count == 4
