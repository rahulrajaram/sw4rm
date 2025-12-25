#!/usr/bin/env python3
"""
Multi-Agent Negotiation and Debate Example for SW4RM Protocol.

This example demonstrates:
- Multi-agent negotiation using NegotiationRoomClient
- Producer submitting an artifact for approval
- Multiple critics evaluating and voting on the artifact
- Coordinator aggregating votes and making decisions
- Complete negotiation room flow from submission to decision

Prerequisites:
  - Generate protobuf stubs: `make protos`
  - Install deps: `python -m pip install -e ".[dev]"`

Run:
  python examples/negotiation_debate_example.py
"""
from __future__ import annotations

import json
import time
import uuid
from typing import Any

# SW4RM SDK imports
from sw4rm.clients.negotiation_room import NegotiationRoomClient
from sw4rm.negotiation_types import (
    ArtifactType,
    DecisionOutcome,
    NegotiationProposal,
    NegotiationVote,
    NegotiationDecision,
    AggregatedScore,
    aggregate_votes,
)


# ---------------------------------------------------------------------------
# Agent Role Implementations
# ---------------------------------------------------------------------------

class ProducerAgent:
    """Agent that produces artifacts and submits them for review.

    Producers create work products (code, plans, requirements, etc.) and
    submit them to the negotiation room for multi-agent approval.
    """

    def __init__(self, agent_id: str, room_client: NegotiationRoomClient):
        """Initialize the producer agent.

        Args:
            agent_id: Unique identifier for this agent
            room_client: Client for interacting with negotiation rooms
        """
        self.agent_id = agent_id
        self.room_client = room_client

    def create_code_proposal(
        self,
        code: str,
        description: str,
        critics: list[str],
        room_id: str
    ) -> str:
        """Create and submit a code artifact for review.

        Args:
            code: The source code to be reviewed
            description: Description of what the code does
            critics: List of critic agent IDs to review the code
            room_id: Negotiation room identifier

        Returns:
            The artifact_id for tracking the proposal
        """
        artifact_id = f"code-{uuid.uuid4().hex[:8]}"

        # Package the artifact with metadata
        artifact_content = {
            "code": code,
            "description": description,
            "language": "python",
            "producer": self.agent_id,
            "submitted_at": int(time.time())
        }

        proposal = NegotiationProposal(
            artifact_type=ArtifactType.CODE,
            artifact_id=artifact_id,
            producer_id=self.agent_id,
            artifact=json.dumps(artifact_content).encode("utf-8"),
            artifact_content_type="application/json",
            requested_critics=critics,
            negotiation_room_id=room_id
        )

        self.room_client.submit_proposal(proposal)

        print(f"\n[Producer {self.agent_id}] Submitted code proposal: {artifact_id}")
        print(f"  Description: {description}")
        print(f"  Requested critics: {critics}")

        return artifact_id

    def wait_for_decision(self, artifact_id: str, timeout_s: float = 30.0) -> NegotiationDecision:
        """Wait for a decision on the submitted artifact.

        Args:
            artifact_id: The artifact to wait for
            timeout_s: Maximum time to wait

        Returns:
            The final decision
        """
        print(f"\n[Producer {self.agent_id}] Waiting for decision on {artifact_id}...")
        decision = self.room_client.wait_for_decision(artifact_id, timeout_s)
        return decision


class CriticAgent:
    """Agent that evaluates artifacts and provides votes.

    Critics review artifacts submitted by producers, score them based on
    quality criteria, and provide feedback for improvement.
    """

    def __init__(
        self,
        agent_id: str,
        room_client: NegotiationRoomClient,
        expertise: str = "general"
    ):
        """Initialize the critic agent.

        Args:
            agent_id: Unique identifier for this agent
            room_client: Client for interacting with negotiation rooms
            expertise: Area of expertise (e.g., "security", "performance", "style")
        """
        self.agent_id = agent_id
        self.room_client = room_client
        self.expertise = expertise

    def evaluate_artifact(
        self,
        artifact_id: str,
        room_id: str,
        score: float,
        confidence: float,
        passed: bool,
        strengths: list[str],
        weaknesses: list[str],
        recommendations: list[str]
    ) -> NegotiationVote:
        """Evaluate an artifact and submit a vote.

        Args:
            artifact_id: The artifact being evaluated
            room_id: Negotiation room identifier
            score: Numerical score (0-10)
            confidence: Confidence in the evaluation (0-1)
            passed: Whether the artifact meets minimum criteria
            strengths: Identified strengths
            weaknesses: Identified weaknesses
            recommendations: Suggestions for improvement

        Returns:
            The submitted vote
        """
        vote = NegotiationVote(
            artifact_id=artifact_id,
            critic_id=self.agent_id,
            score=score,
            confidence=confidence,
            passed=passed,
            strengths=strengths,
            weaknesses=weaknesses,
            recommendations=recommendations,
            negotiation_room_id=room_id
        )

        self.room_client.submit_vote(vote)

        print(f"\n[Critic {self.agent_id}] Submitted vote for {artifact_id}")
        print(f"  Expertise: {self.expertise}")
        print(f"  Score: {score}/10 (confidence: {confidence:.2f})")
        print(f"  Passed: {passed}")
        print(f"  Strengths: {strengths}")
        print(f"  Weaknesses: {weaknesses}")

        return vote


class CoordinatorAgent:
    """Agent that aggregates votes and makes final decisions.

    Coordinators collect votes from all critics, aggregate the scores
    using configurable policies, and make the final approval decision.
    """

    # Default thresholds for decision-making
    APPROVAL_THRESHOLD = 7.0  # Minimum weighted mean for approval
    REVISION_THRESHOLD = 5.0  # Below this, request revision
    MIN_VOTES_REQUIRED = 2    # Minimum number of votes required
    MAX_STD_DEV = 2.0         # Maximum acceptable disagreement

    def __init__(
        self,
        agent_id: str,
        room_client: NegotiationRoomClient,
        policy_version: str = "v1.0"
    ):
        """Initialize the coordinator agent.

        Args:
            agent_id: Unique identifier for this agent
            room_client: Client for interacting with negotiation rooms
            policy_version: Version of the decision policy being used
        """
        self.agent_id = agent_id
        self.room_client = room_client
        self.policy_version = policy_version

    def aggregate_and_decide(
        self,
        artifact_id: str,
        room_id: str
    ) -> NegotiationDecision:
        """Aggregate votes and make a decision on the artifact.

        This implements the coordinator's decision-making logic:
        1. Collect all votes for the artifact
        2. Aggregate scores using weighted averaging
        3. Apply policy thresholds to determine outcome
        4. Store and return the final decision

        Args:
            artifact_id: The artifact to decide on
            room_id: Negotiation room identifier

        Returns:
            The final decision
        """
        print(f"\n[Coordinator {self.agent_id}] Aggregating votes for {artifact_id}")

        # Get all votes
        votes = self.room_client.get_votes(artifact_id)

        if len(votes) < self.MIN_VOTES_REQUIRED:
            print(f"  Warning: Only {len(votes)} votes received, {self.MIN_VOTES_REQUIRED} required")

        # Aggregate votes
        aggregated = aggregate_votes(votes)

        print(f"  Aggregated scores:")
        print(f"    Mean: {aggregated.mean:.2f}")
        print(f"    Weighted Mean: {aggregated.weighted_mean:.2f}")
        print(f"    Min: {aggregated.min_score:.2f}, Max: {aggregated.max_score:.2f}")
        print(f"    Std Dev: {aggregated.std_dev:.2f}")
        print(f"    Vote count: {aggregated.vote_count}")

        # Determine outcome based on policy
        outcome, reason = self._apply_policy(votes, aggregated)

        print(f"\n  Decision: {outcome.name}")
        print(f"  Reason: {reason}")

        # Create and store decision
        decision = NegotiationDecision(
            artifact_id=artifact_id,
            outcome=outcome,
            votes=votes,
            aggregated_score=aggregated,
            policy_version=self.policy_version,
            reason=reason,
            negotiation_room_id=room_id
        )

        self.room_client.store_decision(decision)

        return decision

    def _apply_policy(
        self,
        votes: list[NegotiationVote],
        aggregated: AggregatedScore
    ) -> tuple[DecisionOutcome, str]:
        """Apply decision policy to determine outcome.

        Args:
            votes: All critic votes
            aggregated: Aggregated score statistics

        Returns:
            Tuple of (outcome, reason)
        """
        # Check for high disagreement - may need HITL
        if aggregated.std_dev > self.MAX_STD_DEV:
            return (
                DecisionOutcome.ESCALATED_TO_HITL,
                f"High critic disagreement (std_dev={aggregated.std_dev:.2f}), escalating to human"
            )

        # Check if all critics passed
        all_passed = all(v.passed for v in votes)

        # Check if weighted mean meets approval threshold
        if aggregated.weighted_mean >= self.APPROVAL_THRESHOLD and all_passed:
            return (
                DecisionOutcome.APPROVED,
                f"Weighted mean {aggregated.weighted_mean:.2f} meets threshold {self.APPROVAL_THRESHOLD}, all critics passed"
            )

        # Check if below revision threshold
        if aggregated.weighted_mean < self.REVISION_THRESHOLD:
            return (
                DecisionOutcome.REVISION_REQUESTED,
                f"Weighted mean {aggregated.weighted_mean:.2f} below revision threshold {self.REVISION_THRESHOLD}"
            )

        # In between - request revision with specific feedback
        failing_critics = [v.critic_id for v in votes if not v.passed]
        if failing_critics:
            return (
                DecisionOutcome.REVISION_REQUESTED,
                f"Critics did not pass: {failing_critics}"
            )

        return (
            DecisionOutcome.REVISION_REQUESTED,
            f"Weighted mean {aggregated.weighted_mean:.2f} did not meet approval threshold {self.APPROVAL_THRESHOLD}"
        )


# ---------------------------------------------------------------------------
# Full Negotiation Room Flow
# ---------------------------------------------------------------------------

def run_negotiation_flow() -> NegotiationDecision:
    """Run a complete negotiation room flow.

    This demonstrates the full workflow:
    1. Producer submits code for review
    2. Multiple critics evaluate and vote
    3. Coordinator aggregates and makes decision
    4. Producer receives final decision

    Returns:
        The final decision
    """
    print("=" * 70)
    print("MULTI-AGENT NEGOTIATION EXAMPLE")
    print("=" * 70)

    # Create shared negotiation room client
    room_client = NegotiationRoomClient()
    room_id = f"room-{uuid.uuid4().hex[:8]}"

    print(f"\nNegotiation Room: {room_id}")

    # Create agents
    producer = ProducerAgent("producer-1", room_client)
    critics = [
        CriticAgent("critic-security", room_client, expertise="security"),
        CriticAgent("critic-performance", room_client, expertise="performance"),
        CriticAgent("critic-style", room_client, expertise="code_style"),
    ]
    coordinator = CoordinatorAgent("coordinator-1", room_client)

    # Producer submits code
    print("\n" + "-" * 50)
    print("PHASE 1: PRODUCER SUBMITS ARTIFACT")
    print("-" * 50)

    code_sample = '''
def process_user_data(user_input: str) -> dict:
    """Process user data and return structured result.

    Args:
        user_input: Raw user input string

    Returns:
        Processed data dictionary
    """
    import json
    # Parse and validate input
    data = json.loads(user_input)

    # Apply business logic
    result = {
        "status": "processed",
        "original_length": len(user_input),
        "fields": list(data.keys())
    }

    return result
'''

    artifact_id = producer.create_code_proposal(
        code=code_sample,
        description="User data processing function with JSON parsing",
        critics=[c.agent_id for c in critics],
        room_id=room_id
    )

    # Critics evaluate
    print("\n" + "-" * 50)
    print("PHASE 2: CRITICS EVALUATE ARTIFACT")
    print("-" * 50)

    # Security critic
    critics[0].evaluate_artifact(
        artifact_id=artifact_id,
        room_id=room_id,
        score=6.5,
        confidence=0.85,
        passed=False,
        strengths=[
            "Uses type hints",
            "Has docstring"
        ],
        weaknesses=[
            "No input validation before JSON parsing",
            "Potential injection vulnerability",
            "No exception handling"
        ],
        recommendations=[
            "Add try-except around json.loads",
            "Validate expected data schema",
            "Sanitize user input"
        ]
    )

    # Performance critic
    critics[1].evaluate_artifact(
        artifact_id=artifact_id,
        room_id=room_id,
        score=7.5,
        confidence=0.78,
        passed=True,
        strengths=[
            "Simple and efficient implementation",
            "No unnecessary computations"
        ],
        weaknesses=[
            "Could cache json import at module level",
            "No streaming support for large inputs"
        ],
        recommendations=[
            "Move import to top of file",
            "Consider chunked processing for large data"
        ]
    )

    # Style critic
    critics[2].evaluate_artifact(
        artifact_id=artifact_id,
        room_id=room_id,
        score=8.0,
        confidence=0.92,
        passed=True,
        strengths=[
            "Good docstring format (Google style)",
            "Proper type hints",
            "Clean variable names",
            "Appropriate function length"
        ],
        weaknesses=[
            "Import inside function is not PEP-8 compliant"
        ],
        recommendations=[
            "Move import json to top of module"
        ]
    )

    # Coordinator makes decision
    print("\n" + "-" * 50)
    print("PHASE 3: COORDINATOR AGGREGATES AND DECIDES")
    print("-" * 50)

    decision = coordinator.aggregate_and_decide(artifact_id, room_id)

    # Producer receives decision
    print("\n" + "-" * 50)
    print("PHASE 4: PRODUCER RECEIVES DECISION")
    print("-" * 50)

    print(f"\n[Producer {producer.agent_id}] Received decision:")
    print(f"  Outcome: {decision.outcome.name}")
    print(f"  Policy Version: {decision.policy_version}")
    print(f"  Reason: {decision.reason}")

    if decision.outcome == DecisionOutcome.REVISION_REQUESTED:
        print("\n  Action Required: Revise and resubmit")
        print("  Key feedback to address:")
        for vote in decision.votes:
            if not vote.passed or vote.recommendations:
                print(f"    From {vote.critic_id}:")
                for rec in vote.recommendations[:2]:  # Show first 2 recommendations
                    print(f"      - {rec}")

    return decision


def run_approval_scenario():
    """Run a scenario where the artifact gets approved."""
    print("\n" + "=" * 70)
    print("APPROVAL SCENARIO")
    print("=" * 70)

    room_client = NegotiationRoomClient()
    room_id = f"room-approve-{uuid.uuid4().hex[:8]}"

    producer = ProducerAgent("producer-2", room_client)
    critics = [
        CriticAgent("critic-a", room_client),
        CriticAgent("critic-b", room_client),
    ]
    coordinator = CoordinatorAgent("coordinator-2", room_client)

    # Submit high-quality artifact
    artifact_id = producer.create_code_proposal(
        code="# Well-tested, secure code",
        description="Production-ready implementation",
        critics=[c.agent_id for c in critics],
        room_id=room_id
    )

    # All critics give high scores
    critics[0].evaluate_artifact(
        artifact_id=artifact_id,
        room_id=room_id,
        score=9.0,
        confidence=0.95,
        passed=True,
        strengths=["Excellent security practices", "Comprehensive tests"],
        weaknesses=[],
        recommendations=[]
    )

    critics[1].evaluate_artifact(
        artifact_id=artifact_id,
        room_id=room_id,
        score=8.5,
        confidence=0.88,
        passed=True,
        strengths=["Great performance", "Clean code"],
        weaknesses=["Minor style nit"],
        recommendations=["Consider adding inline comments"]
    )

    decision = coordinator.aggregate_and_decide(artifact_id, room_id)

    print(f"\nFinal Outcome: {decision.outcome.name}")
    assert decision.outcome == DecisionOutcome.APPROVED, "Expected approval!"


def run_deadlock_scenario():
    """Run a scenario that results in HITL escalation due to disagreement."""
    print("\n" + "=" * 70)
    print("DEADLOCK/ESCALATION SCENARIO")
    print("=" * 70)

    room_client = NegotiationRoomClient()
    room_id = f"room-deadlock-{uuid.uuid4().hex[:8]}"

    producer = ProducerAgent("producer-3", room_client)
    critics = [
        CriticAgent("critic-x", room_client),
        CriticAgent("critic-y", room_client),
    ]
    coordinator = CoordinatorAgent("coordinator-3", room_client)

    artifact_id = producer.create_code_proposal(
        code="# Controversial implementation",
        description="Approach with trade-offs",
        critics=[c.agent_id for c in critics],
        room_id=room_id
    )

    # Critics strongly disagree
    critics[0].evaluate_artifact(
        artifact_id=artifact_id,
        room_id=room_id,
        score=9.0,  # Very high
        confidence=0.90,
        passed=True,
        strengths=["Innovative approach", "Solves problem elegantly"],
        weaknesses=[],
        recommendations=[]
    )

    critics[1].evaluate_artifact(
        artifact_id=artifact_id,
        room_id=room_id,
        score=3.0,  # Very low - high disagreement!
        confidence=0.92,
        passed=False,
        strengths=["Attempts to solve the problem"],
        weaknesses=["Completely wrong approach", "Major security flaws"],
        recommendations=["Rewrite from scratch"]
    )

    decision = coordinator.aggregate_and_decide(artifact_id, room_id)

    print(f"\nFinal Outcome: {decision.outcome.name}")
    print("Note: High disagreement between critics led to HITL escalation")


def main() -> int:
    """Run all negotiation examples."""
    print("\nSW4RM Multi-Agent Negotiation Example")
    print("This demonstrates the Negotiation Room pattern for artifact approval\n")

    # Run main flow
    run_negotiation_flow()

    # Run approval scenario
    run_approval_scenario()

    # Run deadlock scenario
    run_deadlock_scenario()

    print("\n" + "=" * 70)
    print("ALL NEGOTIATION SCENARIOS COMPLETED")
    print("=" * 70)
    print("\nKey takeaways:")
    print("1. Producers submit artifacts to NegotiationRoomClient")
    print("2. Critics evaluate and submit votes with scores and feedback")
    print("3. Coordinators aggregate votes and apply decision policies")
    print("4. High disagreement between critics triggers HITL escalation")
    print("5. Decisions include full audit trail of votes and reasoning")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
