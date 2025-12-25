from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Dict, Optional, Any, List
from collections import deque

from . import constants as C
from .persistence import PersistenceBackend, JSONFilePersistence, PersistentActivityRecord
from .buffer_strategy import BufferStrategy, DEFAULT_BUFFER_STRATEGY


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
    """In-memory activity buffer with configurable pruning strategy.

    Tracks inbound/outbound envelopes by message_id and records ACK progression.
    Supports Three-ID model: deduplication via idempotency_token, workflow linking
    via correlation_id, and per-attempt tracking via message_id.

    Not thread-safe; callers should synchronize if used across threads.
    """

    def __init__(
        self,
        *,
        max_items: int = 1000,
        strategy: Optional[BufferStrategy] = None,
        dedup_window_s: int = 3600
    ) -> None:
        self._by_id: Dict[str, ActivityRecord] = {}
        self._by_idempotency_token: Dict[str, str] = {}  # token -> message_id
        self._order: deque[str] = deque()
        self._max_items = max_items
        self.strategy = strategy or DEFAULT_BUFFER_STRATEGY
        self.dedup_window_s = dedup_window_s  # Default: 1 hour per spec §11.1

    def _prune_if_needed(self) -> None:
        excess = max(0, len(self._order) - self._max_items)
        if excess > 0:
            victims = self.strategy.victims(list(self._order), excess)
            for victim_id in victims:
                if victim_id in self._by_id:
                    # Clean up idempotency token mapping
                    rec = self._by_id[victim_id]
                    token = rec.idempotency_token
                    if token and token in self._by_idempotency_token:
                        if self._by_idempotency_token[token] == victim_id:
                            del self._by_idempotency_token[token]
                    del self._by_id[victim_id]
                # Remove from order deque
                try:
                    self._order.remove(victim_id)
                except ValueError:
                    pass  # Item may have been removed already

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
        rec = ActivityRecord(message_id=mid, direction="in", envelope=envelope)
        self._by_id[mid] = rec
        self._order.append(mid)

        # Track idempotency token for deduplication
        token = rec.idempotency_token
        if token:
            self._by_idempotency_token[token] = mid

        self._prune_if_needed()
        self._cleanup_expired_dedup_entries()
        return rec

    def record_outgoing(self, envelope: Dict[str, Any]) -> ActivityRecord:
        mid = str(envelope.get("message_id"))
        rec = ActivityRecord(message_id=mid, direction="out", envelope=envelope)
        self._by_id[mid] = rec
        self._order.append(mid)

        # Track idempotency token for deduplication
        token = rec.idempotency_token
        if token:
            self._by_idempotency_token[token] = mid

        self._prune_if_needed()
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
        ids = self._order[-n:]
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
        max_items: int = 1000,
        persistence: Optional[PersistenceBackend] = None,
        strategy: Optional[BufferStrategy] = None,
        dedup_window_s: int = 3600
    ):
        self._by_id: Dict[str, PersistentActivityRecord] = {}
        self._by_idempotency_token: Dict[str, str] = {}  # token -> message_id
        self._order: deque[str] = deque()
        self._max_items = max_items
        self._persistence = persistence or JSONFilePersistence()
        self.strategy = strategy or DEFAULT_BUFFER_STRATEGY
        self.dedup_window_s = dedup_window_s
        self._dirty = False  # Track if we need to save

        # Load existing data on initialization
        self._load_from_persistence()

    def _load_from_persistence(self) -> None:
        """Load activity records from persistent storage."""
        try:
            records_data, order = self._persistence.load_records()

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
            self._prune_if_needed()

            print(f"[ActivityBuffer] Loaded {len(self._by_id)} records from persistence")
        except Exception as e:
            print(f"[ActivityBuffer] Failed to load from persistence: {e}")
            self._by_id = {}
            self._by_idempotency_token = {}
            self._order = deque()

    def _save_to_persistence(self) -> None:
        """Save current state to persistent storage."""
        if not self._dirty:
            return
            
        try:
            records_data = {mid: rec.to_dict() for mid, rec in self._by_id.items()}
            self._persistence.save_records(records_data, list(self._order))
            self._dirty = False
        except Exception as e:
            print(f"[ActivityBuffer] Failed to save to persistence: {e}")

    def _prune_if_needed(self) -> None:
        """Remove records using configured strategy when we exceed max_items."""
        excess = max(0, len(self._order) - self._max_items)
        if excess > 0:
            victims = self.strategy.victims(list(self._order), excess)
            for victim_id in victims:
                if victim_id in self._by_id:
                    # Clean up idempotency token mapping
                    rec = self._by_id[victim_id]
                    token = rec.envelope.get("idempotency_token", "")
                    if token and token in self._by_idempotency_token:
                        if self._by_idempotency_token[token] == victim_id:
                            del self._by_idempotency_token[token]
                    del self._by_id[victim_id]
                # Remove from order deque
                try:
                    self._order.remove(victim_id)
                except ValueError:
                    pass  # Item may have been removed already
            self._dirty = True

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
        rec = PersistentActivityRecord(message_id=mid, direction="in", envelope=envelope)

        self._by_id[mid] = rec
        self._order.append(mid)

        # Track idempotency token for deduplication
        token = rec.envelope.get("idempotency_token", "")
        if token:
            self._by_idempotency_token[token] = mid

        self._prune_if_needed()
        self._cleanup_expired_dedup_entries()
        self._dirty = True

        return rec

    def record_outgoing(self, envelope: Dict[str, Any]) -> PersistentActivityRecord:
        """Record an outgoing message envelope."""
        mid = str(envelope.get("message_id"))
        rec = PersistentActivityRecord(message_id=mid, direction="out", envelope=envelope)

        self._by_id[mid] = rec
        self._order.append(mid)

        # Track idempotency token for deduplication
        token = rec.envelope.get("idempotency_token", "")
        if token:
            self._by_idempotency_token[token] = mid

        self._prune_if_needed()
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
        ids = self._order[-n:]
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

