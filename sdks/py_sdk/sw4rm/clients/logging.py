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

    def ingest(self, event: dict) -> Any:
        """Ingest a log event into the logging service.

        Args:
            event: Dictionary with LogEvent fields (timestamp, level, message,
                correlation_id, agent_id, metadata, etc.)

        Returns:
            IngestResponse with acknowledgment
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.IngestRequest(event=self._pb2.LogEvent(**event))
        return self._stub.Ingest(req)

