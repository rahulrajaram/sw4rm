from __future__ import annotations

from typing import Any


class LoggingClient:
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
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.IngestRequest(event=self._pb2.LogEvent(**event))
        return self._stub.Ingest(req)

