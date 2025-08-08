from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Dict, Optional, Any, List

from . import constants as C


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


class ActivityBuffer:
    """In-memory activity buffer with simple reconciliation.

    Tracks inbound/outbound envelopes by message_id and records ACK progression.
    Not thread-safe; callers should synchronize if used across threads.
    """

    def __init__(self, *, max_items: int = 1000) -> None:
        self._by_id: Dict[str, ActivityRecord] = {}
        self._order: List[str] = []
        self._max_items = max_items

    def _prune_if_needed(self) -> None:
        while len(self._order) > self._max_items:
            oldest = self._order.pop(0)
            self._by_id.pop(oldest, None)

    def record_incoming(self, envelope: Dict[str, Any]) -> ActivityRecord:
        mid = str(envelope.get("message_id"))
        rec = ActivityRecord(message_id=mid, direction="in", envelope=envelope)
        self._by_id[mid] = rec
        self._order.append(mid)
        self._prune_if_needed()
        return rec

    def record_outgoing(self, envelope: Dict[str, Any]) -> ActivityRecord:
        mid = str(envelope.get("message_id"))
        rec = ActivityRecord(message_id=mid, direction="out", envelope=envelope)
        self._by_id[mid] = rec
        self._order.append(mid)
        self._prune_if_needed()
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

