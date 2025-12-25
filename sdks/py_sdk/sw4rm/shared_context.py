"""Shared context management for SW4RM agents.

This module provides data structures and management for shared context between
agents. Shared contexts enable agents to coordinate state with optimistic locking
for concurrent updates and conflict detection.

The SharedContextManager implements a lightweight in-memory store with version
control and locking mechanisms to prevent race conditions during updates.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from typing import Dict, Optional
import uuid


@dataclass
class SharedContext:
    """A shared context record with versioning and locking support.

    Shared contexts enable multiple agents to read and update shared state
    with optimistic concurrency control. Each update increments the version,
    and updates must specify the expected version to detect conflicts.

    Attributes:
        context_id: Unique identifier for this context
        version: Version identifier for optimistic locking (increments on update)
        data: The context data dictionary
        locked_by: Agent ID that currently holds the lock, or None if unlocked
        created_at: Timestamp when context was created
        updated_at: Timestamp of last update
    """

    context_id: str
    version: str
    data: Dict
    locked_by: Optional[str] = None
    created_at: datetime = field(default_factory=datetime.utcnow)
    updated_at: datetime = field(default_factory=datetime.utcnow)

    def to_dict(self) -> Dict:
        """Convert context to dictionary representation.

        Returns:
            Dictionary with all context fields, suitable for JSON serialization.
        """
        return {
            "context_id": self.context_id,
            "version": self.version,
            "data": self.data,
            "locked_by": self.locked_by,
            "created_at": self.created_at.isoformat() if self.created_at else None,
            "updated_at": self.updated_at.isoformat() if self.updated_at else None,
        }

    @classmethod
    def from_dict(cls, data: Dict) -> SharedContext:
        """Reconstruct context from dictionary representation.

        Args:
            data: Dictionary with context fields

        Returns:
            SharedContext instance
        """
        created_at = (
            datetime.fromisoformat(data["created_at"])
            if data.get("created_at")
            else datetime.utcnow()
        )
        updated_at = (
            datetime.fromisoformat(data["updated_at"])
            if data.get("updated_at")
            else datetime.utcnow()
        )

        return cls(
            context_id=data["context_id"],
            version=data["version"],
            data=data["data"],
            locked_by=data.get("locked_by"),
            created_at=created_at,
            updated_at=updated_at,
        )


class SharedContextManager:
    """Manager for shared context creation, retrieval, and updates.

    This class provides a lightweight in-memory store for shared contexts with
    support for:
    - Optimistic locking via version checking
    - Explicit locks to prevent concurrent modifications
    - Atomic updates with conflict detection

    Example:
        >>> manager = SharedContextManager()
        >>> ctx = manager.create("workflow-123", {"step": 1, "status": "running"})
        >>> ctx.version
        '1'
        >>> updated = manager.update("workflow-123", {"step": 2, "status": "completed"}, "1")
        >>> updated.version
        '2'
        >>> # Conflict detection
        >>> try:
        ...     manager.update("workflow-123", {"step": 3}, "1")  # Stale version
        ... except ValueError as e:
        ...     print("Conflict detected")
        Conflict detected
    """

    def __init__(self) -> None:
        """Initialize an empty shared context store."""
        self._contexts: Dict[str, SharedContext] = {}

    def create(self, context_id: str, initial_data: Dict) -> SharedContext:
        """Create a new shared context with initial data.

        Args:
            context_id: Unique identifier for the context
            initial_data: Initial data dictionary

        Returns:
            The created SharedContext instance

        Raises:
            ValueError: If a context with this ID already exists

        Example:
            >>> manager = SharedContextManager()
            >>> ctx = manager.create("session-456", {"user": "alice", "state": "active"})
            >>> ctx.context_id
            'session-456'
            >>> ctx.version
            '1'
        """
        if context_id in self._contexts:
            raise ValueError(f"Context '{context_id}' already exists")

        context = SharedContext(
            context_id=context_id,
            version="1",
            data=initial_data.copy(),
            locked_by=None,
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )

        self._contexts[context_id] = context
        return context

    def get(self, context_id: str) -> Optional[SharedContext]:
        """Retrieve a shared context by ID.

        Args:
            context_id: The context identifier

        Returns:
            The SharedContext instance if found, None otherwise

        Example:
            >>> manager = SharedContextManager()
            >>> manager.create("ctx-1", {"key": "value"})
            SharedContext(...)
            >>> ctx = manager.get("ctx-1")
            >>> ctx.data["key"]
            'value'
            >>> manager.get("nonexistent")
            None
        """
        return self._contexts.get(context_id)

    def update(
        self, context_id: str, data: Dict, expected_version: str
    ) -> SharedContext:
        """Update a shared context with optimistic locking.

        This method performs an atomic update with conflict detection. The update
        only succeeds if the current version matches the expected version,
        ensuring no other agent modified the context in the meantime.

        Args:
            context_id: The context identifier
            data: New data dictionary (replaces existing data)
            expected_version: The version the caller expects (for conflict detection)

        Returns:
            The updated SharedContext with incremented version

        Raises:
            ValueError: If context not found, version mismatch, or context is locked

        Example:
            >>> manager = SharedContextManager()
            >>> ctx = manager.create("ctx-1", {"count": 0})
            >>> # Agent A updates
            >>> ctx = manager.update("ctx-1", {"count": 1}, "1")
            >>> ctx.version
            '2'
            >>> # Agent B tries to update with stale version
            >>> try:
            ...     manager.update("ctx-1", {"count": 2}, "1")
            ... except ValueError as e:
            ...     print("Conflict!")
            Conflict!
        """
        context = self._contexts.get(context_id)
        if context is None:
            raise ValueError(f"Context '{context_id}' not found")

        # Check if locked by another agent
        if context.locked_by is not None:
            raise ValueError(
                f"Context '{context_id}' is locked by '{context.locked_by}'"
            )

        # Optimistic locking: check version
        if context.version != expected_version:
            raise ValueError(
                f"Version conflict for context '{context_id}': "
                f"expected '{expected_version}', current '{context.version}'"
            )

        # Increment version (simple integer-based versioning)
        new_version = str(int(context.version) + 1)

        # Update context
        context.version = new_version
        context.data = data.copy()
        context.updated_at = datetime.utcnow()

        return context

    def lock(self, context_id: str, agent_id: str) -> bool:
        """Acquire an exclusive lock on a shared context.

        Locks prevent other agents from updating the context until it's unlocked.
        An agent can re-acquire a lock it already holds (idempotent).

        Args:
            context_id: The context identifier
            agent_id: The agent requesting the lock

        Returns:
            True if lock acquired, False if already locked by another agent

        Raises:
            ValueError: If context not found

        Example:
            >>> manager = SharedContextManager()
            >>> manager.create("ctx-1", {})
            SharedContext(...)
            >>> manager.lock("ctx-1", "agent-A")
            True
            >>> manager.lock("ctx-1", "agent-B")  # Already locked
            False
            >>> manager.lock("ctx-1", "agent-A")  # Idempotent
            True
        """
        context = self._contexts.get(context_id)
        if context is None:
            raise ValueError(f"Context '{context_id}' not found")

        # If already locked by this agent, return True (idempotent)
        if context.locked_by == agent_id:
            return True

        # If locked by another agent, return False
        if context.locked_by is not None:
            return False

        # Acquire lock
        context.locked_by = agent_id
        return True

    def unlock(self, context_id: str, agent_id: str) -> bool:
        """Release an exclusive lock on a shared context.

        Only the agent that acquired the lock can release it. Attempting to
        unlock a context locked by another agent returns False.

        Args:
            context_id: The context identifier
            agent_id: The agent releasing the lock

        Returns:
            True if lock released, False if not locked by this agent

        Raises:
            ValueError: If context not found

        Example:
            >>> manager = SharedContextManager()
            >>> manager.create("ctx-1", {})
            SharedContext(...)
            >>> manager.lock("ctx-1", "agent-A")
            True
            >>> manager.unlock("ctx-1", "agent-B")  # Wrong agent
            False
            >>> manager.unlock("ctx-1", "agent-A")  # Correct agent
            True
        """
        context = self._contexts.get(context_id)
        if context is None:
            raise ValueError(f"Context '{context_id}' not found")

        # If not locked or locked by another agent, return False
        if context.locked_by != agent_id:
            return False

        # Release lock
        context.locked_by = None
        return True

    def delete(self, context_id: str) -> bool:
        """Delete a shared context.

        Args:
            context_id: The context identifier

        Returns:
            True if context was deleted, False if not found

        Example:
            >>> manager = SharedContextManager()
            >>> manager.create("ctx-1", {})
            SharedContext(...)
            >>> manager.delete("ctx-1")
            True
            >>> manager.delete("ctx-1")  # Already deleted
            False
        """
        if context_id in self._contexts:
            del self._contexts[context_id]
            return True
        return False

    def list_contexts(self) -> list[str]:
        """List all context IDs in the manager.

        Returns:
            List of context IDs

        Example:
            >>> manager = SharedContextManager()
            >>> manager.create("ctx-1", {})
            SharedContext(...)
            >>> manager.create("ctx-2", {})
            SharedContext(...)
            >>> sorted(manager.list_contexts())
            ['ctx-1', 'ctx-2']
        """
        return list(self._contexts.keys())

    def clear(self) -> None:
        """Clear all contexts from the manager.

        Example:
            >>> manager = SharedContextManager()
            >>> manager.create("ctx-1", {})
            SharedContext(...)
            >>> manager.clear()
            >>> manager.list_contexts()
            []
        """
        self._contexts.clear()
