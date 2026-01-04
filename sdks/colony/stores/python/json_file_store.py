"""JSON file-based storage backend for NegotiationRoomClient.

This is a Colony module - an optional persistence backend that is not part
of the core SW4RM protocol. For production deployments requiring horizontal
scaling, consider the Redis or PostgreSQL backends instead.

Installation:
    This module has no additional dependencies beyond the core SDK.

Usage:
    from sw4rm.clients import NegotiationRoomClient
    from colony.stores.python.json_file_store import JSONFileNegotiationRoomStore

    store = JSONFileNegotiationRoomStore("/var/lib/sw4rm/negotiation")
    client = NegotiationRoomClient(store=store)
"""
from __future__ import annotations

import json
import threading
from pathlib import Path
from typing import List, Optional

from sw4rm.clients.negotiation_room_store import NegotiationRoomStoreABC
from sw4rm.negotiation_types import (
    NegotiationProposal,
    NegotiationVote,
    NegotiationDecision,
)


class JSONFileNegotiationRoomStore(NegotiationRoomStoreABC):
    """File-based implementation of NegotiationRoomStore using JSON.

    Persists proposals, votes, and decisions to disk as JSON files. This enables
    state sharing across multiple processes on the same machine, as well as
    persistence across process restarts.

    Storage format:
        {storage_dir}/
            proposals/
                {artifact_id}.json
            votes/
                {artifact_id}.json  # Array of votes
            decisions/
                {artifact_id}.json

    Thread-safety: This implementation IS thread-safe within a single process.
    For multi-process safety, uses atomic file operations.

    Limitations:
        - Not suitable for multi-node deployments (use Redis/PostgreSQL instead)
        - No file locking for cross-process safety (TODO: add flock)
        - No crash recovery for partial writes

    Note: For production multi-node deployments, prefer the Redis or PostgreSQL
    storage backends from the colony/stores module.
    """

    def __init__(self, storage_dir: str | Path) -> None:
        """Initialize a JSON file-based store.

        Creates the storage directory structure if it doesn't exist.

        Args:
            storage_dir: Directory to store JSON files.
        """
        self._lock = threading.RLock()
        self.storage_dir = Path(storage_dir)
        self._proposals_dir = self.storage_dir / "proposals"
        self._votes_dir = self.storage_dir / "votes"
        self._decisions_dir = self.storage_dir / "decisions"

        # Create directories
        self._proposals_dir.mkdir(parents=True, exist_ok=True)
        self._votes_dir.mkdir(parents=True, exist_ok=True)
        self._decisions_dir.mkdir(parents=True, exist_ok=True)

    def _sanitize_id(self, artifact_id: str) -> str:
        """Sanitize artifact_id for filesystem safety."""
        return artifact_id.replace("/", "_").replace("\\", "_")

    def has_proposal(self, artifact_id: str) -> bool:
        """Check if a proposal exists for the given artifact_id."""
        safe_id = self._sanitize_id(artifact_id)
        proposal_file = self._proposals_dir / f"{safe_id}.json"
        return proposal_file.exists()

    def get_proposal(self, artifact_id: str) -> Optional[NegotiationProposal]:
        """Retrieve a proposal by artifact_id."""
        safe_id = self._sanitize_id(artifact_id)
        proposal_file = self._proposals_dir / f"{safe_id}.json"

        if not proposal_file.exists():
            return None

        with self._lock:
            try:
                with open(proposal_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                return NegotiationProposal.from_dict(data)
            except (json.JSONDecodeError, IOError, KeyError):
                return None

    def save_proposal(self, proposal: NegotiationProposal) -> None:
        """Save a proposal to storage."""
        artifact_id = proposal.artifact_id
        safe_id = self._sanitize_id(artifact_id)
        proposal_file = self._proposals_dir / f"{safe_id}.json"

        with self._lock:
            if proposal_file.exists():
                raise ValueError(
                    f"Proposal with artifact_id '{artifact_id}' already exists"
                )

            # Atomic write: write to temp file, then rename
            temp_file = proposal_file.with_suffix(".tmp")
            with open(temp_file, "w", encoding="utf-8") as f:
                json.dump(proposal.to_dict(), f, indent=2, ensure_ascii=False)
            temp_file.rename(proposal_file)

            # Initialize empty votes file
            votes_file = self._votes_dir / f"{safe_id}.json"
            if not votes_file.exists():
                with open(votes_file, "w", encoding="utf-8") as f:
                    json.dump([], f)

    def list_proposals(
        self, negotiation_room_id: Optional[str] = None
    ) -> List[NegotiationProposal]:
        """List all proposals, optionally filtered by negotiation room."""
        proposals = []

        with self._lock:
            for proposal_file in self._proposals_dir.glob("*.json"):
                try:
                    with open(proposal_file, "r", encoding="utf-8") as f:
                        data = json.load(f)
                    proposal = NegotiationProposal.from_dict(data)

                    if negotiation_room_id is None:
                        proposals.append(proposal)
                    elif proposal.negotiation_room_id == negotiation_room_id:
                        proposals.append(proposal)
                except (json.JSONDecodeError, IOError, KeyError):
                    continue

        return proposals

    def get_votes(self, artifact_id: str) -> List[NegotiationVote]:
        """Retrieve all votes for a specific artifact."""
        safe_id = self._sanitize_id(artifact_id)
        votes_file = self._votes_dir / f"{safe_id}.json"

        if not votes_file.exists():
            return []

        with self._lock:
            try:
                with open(votes_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                return [NegotiationVote.from_dict(v) for v in data]
            except (json.JSONDecodeError, IOError, KeyError):
                return []

    def add_vote(self, vote: NegotiationVote) -> None:
        """Add a vote for an artifact."""
        artifact_id = vote.artifact_id
        safe_id = self._sanitize_id(artifact_id)
        votes_file = self._votes_dir / f"{safe_id}.json"

        with self._lock:
            # Load existing votes
            if votes_file.exists():
                try:
                    with open(votes_file, "r", encoding="utf-8") as f:
                        votes_data = json.load(f)
                except (json.JSONDecodeError, IOError):
                    votes_data = []
            else:
                votes_data = []

            # Check for duplicate vote
            critic_id = vote.critic_id
            for v in votes_data:
                if v.get("critic_id") == critic_id:
                    raise ValueError(
                        f"Critic '{critic_id}' has already voted for "
                        f"artifact '{artifact_id}'"
                    )

            # Add new vote
            votes_data.append(vote.to_dict())

            # Atomic write
            temp_file = votes_file.with_suffix(".tmp")
            with open(temp_file, "w", encoding="utf-8") as f:
                json.dump(votes_data, f, indent=2, ensure_ascii=False)
            temp_file.rename(votes_file)

    def get_decision(self, artifact_id: str) -> Optional[NegotiationDecision]:
        """Retrieve the decision for an artifact."""
        safe_id = self._sanitize_id(artifact_id)
        decision_file = self._decisions_dir / f"{safe_id}.json"

        if not decision_file.exists():
            return None

        with self._lock:
            try:
                with open(decision_file, "r", encoding="utf-8") as f:
                    data = json.load(f)
                return NegotiationDecision.from_dict(data)
            except (json.JSONDecodeError, IOError, KeyError):
                return None

    def save_decision(self, decision: NegotiationDecision) -> None:
        """Save a decision for an artifact."""
        artifact_id = decision.artifact_id
        safe_id = self._sanitize_id(artifact_id)
        decision_file = self._decisions_dir / f"{safe_id}.json"

        with self._lock:
            if decision_file.exists():
                raise ValueError(
                    f"Decision already exists for artifact_id '{artifact_id}'"
                )

            # Atomic write
            temp_file = decision_file.with_suffix(".tmp")
            with open(temp_file, "w", encoding="utf-8") as f:
                json.dump(decision.to_dict(), f, indent=2, ensure_ascii=False)
            temp_file.rename(decision_file)
