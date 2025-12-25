from __future__ import annotations

from typing import Any, Iterable


class NegotiationClient:
    """Client for managing multi-agent negotiation sessions.

    The NegotiationClient provides access to the NegotiationService, which
    enables collaborative decision-making between multiple agents through
    proposals, counter-proposals, evaluations, and final decisions.

    Negotiation Workflow:
        1. open() - Initiate a negotiation session with participants
        2. propose() - First agent submits initial proposal
        3. counter() - Other agents submit counter-proposals (multiple rounds)
        4. evaluate() - Agents evaluate current proposals with confidence scores
        5. decide() - Coordinator makes final decision to close negotiation
        6. abort() - Cancel negotiation if needed

    The negotiation service supports configurable debate intensity levels
    (LOWEST to HIGHEST) and timeouts to control the negotiation process.

    Example:
        >>> import grpc
        >>> channel = grpc.insecure_channel("localhost:50056")
        >>> client = NegotiationClient(channel)
        >>> client.open(
        ...     negotiation_id="neg-1",
        ...     correlation_id="wf-1",
        ...     topic="API Design",
        ...     participants=["agent-1", "agent-2"]
        ... )
    """

    def __init__(self, channel: Any) -> None:
        """Initialize the NegotiationClient.

        Args:
            channel: gRPC channel connected to the NegotiationService.
        """
        self._channel = channel
        try:
            from sw4rm.protos import negotiation_pb2, negotiation_pb2_grpc  # type: ignore
            self._pb2 = negotiation_pb2
            self._stub = negotiation_pb2_grpc.NegotiationServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def open(
        self,
        negotiation_id: str,
        correlation_id: str,
        topic: str,
        participants: list[str],
        intensity: int = 0,
        debate_timeout_seconds: int | None = None,
    ) -> Any:
        """Open a new negotiation session.

        Initiates a multi-agent negotiation with specified participants and
        parameters. The negotiation remains open until a decision is made or
        it is aborted.

        Args:
            negotiation_id: Unique identifier for this negotiation session.
            correlation_id: Identifier linking this negotiation to a larger workflow.
            topic: Human-readable description of what is being negotiated.
            participants: List of agent IDs that will participate in the negotiation.
            intensity: Debate intensity level (0=LOWEST to 4=HIGHEST, default 0).
            debate_timeout_seconds: Optional timeout in seconds for the entire negotiation.

        Returns:
            NegotiationOpenResponse confirming the session was opened.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> client.open(
            ...     negotiation_id="neg-design-123",
            ...     correlation_id="workflow-456",
            ...     topic="API Design Review",
            ...     participants=["architect-1", "security-reviewer", "api-reviewer"],
            ...     intensity=2,
            ...     debate_timeout_seconds=600
            ... )
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        duration = None
        if debate_timeout_seconds is not None:
            duration = self._pb2.google_dot_protobuf_dot_duration__pb2.Duration(
                seconds=debate_timeout_seconds
            )
        req = self._pb2.NegotiationOpen(
            negotiation_id=negotiation_id,
            correlation_id=correlation_id,
            topic=topic,
            participants=participants,
            intensity=intensity,
            debate_timeout=duration,
        )
        return self._stub.Open(req)

    def propose(
        self,
        negotiation_id: str,
        from_agent: str,
        content_type: str,
        payload: bytes,
    ) -> Any:
        """Submit an initial proposal to a negotiation.

        The first agent to submit a proposal defines the starting point for
        the negotiation. Other agents will respond with counter-proposals or
        evaluations.

        Args:
            negotiation_id: Unique identifier of the negotiation session.
            from_agent: Agent ID submitting the proposal.
            content_type: MIME type or content type of the payload.
            payload: Binary payload containing the proposal (e.g., JSON, protobuf).

        Returns:
            ProposalResponse confirming the proposal was recorded.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> import json
            >>> proposal = {"endpoint": "/api/v2/users", "method": "POST"}
            >>> client.propose(
            ...     negotiation_id="neg-123",
            ...     from_agent="architect-1",
            ...     content_type="application/json",
            ...     payload=json.dumps(proposal).encode()
            ... )
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.Proposal(
            negotiation_id=negotiation_id,
            from_agent=from_agent,
            content_type=content_type,
            payload=payload,
        )
        return self._stub.Propose(req)

    def counter(
        self,
        negotiation_id: str,
        from_agent: str,
        content_type: str,
        payload: bytes,
    ) -> Any:
        """Submit a counter-proposal to a negotiation.

        Agents use counter-proposals to suggest modifications to the current
        proposal. Multiple rounds of counter-proposals can occur until consensus
        is reached or the negotiation is decided/aborted.

        Args:
            negotiation_id: Unique identifier of the negotiation session.
            from_agent: Agent ID submitting the counter-proposal.
            content_type: MIME type or content type of the payload.
            payload: Binary payload containing the counter-proposal.

        Returns:
            CounterProposalResponse confirming the counter was recorded.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> import json
            >>> counter = {"endpoint": "/api/v2/users", "method": "POST", "auth": "required"}
            >>> client.counter(
            ...     negotiation_id="neg-123",
            ...     from_agent="security-agent",
            ...     content_type="application/json",
            ...     payload=json.dumps(counter).encode()
            ... )
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.CounterProposal(
            negotiation_id=negotiation_id,
            from_agent=from_agent,
            content_type=content_type,
            payload=payload,
        )
        return self._stub.Counter(req)

    def evaluate(
        self,
        negotiation_id: str,
        from_agent: str,
        confidence_score: float | None = None,
        notes: str = "",
    ) -> Any:
        """Submit an evaluation of the current proposal.

        Agents evaluate proposals to indicate their level of agreement or
        satisfaction. The confidence score (0.0-1.0) indicates how confident
        the agent is in their evaluation.

        Args:
            negotiation_id: Unique identifier of the negotiation session.
            from_agent: Agent ID submitting the evaluation.
            confidence_score: Confidence level from 0.0 (uncertain) to 1.0 (certain).
            notes: Optional qualitative feedback or explanation.

        Returns:
            EvaluationResponse confirming the evaluation was recorded.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> client.evaluate(
            ...     negotiation_id="neg-123",
            ...     from_agent="reviewer-1",
            ...     confidence_score=0.85,
            ...     notes="Looks good but needs more error handling"
            ... )
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.Evaluation(
            negotiation_id=negotiation_id,
            from_agent=from_agent,
            confidence_score=confidence_score or 0.0,
            notes=notes,
        )
        return self._stub.Evaluate(req)

    def decide(
        self,
        negotiation_id: str,
        decided_by: str,
        content_type: str,
        result: bytes,
    ) -> Any:
        """Make a final decision to conclude the negotiation.

        Typically called by a coordinator or lead agent to finalize the
        negotiation with the agreed-upon outcome. This closes the negotiation.

        Args:
            negotiation_id: Unique identifier of the negotiation session.
            decided_by: Agent ID making the final decision.
            content_type: MIME type or content type of the result.
            result: Binary payload containing the final decision/agreement.

        Returns:
            DecisionResponse confirming the decision was recorded and negotiation closed.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> import json
            >>> decision = {"endpoint": "/api/v2/users", "method": "POST", "approved": True}
            >>> client.decide(
            ...     negotiation_id="neg-123",
            ...     decided_by="coordinator-1",
            ...     content_type="application/json",
            ...     result=json.dumps(decision).encode()
            ... )
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.Decision(
            negotiation_id=negotiation_id,
            decided_by=decided_by,
            content_type=content_type,
            result=result,
        )
        return self._stub.Decide(req)

    def abort(self, negotiation_id: str, reason: str = "") -> Any:
        """Abort an ongoing negotiation.

        Terminates the negotiation without reaching a decision. This can be
        called when the negotiation is no longer relevant or has reached an
        impasse.

        Args:
            negotiation_id: Unique identifier of the negotiation session.
            reason: Optional explanation for why the negotiation is being aborted.

        Returns:
            AbortResponse confirming the negotiation was aborted.

        Raises:
            RuntimeError: If protobuf stubs are not generated.
            grpc.RpcError: If the RPC call fails.

        Example:
            >>> client.abort(
            ...     negotiation_id="neg-123",
            ...     reason="Requirements changed, no longer applicable"
            ... )
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        # Updated to match proto rename: AbortRequest
        req = self._pb2.AbortRequest(negotiation_id=negotiation_id, reason=reason)
        return self._stub.Abort(req)

