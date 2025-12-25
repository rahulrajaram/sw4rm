"""Client for managing agent handoffs.

This module provides the HandoffClient class for managing handoff requests,
responses, and pending handoffs between agents.
"""

from __future__ import annotations

import uuid
from typing import Any, Optional
from collections import defaultdict
from threading import Lock

from sw4rm.handoff.types import HandoffRequest, HandoffResponse, HandoffStatus


# Shared in-memory storage for handoffs (for development/testing)
# In production, this would be replaced by a distributed service
_shared_handoffs: dict[str, tuple[HandoffRequest, HandoffResponse]] = {}
_shared_pending_by_agent: dict[str, list[str]] = defaultdict(list)
_shared_lock = Lock()


class HandoffClient:
    """Client for managing agent handoff operations.

    This client provides methods for requesting handoffs, accepting/rejecting
    handoff requests, and querying pending handoffs. It maintains an in-memory
    store of handoff requests and their statuses.

    In a production system, this would interface with a distributed handoff
    service via gRPC. For now, it provides a local implementation suitable
    for development and testing.
    """

    def __init__(self, channel: Optional[Any] = None) -> None:
        """Initialize the HandoffClient.

        Args:
            channel: Optional gRPC channel for communication with handoff service.
                If None, uses shared in-memory storage (for development/testing).
        """
        self._channel = channel

        # Placeholder for future gRPC stub
        self._stub = None
        if channel:
            try:
                # Future: from sw4rm.protos import handoff_pb2, handoff_pb2_grpc
                # self._pb2 = handoff_pb2
                # self._stub = handoff_pb2_grpc.HandoffServiceStub(channel)
                pass
            except Exception:
                pass

    def request_handoff(self, request: HandoffRequest) -> HandoffResponse:
        """Request a handoff to another agent.

        Creates a new handoff request and returns a response with a unique
        handoff ID. The handoff will be in PENDING status until the target
        agent accepts or rejects it.

        Args:
            request: The handoff request containing from_agent, to_agent,
                reason, context, and other parameters

        Returns:
            HandoffResponse with accepted=True (pending acceptance), handoff_id,
            and status=PENDING

        Raises:
            RuntimeError: If gRPC stub is configured but not available
        """
        if self._stub:
            # Future: Use gRPC stub
            raise RuntimeError("gRPC handoff service not yet implemented")

        # In-memory implementation
        handoff_id = str(uuid.uuid4())
        response = HandoffResponse(
            accepted=True,  # Accepted for processing, but status is PENDING
            handoff_id=handoff_id,
            status=HandoffStatus.PENDING,
            metadata={"created_at": self._get_timestamp()}
        )

        with _shared_lock:
            _shared_handoffs[handoff_id] = (request, response)
            _shared_pending_by_agent[request.to_agent].append(handoff_id)

        return response

    def accept_handoff(self, handoff_id: str) -> HandoffResponse:
        """Accept a pending handoff request.

        Updates the handoff status to ACCEPTED and returns the updated response.

        Args:
            handoff_id: Unique identifier of the handoff to accept

        Returns:
            Updated HandoffResponse with accepted=True and status=ACCEPTED

        Raises:
            ValueError: If handoff_id is not found or handoff is not in PENDING status
            RuntimeError: If gRPC stub is configured but not available
        """
        if self._stub:
            # Future: Use gRPC stub
            raise RuntimeError("gRPC handoff service not yet implemented")

        with _shared_lock:
            if handoff_id not in _shared_handoffs:
                raise ValueError(f"Handoff {handoff_id} not found")

            request, response = _shared_handoffs[handoff_id]

            if response.status != HandoffStatus.PENDING:
                raise ValueError(
                    f"Handoff {handoff_id} is not in PENDING status "
                    f"(current: {response.status.value})"
                )

            # Update response
            response.accepted = True
            response.status = HandoffStatus.ACCEPTED
            response.metadata["accepted_at"] = self._get_timestamp()

            # Remove from pending list
            if handoff_id in _shared_pending_by_agent[request.to_agent]:
                _shared_pending_by_agent[request.to_agent].remove(handoff_id)

            return response

    def reject_handoff(self, handoff_id: str, reason: str) -> HandoffResponse:
        """Reject a pending handoff request.

        Updates the handoff status to REJECTED with the provided reason.

        Args:
            handoff_id: Unique identifier of the handoff to reject
            reason: Human-readable explanation of why the handoff was rejected

        Returns:
            Updated HandoffResponse with accepted=False, status=REJECTED,
            and rejection_reason set

        Raises:
            ValueError: If handoff_id is not found or handoff is not in PENDING status
            RuntimeError: If gRPC stub is configured but not available
        """
        if self._stub:
            # Future: Use gRPC stub
            raise RuntimeError("gRPC handoff service not yet implemented")

        with _shared_lock:
            if handoff_id not in _shared_handoffs:
                raise ValueError(f"Handoff {handoff_id} not found")

            request, response = _shared_handoffs[handoff_id]

            if response.status != HandoffStatus.PENDING:
                raise ValueError(
                    f"Handoff {handoff_id} is not in PENDING status "
                    f"(current: {response.status.value})"
                )

            # Update response
            response.accepted = False
            response.status = HandoffStatus.REJECTED
            response.rejection_reason = reason
            response.metadata["rejected_at"] = self._get_timestamp()

            # Remove from pending list
            if handoff_id in _shared_pending_by_agent[request.to_agent]:
                _shared_pending_by_agent[request.to_agent].remove(handoff_id)

            return response

    def complete_handoff(self, handoff_id: str) -> HandoffResponse:
        """Mark a handoff as completed.

        Updates the handoff status to COMPLETED after the receiving agent
        has successfully taken over execution.

        Args:
            handoff_id: Unique identifier of the handoff to complete

        Returns:
            Updated HandoffResponse with status=COMPLETED

        Raises:
            ValueError: If handoff_id is not found or handoff is not in ACCEPTED status
            RuntimeError: If gRPC stub is configured but not available
        """
        if self._stub:
            # Future: Use gRPC stub
            raise RuntimeError("gRPC handoff service not yet implemented")

        with _shared_lock:
            if handoff_id not in _shared_handoffs:
                raise ValueError(f"Handoff {handoff_id} not found")

            request, response = _shared_handoffs[handoff_id]

            if response.status != HandoffStatus.ACCEPTED:
                raise ValueError(
                    f"Handoff {handoff_id} is not in ACCEPTED status "
                    f"(current: {response.status.value})"
                )

            # Update response
            response.status = HandoffStatus.COMPLETED
            response.metadata["completed_at"] = self._get_timestamp()

            return response

    def get_pending_handoffs(self, agent_id: str) -> list[HandoffRequest]:
        """Get all pending handoffs for a specific agent.

        Returns all handoff requests that are waiting for the specified
        agent to accept or reject them.

        Args:
            agent_id: ID of the agent to query for pending handoffs

        Returns:
            List of HandoffRequest objects in PENDING status for this agent

        Raises:
            RuntimeError: If gRPC stub is configured but not available
        """
        if self._stub:
            # Future: Use gRPC stub
            raise RuntimeError("gRPC handoff service not yet implemented")

        with _shared_lock:
            pending_ids = _shared_pending_by_agent.get(agent_id, [])
            requests = []
            for handoff_id in pending_ids:
                if handoff_id in _shared_handoffs:
                    request, response = _shared_handoffs[handoff_id]
                    if response.status == HandoffStatus.PENDING:
                        requests.append(request)
            return requests

    def get_handoff_status(self, handoff_id: str) -> Optional[HandoffResponse]:
        """Get the current status of a handoff.

        Args:
            handoff_id: Unique identifier of the handoff

        Returns:
            HandoffResponse if found, None otherwise

        Raises:
            RuntimeError: If gRPC stub is configured but not available
        """
        if self._stub:
            # Future: Use gRPC stub
            raise RuntimeError("gRPC handoff service not yet implemented")

        with _shared_lock:
            if handoff_id in _shared_handoffs:
                _, response = _shared_handoffs[handoff_id]
                return response
            return None

    def _get_timestamp(self) -> str:
        """Get current timestamp as ISO string.

        Returns:
            ISO 8601 formatted timestamp string
        """
        from datetime import datetime, timezone
        return datetime.now(timezone.utc).isoformat()

    @staticmethod
    def clear_all_handoffs() -> None:
        """Clear all handoff data from shared storage.

        This is primarily for testing purposes. In production, this would not
        be available as handoff data would be managed by a distributed service.
        """
        global _shared_handoffs, _shared_pending_by_agent
        with _shared_lock:
            _shared_handoffs.clear()
            _shared_pending_by_agent.clear()
