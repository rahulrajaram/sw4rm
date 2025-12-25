"""Envelope construction and manipulation utilities.

The Three-ID Envelope Model tracks message lifecycle with three distinct identifiers:

1. **message_id**: Unique per delivery attempt (UUID). Changes on retry.
   - Purpose: Tracks individual message instances through the transport layer
   - Scope: Single delivery attempt
   - Generation: New UUID for each attempt

2. **correlation_id**: Workflow/session scope identifier (UUID).
   - Purpose: Links related messages in a conversation or workflow
   - Scope: Entire workflow or session
   - Generation: New UUID for new workflows, copied from parent for related messages

3. **idempotency_token**: Deterministic token for deduplication.
   - Purpose: Enables detection of duplicate operations across retries
   - Scope: Logical operation (stable across retries)
   - Format: {producer_id}:{operation_type}:{deterministic_hash}
   - Generation: Computed from canonical operation parameters

Envelope State Lifecycle:
- CREATED: Envelope created but not yet sent
- PENDING: Sent and awaiting acknowledgment
- RUNNING: Operation in progress
- FULFILLED: Successfully completed
- REJECTED: Explicitly rejected by recipient
- FAILED: Failed due to error
- TIMED_OUT: Exceeded TTL or timeout threshold
"""
import hashlib
import json
import time
import uuid
from typing import Any, Optional

from . import constants as C


def new_uuid() -> str:
    return str(uuid.uuid4())


def now_hlc_stub() -> str:
    # Placeholder for HLC; using unix ms as string here.
    return str(int(time.time() * 1000))


def compute_deterministic_hash(params: dict[str, Any]) -> str:
    """Compute deterministic hash from canonical operation parameters.

    Args:
        params: Dictionary of parameters that uniquely identify the operation.
                Should include all fields that distinguish this operation from others.

    Returns:
        Hexadecimal SHA256 hash of the canonicalized parameters.

    Example:
        >>> params = {"tool": "git_commit", "repo": "myrepo", "files": ["a.py"]}
        >>> hash1 = compute_deterministic_hash(params)
        >>> hash2 = compute_deterministic_hash(params)
        >>> hash1 == hash2
        True
    """
    # Canonicalize: sort keys, use compact JSON encoding
    canonical = json.dumps(params, sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(canonical.encode('utf-8')).hexdigest()[:16]


def make_idempotency_token(producer_id: str, operation_type: str, deterministic_hash: str) -> str:
    """Create idempotency token in the format: {producer_id}:{operation_type}:{deterministic_hash}.

    Args:
        producer_id: ID of the agent/service producing the message
        operation_type: Type of operation (e.g., "tool_call", "task_submit")
        deterministic_hash: Hash computed from canonical operation parameters

    Returns:
        Formatted idempotency token

    Example:
        >>> token = make_idempotency_token("agent-1", "git_commit", "abc123")
        >>> token
        'agent-1:git_commit:abc123'
    """
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
    state: int = C.CREATED,
    effective_policy_id: Optional[str] = None,
    audit_proof: Optional[bytes] = None,
    audit_policy_id: Optional[str] = None,
) -> dict:
    """Build a message envelope with Three-ID model support.

    Args:
        producer_id: ID of the producing agent/service
        message_type: Type of message (see constants.MessageType)
        content_type: MIME type of payload (default: "application/json")
        payload: Message payload bytes
        correlation_id: Workflow/session identifier (auto-generated if None)
        sequence_number: Sequence number for ordering (default: 1)
        retry_count: Number of retry attempts (default: 0)
        idempotency_token: Stable token for deduplication (optional)
        repo_id: Repository identifier (optional)
        worktree_id: Worktree identifier (optional)
        ttl_ms: Time-to-live in milliseconds (default: 0 = no expiry)
        state: Initial envelope state (default: CREATED)
        effective_policy_id: ID of the effective policy governing this operation.
            Should be attached when:
            - Initiating a negotiation (policy governs negotiation behavior)
            - Submitting tasks for execution (policy governs execution constraints)
            - When policy context is required for processing/auditing
        audit_proof: Optional cryptographic proof for audit trail (bytes)
        audit_policy_id: Optional ID of the audit policy governing this envelope

    Returns:
        Dictionary compatible with sw4rm.common.Envelope protobuf message

    Note:
        - message_id is always auto-generated (new UUID per attempt)
        - correlation_id is auto-generated if not provided
        - For retry scenarios: keep correlation_id and idempotency_token,
          but increment retry_count and let message_id regenerate
    """
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
        "state": state,
        "effective_policy_id": effective_policy_id or "",
        # timestamp and payload are set by the sender or router in real impl
        "payload": payload,
        "audit_proof": audit_proof or b"",
        "audit_policy_id": audit_policy_id or "",
    }
    return env


def update_envelope_state(envelope: dict, new_state: int) -> dict:
    """Update the state of an envelope.

    Args:
        envelope: Envelope dictionary
        new_state: New state value (see constants.EnvelopeState)

    Returns:
        Updated envelope (same object, modified in place)

    Example:
        >>> env = build_envelope(producer_id="agent-1", message_type=C.DATA)
        >>> env = update_envelope_state(env, C.PENDING)
        >>> env["state"] == C.PENDING
        True
    """
    envelope["state"] = new_state
    return envelope


def is_terminal_state(state: int) -> bool:
    """Check if an envelope state is terminal (no further transitions expected).

    Terminal states are: FULFILLED, REJECTED, FAILED, TIMED_OUT

    Args:
        state: Envelope state value

    Returns:
        True if state is terminal, False otherwise

    Example:
        >>> is_terminal_state(C.FULFILLED_ENVELOPE)
        True
        >>> is_terminal_state(C.PENDING)
        False
    """
    return state in (
        C.FULFILLED_ENVELOPE,
        C.REJECTED_ENVELOPE,
        C.FAILED_ENVELOPE,
        C.TIMED_OUT_ENVELOPE,
    )

