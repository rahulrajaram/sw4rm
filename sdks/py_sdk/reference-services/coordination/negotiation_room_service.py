# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Negotiation Room Service gRPC Server Implementation.

This module provides the gRPC server implementation for the NegotiationRoomService,
enabling distributed multi-agent artifact approval workflows with centralized state.

The service maintains:
- Proposals indexed by artifact_id
- Votes indexed by artifact_id -> list of votes
- Decisions indexed by artifact_id

Example usage:
    from coordination.negotiation_room_service import NegotiationRoomServiceImpl
    from sw4rm.protos import negotiation_room_pb2_grpc

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    negotiation_room_pb2_grpc.add_NegotiationRoomServiceServicer_to_server(
        NegotiationRoomServiceImpl(), server
    )
"""

import logging
import math
import threading
import time
from typing import Dict, List, Optional

import grpc
from google.protobuf import timestamp_pb2

from sw4rm.protos import negotiation_room_pb2, negotiation_room_pb2_grpc

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger(__name__)


def _current_timestamp() -> timestamp_pb2.Timestamp:
    """Get current time as a protobuf Timestamp."""
    ts = timestamp_pb2.Timestamp()
    ts.GetCurrentTime()
    return ts


class NegotiationRoomServiceImpl(negotiation_room_pb2_grpc.NegotiationRoomServiceServicer):
    """
    gRPC server implementation for NegotiationRoomService.

    Provides centralized artifact approval workflows for distributed agent
    deployments. Thread-safe implementation using RLock for all state mutations.

    State storage:
    - proposals: Dict[artifact_id, NegotiationProposal]
    - votes: Dict[artifact_id, List[NegotiationVote]]
    - decisions: Dict[artifact_id, NegotiationDecision]
    """

    def __init__(self):
        """Initialize the negotiation room service with empty state."""
        self._lock = threading.RLock()
        self._proposals: Dict[str, negotiation_room_pb2.NegotiationProposal] = {}
        self._votes: Dict[str, List[negotiation_room_pb2.NegotiationVote]] = {}
        self._decisions: Dict[str, negotiation_room_pb2.NegotiationDecision] = {}
        self._decision_events: Dict[str, threading.Event] = {}
        logger.info("NegotiationRoomService initialized")

    def SubmitProposal(
        self,
        request: negotiation_room_pb2.SubmitProposalRequest,
        context: grpc.ServicerContext
    ) -> negotiation_room_pb2.SubmitProposalResponse:
        """
        Submit an artifact proposal for multi-agent review.

        Stores the proposal and initializes empty vote tracking.
        Typically called by producer agents.

        Args:
            request: SubmitProposalRequest containing NegotiationProposal
            context: gRPC context

        Returns:
            SubmitProposalResponse with artifact_id and negotiation_room_id

        Raises:
            ALREADY_EXISTS: If a proposal with the same artifact_id exists
            INVALID_ARGUMENT: If artifact_id or producer_id is empty
        """
        proposal = request.proposal
        artifact_id = proposal.artifact_id
        negotiation_room_id = proposal.negotiation_room_id

        # Validate required fields
        if not artifact_id:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details("artifact_id is required")
            return negotiation_room_pb2.SubmitProposalResponse()

        if not proposal.producer_id:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details("producer_id is required")
            return negotiation_room_pb2.SubmitProposalResponse()

        with self._lock:
            if artifact_id in self._proposals:
                context.set_code(grpc.StatusCode.ALREADY_EXISTS)
                context.set_details(
                    f"Proposal with artifact_id '{artifact_id}' already exists"
                )
                return negotiation_room_pb2.SubmitProposalResponse()

            # Set created_at if not provided
            if not proposal.created_at.ByteSize():
                proposal.created_at.CopyFrom(_current_timestamp())

            self._proposals[artifact_id] = proposal
            self._votes[artifact_id] = []
            self._decision_events[artifact_id] = threading.Event()

            logger.info(
                f"Proposal submitted: {artifact_id} by {proposal.producer_id} "
                f"in room {negotiation_room_id}"
            )

        return negotiation_room_pb2.SubmitProposalResponse(
            artifact_id=artifact_id,
            negotiation_room_id=negotiation_room_id
        )

    def SubmitVote(
        self,
        request: negotiation_room_pb2.SubmitVoteRequest,
        context: grpc.ServicerContext
    ) -> negotiation_room_pb2.SubmitVoteResponse:
        """
        Submit a critic's vote for an artifact.

        Adds the vote to the collection for the specified artifact.
        Typically called by critic agents after evaluating an artifact.

        Args:
            request: SubmitVoteRequest containing NegotiationVote
            context: gRPC context

        Returns:
            SubmitVoteResponse with artifact_id and critic_id

        Raises:
            NOT_FOUND: If no proposal exists for the artifact_id
            ALREADY_EXISTS: If the critic has already voted
            INVALID_ARGUMENT: If score or confidence are out of range
        """
        vote = request.vote
        artifact_id = vote.artifact_id
        critic_id = vote.critic_id

        # Validate required fields
        if not artifact_id:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details("artifact_id is required")
            return negotiation_room_pb2.SubmitVoteResponse()

        if not critic_id:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details("critic_id is required")
            return negotiation_room_pb2.SubmitVoteResponse()

        # Validate score range [0, 10]
        if vote.score < 0 or vote.score > 10:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details(
                f"score must be in range [0, 10], got {vote.score}"
            )
            return negotiation_room_pb2.SubmitVoteResponse()

        # Validate confidence range [0, 1]
        if vote.confidence < 0 or vote.confidence > 1:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details(
                f"confidence must be in range [0, 1], got {vote.confidence}"
            )
            return negotiation_room_pb2.SubmitVoteResponse()

        with self._lock:
            if artifact_id not in self._proposals:
                context.set_code(grpc.StatusCode.NOT_FOUND)
                context.set_details(
                    f"No proposal found for artifact_id '{artifact_id}'"
                )
                return negotiation_room_pb2.SubmitVoteResponse()

            # Check if critic already voted
            existing_votes = self._votes.get(artifact_id, [])
            for existing_vote in existing_votes:
                if existing_vote.critic_id == critic_id:
                    context.set_code(grpc.StatusCode.ALREADY_EXISTS)
                    context.set_details(
                        f"Critic '{critic_id}' has already voted for "
                        f"artifact '{artifact_id}'"
                    )
                    return negotiation_room_pb2.SubmitVoteResponse()

            # Set voted_at if not provided
            if not vote.voted_at.ByteSize():
                vote.voted_at.CopyFrom(_current_timestamp())

            self._votes[artifact_id].append(vote)
            logger.info(
                f"Vote submitted: {critic_id} for {artifact_id} "
                f"(score={vote.score}, confidence={vote.confidence})"
            )

        return negotiation_room_pb2.SubmitVoteResponse(
            artifact_id=artifact_id,
            critic_id=critic_id
        )

    def GetVotes(
        self,
        request: negotiation_room_pb2.GetVotesRequest,
        context: grpc.ServicerContext
    ) -> negotiation_room_pb2.GetVotesResponse:
        """
        Retrieve all votes for a specific artifact.

        Returns all critic votes that have been submitted for the artifact.
        Typically called by coordinator agents to aggregate votes.

        Args:
            request: GetVotesRequest with artifact_id and negotiation_room_id
            context: gRPC context

        Returns:
            GetVotesResponse with list of votes and vote count

        Raises:
            NOT_FOUND: If no proposal exists for the artifact_id
        """
        artifact_id = request.artifact_id

        with self._lock:
            if artifact_id not in self._proposals:
                context.set_code(grpc.StatusCode.NOT_FOUND)
                context.set_details(
                    f"No proposal found for artifact_id '{artifact_id}'"
                )
                return negotiation_room_pb2.GetVotesResponse()

            votes = self._votes.get(artifact_id, [])
            logger.debug(f"GetVotes: {artifact_id} has {len(votes)} votes")

        return negotiation_room_pb2.GetVotesResponse(
            votes=votes,
            vote_count=len(votes)
        )

    def GetDecision(
        self,
        request: negotiation_room_pb2.GetDecisionRequest,
        context: grpc.ServicerContext
    ) -> negotiation_room_pb2.GetDecisionResponse:
        """
        Retrieve the decision for an artifact (non-blocking).

        Returns the final decision if one has been made, or an empty
        response if the artifact is still under review.

        Args:
            request: GetDecisionRequest with artifact_id and negotiation_room_id
            context: gRPC context

        Returns:
            GetDecisionResponse with decision if available

        Raises:
            NOT_FOUND: If no proposal exists for the artifact_id
        """
        artifact_id = request.artifact_id

        with self._lock:
            if artifact_id not in self._proposals:
                context.set_code(grpc.StatusCode.NOT_FOUND)
                context.set_details(
                    f"No proposal found for artifact_id '{artifact_id}'"
                )
                return negotiation_room_pb2.GetDecisionResponse()

            decision = self._decisions.get(artifact_id)
            if decision:
                logger.debug(f"GetDecision: {artifact_id} -> {decision.outcome}")
            else:
                logger.debug(f"GetDecision: {artifact_id} -> no decision yet")

        return negotiation_room_pb2.GetDecisionResponse(
            decision=decision
        )

    def WaitForDecision(
        self,
        request: negotiation_room_pb2.WaitForDecisionRequest,
        context: grpc.ServicerContext
    ) -> negotiation_room_pb2.WaitForDecisionResponse:
        """
        Wait for a decision to be made on an artifact (blocking).

        Blocks until a decision is available or timeout is reached.
        Useful for producer agents waiting for review outcome.

        Args:
            request: WaitForDecisionRequest with artifact_id, negotiation_room_id,
                    and optional timeout_seconds
            context: gRPC context

        Returns:
            WaitForDecisionResponse with decision

        Raises:
            NOT_FOUND: If no proposal exists for the artifact_id
            DEADLINE_EXCEEDED: If timeout is reached without a decision
        """
        artifact_id = request.artifact_id
        timeout_seconds = request.timeout_seconds or 30

        # Check proposal exists
        with self._lock:
            if artifact_id not in self._proposals:
                context.set_code(grpc.StatusCode.NOT_FOUND)
                context.set_details(
                    f"No proposal found for artifact_id '{artifact_id}'"
                )
                return negotiation_room_pb2.WaitForDecisionResponse()

            # Check if decision already exists
            decision = self._decisions.get(artifact_id)
            if decision:
                return negotiation_room_pb2.WaitForDecisionResponse(
                    decision=decision
                )

            event = self._decision_events.get(artifact_id)

        # Wait for decision event
        if event and event.wait(timeout=timeout_seconds):
            with self._lock:
                decision = self._decisions.get(artifact_id)
                if decision:
                    return negotiation_room_pb2.WaitForDecisionResponse(
                        decision=decision
                    )

        # Timeout reached
        context.set_code(grpc.StatusCode.DEADLINE_EXCEEDED)
        context.set_details(
            f"No decision made for artifact '{artifact_id}' "
            f"within {timeout_seconds} seconds"
        )
        return negotiation_room_pb2.WaitForDecisionResponse()

    # Additional methods for storing decisions (called by coordinators)

    def store_decision(
        self,
        decision: negotiation_room_pb2.NegotiationDecision
    ) -> bool:
        """
        Store a decision for an artifact (internal use).

        Called by coordinators after aggregating votes and applying policy.

        Args:
            decision: The NegotiationDecision to store

        Returns:
            True if stored successfully, False if proposal not found or
            decision already exists
        """
        artifact_id = decision.artifact_id

        with self._lock:
            if artifact_id not in self._proposals:
                return False

            if artifact_id in self._decisions:
                return False

            # Set decided_at if not provided
            if not decision.decided_at.ByteSize():
                decision.decided_at.CopyFrom(_current_timestamp())

            self._decisions[artifact_id] = decision

            # Signal waiting clients
            event = self._decision_events.get(artifact_id)
            if event:
                event.set()

            outcome_name = negotiation_room_pb2.DecisionOutcome.Name(decision.outcome)
            logger.info(
                f"Decision stored: {artifact_id} -> {outcome_name}"
            )

        return True

    def aggregate_votes(
        self,
        artifact_id: str
    ) -> Optional[negotiation_room_pb2.AggregatedScore]:
        """
        Compute aggregated statistics for votes on an artifact.

        Args:
            artifact_id: The artifact to aggregate votes for

        Returns:
            AggregatedScore with statistics, or None if no votes
        """
        with self._lock:
            votes = self._votes.get(artifact_id, [])
            if not votes:
                return None

            scores = [v.score for v in votes]
            confidences = [v.confidence for v in votes]

            # Basic statistics
            mean = sum(scores) / len(scores)
            min_score = min(scores)
            max_score = max(scores)

            # Standard deviation
            variance = sum((s - mean) ** 2 for s in scores) / len(scores)
            std_dev = math.sqrt(variance)

            # Confidence-weighted mean
            total_confidence = sum(confidences)
            if total_confidence > 0:
                weighted_mean = sum(
                    s * c for s, c in zip(scores, confidences)
                ) / total_confidence
            else:
                weighted_mean = mean

        return negotiation_room_pb2.AggregatedScore(
            mean=mean,
            min_score=min_score,
            max_score=max_score,
            std_dev=std_dev,
            weighted_mean=weighted_mean,
            vote_count=len(votes)
        )

    def get_proposal(
        self,
        artifact_id: str
    ) -> Optional[negotiation_room_pb2.NegotiationProposal]:
        """Get a proposal by artifact_id (internal use)."""
        with self._lock:
            return self._proposals.get(artifact_id)

    def list_proposals(
        self,
        negotiation_room_id: Optional[str] = None
    ) -> List[negotiation_room_pb2.NegotiationProposal]:
        """
        List all proposals, optionally filtered by room.

        Args:
            negotiation_room_id: If provided, filter by room

        Returns:
            List of matching proposals
        """
        with self._lock:
            proposals = list(self._proposals.values())
            if negotiation_room_id:
                proposals = [
                    p for p in proposals
                    if p.negotiation_room_id == negotiation_room_id
                ]
        return proposals

    def clear_all(self) -> None:
        """Clear all negotiation room data (for testing)."""
        with self._lock:
            self._proposals.clear()
            self._votes.clear()
            self._decisions.clear()
            # Clear events
            for event in self._decision_events.values():
                event.set()
            self._decision_events.clear()
            logger.info("NegotiationRoomService state cleared")
