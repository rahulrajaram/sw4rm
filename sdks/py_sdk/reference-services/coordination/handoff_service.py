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
Handoff Service gRPC Server Implementation.

This module provides the gRPC server implementation for the HandoffService,
enabling distributed agent-to-agent task handoffs with centralized state.

The service maintains:
- Handoff requests indexed by request_id
- Pending handoffs indexed by target agent_id
- Handoff status tracking (pending, accepted, rejected, completed, expired)

Example usage:
    from coordination.handoff_service import HandoffServiceImpl
    from sw4rm.protos import handoff_pb2_grpc

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    handoff_pb2_grpc.add_HandoffServiceServicer_to_server(
        HandoffServiceImpl(), server
    )
"""

import logging
import threading
import time
from typing import Dict, Set, Optional

import grpc

from sw4rm.protos import handoff_pb2, handoff_pb2_grpc, common_pb2

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger(__name__)


class HandoffServiceImpl(handoff_pb2_grpc.HandoffServiceServicer):
    """
    gRPC server implementation for HandoffService.

    Provides centralized handoff coordination for distributed agent deployments.
    Thread-safe implementation using RLock for all state mutations.

    State storage:
    - requests: Dict[request_id, HandoffRequest] - all handoff requests
    - responses: Dict[request_id, HandoffResponse] - responses for completed handoffs
    - pending_by_agent: Dict[agent_id, Set[request_id]] - pending handoffs per agent
    - status: Dict[request_id, HandoffStatus] - current status of each handoff
    """

    def __init__(self):
        """Initialize the handoff service with empty state."""
        self._lock = threading.RLock()
        self._requests: Dict[str, handoff_pb2.HandoffRequest] = {}
        self._responses: Dict[str, handoff_pb2.HandoffResponse] = {}
        self._pending_by_agent: Dict[str, Set[str]] = {}
        self._status: Dict[str, int] = {}  # HandoffStatus enum values
        logger.info("HandoffService initialized")

    def RequestHandoff(
        self,
        request: handoff_pb2.HandoffRequest,
        context: grpc.ServicerContext
    ) -> common_pb2.Empty:
        """
        Request a handoff to another agent.

        Creates a new handoff request and adds it to the pending queue for
        the target agent. The handoff remains in PENDING status until
        accepted or rejected.

        Args:
            request: HandoffRequest containing from_agent, to_agent, reason,
                    context_snapshot, and other handoff parameters
            context: gRPC context

        Returns:
            Empty response on success

        Raises:
            ALREADY_EXISTS: If a request with the same request_id exists
            INVALID_ARGUMENT: If request_id, from_agent, or to_agent is empty
        """
        request_id = request.request_id
        from_agent = request.from_agent
        to_agent = request.to_agent

        # Validate required fields
        if not request_id:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details("request_id is required")
            return common_pb2.Empty()

        if not from_agent:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details("from_agent is required")
            return common_pb2.Empty()

        if not to_agent:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details("to_agent is required")
            return common_pb2.Empty()

        with self._lock:
            if request_id in self._requests:
                context.set_code(grpc.StatusCode.ALREADY_EXISTS)
                context.set_details(f"Handoff request '{request_id}' already exists")
                return common_pb2.Empty()

            # Store the request
            self._requests[request_id] = request
            self._status[request_id] = handoff_pb2.HandoffStatus.PENDING

            # Add to pending queue for target agent
            if to_agent not in self._pending_by_agent:
                self._pending_by_agent[to_agent] = set()
            self._pending_by_agent[to_agent].add(request_id)

            logger.info(
                f"Handoff requested: {request_id} from {from_agent} to {to_agent}"
            )

        return common_pb2.Empty()

    def AcceptHandoff(
        self,
        request: handoff_pb2.HandoffResponse,
        context: grpc.ServicerContext
    ) -> common_pb2.Empty:
        """
        Accept a pending handoff request.

        Marks the handoff as ACCEPTED and stores the response. Removes the
        handoff from the pending queue for the target agent.

        Args:
            request: HandoffResponse with request_id and accepting_agent
            context: gRPC context

        Returns:
            Empty response on success

        Raises:
            NOT_FOUND: If no request exists with the given request_id
            FAILED_PRECONDITION: If the handoff is not in PENDING status
        """
        request_id = request.request_id

        with self._lock:
            if request_id not in self._requests:
                context.set_code(grpc.StatusCode.NOT_FOUND)
                context.set_details(f"Handoff request '{request_id}' not found")
                return common_pb2.Empty()

            current_status = self._status.get(request_id)
            if current_status != handoff_pb2.HandoffStatus.PENDING:
                context.set_code(grpc.StatusCode.FAILED_PRECONDITION)
                context.set_details(
                    f"Handoff '{request_id}' is not in PENDING status"
                )
                return common_pb2.Empty()

            # Update status and store response
            self._status[request_id] = handoff_pb2.HandoffStatus.ACCEPTED

            # Create and store the response
            response = handoff_pb2.HandoffResponse(
                request_id=request_id,
                accepted=True,
                accepting_agent=request.accepting_agent or "",
                rejection_reason=""
            )
            self._responses[request_id] = response

            # Remove from pending queue
            original_request = self._requests[request_id]
            to_agent = original_request.to_agent
            if to_agent in self._pending_by_agent:
                self._pending_by_agent[to_agent].discard(request_id)

            logger.info(
                f"Handoff accepted: {request_id} by {request.accepting_agent}"
            )

        return common_pb2.Empty()

    def RejectHandoff(
        self,
        request: handoff_pb2.HandoffResponse,
        context: grpc.ServicerContext
    ) -> common_pb2.Empty:
        """
        Reject a pending handoff request.

        Marks the handoff as REJECTED and stores the response with the
        rejection reason. Removes the handoff from the pending queue.

        Args:
            request: HandoffResponse with request_id and rejection_reason
            context: gRPC context

        Returns:
            Empty response on success

        Raises:
            NOT_FOUND: If no request exists with the given request_id
            FAILED_PRECONDITION: If the handoff is not in PENDING status
        """
        request_id = request.request_id

        with self._lock:
            if request_id not in self._requests:
                context.set_code(grpc.StatusCode.NOT_FOUND)
                context.set_details(f"Handoff request '{request_id}' not found")
                return common_pb2.Empty()

            current_status = self._status.get(request_id)
            if current_status != handoff_pb2.HandoffStatus.PENDING:
                context.set_code(grpc.StatusCode.FAILED_PRECONDITION)
                context.set_details(
                    f"Handoff '{request_id}' is not in PENDING status"
                )
                return common_pb2.Empty()

            # Update status and store response
            self._status[request_id] = handoff_pb2.HandoffStatus.REJECTED

            response = handoff_pb2.HandoffResponse(
                request_id=request_id,
                accepted=False,
                accepting_agent="",
                rejection_reason=request.rejection_reason or "Rejected"
            )
            self._responses[request_id] = response

            # Remove from pending queue
            original_request = self._requests[request_id]
            to_agent = original_request.to_agent
            if to_agent in self._pending_by_agent:
                self._pending_by_agent[to_agent].discard(request_id)

            logger.info(
                f"Handoff rejected: {request_id}, reason: {request.rejection_reason}"
            )

        return common_pb2.Empty()

    def GetPendingHandoffs(
        self,
        request: handoff_pb2.GetPendingHandoffsRequest,
        context: grpc.ServicerContext
    ) -> handoff_pb2.GetPendingHandoffsResponse:
        """
        Get all pending handoff requests for an agent.

        Returns all handoff requests that are in PENDING status and
        addressed to the specified agent.

        Args:
            request: GetPendingHandoffsRequest with agent_id
            context: gRPC context

        Returns:
            GetPendingHandoffsResponse with list of pending HandoffRequests
        """
        agent_id = request.agent_id

        with self._lock:
            pending_ids = self._pending_by_agent.get(agent_id, set())
            pending_requests = []

            for request_id in pending_ids:
                if request_id in self._requests:
                    status = self._status.get(request_id)
                    if status == handoff_pb2.HandoffStatus.PENDING:
                        pending_requests.append(self._requests[request_id])

            logger.debug(
                f"GetPendingHandoffs for {agent_id}: {len(pending_requests)} pending"
            )

        return handoff_pb2.GetPendingHandoffsResponse(
            pending_requests=pending_requests
        )

    def CompleteHandoff(
        self,
        request: handoff_pb2.CompleteHandoffRequest,
        context: grpc.ServicerContext
    ) -> handoff_pb2.CompleteHandoffResponse:
        """
        Complete or expire a handoff.

        Updates the handoff status to COMPLETED or EXPIRED. This is called
        after the receiving agent has processed the handoff or when the
        handoff times out.

        Args:
            request: CompleteHandoffRequest with request_id and status
            context: gRPC context

        Returns:
            CompleteHandoffResponse with success flag and message

        Raises:
            NOT_FOUND: If no request exists with the given request_id
        """
        request_id = request.request_id
        new_status = request.status

        with self._lock:
            if request_id not in self._requests:
                return handoff_pb2.CompleteHandoffResponse(
                    success=False,
                    message=f"Handoff request '{request_id}' not found"
                )

            old_status = self._status.get(request_id)
            self._status[request_id] = new_status

            # Clean up pending queue if still there
            original_request = self._requests[request_id]
            to_agent = original_request.to_agent
            if to_agent in self._pending_by_agent:
                self._pending_by_agent[to_agent].discard(request_id)

            status_name = handoff_pb2.HandoffStatus.Name(new_status)
            logger.info(
                f"Handoff completed: {request_id} with status {status_name}"
            )

        return handoff_pb2.CompleteHandoffResponse(
            success=True,
            message=f"Handoff '{request_id}' marked as {status_name}"
        )

    # Additional helper methods for service management

    def get_handoff_status(self, request_id: str) -> Optional[int]:
        """Get the current status of a handoff (internal use)."""
        with self._lock:
            return self._status.get(request_id)

    def get_handoff_response(self, request_id: str) -> Optional[handoff_pb2.HandoffResponse]:
        """Get the response for a handoff if available (internal use)."""
        with self._lock:
            return self._responses.get(request_id)

    def clear_all(self) -> None:
        """Clear all handoff data (for testing)."""
        with self._lock:
            self._requests.clear()
            self._responses.clear()
            self._pending_by_agent.clear()
            self._status.clear()
            logger.info("HandoffService state cleared")
