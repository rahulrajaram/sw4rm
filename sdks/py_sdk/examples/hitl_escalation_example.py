#!/usr/bin/env python3
"""
Human-in-the-Loop (HITL) Escalation Example for SW4RM Protocol.

This example demonstrates:
- TASK_ESCALATION for low-confidence decisions
- CONFLICT escalation flow for unresolved disputes between agents
- DEBATE_DEADLOCK handling when multi-agent debates fail to converge
- SECURITY_APPROVAL for high-risk actions

Prerequisites:
  - Generate protobuf stubs: `make protos`
  - Install deps: `python -m pip install -e ".[dev]"`
  - Optional: Running HITL service on localhost:50053

Run:
  python examples/hitl_escalation_example.py
"""
from __future__ import annotations

import json
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Callable, Optional

# SW4RM SDK imports
from sw4rm import constants as C


# ---------------------------------------------------------------------------
# Mock HITL Client for demonstration (real implementation uses gRPC)
# ---------------------------------------------------------------------------

class HitlReasonType(Enum):
    """Reasons for HITL escalation."""
    UNSPECIFIED = 0
    CONFLICT = 1
    SECURITY_APPROVAL = 2
    TASK_ESCALATION = 3
    MANUAL_OVERRIDE = 4
    WORKTREE_OVERRIDE = 5
    DEBATE_DEADLOCK = 6
    TOOL_PRIVILEGE_ESCALATION = 7
    CONNECTOR_APPROVAL = 8


@dataclass
class HitlInvocation:
    """A request for human-in-the-loop decision.

    Attributes:
        correlation_id: Unique identifier linking this to the original request
        reason_type: Why HITL is being invoked
        context: JSON context explaining the situation
        options: Available choices for the human operator
        timeout_ms: How long to wait for human response
        metadata: Additional context for the human operator
    """
    correlation_id: str
    reason_type: HitlReasonType
    context: dict[str, Any]
    options: list[str]
    timeout_ms: int = 30000
    metadata: dict[str, Any] = field(default_factory=dict)


@dataclass
class HitlDecision:
    """Human decision in response to a HITL invocation.

    Attributes:
        invocation_id: Reference to the original invocation
        chosen_option: The option selected by the human
        confidence: How confident the human is in their decision (0-1)
        reason: Human-provided explanation for their choice
        timestamp_ms: When the decision was made
    """
    invocation_id: str
    chosen_option: str
    confidence: float
    reason: str
    timestamp_ms: int = field(default_factory=lambda: int(time.time() * 1000))


class MockHitlService:
    """Mock HITL service for demonstration purposes.

    In production, this would connect to a real HITL service via gRPC.
    This mock simulates human decision-making with configurable behavior.
    """

    def __init__(self, auto_decision: Optional[str] = None, delay_ms: int = 100):
        """Initialize the mock HITL service.

        Args:
            auto_decision: If set, automatically return this decision.
                          If None, prompts for interactive input.
            delay_ms: Simulated delay before returning decision
        """
        self.auto_decision = auto_decision
        self.delay_ms = delay_ms
        self._pending_invocations: dict[str, HitlInvocation] = {}
        self._decisions: dict[str, HitlDecision] = {}

    def submit(self, invocation: HitlInvocation) -> str:
        """Submit a HITL invocation for human decision.

        Args:
            invocation: The HITL request

        Returns:
            Invocation ID for tracking
        """
        invocation_id = str(uuid.uuid4())
        self._pending_invocations[invocation_id] = invocation

        print(f"\n[HITL] New invocation submitted: {invocation_id}")
        print(f"  Reason: {invocation.reason_type.name}")
        print(f"  Context: {json.dumps(invocation.context, indent=2)}")
        print(f"  Options: {invocation.options}")

        return invocation_id

    def get_decision(self, invocation_id: str, timeout_ms: int = 30000) -> Optional[HitlDecision]:
        """Wait for and retrieve a human decision.

        Args:
            invocation_id: The invocation to wait for
            timeout_ms: Maximum time to wait for decision

        Returns:
            The human's decision, or None if timeout
        """
        # Check if already decided
        if invocation_id in self._decisions:
            return self._decisions[invocation_id]

        invocation = self._pending_invocations.get(invocation_id)
        if not invocation:
            return None

        # Simulate delay
        time.sleep(self.delay_ms / 1000)

        # Auto-decision or interactive
        if self.auto_decision:
            chosen = self.auto_decision if self.auto_decision in invocation.options else invocation.options[0]
            reason = "Auto-decided by test configuration"
            confidence = 0.9
        else:
            # For demonstration, just pick the first option
            chosen = invocation.options[0]
            reason = "Demo mode: selected first option"
            confidence = 0.8

        decision = HitlDecision(
            invocation_id=invocation_id,
            chosen_option=chosen,
            confidence=confidence,
            reason=reason
        )

        self._decisions[invocation_id] = decision
        del self._pending_invocations[invocation_id]

        print(f"\n[HITL] Decision received for {invocation_id}")
        print(f"  Chosen: {decision.chosen_option}")
        print(f"  Confidence: {decision.confidence}")
        print(f"  Reason: {decision.reason}")

        return decision


# ---------------------------------------------------------------------------
# Escalation Handler
# ---------------------------------------------------------------------------

class EscalationHandler:
    """Handles escalation flows for agents when automated decision-making fails.

    This class provides patterns for:
    - Escalating to HITL when confidence thresholds aren't met
    - Resolving conflicts between agents
    - Breaking debate deadlocks
    """

    def __init__(self, hitl_service: MockHitlService, agent_id: str):
        """Initialize the escalation handler.

        Args:
            hitl_service: Service for submitting HITL requests
            agent_id: ID of the agent using this handler
        """
        self.hitl_service = hitl_service
        self.agent_id = agent_id
        self.escalation_count = 0

    def escalate_uncertainty(
        self,
        task_description: str,
        confidence: float,
        options: list[str],
        threshold: float = 0.7
    ) -> Optional[str]:
        """Escalate to HITL when confidence is below threshold.

        This is used when an agent has low confidence in its decision
        and needs human guidance.

        Args:
            task_description: Description of what the agent is trying to decide
            confidence: Current confidence level (0-1)
            options: Available choices
            threshold: Minimum confidence required for autonomous decision

        Returns:
            Human's chosen option, or None if no escalation needed
        """
        if confidence >= threshold:
            print(f"[Escalation] Confidence {confidence:.2f} >= threshold {threshold:.2f}, no escalation needed")
            return None

        print(f"\n[Escalation] Low confidence ({confidence:.2f}) detected for: {task_description}")
        print("[Escalation] Escalating to HITL for human decision...")

        invocation = HitlInvocation(
            correlation_id=str(uuid.uuid4()),
            reason_type=HitlReasonType.TASK_ESCALATION,
            context={
                "agent_id": self.agent_id,
                "task": task_description,
                "agent_confidence": confidence,
                "threshold": threshold,
                "escalation_reason": "Agent confidence below threshold"
            },
            options=options
        )

        invocation_id = self.hitl_service.submit(invocation)
        decision = self.hitl_service.get_decision(invocation_id)

        if decision:
            self.escalation_count += 1
            return decision.chosen_option

        print("[Escalation] HITL timeout - no decision received")
        return None

    def escalate_conflict(
        self,
        agents_involved: list[str],
        conflicting_proposals: dict[str, Any],
        conflict_description: str
    ) -> Optional[str]:
        """Escalate unresolved conflict between agents to HITL.

        When multiple agents cannot agree on a decision, this escalates
        to a human operator to resolve the conflict.

        Args:
            agents_involved: IDs of agents in conflict
            conflicting_proposals: Each agent's proposed solution
            conflict_description: Human-readable description of the conflict

        Returns:
            ID of the winning proposal, or None if timeout
        """
        print(f"\n[Escalation] Conflict detected between agents: {agents_involved}")
        print(f"[Escalation] Description: {conflict_description}")
        print(f"[Escalation] Conflicting proposals:")
        for agent, proposal in conflicting_proposals.items():
            print(f"  {agent}: {proposal}")

        options = [f"accept_{agent}" for agent in agents_involved] + ["reject_all", "merge_proposals"]

        invocation = HitlInvocation(
            correlation_id=str(uuid.uuid4()),
            reason_type=HitlReasonType.CONFLICT,
            context={
                "escalating_agent": self.agent_id,
                "agents_involved": agents_involved,
                "proposals": conflicting_proposals,
                "conflict_description": conflict_description
            },
            options=options,
            metadata={
                "priority": "high",
                "category": "multi_agent_conflict"
            }
        )

        invocation_id = self.hitl_service.submit(invocation)
        decision = self.hitl_service.get_decision(invocation_id)

        if decision:
            self.escalation_count += 1
            return decision.chosen_option

        print("[Escalation] HITL timeout - conflict unresolved")
        return None

    def escalate_debate_deadlock(
        self,
        debate_id: str,
        debate_rounds: int,
        final_positions: dict[str, dict[str, Any]],
        max_rounds: int = 5
    ) -> Optional[str]:
        """Escalate when a multi-agent debate fails to converge.

        In negotiation scenarios, agents may debate over multiple rounds
        but fail to reach consensus. This escalates such deadlocks to HITL.

        Args:
            debate_id: Identifier for the debate session
            debate_rounds: Number of rounds completed
            final_positions: Each agent's final position with reasoning
            max_rounds: Maximum rounds before considering it a deadlock

        Returns:
            Resolution decision, or None if timeout
        """
        print(f"\n[Escalation] Debate deadlock detected!")
        print(f"  Debate ID: {debate_id}")
        print(f"  Rounds completed: {debate_rounds}/{max_rounds}")
        print("  Final positions:")
        for agent, position in final_positions.items():
            print(f"    {agent}:")
            print(f"      Stance: {position.get('stance', 'unknown')}")
            print(f"      Confidence: {position.get('confidence', 0):.2f}")
            print(f"      Key arguments: {position.get('arguments', [])}")

        # Build options from final positions
        options = list(final_positions.keys()) + ["compromise", "defer_decision"]

        invocation = HitlInvocation(
            correlation_id=str(uuid.uuid4()),
            reason_type=HitlReasonType.DEBATE_DEADLOCK,
            context={
                "debate_id": debate_id,
                "rounds_completed": debate_rounds,
                "max_rounds": max_rounds,
                "final_positions": final_positions,
                "escalating_agent": self.agent_id
            },
            options=options,
            timeout_ms=60000,  # Longer timeout for complex debates
            metadata={
                "debate_intensity": "high",
                "requires_domain_expertise": True
            }
        )

        invocation_id = self.hitl_service.submit(invocation)
        decision = self.hitl_service.get_decision(invocation_id)

        if decision:
            self.escalation_count += 1
            return decision.chosen_option

        print("[Escalation] HITL timeout - debate remains deadlocked")
        return None

    def escalate_high_risk(
        self,
        action_description: str,
        risk_assessment: dict[str, Any],
        proposed_action: str
    ) -> bool:
        """Escalate for approval when proposed action is high-risk.

        Certain actions may require human approval due to their potential
        impact. This escalates such actions for explicit approval.

        Args:
            action_description: What action is being proposed
            risk_assessment: Assessment of potential impacts
            proposed_action: The specific action to approve/reject

        Returns:
            True if action is approved, False otherwise
        """
        print(f"\n[Escalation] High-risk action requiring approval")
        print(f"  Action: {action_description}")
        print(f"  Risk level: {risk_assessment.get('level', 'unknown')}")
        print(f"  Potential impacts: {risk_assessment.get('impacts', [])}")

        invocation = HitlInvocation(
            correlation_id=str(uuid.uuid4()),
            reason_type=HitlReasonType.SECURITY_APPROVAL,
            context={
                "agent_id": self.agent_id,
                "action": action_description,
                "proposed_action": proposed_action,
                "risk_assessment": risk_assessment
            },
            options=["approve", "reject", "modify"],
            metadata={
                "requires_immediate_attention": risk_assessment.get("level") == "critical"
            }
        )

        invocation_id = self.hitl_service.submit(invocation)
        decision = self.hitl_service.get_decision(invocation_id)

        if decision and decision.chosen_option == "approve":
            self.escalation_count += 1
            print("[Escalation] Action APPROVED by human operator")
            return True

        print(f"[Escalation] Action NOT approved: {decision.chosen_option if decision else 'timeout'}")
        return False


# ---------------------------------------------------------------------------
# Example Scenarios
# ---------------------------------------------------------------------------

def demo_uncertainty_escalation():
    """Demonstrate escalation due to low confidence."""
    print("\n" + "=" * 60)
    print("SCENARIO 1: Uncertainty Escalation")
    print("=" * 60)

    # Create mock service with auto-decision for demo
    hitl_service = MockHitlService(auto_decision="option_b")
    handler = EscalationHandler(hitl_service, agent_id="classifier-agent-1")

    # Scenario: Agent must classify a document but is uncertain
    result = handler.escalate_uncertainty(
        task_description="Classify document XYZ-123 as either 'public', 'internal', or 'confidential'",
        confidence=0.45,  # Low confidence
        options=["public", "internal", "confidential"],
        threshold=0.7
    )

    print(f"\nResult: Document classified as '{result}'")


def demo_conflict_escalation():
    """Demonstrate escalation due to agent conflict."""
    print("\n" + "=" * 60)
    print("SCENARIO 2: Multi-Agent Conflict Escalation")
    print("=" * 60)

    hitl_service = MockHitlService(auto_decision="accept_security-agent")
    handler = EscalationHandler(hitl_service, agent_id="orchestrator-1")

    # Scenario: Performance and security agents disagree on configuration
    result = handler.escalate_conflict(
        agents_involved=["performance-agent", "security-agent"],
        conflicting_proposals={
            "performance-agent": {
                "recommendation": "Enable caching for faster response",
                "justification": "Reduces latency by 40%",
                "risk_score": 0.2
            },
            "security-agent": {
                "recommendation": "Disable caching to prevent data leaks",
                "justification": "Cache could expose sensitive data",
                "risk_score": 0.7
            }
        },
        conflict_description="Performance vs Security trade-off for API caching"
    )

    print(f"\nResult: Conflict resolved with decision: '{result}'")


def demo_debate_deadlock():
    """Demonstrate escalation due to debate deadlock."""
    print("\n" + "=" * 60)
    print("SCENARIO 3: Debate Deadlock Escalation")
    print("=" * 60)

    hitl_service = MockHitlService(auto_decision="compromise")
    handler = EscalationHandler(hitl_service, agent_id="moderator-1")

    # Scenario: Multiple agents debated but couldn't reach consensus
    result = handler.escalate_debate_deadlock(
        debate_id="debate-2024-001",
        debate_rounds=5,
        final_positions={
            "agent-alpha": {
                "stance": "Use microservices architecture",
                "confidence": 0.85,
                "arguments": [
                    "Better scalability",
                    "Independent deployments",
                    "Technology flexibility"
                ]
            },
            "agent-beta": {
                "stance": "Use monolithic architecture",
                "confidence": 0.78,
                "arguments": [
                    "Simpler to develop",
                    "Lower operational overhead",
                    "Better for small team"
                ]
            },
            "agent-gamma": {
                "stance": "Use modular monolith",
                "confidence": 0.72,
                "arguments": [
                    "Best of both worlds",
                    "Easier migration path",
                    "Lower complexity initially"
                ]
            }
        },
        max_rounds=5
    )

    print(f"\nResult: Debate resolved with decision: '{result}'")


def demo_high_risk_approval():
    """Demonstrate escalation for high-risk action approval."""
    print("\n" + "=" * 60)
    print("SCENARIO 4: High-Risk Action Approval")
    print("=" * 60)

    hitl_service = MockHitlService(auto_decision="approve")
    handler = EscalationHandler(hitl_service, agent_id="deploy-agent-1")

    # Scenario: Agent wants to deploy to production but it's high-risk
    approved = handler.escalate_high_risk(
        action_description="Deploy version 2.5.0 to production during peak hours",
        risk_assessment={
            "level": "high",
            "impacts": [
                "Service disruption possible",
                "10,000+ active users affected",
                "Rollback required if issues"
            ],
            "mitigations": [
                "Canary deployment available",
                "Rollback tested",
                "Monitoring alerts configured"
            ]
        },
        proposed_action="kubectl apply -f production-deployment.yaml"
    )

    print(f"\nResult: Deployment {'APPROVED' if approved else 'REJECTED'}")


def main() -> int:
    """Run all HITL escalation demonstrations."""
    print("SW4RM HITL Escalation Example")
    print("=" * 60)
    print("\nThis example demonstrates various HITL escalation scenarios")
    print("that agents can use when automated decision-making fails.\n")

    # Run all demo scenarios
    demo_uncertainty_escalation()
    demo_conflict_escalation()
    demo_debate_deadlock()
    demo_high_risk_approval()

    print("\n" + "=" * 60)
    print("All HITL escalation scenarios completed!")
    print("=" * 60)
    print("\nKey takeaways:")
    print("1. Use TASK_ESCALATION when agent confidence is below threshold")
    print("2. Use CONFLICT when agents cannot agree")
    print("3. Use DEBATE_DEADLOCK when multi-round debates fail to converge")
    print("4. Use SECURITY_APPROVAL for actions requiring explicit human approval")
    print("5. Always provide clear context and options for human operators")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
