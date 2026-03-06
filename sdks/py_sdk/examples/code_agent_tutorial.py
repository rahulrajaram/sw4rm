#!/usr/bin/env python3
"""Code-Agent Tutorial — 3-agent code review swarm using SW4RM.

Demonstrates a realistic multi-agent workflow:
  1. WriterAgent generates code (stubbed LLM)
  2. Two ReviewerAgents vote on quality (correctness + style)
  3. Coordinator aggregates votes and decides: APPROVED or REVISION_REQUESTED
  4. If approved: handoff to DeployerAgent via SW4RM Handoff protocol
  5. If revision: feedback logged (no retry in this tutorial)

Runs standalone in mock mode — no gRPC services needed.

Usage:
    cd sdks/py_sdk
    python examples/code_agent_tutorial.py
"""

import sys
import os

# Ensure the SDK is importable when running from repo root
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sw4rm.clients.negotiation_room import NegotiationRoomClient
from sw4rm.negotiation_types import (
    AggregatedScore,
    ArtifactType,
    DecisionOutcome,
    NegotiationDecision,
    NegotiationProposal,
    NegotiationVote,
    aggregate_votes,
)
from sw4rm.clients.handoff import HandoffClient
from sw4rm.handoff.types import HandoffRequest
from sw4rm.handoff.context import HandoffContext, serialize_context, deserialize_context


# ---------------------------------------------------------------------------
# Agent definitions (stubbed — replace with real LLM calls)
# ---------------------------------------------------------------------------

FIBONACCI_CODE = '''\
def fibonacci(n: int) -> list[int]:
    """Return the first n Fibonacci numbers."""
    if n <= 0:
        return []
    if n == 1:
        return [0]
    fibs = [0, 1]
    for _ in range(2, n):
        fibs.append(fibs[-1] + fibs[-2])
    return fibs
'''

ROOM_ID = "code-review-room-1"
ARTIFACT_ID = "fib-v1"


class WriterAgent:
    """Generates code artifacts. In production, wraps an LLM."""

    agent_id = "writer-agent"

    def generate(self, prompt: str) -> str:
        """Return generated code (stubbed)."""
        print(f"  [{self.agent_id}] Generating code for: {prompt}")
        print(f"  [{self.agent_id}] Produced fibonacci implementation ({len(FIBONACCI_CODE)} chars)")
        return FIBONACCI_CODE


class ReviewerAgent:
    """Reviews code artifacts and votes. In production, wraps an LLM."""

    def __init__(self, agent_id: str, focus: str, score: float, confidence: float):
        self.agent_id = agent_id
        self.focus = focus
        self._score = score
        self._confidence = confidence

    def review(self, code: str) -> NegotiationVote:
        """Review code and return a vote (stubbed)."""
        print(f"  [{self.agent_id}] Reviewing code (focus: {self.focus})...")

        passed = self._score >= 6.0
        vote = NegotiationVote(
            artifact_id=ARTIFACT_ID,
            critic_id=self.agent_id,
            score=self._score,
            confidence=self._confidence,
            passed=passed,
            strengths=self._get_strengths(),
            weaknesses=self._get_weaknesses(),
            recommendations=self._get_recommendations(),
            negotiation_room_id=ROOM_ID,
        )
        print(f"  [{self.agent_id}] Score: {self._score}/10 "
              f"(confidence: {self._confidence}) — {'PASS' if passed else 'FAIL'}")
        return vote

    def _get_strengths(self) -> list:
        if self.focus == "correctness":
            return ["Handles edge cases (n<=0, n==1)", "Efficient iterative approach"]
        return ["Clean function signature", "Type hints present", "Docstring included"]

    def _get_weaknesses(self) -> list:
        if self.focus == "correctness":
            return ["No input validation for non-integer types"]
        return ["Could use more descriptive variable name than 'fibs'"]

    def _get_recommendations(self) -> list:
        if self.focus == "correctness":
            return ["Add isinstance check or let TypeError propagate"]
        return ["Consider 'sequence' instead of 'fibs'"]


class DeployerAgent:
    """Deploys approved code. In production, wraps CI/CD tooling."""

    agent_id = "deployer-agent"

    def deploy(self, code: str, context: HandoffContext) -> str:
        """Deploy code (stubbed)."""
        print(f"  [{self.agent_id}] Received handoff with "
              f"{len(context.conversation_history)} history entries")
        print(f"  [{self.agent_id}] Deploying {len(code)} chars of code...")
        print(f"  [{self.agent_id}] Deployment successful (stubbed)")
        return "deploy-id-001"


# ---------------------------------------------------------------------------
# Coordinator — orchestrates the full workflow
# ---------------------------------------------------------------------------

APPROVAL_THRESHOLD = 7.0  # Weighted mean must be >= 7.0
ALL_MUST_PASS = True       # All reviewers must individually pass


def run_code_review_swarm():
    """Run the complete code-review swarm workflow."""

    print("=" * 60)
    print("  SW4RM Code-Agent Tutorial")
    print("  3-Agent Code Review Swarm")
    print("=" * 60)

    # --- Initialize agents ---
    writer = WriterAgent()
    reviewer_correctness = ReviewerAgent(
        "reviewer-correctness", "correctness", score=8.5, confidence=0.9,
    )
    reviewer_style = ReviewerAgent(
        "reviewer-style", "style", score=7.5, confidence=0.85,
    )
    deployer = DeployerAgent()

    # --- Initialize SW4RM clients (in-process mock mode) ---
    negotiation = NegotiationRoomClient()
    handoff_client = HandoffClient()

    # =========================================================
    # Step 1: Writer generates code
    # =========================================================
    print("\n--- Step 1: Code Generation ---")
    code = writer.generate("Write a fibonacci function in Python")

    # =========================================================
    # Step 2: Submit proposal to negotiation room
    # =========================================================
    print("\n--- Step 2: Submit Proposal ---")
    proposal = NegotiationProposal(
        artifact_type=ArtifactType.CODE,
        artifact_id=ARTIFACT_ID,
        producer_id=writer.agent_id,
        artifact=code.encode("utf-8"),
        artifact_content_type="text/x-python",
        requested_critics=[
            reviewer_correctness.agent_id,
            reviewer_style.agent_id,
        ],
        negotiation_room_id=ROOM_ID,
    )
    artifact_id = negotiation.submit_proposal(proposal)
    print(f"  Proposal submitted: artifact_id={artifact_id}")

    # =========================================================
    # Step 3: Reviewers vote
    # =========================================================
    print("\n--- Step 3: Code Review ---")
    vote_correctness = reviewer_correctness.review(code)
    negotiation.submit_vote(vote_correctness)

    vote_style = reviewer_style.review(code)
    negotiation.submit_vote(vote_style)

    # =========================================================
    # Step 4: Aggregate votes and decide
    # =========================================================
    print("\n--- Step 4: Vote Aggregation ---")
    votes = negotiation.get_votes(artifact_id)
    aggregated = aggregate_votes(votes)

    print(f"  Votes collected: {aggregated.vote_count}")
    print(f"  Mean score:      {aggregated.mean:.2f}")
    print(f"  Weighted mean:   {aggregated.weighted_mean:.2f}")
    print(f"  Score range:     [{aggregated.min_score:.1f}, {aggregated.max_score:.1f}]")
    print(f"  Std deviation:   {aggregated.std_dev:.2f}")

    all_passed = all(v.passed for v in votes)
    approved = (
        aggregated.weighted_mean >= APPROVAL_THRESHOLD
        and (all_passed or not ALL_MUST_PASS)
    )

    outcome = DecisionOutcome.APPROVED if approved else DecisionOutcome.REVISION_REQUESTED
    reason = (
        f"Weighted mean {aggregated.weighted_mean:.2f} >= {APPROVAL_THRESHOLD} "
        f"and all reviewers passed"
        if approved
        else f"Weighted mean {aggregated.weighted_mean:.2f} < {APPROVAL_THRESHOLD} "
        f"or not all reviewers passed"
    )

    decision = NegotiationDecision(
        artifact_id=artifact_id,
        outcome=outcome,
        votes=votes,
        aggregated_score=aggregated,
        policy_version="1.0",
        reason=reason,
        negotiation_room_id=ROOM_ID,
    )
    negotiation.store_decision(decision)
    print(f"\n  Decision: {outcome.name}")
    print(f"  Reason:   {reason}")

    # =========================================================
    # Step 5: Handoff or feedback loop
    # =========================================================
    if outcome == DecisionOutcome.APPROVED:
        print("\n--- Step 5: Handoff to Deployer ---")

        # Build handoff context with review history
        context = HandoffContext(
            conversation_history=[
                {"step": "generation", "agent": writer.agent_id, "output": "fibonacci code"},
                {"step": "review", "agent": reviewer_correctness.agent_id,
                 "score": vote_correctness.score, "passed": vote_correctness.passed},
                {"step": "review", "agent": reviewer_style.agent_id,
                 "score": vote_style.score, "passed": vote_style.passed},
                {"step": "decision", "outcome": outcome.name,
                 "weighted_mean": aggregated.weighted_mean},
            ],
            tool_state={"code": code, "artifact_id": artifact_id},
            metadata={"room_id": ROOM_ID},
        )

        # Serialize context for transport
        context_bytes = serialize_context(context)
        print(f"  Context serialized: {len(context_bytes)} bytes")

        # Request handoff
        handoff_req = HandoffRequest(
            from_agent=writer.agent_id,
            to_agent=deployer.agent_id,
            reason="Code approved — deploy to staging",
            context_snapshot=context_bytes,
            preserve_history=True,
            capabilities_required=["deployment"],
        )
        handoff_resp = handoff_client.request_handoff(handoff_req)
        print(f"  Handoff requested: id={handoff_resp.handoff_id}")

        # Deployer accepts
        accept_resp = handoff_client.accept_handoff(handoff_resp.handoff_id)
        print(f"  Handoff accepted:  status={accept_resp.status.value}")

        # Deployer deserializes context and deploys
        restored_context = deserialize_context(context_bytes)
        deploy_id = deployer.deploy(code, restored_context)

        # Complete handoff
        complete_resp = handoff_client.complete_handoff(handoff_resp.handoff_id)
        print(f"  Handoff completed: status={complete_resp.status.value}")
        print(f"  Deploy ID:         {deploy_id}")

    else:
        print("\n--- Step 5: Revision Requested ---")
        print("  Feedback for writer:")
        for v in votes:
            if v.weaknesses:
                print(f"    [{v.critic_id}] Weaknesses: {', '.join(v.weaknesses)}")
            if v.recommendations:
                print(f"    [{v.critic_id}] Recommendations: {', '.join(v.recommendations)}")
        print("  (In production, the writer would revise and re-submit)")

    # =========================================================
    # Summary
    # =========================================================
    print("\n" + "=" * 60)
    print("  Tutorial Complete")
    print(f"  Outcome: {outcome.name}")
    print(f"  Agents involved: {writer.agent_id}, "
          f"{reviewer_correctness.agent_id}, "
          f"{reviewer_style.agent_id}, "
          f"{deployer.agent_id}")
    print("=" * 60)


if __name__ == "__main__":
    run_code_review_swarm()
