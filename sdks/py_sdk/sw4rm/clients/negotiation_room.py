"""Negotiation Room client for SW4RM.

This module provides the NegotiationRoomClient for managing multi-agent
artifact approval workflows using the Negotiation Room pattern. The client
supports:
- Submitting artifacts for review
- Collecting votes from critics
- Retrieving and waiting for decisions
- Coordinating the review process

Based on SPEC_REQUESTS.md section 6.1.
"""
from __future__ import annotations

import time
from typing import Optional

from sw4rm.negotiation_types import (
    NegotiationProposal,
    NegotiationVote,
    NegotiationDecision,
)


class NegotiationRoomClient:
    """Client for interacting with negotiation rooms.

    Manages the lifecycle of artifact proposals through the multi-agent
    review process. Producers submit proposals, critics submit votes,
    and coordinators retrieve votes to make decisions.

    This is an in-memory implementation for Phase 2.2. Future phases
    will integrate with persistent storage and gRPC services.

    Attributes:
        _proposals: In-memory storage for proposals keyed by artifact_id
        _votes: In-memory storage for votes keyed by artifact_id
        _decisions: In-memory storage for decisions keyed by artifact_id
    """

    def __init__(self) -> None:
        """Initialize the negotiation room client with in-memory storage."""
        self._proposals: dict[str, NegotiationProposal] = {}
        self._votes: dict[str, list[NegotiationVote]] = {}
        self._decisions: dict[str, NegotiationDecision] = {}

    def submit_proposal(self, proposal: NegotiationProposal) -> str:
        """Submit an artifact proposal for multi-agent review.

        Stores the proposal and initializes empty vote tracking for the artifact.
        This method is typically called by producer agents.

        Args:
            proposal: The negotiation proposal containing artifact details

        Returns:
            The artifact_id of the submitted proposal

        Raises:
            ValueError: If a proposal with the same artifact_id already exists

        Example:
            >>> client = NegotiationRoomClient()
            >>> proposal = NegotiationProposal(
            ...     artifact_type=ArtifactType.CODE,
            ...     artifact_id="code-123",
            ...     producer_id="agent-producer",
            ...     artifact=b"def hello(): pass",
            ...     artifact_content_type="text/x-python",
            ...     requested_critics=["critic-1", "critic-2"],
            ...     negotiation_room_id="room-1"
            ... )
            >>> artifact_id = client.submit_proposal(proposal)
            >>> artifact_id
            'code-123'
        """
        artifact_id = proposal.artifact_id

        if artifact_id in self._proposals:
            raise ValueError(
                f"Proposal with artifact_id '{artifact_id}' already exists"
            )

        self._proposals[artifact_id] = proposal
        self._votes[artifact_id] = []

        return artifact_id

    def submit_vote(self, vote: NegotiationVote) -> None:
        """Submit a critic's vote for an artifact.

        Adds the vote to the collection for the specified artifact.
        This method is typically called by critic agents after evaluating
        an artifact.

        Args:
            vote: The negotiation vote containing the critic's evaluation

        Raises:
            ValueError: If no proposal exists for the vote's artifact_id
            ValueError: If the critic has already voted for this artifact

        Example:
            >>> vote = NegotiationVote(
            ...     artifact_id="code-123",
            ...     critic_id="critic-1",
            ...     score=8.5,
            ...     confidence=0.9,
            ...     passed=True,
            ...     strengths=["Good structure"],
            ...     weaknesses=["Needs tests"],
            ...     recommendations=["Add unit tests"],
            ...     negotiation_room_id="room-1"
            ... )
            >>> client.submit_vote(vote)
        """
        artifact_id = vote.artifact_id

        if artifact_id not in self._proposals:
            raise ValueError(
                f"No proposal found for artifact_id '{artifact_id}'"
            )

        # Check if this critic has already voted
        existing_votes = self._votes.get(artifact_id, [])
        for existing_vote in existing_votes:
            if existing_vote.critic_id == vote.critic_id:
                raise ValueError(
                    f"Critic '{vote.critic_id}' has already voted for "
                    f"artifact '{artifact_id}'"
                )

        self._votes[artifact_id].append(vote)

    def get_votes(self, artifact_id: str) -> list[NegotiationVote]:
        """Retrieve all votes for a specific artifact.

        Returns all critic votes that have been submitted for the artifact.
        This method is typically called by coordinator agents to aggregate
        votes and make decisions.

        Args:
            artifact_id: The identifier of the artifact

        Returns:
            List of all votes for the artifact (empty list if no votes yet)

        Raises:
            ValueError: If no proposal exists for the artifact_id

        Example:
            >>> votes = client.get_votes("code-123")
            >>> len(votes)
            1
        """
        if artifact_id not in self._proposals:
            raise ValueError(
                f"No proposal found for artifact_id '{artifact_id}'"
            )

        return self._votes.get(artifact_id, [])

    def get_decision(self, artifact_id: str) -> Optional[NegotiationDecision]:
        """Retrieve the decision for a specific artifact if available.

        Returns the final decision if one has been made, or None if the
        artifact is still under review.

        Args:
            artifact_id: The identifier of the artifact

        Returns:
            The negotiation decision if available, None otherwise

        Raises:
            ValueError: If no proposal exists for the artifact_id

        Example:
            >>> decision = client.get_decision("code-123")
            >>> decision is None  # Before decision is made
            True
        """
        if artifact_id not in self._proposals:
            raise ValueError(
                f"No proposal found for artifact_id '{artifact_id}'"
            )

        return self._decisions.get(artifact_id)

    def store_decision(self, decision: NegotiationDecision) -> None:
        """Store a decision for an artifact.

        This is an internal method used by coordinators to record the
        final decision after evaluating votes. Once a decision is stored,
        it becomes available via get_decision() and wait_for_decision().

        Args:
            decision: The negotiation decision to store

        Raises:
            ValueError: If no proposal exists for the decision's artifact_id
            ValueError: If a decision already exists for this artifact

        Example:
            >>> from sw4rm.negotiation_types import DecisionOutcome, aggregate_votes
            >>> votes = client.get_votes("code-123")
            >>> aggregated = aggregate_votes(votes)
            >>> decision = NegotiationDecision(
            ...     artifact_id="code-123",
            ...     outcome=DecisionOutcome.APPROVED,
            ...     votes=votes,
            ...     aggregated_score=aggregated,
            ...     policy_version="1.0",
            ...     reason="Met all criteria",
            ...     negotiation_room_id="room-1"
            ... )
            >>> client.store_decision(decision)
        """
        artifact_id = decision.artifact_id

        if artifact_id not in self._proposals:
            raise ValueError(
                f"No proposal found for artifact_id '{artifact_id}'"
            )

        if artifact_id in self._decisions:
            raise ValueError(
                f"Decision already exists for artifact_id '{artifact_id}'"
            )

        self._decisions[artifact_id] = decision

    def wait_for_decision(
        self,
        artifact_id: str,
        timeout_s: float = 30.0,
        poll_interval_s: float = 0.1,
    ) -> NegotiationDecision:
        """Wait for a decision to be made on an artifact.

        Polls for a decision until one is available or the timeout is reached.
        This method is useful for producer agents waiting for the outcome
        of their artifact review.

        Args:
            artifact_id: The identifier of the artifact
            timeout_s: Maximum time to wait in seconds (default: 30.0)
            poll_interval_s: Time between polling attempts in seconds (default: 0.1)

        Returns:
            The negotiation decision once available

        Raises:
            ValueError: If no proposal exists for the artifact_id
            TimeoutError: If no decision is made within the timeout period

        Example:
            >>> # In a separate thread/process, a coordinator makes a decision
            >>> decision = client.wait_for_decision("code-123", timeout_s=10.0)
            >>> decision.outcome
            <DecisionOutcome.APPROVED: 1>
        """
        if artifact_id not in self._proposals:
            raise ValueError(
                f"No proposal found for artifact_id '{artifact_id}'"
            )

        start_time = time.time()

        while time.time() - start_time < timeout_s:
            decision = self.get_decision(artifact_id)
            if decision is not None:
                return decision

            time.sleep(poll_interval_s)

        raise TimeoutError(
            f"No decision made for artifact '{artifact_id}' within "
            f"{timeout_s} seconds"
        )

    def get_proposal(self, artifact_id: str) -> Optional[NegotiationProposal]:
        """Retrieve the original proposal for an artifact.

        Useful for critics that need to review the original artifact
        before submitting a vote.

        Args:
            artifact_id: The identifier of the artifact

        Returns:
            The negotiation proposal if it exists, None otherwise

        Example:
            >>> proposal = client.get_proposal("code-123")
            >>> proposal.artifact_type
            <ArtifactType.CODE: 3>
        """
        return self._proposals.get(artifact_id)

    def list_proposals(
        self,
        negotiation_room_id: Optional[str] = None,
    ) -> list[NegotiationProposal]:
        """List all proposals, optionally filtered by negotiation room.

        Args:
            negotiation_room_id: If provided, only return proposals for this room

        Returns:
            List of proposals matching the filter criteria

        Example:
            >>> proposals = client.list_proposals(negotiation_room_id="room-1")
            >>> len(proposals)
            1
        """
        if negotiation_room_id is None:
            return list(self._proposals.values())

        return [
            p for p in self._proposals.values()
            if p.negotiation_room_id == negotiation_room_id
        ]
