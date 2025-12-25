"""Types for the agent handoff protocol.

This module defines the core data structures used in agent-to-agent handoffs.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional, Any


class HandoffStatus(Enum):
    """Status of a handoff request.

    Attributes:
        PENDING: Handoff has been requested but not yet accepted or rejected
        ACCEPTED: Handoff has been accepted by the target agent
        REJECTED: Handoff has been rejected by the target agent
        COMPLETED: Handoff has been completed successfully
    """
    PENDING = "PENDING"
    ACCEPTED = "ACCEPTED"
    REJECTED = "REJECTED"
    COMPLETED = "COMPLETED"


@dataclass
class HandoffRequest:
    """Request to hand off execution to another agent.

    Attributes:
        from_agent: ID of the agent initiating the handoff
        to_agent: ID of the agent that should receive the handoff
        reason: Human-readable explanation of why the handoff is needed
        context_snapshot: Serialized context data (conversation history, tool state, etc.)
        preserve_history: Whether to preserve conversation history in the handoff
        capabilities_required: List of capabilities the target agent must have
        metadata: Additional metadata for the handoff
    """
    from_agent: str
    to_agent: str
    reason: str
    context_snapshot: Optional[bytes] = None
    preserve_history: bool = True
    capabilities_required: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class HandoffResponse:
    """Response to a handoff request.

    Attributes:
        accepted: Whether the handoff was accepted
        handoff_id: Unique identifier for the handoff transaction
        rejection_reason: Explanation if the handoff was rejected
        status: Current status of the handoff
        metadata: Additional metadata about the handoff
    """
    accepted: bool
    handoff_id: str
    rejection_reason: Optional[str] = None
    status: HandoffStatus = HandoffStatus.PENDING
    metadata: dict[str, Any] = field(default_factory=dict)
