"""Agent handoff protocol for SW4RM.

This module provides the infrastructure for agents to hand off tasks
to other agents, including context preservation and capability matching.
"""

from __future__ import annotations

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
from sw4rm.handoff.client import HandoffClient

__all__ = [
    "HandoffRequest",
    "HandoffResponse",
    "HandoffStatus",
    "HandoffContext",
    "serialize_context",
    "deserialize_context",
    "HandoffClient",
]
