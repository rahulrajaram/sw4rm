"""SW4-004 cancellation helpers for gateway implementations."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Callable, Iterable, Optional

from sw4rm.protos import common_pb2, handoff_pb2


MIN_GRACE_PERIOD_MS = 5000


@dataclass
class CancellationFlag:
    """Cancellation state for one delegation correlation."""

    cancelled: bool
    grace_period_ms: int
    cancel_time_ms: int


class CancellationManager:
    """Tracks cancellation state and grace-expiry preemption decisions."""

    def __init__(self, *, time_ms_fn: Optional[Callable[[], int]] = None) -> None:
        self._time_ms = time_ms_fn or (lambda: int(time.time() * 1000))
        self.child_delegations: dict[str, list[str]] = {}
        self.cancellation_flags: dict[str, CancellationFlag] = {}

    def register_child_delegation(
        self, parent_correlation_id: str, child_correlation_id: str
    ) -> None:
        """Link parent/child delegation ids for cancellation cascade."""
        self.child_delegations.setdefault(parent_correlation_id, []).append(
            child_correlation_id
        )

    def handle_cancel_delegation(
        self, cancel: handoff_pb2.CancelDelegation
    ) -> handoff_pb2.CancelDelegationResponse:
        """Set cancellation flags for correlation and any known children."""
        grace_period_ms = max(int(cancel.grace_period_ms), MIN_GRACE_PERIOD_MS)
        cancel_time_ms = self._time_ms()

        self.cancellation_flags[cancel.correlation_id] = CancellationFlag(
            cancelled=True,
            grace_period_ms=grace_period_ms,
            cancel_time_ms=cancel_time_ms,
        )

        for child_corr in self.child_delegations.get(cancel.correlation_id, []):
            self.cancellation_flags[child_corr] = CancellationFlag(
                cancelled=True,
                grace_period_ms=grace_period_ms,
                cancel_time_ms=cancel_time_ms,
            )

        return handoff_pb2.CancelDelegationResponse(acknowledged=True)

    def is_cancelled(self, correlation_id: str) -> bool:
        """Return True when a cancellation flag exists and is active."""
        entry = self.cancellation_flags.get(correlation_id)
        return bool(entry and entry.cancelled)

    def is_grace_expired(
        self, correlation_id: str, *, now_ms: Optional[int] = None
    ) -> bool:
        """Return True when cancellation grace period has elapsed."""
        entry = self.cancellation_flags.get(correlation_id)
        if entry is None or not entry.cancelled:
            return False
        current_ms = self._time_ms() if now_ms is None else now_ms
        return (current_ms - entry.cancel_time_ms) >= entry.grace_period_ms

    def forced_preemption_error_code(
        self, correlation_id: str, *, now_ms: Optional[int] = None
    ) -> int:
        """Return FORCED_PREEMPTION once grace expires, otherwise unspecified."""
        if self.is_grace_expired(correlation_id, now_ms=now_ms):
            return common_pb2.FORCED_PREEMPTION
        return common_pb2.ERROR_CODE_UNSPECIFIED

    def collect_forced_preemptions(
        self, correlation_ids: Iterable[str], *, now_ms: Optional[int] = None
    ) -> set[str]:
        """Return cancelled correlations whose grace period has expired."""
        current_ms = self._time_ms() if now_ms is None else now_ms
        forced: set[str] = set()
        for correlation_id in correlation_ids:
            if self.is_grace_expired(correlation_id, now_ms=current_ms):
                forced.add(correlation_id)
        return forced
