"""Tests for HitlClient against the real generated protobuf modules.

The gRPC stub is mocked at the RPC boundary only; request construction uses
the real ``sw4rm.protos.hitl_pb2`` messages so drift between the client and
the canonical protos fails here instead of at call time.
"""
import pytest
from unittest.mock import MagicMock, patch

from sw4rm.protos import common_pb2, hitl_pb2
from sw4rm.clients.hitl import HitlClient


class TestHitlClientConstruction:
    """Tests for HitlClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that HitlClient initializes correctly with a valid channel."""
        mock_channel = MagicMock()
        client = HitlClient(mock_channel)
        assert client._channel == mock_channel

    def test_constructor_loads_real_pb2(self):
        """Test that the constructor binds the real generated modules."""
        client = HitlClient(MagicMock())
        assert client._pb2 is hitl_pb2
        assert client._stub is not None

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        with patch.dict('sys.modules', {'sw4rm.protos': None}):
            client = HitlClient(MagicMock())
            assert client._stub is None
            assert client._pb2 is None


class TestHitlClientDecide:
    """Tests for HitlClient.decide method."""

    def test_decide_with_invocation_dict(self):
        """Test decide builds a real HitlInvocation from a dict."""
        stub = MagicMock()
        client = HitlClient(MagicMock())
        client._stub = stub

        result = client.decide({
            "reason_type": common_pb2.HitlReasonType.SECURITY_APPROVAL,
            "context": b"Need human review",
            "proposed_actions": ["approve", "reject"],
            "priority": 3,
        })

        sent = stub.Decide.call_args[0][0]
        assert isinstance(sent, hitl_pb2.HitlInvocation)
        assert sent.reason_type == common_pb2.HitlReasonType.SECURITY_APPROVAL
        assert sent.context == b"Need human review"
        assert list(sent.proposed_actions) == ["approve", "reject"]
        assert sent.priority == 3
        assert result is stub.Decide.return_value

    def test_decide_with_minimal_invocation(self):
        """Test decide with all fields defaulted."""
        stub = MagicMock()
        client = HitlClient(MagicMock())
        client._stub = stub

        client.decide({})

        sent = stub.Decide.call_args[0][0]
        assert isinstance(sent, hitl_pb2.HitlInvocation)
        assert sent.reason_type == common_pb2.HITL_REASON_UNSPECIFIED
        assert sent.priority == 0

    def test_decide_accepts_prebuilt_invocation(self):
        """Test decide passes a HitlInvocation through unchanged."""
        stub = MagicMock()
        client = HitlClient(MagicMock())
        client._stub = stub

        invocation = hitl_pb2.HitlInvocation(
            reason_type=common_pb2.HitlReasonType.CONFLICT,
            priority=1,
        )
        client.decide(invocation)

        sent = stub.Decide.call_args[0][0]
        assert sent is invocation

    def test_decide_rejects_unknown_fields(self):
        """Test decide fails loudly on fields that do not exist in the proto."""
        client = HitlClient(MagicMock())
        with pytest.raises(ValueError):
            client.decide({"correlation_id": "corr-1", "options": ["approve"]})

    def test_decide_with_stub_none_raises_runtime_error(self):
        """Test decide raises RuntimeError when stub is None."""
        client = HitlClient(MagicMock())
        client._stub = None
        client._pb2 = None

        with pytest.raises(RuntimeError) as exc_info:
            client.decide({})
        assert "Protobuf stubs not generated" in str(exc_info.value)


class TestHitlClientIntegration:
    """Integration-style tests for HitlClient."""

    def test_multiple_hitl_invocations_in_sequence(self):
        """Test multiple HITL invocations in sequence."""
        stub = MagicMock()
        client = HitlClient(MagicMock())
        client._stub = stub

        for i in range(3):
            client.decide({
                "reason_type": common_pb2.HitlReasonType.TASK_ESCALATION,
                "priority": i,
            })

        assert stub.Decide.call_count == 3
        sent = [call.args[0] for call in stub.Decide.call_args_list]
        assert [invocation.priority for invocation in sent] == [0, 1, 2]

    def test_different_reason_types(self):
        """Test HITL invocations across the canonical HitlReasonType enum."""
        stub = MagicMock()
        client = HitlClient(MagicMock())
        client._stub = stub

        reason_types = [
            common_pb2.HitlReasonType.CONFLICT,
            common_pb2.HitlReasonType.SECURITY_APPROVAL,
            common_pb2.HitlReasonType.TASK_ESCALATION,
            common_pb2.HitlReasonType.MANUAL_OVERRIDE,
            common_pb2.HitlReasonType.DEBATE_DEADLOCK,
        ]
        for reason_type in reason_types:
            client.decide({"reason_type": reason_type})

        assert stub.Decide.call_count == 5
        sent = [call.args[0].reason_type for call in stub.Decide.call_args_list]
        assert sent == reason_types
