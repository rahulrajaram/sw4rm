from __future__ import annotations

from typing import Any


class LoggingClient:
    """Client for the SW4RM Logging Service.

    Provides centralized log ingestion for agent activities. Log events are
    structured with correlation IDs for tracing across distributed agent
    interactions.

    Attributes:
        _channel: gRPC channel for service communication
        _stub: Generated gRPC stub for LoggingService
    """

    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import logging_pb2, logging_pb2_grpc  # type: ignore
            self._pb2 = logging_pb2
            self._stub = logging_pb2_grpc.LoggingServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def ingest(self, event: Any) -> Any:
        """Ingest a log event into the logging service.

        Args:
            event: A ``LogEvent`` message, or a dict with ``LogEvent``
                fields (``ts`` — a ``google.protobuf.Timestamp``,
                ``correlation_id``, ``agent_id``, ``event_type``,
                ``level`` — INFO|WARN|ERROR, ``details_json``).

        Returns:
            IngestResponse with the acknowledgment (``ok``).
        """
        self._require()
        if not isinstance(event, self._pb2.LogEvent):
            event = self._pb2.LogEvent(**event)
        return self._stub.Ingest(event)

    def _require(self) -> None:
        if not self._stub:
            raise RuntimeError(
                "Protobuf stubs not generated for logging. Run protoc to generate sw4rm/protos/*_pb2.py"
            )
