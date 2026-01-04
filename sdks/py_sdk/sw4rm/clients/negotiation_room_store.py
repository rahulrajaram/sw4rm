"""Negotiation Room storage backend abstraction.

This module provides a pluggable storage layer for NegotiationRoomClient,
enabling shared state across multiple client instances.

The key insight is that NegotiationRoomClient previously used instance-local
storage (self._proposals, self._votes, self._decisions), which broke
multi-instance deployments. By extracting storage into a separate abstraction
that can be shared via dependency injection, we enable:

1. Multiple client instances sharing the same storage
2. Producer/Critic/Coordinator agents in different processes sharing state
3. Future gRPC integration where the server becomes the source of truth

For persistent storage backends (JSON file, Redis, PostgreSQL), see the
colony/stores module which provides optional persistence implementations.

Based on the PolicyStore pattern established in policy_store.py.
"""
from __future__ import annotations

import threading
from abc import ABC, abstractmethod
from typing import List, Optional, Protocol

from sw4rm.negotiation_types import (
    NegotiationProposal,
    NegotiationVote,
    NegotiationDecision,
)


class NegotiationRoomStore(Protocol):
    """Protocol defining the interface for negotiation room storage backends.

    All storage implementations must support these operations for proposals,
    votes, and decisions. Thread-safety requirements are implementation-specific.

    This follows the same pattern as PolicyStore from policy_store.py, enabling
    pluggable backends ranging from in-memory to file-based to gRPC-based.
    """

    def has_proposal(self, artifact_id: str) -> bool:
        """Check if a proposal exists for the given artifact_id.

        Args:
            artifact_id: Unique identifier for the artifact.

        Returns:
            True if a proposal exists, False otherwise.
        """
        ...

    def get_proposal(self, artifact_id: str) -> Optional[NegotiationProposal]:
        """Retrieve a proposal by artifact_id.

        Args:
            artifact_id: Unique identifier for the artifact.

        Returns:
            The proposal if found, None otherwise.
        """
        ...

    def save_proposal(self, proposal: NegotiationProposal) -> None:
        """Save a proposal to storage.

        Args:
            proposal: The proposal to save.

        Raises:
            ValueError: If a proposal with the same artifact_id already exists.
        """
        ...

    def list_proposals(
        self, negotiation_room_id: Optional[str] = None
    ) -> List[NegotiationProposal]:
        """List all proposals, optionally filtered by negotiation room.

        Args:
            negotiation_room_id: If provided, only return proposals for this room.

        Returns:
            List of proposals matching the filter criteria.
        """
        ...

    def get_votes(self, artifact_id: str) -> List[NegotiationVote]:
        """Retrieve all votes for a specific artifact.

        Args:
            artifact_id: The identifier of the artifact.

        Returns:
            List of all votes for the artifact (empty list if no votes).
        """
        ...

    def add_vote(self, vote: NegotiationVote) -> None:
        """Add a vote for an artifact.

        Args:
            vote: The vote to add.

        Raises:
            ValueError: If the critic has already voted for this artifact.
        """
        ...

    def get_decision(self, artifact_id: str) -> Optional[NegotiationDecision]:
        """Retrieve the decision for an artifact.

        Args:
            artifact_id: The identifier of the artifact.

        Returns:
            The decision if available, None otherwise.
        """
        ...

    def save_decision(self, decision: NegotiationDecision) -> None:
        """Save a decision for an artifact.

        Args:
            decision: The decision to save.

        Raises:
            ValueError: If a decision already exists for this artifact.
        """
        ...


class NegotiationRoomStoreABC(ABC):
    """Abstract base class for negotiation room storage backends.

    Provides the same interface as NegotiationRoomStore Protocol but as an ABC
    for implementations that prefer inheritance over structural typing.
    """

    @abstractmethod
    def has_proposal(self, artifact_id: str) -> bool:
        """Check if a proposal exists for the given artifact_id."""
        pass

    @abstractmethod
    def get_proposal(self, artifact_id: str) -> Optional[NegotiationProposal]:
        """Retrieve a proposal by artifact_id."""
        pass

    @abstractmethod
    def save_proposal(self, proposal: NegotiationProposal) -> None:
        """Save a proposal to storage."""
        pass

    @abstractmethod
    def list_proposals(
        self, negotiation_room_id: Optional[str] = None
    ) -> List[NegotiationProposal]:
        """List all proposals, optionally filtered by negotiation room."""
        pass

    @abstractmethod
    def get_votes(self, artifact_id: str) -> List[NegotiationVote]:
        """Retrieve all votes for a specific artifact."""
        pass

    @abstractmethod
    def add_vote(self, vote: NegotiationVote) -> None:
        """Add a vote for an artifact."""
        pass

    @abstractmethod
    def get_decision(self, artifact_id: str) -> Optional[NegotiationDecision]:
        """Retrieve the decision for an artifact."""
        pass

    @abstractmethod
    def save_decision(self, decision: NegotiationDecision) -> None:
        """Save a decision for an artifact."""
        pass


class InMemoryNegotiationRoomStore(NegotiationRoomStoreABC):
    """Thread-safe in-memory implementation of NegotiationRoomStore.

    Stores proposals, votes, and decisions in memory with thread-safe access.
    Data is lost when the process terminates. Suitable for testing and
    single-process deployments.

    Thread-safety: This implementation IS thread-safe. All operations are
    protected by a reentrant lock (RLock) to allow nested calls.

    Usage for shared state across multiple client instances:
        # Create a single shared store
        shared_store = InMemoryNegotiationRoomStore()

        # Pass to multiple clients
        producer_client = NegotiationRoomClient(store=shared_store)
        critic_client = NegotiationRoomClient(store=shared_store)
        coordinator_client = NegotiationRoomClient(store=shared_store)

        # Now all clients share the same state
    """

    def __init__(self) -> None:
        """Initialize an empty in-memory store with thread-safe access."""
        self._lock = threading.RLock()
        self._proposals: dict[str, NegotiationProposal] = {}
        self._votes: dict[str, list[NegotiationVote]] = {}
        self._decisions: dict[str, NegotiationDecision] = {}

    def has_proposal(self, artifact_id: str) -> bool:
        """Check if a proposal exists for the given artifact_id.

        Thread-safe.

        Args:
            artifact_id: Unique identifier for the artifact.

        Returns:
            True if a proposal exists, False otherwise.
        """
        with self._lock:
            return artifact_id in self._proposals

    def get_proposal(self, artifact_id: str) -> Optional[NegotiationProposal]:
        """Retrieve a proposal by artifact_id.

        Thread-safe.

        Args:
            artifact_id: Unique identifier for the artifact.

        Returns:
            The proposal if found, None otherwise.
        """
        with self._lock:
            return self._proposals.get(artifact_id)

    def save_proposal(self, proposal: NegotiationProposal) -> None:
        """Save a proposal to storage.

        Thread-safe.

        Args:
            proposal: The proposal to save.

        Raises:
            ValueError: If a proposal with the same artifact_id already exists.
        """
        with self._lock:
            artifact_id = proposal.artifact_id
            if artifact_id in self._proposals:
                raise ValueError(
                    f"Proposal with artifact_id '{artifact_id}' already exists"
                )
            self._proposals[artifact_id] = proposal
            self._votes[artifact_id] = []

    def list_proposals(
        self, negotiation_room_id: Optional[str] = None
    ) -> List[NegotiationProposal]:
        """List all proposals, optionally filtered by negotiation room.

        Thread-safe.

        Args:
            negotiation_room_id: If provided, only return proposals for this room.

        Returns:
            List of proposals matching the filter criteria.
        """
        with self._lock:
            if negotiation_room_id is None:
                return list(self._proposals.values())

            return [
                p
                for p in self._proposals.values()
                if p.negotiation_room_id == negotiation_room_id
            ]

    def get_votes(self, artifact_id: str) -> List[NegotiationVote]:
        """Retrieve all votes for a specific artifact.

        Thread-safe.

        Args:
            artifact_id: The identifier of the artifact.

        Returns:
            List of all votes for the artifact (empty list if no votes).
        """
        with self._lock:
            return list(self._votes.get(artifact_id, []))

    def add_vote(self, vote: NegotiationVote) -> None:
        """Add a vote for an artifact.

        Thread-safe.

        Args:
            vote: The vote to add.

        Raises:
            ValueError: If the critic has already voted for this artifact.
        """
        with self._lock:
            artifact_id = vote.artifact_id
            critic_id = vote.critic_id

            # Check if this critic has already voted
            existing_votes = self._votes.get(artifact_id, [])
            for existing_vote in existing_votes:
                if existing_vote.critic_id == critic_id:
                    raise ValueError(
                        f"Critic '{critic_id}' has already voted for "
                        f"artifact '{artifact_id}'"
                    )

            # Initialize votes list if needed (for cases where proposal
            # was loaded from external source)
            if artifact_id not in self._votes:
                self._votes[artifact_id] = []

            self._votes[artifact_id].append(vote)

    def get_decision(self, artifact_id: str) -> Optional[NegotiationDecision]:
        """Retrieve the decision for an artifact.

        Thread-safe.

        Args:
            artifact_id: The identifier of the artifact.

        Returns:
            The decision if available, None otherwise.
        """
        with self._lock:
            return self._decisions.get(artifact_id)

    def save_decision(self, decision: NegotiationDecision) -> None:
        """Save a decision for an artifact.

        Thread-safe.

        Args:
            decision: The decision to save.

        Raises:
            ValueError: If a decision already exists for this artifact.
        """
        with self._lock:
            artifact_id = decision.artifact_id
            if artifact_id in self._decisions:
                raise ValueError(
                    f"Decision already exists for artifact_id '{artifact_id}'"
                )
            self._decisions[artifact_id] = decision


# Singleton for easy sharing across the application
_default_store: Optional[InMemoryNegotiationRoomStore] = None
_default_store_lock = threading.Lock()


def get_default_store() -> InMemoryNegotiationRoomStore:
    """Get the default shared in-memory store.

    This provides a convenient way to share state across multiple
    NegotiationRoomClient instances within the same process without
    explicitly passing a store instance.

    Returns:
        The default shared InMemoryNegotiationRoomStore instance.

    Example:
        # All clients automatically share the same store
        client1 = NegotiationRoomClient()  # Uses default store
        client2 = NegotiationRoomClient()  # Uses same default store

        # Equivalent to:
        store = get_default_store()
        client1 = NegotiationRoomClient(store=store)
        client2 = NegotiationRoomClient(store=store)
    """
    global _default_store
    with _default_store_lock:
        if _default_store is None:
            _default_store = InMemoryNegotiationRoomStore()
        return _default_store


def reset_default_store() -> None:
    """Reset the default store (primarily for testing).

    This clears the default store singleton, causing a new store
    to be created on the next call to get_default_store().
    """
    global _default_store
    with _default_store_lock:
        _default_store = None
