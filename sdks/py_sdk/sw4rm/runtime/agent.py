from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Optional, Iterable, ContextManager
import contextlib


@dataclass
class PreemptionState:
    requested: bool = False
    reason: str | None = None


class Agent:
    """Base Agent runtime skeleton.

    Subclass and implement the on_* hooks to handle messages.
    This skeleton does not open network connections; it is a scaffold
    for your business logic layered over the gRPC clients.
    """

    def __init__(self, agent_id: str, name: str) -> None:
        self.agent_id = agent_id
        self.name = name
        self._preemption = PreemptionState()

    # Lifecycle hooks
    def on_startup(self) -> None:
        pass

    def on_shutdown(self) -> None:
        pass

    # Message handling hooks (override as needed)
    def on_message(self, envelope: dict) -> None:
        pass

    def on_control(self, envelope: dict) -> None:
        # Handle preemption requests or shutdown controls
        msg = envelope
        if msg.get("content_type") == "application/json":
            try:
                import json
                body = json.loads(msg.get("payload", b""))
            except Exception:
                body = {}
            if body.get("type") == "PREEMPT_REQUEST":
                self._preemption.requested = True
                self._preemption.reason = body.get("reason")

    def on_tool_call(self, envelope: dict) -> None:
        pass

    def on_hitl(self, envelope: dict) -> None:
        pass

    # Cooperative preemption helpers
    def safe_point(self) -> bool:
        """Return True if preemption is requested and caller should yield."""
        return self._preemption.requested

    @contextlib.contextmanager
    def non_preemptible(self, *, deadline_ms: Optional[int] = None) -> ContextManager[None]:
        prev = self._preemption.requested
        try:
            # Mask preemption inside critical section (cooperative model)
            self._preemption.requested = False
            yield
        finally:
            # Restore request flag; scheduler may still enforce hard kill externally
            self._preemption.requested = prev

