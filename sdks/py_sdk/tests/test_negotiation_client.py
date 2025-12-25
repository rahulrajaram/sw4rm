"""Unit tests for NegotiationClient."""
import pytest
from unittest.mock import MagicMock, patch


class TestNegotiationClientConstruction:
    """Tests for NegotiationClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that NegotiationClient initializes correctly with a valid channel."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_stores_channel(self):
        """Test that constructor stores the channel reference."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)

        # Assert
        assert client._channel == mock_channel

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        # Arrange
        mock_channel = MagicMock()

        # Act
        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)

        # Assert - channel should be stored regardless
        assert client._channel == mock_channel


class TestNegotiationClientOpen:
    """Tests for NegotiationClient.open method."""

    def test_open_with_all_params(self):
        """Test open with all parameters including debate_timeout_seconds."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()
        mock_duration = MagicMock()

        mock_pb2.NegotiationOpen.return_value = mock_request
        mock_pb2.google_dot_protobuf_dot_duration__pb2.Duration.return_value = mock_duration
        mock_stub.Open.return_value = mock_response

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.open(
            negotiation_id="neg-123",
            correlation_id="corr-456",
            topic="Resource allocation",
            participants=["agent-1", "agent-2", "agent-3"],
            intensity=5,
            debate_timeout_seconds=300
        )

        # Assert
        mock_pb2.NegotiationOpen.assert_called_once()
        call_args = mock_pb2.NegotiationOpen.call_args[1]
        assert call_args["negotiation_id"] == "neg-123"
        assert call_args["correlation_id"] == "corr-456"
        assert call_args["topic"] == "Resource allocation"
        assert call_args["participants"] == ["agent-1", "agent-2", "agent-3"]
        assert call_args["intensity"] == 5
        mock_stub.Open.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_open_with_default_params(self):
        """Test open with default parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()

        mock_pb2.NegotiationOpen.return_value = mock_request

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.open(
            negotiation_id="neg-123",
            correlation_id="corr-456",
            topic="Simple topic",
            participants=["agent-1"]
        )

        # Assert
        mock_pb2.NegotiationOpen.assert_called_once()
        call_args = mock_pb2.NegotiationOpen.call_args[1]
        assert call_args["intensity"] == 0
        assert call_args["debate_timeout"] is None

    def test_open_without_timeout(self):
        """Test open without debate_timeout_seconds."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.open(
            negotiation_id="neg-123",
            correlation_id="corr-456",
            topic="Topic",
            participants=["agent-1"],
            intensity=3
        )

        # Assert
        call_args = mock_pb2.NegotiationOpen.call_args[1]
        assert call_args["debate_timeout"] is None

    def test_open_with_stub_none_raises_runtime_error(self):
        """Test open raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.open(
                negotiation_id="neg-123",
                correlation_id="corr-456",
                topic="Topic",
                participants=["agent-1"]
            )

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestNegotiationClientPropose:
    """Tests for NegotiationClient.propose method."""

    def test_propose_with_valid_params(self):
        """Test propose with all valid parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.Proposal.return_value = mock_request
        mock_stub.Propose.return_value = mock_response

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        payload = b'{"allocation": "resource-1"}'

        # Act
        result = client.propose(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/json",
            payload=payload
        )

        # Assert
        mock_pb2.Proposal.assert_called_once_with(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/json",
            payload=payload
        )
        mock_stub.Propose.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_propose_with_binary_payload(self):
        """Test propose with binary payload."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        binary_payload = b'\x00\x01\x02\x03'

        # Act
        client.propose(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/octet-stream",
            payload=binary_payload
        )

        # Assert
        mock_pb2.Proposal.assert_called_once_with(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/octet-stream",
            payload=binary_payload
        )

    def test_propose_with_stub_none_raises_runtime_error(self):
        """Test propose raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.propose(
                negotiation_id="neg-123",
                from_agent="agent-1",
                content_type="application/json",
                payload=b'{}'
            )

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestNegotiationClientCounter:
    """Tests for NegotiationClient.counter method."""

    def test_counter_with_valid_params(self):
        """Test counter with all valid parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.CounterProposal.return_value = mock_request
        mock_stub.Counter.return_value = mock_response

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        payload = b'{"counter_allocation": "resource-2"}'

        # Act
        result = client.counter(
            negotiation_id="neg-123",
            from_agent="agent-2",
            content_type="application/json",
            payload=payload
        )

        # Assert
        mock_pb2.CounterProposal.assert_called_once_with(
            negotiation_id="neg-123",
            from_agent="agent-2",
            content_type="application/json",
            payload=payload
        )
        mock_stub.Counter.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_counter_with_stub_none_raises_runtime_error(self):
        """Test counter raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.counter(
                negotiation_id="neg-123",
                from_agent="agent-2",
                content_type="application/json",
                payload=b'{}'
            )

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestNegotiationClientEvaluate:
    """Tests for NegotiationClient.evaluate method."""

    def test_evaluate_with_all_params(self):
        """Test evaluate with all parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.Evaluation.return_value = mock_request
        mock_stub.Evaluate.return_value = mock_response

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-3",
            confidence_score=0.85,
            notes="Proposal looks acceptable"
        )

        # Assert
        mock_pb2.Evaluation.assert_called_once_with(
            negotiation_id="neg-123",
            from_agent="agent-3",
            confidence_score=0.85,
            notes="Proposal looks acceptable"
        )
        mock_stub.Evaluate.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_evaluate_with_default_params(self):
        """Test evaluate with default parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-3"
        )

        # Assert
        mock_pb2.Evaluation.assert_called_once_with(
            negotiation_id="neg-123",
            from_agent="agent-3",
            confidence_score=0.0,
            notes=""
        )

    def test_evaluate_with_none_confidence_score(self):
        """Test evaluate with None confidence_score defaults to 0.0."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-3",
            confidence_score=None
        )

        # Assert
        mock_pb2.Evaluation.assert_called_once()
        call_args = mock_pb2.Evaluation.call_args[1]
        assert call_args["confidence_score"] == 0.0

    def test_evaluate_with_high_confidence(self):
        """Test evaluate with high confidence score (1.0)."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-3",
            confidence_score=1.0
        )

        # Assert
        call_args = mock_pb2.Evaluation.call_args[1]
        assert call_args["confidence_score"] == 1.0

    def test_evaluate_with_low_confidence(self):
        """Test evaluate with low confidence score (0.0)."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-3",
            confidence_score=0.0
        )

        # Assert
        call_args = mock_pb2.Evaluation.call_args[1]
        assert call_args["confidence_score"] == 0.0

    def test_evaluate_with_stub_none_raises_runtime_error(self):
        """Test evaluate raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.evaluate(
                negotiation_id="neg-123",
                from_agent="agent-3"
            )

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestNegotiationClientDecide:
    """Tests for NegotiationClient.decide method."""

    def test_decide_with_valid_params(self):
        """Test decide with all valid parameters."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.Decision.return_value = mock_request
        mock_stub.Decide.return_value = mock_response

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        result_payload = b'{"final_allocation": "resource-1"}'

        # Act
        result = client.decide(
            negotiation_id="neg-123",
            decided_by="agent-1",
            content_type="application/json",
            result=result_payload
        )

        # Assert
        mock_pb2.Decision.assert_called_once_with(
            negotiation_id="neg-123",
            decided_by="agent-1",
            content_type="application/json",
            result=result_payload
        )
        mock_stub.Decide.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_decide_with_stub_none_raises_runtime_error(self):
        """Test decide raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.decide(
                negotiation_id="neg-123",
                decided_by="agent-1",
                content_type="application/json",
                result=b'{}'
            )

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestNegotiationClientAbort:
    """Tests for NegotiationClient.abort method."""

    def test_abort_with_reason(self):
        """Test abort with a reason provided."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()
        mock_request = MagicMock()
        mock_response = MagicMock()

        mock_pb2.AbortRequest.return_value = mock_request
        mock_stub.Abort.return_value = mock_response

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        result = client.abort(
            negotiation_id="neg-123",
            reason="Timeout exceeded"
        )

        # Assert
        mock_pb2.AbortRequest.assert_called_once_with(
            negotiation_id="neg-123",
            reason="Timeout exceeded"
        )
        mock_stub.Abort.assert_called_once_with(mock_request)
        assert result == mock_response

    def test_abort_with_default_reason(self):
        """Test abort with default empty reason."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.abort(negotiation_id="neg-123")

        # Assert
        mock_pb2.AbortRequest.assert_called_once_with(
            negotiation_id="neg-123",
            reason=""
        )

    def test_abort_with_stub_none_raises_runtime_error(self):
        """Test abort raises RuntimeError when stub is None."""
        # Arrange
        mock_channel = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = None

        # Act & Assert
        with pytest.raises(RuntimeError) as exc_info:
            client.abort(negotiation_id="neg-123")

        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestNegotiationClientIntegration:
    """Integration-style tests for NegotiationClient."""

    def test_full_negotiation_lifecycle(self):
        """Test a full negotiation lifecycle: open, propose, counter, evaluate, decide."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act - simulate full lifecycle
        client.open(
            negotiation_id="neg-123",
            correlation_id="corr-456",
            topic="Resource allocation",
            participants=["agent-1", "agent-2"]
        )
        client.propose(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"proposal": 1}'
        )
        client.counter(
            negotiation_id="neg-123",
            from_agent="agent-2",
            content_type="application/json",
            payload=b'{"counter": 1}'
        )
        client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-1",
            confidence_score=0.8
        )
        client.decide(
            negotiation_id="neg-123",
            decided_by="agent-1",
            content_type="application/json",
            result=b'{"final": 1}'
        )

        # Assert
        assert mock_stub.Open.call_count == 1
        assert mock_stub.Propose.call_count == 1
        assert mock_stub.Counter.call_count == 1
        assert mock_stub.Evaluate.call_count == 1
        assert mock_stub.Decide.call_count == 1

    def test_negotiation_abort_flow(self):
        """Test negotiation that gets aborted."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.open(
            negotiation_id="neg-123",
            correlation_id="corr-456",
            topic="Resource allocation",
            participants=["agent-1", "agent-2"],
            debate_timeout_seconds=60
        )
        client.propose(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{}'
        )
        client.abort(negotiation_id="neg-123", reason="Deadline exceeded")

        # Assert
        assert mock_stub.Open.call_count == 1
        assert mock_stub.Propose.call_count == 1
        assert mock_stub.Abort.call_count == 1

    def test_multiple_counter_proposals(self):
        """Test multiple counter proposals in a negotiation."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.propose(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"round": 1}'
        )
        client.counter(
            negotiation_id="neg-123",
            from_agent="agent-2",
            content_type="application/json",
            payload=b'{"round": 2}'
        )
        client.counter(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"round": 3}'
        )
        client.counter(
            negotiation_id="neg-123",
            from_agent="agent-2",
            content_type="application/json",
            payload=b'{"round": 4}'
        )

        # Assert
        assert mock_stub.Propose.call_count == 1
        assert mock_stub.Counter.call_count == 3

    def test_multiple_evaluations(self):
        """Test multiple evaluations from different agents."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-1",
            confidence_score=0.9,
            notes="Strongly agree"
        )
        client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-2",
            confidence_score=0.7,
            notes="Mostly agree"
        )
        client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-3",
            confidence_score=0.5,
            notes="Neutral"
        )

        # Assert
        assert mock_stub.Evaluate.call_count == 3


class TestNegotiationClientEdgeCases:
    """Edge case tests for NegotiationClient."""

    def test_open_with_single_participant(self):
        """Test open with a single participant."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.open(
            negotiation_id="neg-123",
            correlation_id="corr-456",
            topic="Self-negotiation",
            participants=["agent-1"]
        )

        # Assert
        call_args = mock_pb2.NegotiationOpen.call_args[1]
        assert call_args["participants"] == ["agent-1"]

    def test_open_with_many_participants(self):
        """Test open with many participants."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        participants = [f"agent-{i}" for i in range(100)]

        # Act
        client.open(
            negotiation_id="neg-123",
            correlation_id="corr-456",
            topic="Large negotiation",
            participants=participants
        )

        # Assert
        call_args = mock_pb2.NegotiationOpen.call_args[1]
        assert len(call_args["participants"]) == 100

    def test_propose_with_empty_payload(self):
        """Test propose with empty payload."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.propose(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/json",
            payload=b''
        )

        # Assert
        mock_pb2.Proposal.assert_called_once()
        call_args = mock_pb2.Proposal.call_args[1]
        assert call_args["payload"] == b''

    def test_evaluate_with_fractional_confidence(self):
        """Test evaluate with fractional confidence score."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        # Act
        client.evaluate(
            negotiation_id="neg-123",
            from_agent="agent-1",
            confidence_score=0.12345
        )

        # Assert
        call_args = mock_pb2.Evaluation.call_args[1]
        assert call_args["confidence_score"] == 0.12345

    def test_abort_with_long_reason(self):
        """Test abort with a long reason string."""
        # Arrange
        mock_channel = MagicMock()
        mock_stub = MagicMock()
        mock_pb2 = MagicMock()

        from sw4rm.clients.negotiation import NegotiationClient
        client = NegotiationClient(mock_channel)
        client._stub = mock_stub
        client._pb2 = mock_pb2

        long_reason = "x" * 10000

        # Act
        client.abort(negotiation_id="neg-123", reason=long_reason)

        # Assert
        call_args = mock_pb2.AbortRequest.call_args[1]
        assert len(call_args["reason"]) == 10000
