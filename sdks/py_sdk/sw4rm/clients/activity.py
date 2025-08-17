from __future__ import annotations

from typing import Any


class ActivityClient:
    """Client for ActivityService to append/list artifacts."""

    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import activity_pb2, activity_pb2_grpc  # type: ignore
            self._pb2 = activity_pb2
            self._stub = activity_pb2_grpc.ActivityServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def _require(self) -> None:
        if not self._stub:
            raise RuntimeError(
                "Protobuf stubs not generated for activity. Run protoc to generate sw4rm/protos/*_pb2.py"
            )

    def append_artifact(self, negotiation_id: str, kind: str, version: str, content_type: str, content: bytes, created_at: str) -> Any:
        self._require()
        artifact = self._pb2.Artifact(
            negotiation_id=negotiation_id,
            kind=kind,
            version=version,
            content_type=content_type,
            content=content,
            created_at=created_at,
        )
        req = self._pb2.AppendArtifactRequest(artifact=artifact)
        return self._stub.AppendArtifact(req)

    def list_artifacts(self, negotiation_id: str, kind: str | None = None) -> Any:
        self._require()
        req = self._pb2.ListArtifactsRequest(negotiation_id=negotiation_id, kind=kind or "")
        return self._stub.ListArtifacts(req)

