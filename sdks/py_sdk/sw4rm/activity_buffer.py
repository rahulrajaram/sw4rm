from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Dict, Optional, Any, List
from collections import deque

from . import constants as C
from .exceptions import BufferFullError
from .persistence import (
    ActivityBufferLoadError,
    PersistenceBackend,
    JSONFilePersistence,
    PersistentActivityRecord,
)


def is_terminal_state(state: int) -> bool:
    """Check if an envelope state is terminal (no further transitions expected).

    Terminal states are: FULFILLED, REJECTED, FAILED, TIMED_OUT

    Args:
        state: Envelope state value

    Returns:
        True if state is terminal, False otherwise
    """
    return state in (
        C.FULFILLED_ENVELOPE,
        C.REJECTED_ENVELOPE,
        C.FAILED_ENVELOPE,
        C.TIMED_OUT_ENVELOPE,
    )


@dataclass
class ActivityRecord:
    message_id: str
    direction: str  # "in" | "out"
    envelope: Dict[str, Any]
    ts_ms: int = field(default_factory=lambda: int(time.time() * 1000))
    ack_stage: int = C.ACK_STAGE_UNSPECIFIED
    error_code: int = C.ERROR_CODE_UNSPECIFIED
    ack_note: str = ""

    def ack(self, stage: int, error_code: int = C.ERROR_CODE_UNSPECIFIED, note: str = "") -> None:
        self.ack_stage = stage
        self.error_code = error_code
        self.ack_note = note

    @property
    def state(self) -> int:
        """Get envelope state from the envelope dict."""
        return self.envelope.get("state", C.ENVELOPE_STATE_UNSPECIFIED)

    @property
    def idempotency_token(self) -> str:
        """Get idempotency token from the envelope dict."""
        return self.envelope.get("idempotency_token", "")

    @property
    def correlation_id(self) -> str:
        """Get correlation ID from the envelope dict."""
        return self.envelope.get("correlation_id", "")


class ActivityBuffer:
    """In-memory activity buffer.

    Capacity is enforced per spec 10.1: registrations beyond max_items are
    rejected with BufferFullError rather than silently evicted (no pluggable
    eviction API; fp-ds-certification#F6 remove branch).

    Tracks inbound/outbound envelopes by message_id and records ACK progression.
    Supports Three-ID model: deduplication via idempotency_token, workflow linking
    via correlation_id, and per-attempt tracking via message_id.

    Not thread-safe; callers should synchronize if used across threads.
    """

    def __init__(
        self,
        *,
        max_items: int = 10000,
        dedup_window_s: int = 3600
    ) -> None:
        self._by_id: Dict[str, ActivityRecord] = {}
        self._by_idempotency_token: Dict[str, str] = {}  # token -> message_id
        self._order: deque[str] = deque()
        self._max_items = max_items
        self.dedup_window_s = dedup_window_s  # Default: 1 hour per spec §11.1

    def _check_capacity(self) -> None:
        """Reject new entries when buffer is full per spec §10.1.

        Raises:
            BufferFullError: When buffer is at capacity
        """
        if len(self._by_id) >= self._max_items:
            raise BufferFullError(
                f"Activity buffer is full (max {self._max_items} items)",
                current_size=len(self._by_id),
                max_size=self._max_items,
            )

    def _cleanup_expired_dedup_entries(self) -> None:
        """Remove idempotency tokens for records outside dedup window."""
        now_ms = int(time.time() * 1000)
        window_ms = self.dedup_window_s * 1000

        # Find expired tokens
        expired_tokens = []
        for token, message_id in self._by_idempotency_token.items():
            rec = self._by_id.get(message_id)
            if rec and (now_ms - rec.ts_ms) > window_ms:
                expired_tokens.append(token)

        # Remove expired mappings
        for token in expired_tokens:
            del self._by_idempotency_token[token]

    def record_incoming(self, envelope: Dict[str, Any]) -> ActivityRecord:
        mid = str(envelope.get("message_id"))
        if mid not in self._by_id:
            self._check_capacity()
            self._order.append(mid)
        rec = ActivityRecord(message_id=mid, direction="in", envelope=envelope)
        self._by_id[mid] = rec

        # Track idempotency token for deduplication
        token = rec.idempotency_token
        if token:
            self._by_idempotency_token[token] = mid

        self._cleanup_expired_dedup_entries()
        return rec

    def record_outgoing(self, envelope: Dict[str, Any]) -> ActivityRecord:
        mid = str(envelope.get("message_id"))
        if mid not in self._by_id:
            self._check_capacity()
            self._order.append(mid)
        rec = ActivityRecord(message_id=mid, direction="out", envelope=envelope)
        self._by_id[mid] = rec

        # Track idempotency token for deduplication
        token = rec.idempotency_token
        if token:
            self._by_idempotency_token[token] = mid

        self._cleanup_expired_dedup_entries()
        return rec

    def ack(self, ack: Dict[str, Any]) -> Optional[ActivityRecord]:
        target = str(ack.get("ack_for_message_id"))
        rec = self._by_id.get(target)
        if rec:
            rec.ack(
                stage=int(ack.get("ack_stage", C.ACK_STAGE_UNSPECIFIED)),
                error_code=int(ack.get("error_code", C.ERROR_CODE_UNSPECIFIED)),
                note=str(ack.get("note", "")),
            )
        return rec

    def get(self, message_id: str) -> Optional[ActivityRecord]:
        return self._by_id.get(message_id)

    def unacked(self) -> List[ActivityRecord]:
        return [r for r in self._by_id.values() if r.ack_stage in (C.ACK_STAGE_UNSPECIFIED, C.RECEIVED, C.READ)]

    def recent(self, n: int = 50) -> List[ActivityRecord]:
        ids = list(self._order)[-n:] if n > 0 else []
        return [self._by_id[i] for i in ids if i in self._by_id]

    def update_state(self, message_id: str, new_state: int) -> Optional[ActivityRecord]:
        """Update the envelope state for a specific message.

        Args:
            message_id: The message_id of the envelope to update
            new_state: New envelope state (see constants.EnvelopeState)

        Returns:
            Updated ActivityRecord if found, None otherwise
        """
        rec = self._by_id.get(message_id)
        if rec:
            rec.envelope["state"] = new_state
        return rec

    def get_by_idempotency_token(self, token: str) -> Optional[ActivityRecord]:
        """Get an activity record by its idempotency token.

        Used for deduplication: check if an operation with this token
        has already been processed within the deduplication window.

        Args:
            token: Idempotency token to look up

        Returns:
            ActivityRecord if found and within dedup window, None otherwise

        Example:
            >>> # Check for duplicate before processing
            >>> existing = buffer.get_by_idempotency_token(token)
            >>> if existing and not is_terminal_state(existing.state):
            ...     # Duplicate in progress, reject or return cached result
            ...     return existing
        """
        self._cleanup_expired_dedup_entries()
        message_id = self._by_idempotency_token.get(token)
        if message_id:
            return self._by_id.get(message_id)
        return None


class PersistentActivityBuffer:
    """Activity buffer with persistent storage across restarts.

    Supports multiple persistence backends (JSON file, SQLite, etc.)
    and provides reconciliation on startup to restore previous state.
    Includes Three-ID support for deduplication and workflow tracking.
    """

    def __init__(
        self,
        *,
        max_items: int = 10000,
        persistence: Optional[PersistenceBackend] = None,
        dedup_window_s: int = 3600,
        load_failure_mode: str = "raise",
    ):
        self._by_id: Dict[str, PersistentActivityRecord] = {}
        self._by_idempotency_token: Dict[str, str] = {}  # token -> message_id
        self._order: deque[str] = deque()
        self._max_items = max_items
        self._persistence = persistence or JSONFilePersistence()
        self.dedup_window_s = dedup_window_s
        # "raise" (default): a corrupted persistence file fails startup loudly.
        # "empty": catch and start empty, logging a degraded-mode warning —
        # opt-in escape hatch for best-effort consumers; never silent.
        if load_failure_mode not in ("raise", "empty"):
            raise ValueError(
                f"load_failure_mode must be 'raise' or 'empty', got {load_failure_mode!r}"
            )
        self.load_failure_mode = load_failure_mode
        self._dirty = False  # Track if we need to save

        # Load existing data on initialization
        self._load_from_persistence()

    def _load_from_persistence(self) -> None:
        """Load activity records from persistent storage.

        A missing persistence file is a fresh start (no error). An
        unreadable/corrupted file raises ActivityBufferLoadError by
        default; with load_failure_mode="empty" it logs loudly and starts
        degraded (never silently).
        """
        try:
            records_data, order = self._persistence.load_records()
        except ActivityBufferLoadError:
            if self.load_failure_mode == "empty":
                import logging

                logging.getLogger(__name__).exception(
                    "[ActivityBuffer] CORRUPTED persistence; starting DEGRADED "
                    "with an empty buffer — recovery state was not restored"
                )
                self._by_id = {}
                self._by_idempotency_token = {}
                self._order = deque()
                return
            raise

        # Reconstruct activity records
        self._by_id = {}
        self._by_idempotency_token = {}
        for message_id, data in records_data.items():
            rec = PersistentActivityRecord.from_dict(data)
            self._by_id[message_id] = rec
            # Rebuild idempotency token index
            token = rec.envelope.get("idempotency_token", "")
            if token:
                self._by_idempotency_token[token] = message_id

        self._order = deque(order)
        if len(self._by_id) > self._max_items:
            self._check_capacity()

        print(f"[ActivityBuffer] Loaded {len(self._by_id)} records from persistence")

    def _save_to_persistence(self) -> None:
        """Save current state to persistent storage.

        Durability contract: save failures raise — silently swallowed save
        errors made the crash-recovery claim false.
        """
        if not self._dirty:
            return

        records_data = {mid: rec.to_dict() for mid, rec in self._by_id.items()}
        self._persistence.save_records(records_data, list(self._order))
        self._dirty = False

    def _check_capacity(self) -> None:
        """Reject new entries when buffer is full per spec §10.1.

        Raises:
            BufferFullError: When buffer is at capacity
        """
        if len(self._by_id) >= self._max_items:
            raise BufferFullError(
                f"Activity buffer is full (max {self._max_items} items)",
                current_size=len(self._by_id),
                max_size=self._max_items,
            )

    def _cleanup_expired_dedup_entries(self) -> None:
        """Remove idempotency tokens for records outside dedup window."""
        now_ms = int(time.time() * 1000)
        window_ms = self.dedup_window_s * 1000

        # Find expired tokens
        expired_tokens = []
        for token, message_id in self._by_idempotency_token.items():
            rec = self._by_id.get(message_id)
            if rec and (now_ms - rec.ts_ms) > window_ms:
                expired_tokens.append(token)

        # Remove expired mappings
        for token in expired_tokens:
            del self._by_idempotency_token[token]

        if expired_tokens:
            self._dirty = True

    def record_incoming(self, envelope: Dict[str, Any]) -> PersistentActivityRecord:
        """Record an incoming message envelope."""
        mid = str(envelope.get("message_id"))
        if mid not in self._by_id:
            self._check_capacity()
            self._order.append(mid)
        rec = PersistentActivityRecord(message_id=mid, direction="in", envelope=envelope)

        self._by_id[mid] = rec

        # Track idempotency token for deduplication
        token = rec.envelope.get("idempotency_token", "")
        if token:
            self._by_idempotency_token[token] = mid

        self._cleanup_expired_dedup_entries()
        self._dirty = True

        return rec

    def record_outgoing(self, envelope: Dict[str, Any]) -> PersistentActivityRecord:
        """Record an outgoing message envelope."""
        mid = str(envelope.get("message_id"))
        if mid not in self._by_id:
            self._check_capacity()
            self._order.append(mid)
        rec = PersistentActivityRecord(message_id=mid, direction="out", envelope=envelope)

        self._by_id[mid] = rec

        # Track idempotency token for deduplication
        token = rec.envelope.get("idempotency_token", "")
        if token:
            self._by_idempotency_token[token] = mid

        self._cleanup_expired_dedup_entries()
        self._dirty = True

        return rec

    def ack(self, ack: Dict[str, Any]) -> Optional[PersistentActivityRecord]:
        """Process an acknowledgment for a previously recorded message."""
        target = str(ack.get("ack_for_message_id"))
        rec = self._by_id.get(target)
        
        if rec:
            rec.ack(
                stage=int(ack.get("ack_stage", C.ACK_STAGE_UNSPECIFIED)),
                error_code=int(ack.get("error_code", C.ERROR_CODE_UNSPECIFIED)),
                note=str(ack.get("note", "")),
            )
            self._dirty = True
            
        return rec

    def get(self, message_id: str) -> Optional[PersistentActivityRecord]:
        """Get an activity record by message ID."""
        return self._by_id.get(message_id)

    def unacked(self) -> List[PersistentActivityRecord]:
        """Get all records that haven't been fully acknowledged."""
        return [r for r in self._by_id.values() 
                if r.ack_stage in (C.ACK_STAGE_UNSPECIFIED, C.RECEIVED, C.READ)]

    def recent(self, n: int = 50) -> List[PersistentActivityRecord]:
        """Get the N most recent activity records."""
        ids = list(self._order)[-n:] if n > 0 else []
        return [self._by_id[i] for i in ids if i in self._by_id]

    def flush(self) -> None:
        """Force save to persistent storage."""
        self._save_to_persistence()

    def reconcile(self) -> List[PersistentActivityRecord]:
        """Return unacked outgoing messages that may need retry/reconciliation."""
        unacked_outgoing = [
            rec for rec in self.unacked()
            if rec.direction == "out"
        ]
        return unacked_outgoing

    def update_state(self, message_id: str, new_state: int) -> Optional[PersistentActivityRecord]:
        """Update the envelope state for a specific message.

        Args:
            message_id: The message_id of the envelope to update
            new_state: New envelope state (see constants.EnvelopeState)

        Returns:
            Updated PersistentActivityRecord if found, None otherwise
        """
        rec = self._by_id.get(message_id)
        if rec:
            rec.envelope["state"] = new_state
            self._dirty = True
        return rec

    def get_by_idempotency_token(self, token: str) -> Optional[PersistentActivityRecord]:
        """Get an activity record by its idempotency token.

        Used for deduplication: check if an operation with this token
        has already been processed within the deduplication window.

        Args:
            token: Idempotency token to look up

        Returns:
            PersistentActivityRecord if found and within dedup window, None otherwise
        """
        self._cleanup_expired_dedup_entries()
        message_id = self._by_idempotency_token.get(token)
        if message_id:
            return self._by_id.get(message_id)
        return None

    def clear(self) -> None:
        """Clear all activity records and persistent storage."""
        self._by_id.clear()
        self._by_idempotency_token.clear()
        self._order.clear()
        self._persistence.clear()
        self._dirty = False

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit - ensure data is saved."""
        self._save_to_persistence()

