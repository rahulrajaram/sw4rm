from __future__ import annotations

from typing import Any


class ReasoningClient:
    """Client for interacting with the ReasoningProxy service.

    The ReasoningProxy provides AI-powered reasoning capabilities including
    parallelism checking, debate evaluation, and text summarization.
    """

    def __init__(self, channel: Any) -> None:
        """Initialize the ReasoningClient.

        Args:
            channel: gRPC channel to use for communication
        """
        self._channel = channel
        try:
            from sw4rm.protos import reasoning_pb2, reasoning_pb2_grpc  # type: ignore
            self._pb2 = reasoning_pb2
            self._stub = reasoning_pb2_grpc.ReasoningProxyStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def check_parallelism(self, scope_a: str, scope_b: str) -> Any:
        """Check if two scopes can be executed in parallel.

        Uses AI reasoning to determine if two task scopes are independent
        and can be safely executed concurrently.

        Args:
            scope_a: Description of the first task scope
            scope_b: Description of the second task scope

        Returns:
            ParallelismCheckResponse with:
                - confidence_score (float): Confidence that scopes are parallel (0-1)
                - notes (str): Explanation of the reasoning

        Raises:
            RuntimeError: If protobuf stubs are not generated
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.ParallelismCheckRequest(scope_a=scope_a, scope_b=scope_b)
        return self._stub.CheckParallelism(req)

    def evaluate_debate(
        self,
        negotiation_id: str,
        proposal_a: str,
        proposal_b: str,
        intensity: str = "low"
    ) -> Any:
        """Evaluate competing proposals in a debate or negotiation.

        Uses AI reasoning to compare and evaluate two competing proposals,
        typically used in agent negotiation scenarios.

        Args:
            negotiation_id: Unique identifier for the negotiation session
            proposal_a: First proposal to evaluate
            proposal_b: Second proposal to evaluate
            intensity: Debate intensity level (e.g., "low", "medium", "high")

        Returns:
            DebateEvaluateResponse with:
                - confidence_score (float): Confidence in the evaluation (0-1)
                - notes (str): Detailed evaluation and reasoning

        Raises:
            RuntimeError: If protobuf stubs are not generated
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.DebateEvaluateRequest(
            negotiation_id=negotiation_id,
            proposal_a=proposal_a,
            proposal_b=proposal_b,
            intensity=intensity
        )
        return self._stub.EvaluateDebate(req)

    def summarize(
        self,
        session_id: str,
        segments: list[dict[str, Any]],
        max_tokens: int = 256,
        mode: str = "rolling"
    ) -> Any:
        """Summarize text segments using AI.

        Generates a concise summary of multiple text segments, useful for
        condensing long conversations or documentation.

        Args:
            session_id: Unique identifier for the summarization session
            segments: List of text segments, each containing:
                - kind (str): Type of segment (e.g., "user", "assistant", "system")
                - content (str): Text content of the segment
                - seq (int): Sequence number
                - at (str): Timestamp or position marker
            max_tokens: Maximum number of tokens in the summary (default: 256)
            mode: Summarization mode (e.g., "rolling", "full") (default: "rolling")

        Returns:
            SummarizeResponse with:
                - summary (str): Generated summary text
                - tokens (int): Number of tokens used
                - cost_cents (float): Cost of the operation in cents
                - model (str): AI model used for summarization

        Raises:
            RuntimeError: If protobuf stubs are not generated
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        pb_segments = [
            self._pb2.TextSegment(
                kind=s.get("kind", ""),
                content=s.get("content", ""),
                seq=int(s.get("seq", 0)),
                at=s.get("at", "")
            )
            for s in segments
        ]
        req = self._pb2.SummarizeRequest(
            session_id=session_id,
            segments=pb_segments,
            max_tokens=max_tokens,
            mode=mode
        )
        return self._stub.Summarize(req)
