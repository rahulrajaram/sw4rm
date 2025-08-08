from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Optional


class LoggingClient:
    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from agentos.protos import logging_pb2, logging_pb2_grpc  # type: ignore
            self._pb2 = logging_pb2
            self._stub = logging_pb2_grpc.LoggingServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def ingest(
        self,
        correlation_id: str,
        agent_id: str,
        event_type: str,
        level: str,
        details_json: str,
        ts: Optional[datetime] = None,
    ) -> Any:
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")

        ts_msg = self._pb2.google_dot_protobuf_dot_timestamp__pb2.Timestamp()
        ts_msg.FromDatetime((ts or datetime.now(timezone.utc)).astimezone(timezone.utc))

        req = self._pb2.LogEvent(
            ts=ts_msg,
            correlation_id=correlation_id,
            agent_id=agent_id,
            event_type=event_type,
            level=level,
            details_json=details_json,
        )
        return self._stub.Ingest(req)

