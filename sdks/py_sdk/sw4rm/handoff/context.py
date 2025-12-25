"""Context management for agent handoffs.

This module provides the HandoffContext dataclass and utilities for serializing
and deserializing handoff context data.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field, asdict
from typing import Any, Optional


@dataclass
class HandoffContext:
    """Context data for an agent handoff.

    This captures all the state needed for a receiving agent to continue
    execution seamlessly after a handoff.

    Attributes:
        conversation_history: List of messages in the conversation history.
            Each message is a dict with 'role', 'content', and optional metadata.
        tool_state: Current state of tools, including active tool calls,
            cached results, and tool configurations
        metadata: Additional metadata like timestamps, agent capabilities,
            resource allocations, etc.
    """
    conversation_history: list[dict[str, Any]] = field(default_factory=list)
    tool_state: dict[str, Any] = field(default_factory=dict)
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """Convert the context to a dictionary.

        Returns:
            Dictionary representation of the context
        """
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> HandoffContext:
        """Create a HandoffContext from a dictionary.

        Args:
            data: Dictionary containing context data

        Returns:
            HandoffContext instance
        """
        return cls(
            conversation_history=data.get("conversation_history", []),
            tool_state=data.get("tool_state", {}),
            metadata=data.get("metadata", {})
        )


def serialize_context(context: HandoffContext) -> bytes:
    """Serialize a HandoffContext to JSON bytes.

    Args:
        context: The HandoffContext to serialize

    Returns:
        JSON-encoded bytes representation of the context

    Raises:
        ValueError: If the context cannot be serialized
    """
    try:
        data = context.to_dict()
        json_str = json.dumps(data, separators=(',', ':'))
        return json_str.encode('utf-8')
    except (TypeError, ValueError) as e:
        raise ValueError(f"Failed to serialize HandoffContext: {e}") from e


def deserialize_context(data: bytes) -> HandoffContext:
    """Deserialize JSON bytes to a HandoffContext.

    Args:
        data: JSON-encoded bytes representation of a context

    Returns:
        HandoffContext instance

    Raises:
        ValueError: If the data cannot be deserialized
    """
    try:
        json_str = data.decode('utf-8')
        context_dict = json.loads(json_str)
        return HandoffContext.from_dict(context_dict)
    except (json.JSONDecodeError, UnicodeDecodeError, KeyError) as e:
        raise ValueError(f"Failed to deserialize HandoffContext: {e}") from e
