"""Tests for LoggingClient against the real generated protobuf modules.

The gRPC stub is mocked at the RPC boundary only; request construction uses
the real ``sw4rm.protos.logging_pb2`` messages so drift between the client
and the canonical protos fails here instead of at call time.
"""
from datetime import datetime, timezone

from google.protobuf.timestamp_pb2 import Timestamp
from unittest.mock import MagicMock, patch

from sw4rm.protos import logging_pb2
from sw4rm.clients.logging import LoggingClient


def _ts(seconds: int) -> Timestamp:
    stamp = Timestamp()
    stamp.FromDatetime(datetime.fromtimestamp(seconds, tz=timezone.utc))
    return stamp


class TestLoggingClientConstruction:
    """Tests for LoggingClient constructor."""

    def test_constructor_with_valid_channel(self):
        """Test that LoggingClient initializes correctly with a valid channel."""
        mock_channel = MagicMock()
        client = LoggingClient(mock_channel)
        assert client._channel == mock_channel

    def test_constructor_loads_real_pb2(self):
        """Test that the constructor binds the real generated modules."""
        client = LoggingClient(MagicMock())
        assert client._pb2 is logging_pb2
        assert client._stub is not None

    def test_constructor_with_import_failure_sets_stub_none(self):
        """Test that stub is None when protobuf imports fail."""
        with patch.dict('sys.modules', {'sw4rm.protos': None}):
            client = LoggingClient(MagicMock())
            assert client._stub is None
            assert client._pb2 is None


class TestLoggingClientIngest:
    """Tests for LoggingClient.ingest method."""

    def test_ingest_with_log_event_dict(self):
        """Test ingest builds a real LogEvent from a dict."""
        stub = MagicMock()
        client = LoggingClient(MagicMock())
        client._stub = stub

        result = client.ingest({
            "ts": _ts(1704067200),
            "correlation_id": "corr-1",
            "agent_id": "agent-1",
            "event_type": "task_lifecycle",
            "level": "INFO",
            "details_json": '{"component": "scheduler"}',
        })

        sent = stub.Ingest.call_args[0][0]
        assert isinstance(sent, logging_pb2.LogEvent)
        assert sent.ts.ToDatetime().year == 2024
        assert sent.correlation_id == "corr-1"
        assert sent.agent_id == "agent-1"
        assert sent.event_type == "task_lifecycle"
        assert sent.level == "INFO"
        assert sent.details_json == '{"component": "scheduler"}'
        assert result is stub.Ingest.return_value

    def test_ingest_with_minimal_event(self):
        """Test ingest with all fields defaulted."""
        stub = MagicMock()
        client = LoggingClient(MagicMock())
        client._stub = stub

        client.ingest({})

        sent = stub.Ingest.call_args[0][0]
        assert isinstance(sent, logging_pb2.LogEvent)
        assert sent.level == ""
        assert not sent.ts.seconds

    def test_ingest_accepts_prebuilt_event(self):
        """Test ingest passes a LogEvent through unchanged."""
        stub = MagicMock()
        client = LoggingClient(MagicMock())
        client._stub = stub

        event = logging_pb2.LogEvent(level="WARN", agent_id="agent-2")
        client.ingest(event)

        sent = stub.Ingest.call_args[0][0]
        assert sent is event

    def test_ingest_rejects_unknown_fields(self):
        """Test ingest fails loudly on fields that do not exist in the proto."""
        client = LoggingClient(MagicMock())
        try:
            client.ingest({"message": "not a LogEvent field"})
        except ValueError:
            pass
        else:
            raise AssertionError("expected ValueError for unknown field")

    def test_ingest_with_different_log_levels(self):
        """Test ingest with the canonical INFO|WARN|ERROR levels."""
        stub = MagicMock()
        client = LoggingClient(MagicMock())
        client._stub = stub

        for level in ["INFO", "WARN", "ERROR"]:
            client.ingest({"level": level})

        sent = [call.args[0].level for call in stub.Ingest.call_args_list]
        assert sent == ["INFO", "WARN", "ERROR"]

    def test_ingest_with_stub_none_raises_runtime_error(self):
        """Test ingest raises RuntimeError when stub is None."""
        client = LoggingClient(MagicMock())
        client._stub = None
        client._pb2 = None

        try:
            client.ingest({})
        except RuntimeError as exc_info:
            assert "Protobuf stubs not generated" in str(exc_info)
        else:
            raise AssertionError("expected RuntimeError")


class TestLoggingClientIntegration:
    """Integration-style tests for LoggingClient."""

    def test_multiple_log_events_in_sequence(self):
        """Test ingesting multiple log events in sequence."""
        stub = MagicMock()
        client = LoggingClient(MagicMock())
        client._stub = stub

        for i in range(5):
            client.ingest({"correlation_id": f"corr-{i}", "level": "INFO"})

        assert stub.Ingest.call_count == 5
        sent = [call.args[0].correlation_id for call in stub.Ingest.call_args_list]
        assert sent == [f"corr-{i}" for i in range(5)]

    def test_log_event_lifecycle_for_task(self):
        """Test logging lifecycle events for a task execution."""
        stub = MagicMock()
        client = LoggingClient(MagicMock())
        client._stub = stub

        for event_type in ["started", "progress", "completed"]:
            client.ingest({
                "correlation_id": "corr-1",
                "agent_id": "agent-1",
                "event_type": event_type,
                "level": "INFO",
            })

        assert stub.Ingest.call_count == 3
        sent = [call.args[0].event_type for call in stub.Ingest.call_args_list]
        assert sent == ["started", "progress", "completed"]

    def test_concurrent_agent_logging(self):
        """Test logging from multiple agents."""
        stub = MagicMock()
        client = LoggingClient(MagicMock())
        client._stub = stub

        for i, agent_id in enumerate(["agent-1", "agent-2", "agent-3"]):
            client.ingest({"agent_id": agent_id, "correlation_id": f"corr-{i}"})

        assert stub.Ingest.call_count == 3
        sent = [call.args[0].agent_id for call in stub.Ingest.call_args_list]
        assert sent == ["agent-1", "agent-2", "agent-3"]
