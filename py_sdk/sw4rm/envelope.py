import time
import uuid
from typing import Optional


def new_uuid() -> str:
    return str(uuid.uuid4())


def now_hlc_stub() -> str:
    # Placeholder for HLC; using unix ms as string here.
    return str(int(time.time() * 1000))


def make_idempotency_token(producer_id: str, operation_type: str, deterministic_hash: str) -> str:
    return f"{producer_id}:{operation_type}:{deterministic_hash}"


class SequenceTracker:
    def __init__(self, start: int = 1) -> None:
        self._seq = start - 1

    def next(self) -> int:
        self._seq += 1
        return self._seq


def build_envelope(
    *,
    producer_id: str,
    message_type: int,
    content_type: str = "application/json",
    payload: bytes = b"",
    correlation_id: Optional[str] = None,
    sequence_number: Optional[int] = None,
    retry_count: int = 0,
    idempotency_token: Optional[str] = None,
    repo_id: Optional[str] = None,
    worktree_id: Optional[str] = None,
    ttl_ms: Optional[int] = None,
) -> dict:
    # Returns a plain dict compatible with sw4rm.common.Envelope fields.
    # Callers can adapt this to the generated protobuf class if available.
    env = {
        "message_id": new_uuid(),
        "idempotency_token": idempotency_token or "",
        "producer_id": producer_id,
        "correlation_id": correlation_id or new_uuid(),
        "sequence_number": sequence_number or 1,
        "retry_count": retry_count,
        "message_type": message_type,
        "content_type": content_type,
        "content_length": len(payload) if payload else 0,
        "repo_id": repo_id or "",
        "worktree_id": worktree_id or "",
        "hlc_timestamp": now_hlc_stub(),
        "ttl_ms": ttl_ms or 0,
        # timestamp and payload are set by the sender or router in real impl
        "payload": payload,
    }
    return env

