"""Agent handoff protocol for SW4RM.

This module provides the infrastructure for agents to hand off tasks
to other agents, including context preservation and capability matching.

Note: HandoffClient has been moved to sw4rm.clients for API consistency.
Importing from this module still works but is deprecated.

Preferred usage:
    from sw4rm.clients import HandoffClient

Deprecated usage (will show warning):
    from sw4rm.handoff import HandoffClient
"""

from __future__ import annotations

import warnings

from sw4rm.handoff.types import (
    HandoffRequest,
    HandoffResponse,
    HandoffStatus,
)
from sw4rm.handoff.context import (
    HandoffContext,
    serialize_context,
    deserialize_context,
)

__all__ = [
    "HandoffRequest",
    "HandoffResponse",
    "HandoffStatus",
    "HandoffContext",
    "serialize_context",
    "deserialize_context",
    "HandoffClient",  # Deprecated: use sw4rm.clients.HandoffClient
]


def __getattr__(name: str):
    """Provide HandoffClient with deprecation warning."""
    if name == "HandoffClient":
        warnings.warn(
            "Importing HandoffClient from sw4rm.handoff is deprecated. "
            "Use: from sw4rm.clients import HandoffClient",
            DeprecationWarning,
            stacklevel=2
        )
        from sw4rm.clients.handoff import HandoffClient
        return HandoffClient
    raise AttributeError(f"module {__name__!r} has no attribute {name!r}")
