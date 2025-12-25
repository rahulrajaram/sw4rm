#!/usr/bin/env python3
"""
Agent Handoff Example for SW4RM Protocol.

This example demonstrates:
- Agent-to-agent handoff using HandoffClient
- Context serialization and preservation
- Capability matching for target agent selection
- Accept/reject handoff flows
- Complete handoff lifecycle

Prerequisites:
  - Generate protobuf stubs: `make protos`
  - Install deps: `python -m pip install -e ".[dev]"`

Run:
  python examples/handoff_example.py
"""
from __future__ import annotations

import json
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Optional

# SW4RM SDK imports
from sw4rm.handoff.client import HandoffClient
from sw4rm.handoff.types import HandoffRequest, HandoffResponse, HandoffStatus
from sw4rm.handoff.context import (
    HandoffContext,
    serialize_context,
    deserialize_context,
)


# ---------------------------------------------------------------------------
# Agent Classes for Demonstration
# ---------------------------------------------------------------------------

@dataclass
class AgentCapabilities:
    """Capabilities that an agent can offer.

    Attributes:
        agent_id: Unique identifier for the agent
        name: Human-readable agent name
        capabilities: List of capabilities this agent provides
        max_concurrent_tasks: Maximum tasks agent can handle
        current_load: Current number of active tasks
    """
    agent_id: str
    name: str
    capabilities: list[str]
    max_concurrent_tasks: int = 5
    current_load: int = 0

    def can_accept(self, required_capabilities: list[str]) -> bool:
        """Check if agent can handle required capabilities.

        Args:
            required_capabilities: Capabilities needed for the task

        Returns:
            True if agent has all required capabilities and capacity
        """
        has_capacity = self.current_load < self.max_concurrent_tasks
        has_capabilities = all(cap in self.capabilities for cap in required_capabilities)
        return has_capacity and has_capabilities


class SourceAgent:
    """Agent that initiates handoffs when it cannot complete a task.

    This represents an agent that encounters a task requiring capabilities
    it doesn't have, and needs to hand off to a more suitable agent.
    """

    def __init__(self, agent_id: str, name: str, handoff_client: HandoffClient):
        """Initialize the source agent.

        Args:
            agent_id: Unique identifier for this agent
            name: Human-readable name
            handoff_client: Client for handoff operations
        """
        self.agent_id = agent_id
        self.name = name
        self.handoff_client = handoff_client
        self.conversation_history: list[dict[str, Any]] = []
        self.active_tools: dict[str, Any] = {}

    def add_conversation_turn(self, role: str, content: str) -> None:
        """Add a turn to the conversation history.

        Args:
            role: The role (user, assistant, system)
            content: The message content
        """
        self.conversation_history.append({
            "role": role,
            "content": content,
            "timestamp": int(time.time())
        })

    def request_handoff(
        self,
        target_agent_id: str,
        reason: str,
        required_capabilities: list[str],
        preserve_history: bool = True
    ) -> HandoffResponse:
        """Request a handoff to another agent.

        This creates and submits a handoff request, serializing the current
        context for the target agent to continue execution.

        Args:
            target_agent_id: ID of the agent to hand off to
            reason: Why the handoff is needed
            required_capabilities: Capabilities the target must have
            preserve_history: Whether to include conversation history

        Returns:
            The handoff response
        """
        print(f"\n[{self.name}] Initiating handoff to {target_agent_id}")
        print(f"  Reason: {reason}")
        print(f"  Required capabilities: {required_capabilities}")

        # Build context snapshot
        context = HandoffContext(
            conversation_history=self.conversation_history if preserve_history else [],
            tool_state=self.active_tools.copy(),
            metadata={
                "original_agent": self.agent_id,
                "handoff_timestamp": int(time.time()),
                "task_status": "in_progress"
            }
        )

        # Serialize context
        context_bytes = serialize_context(context)
        print(f"  Context size: {len(context_bytes)} bytes")

        # Create handoff request
        request = HandoffRequest(
            from_agent=self.agent_id,
            to_agent=target_agent_id,
            reason=reason,
            context_snapshot=context_bytes,
            preserve_history=preserve_history,
            capabilities_required=required_capabilities,
            metadata={
                "urgency": "normal",
                "conversation_turns": len(self.conversation_history)
            }
        )

        # Submit handoff request
        response = self.handoff_client.request_handoff(request)

        print(f"  Handoff ID: {response.handoff_id}")
        print(f"  Status: {response.status.value}")

        return response

    def check_handoff_status(self, handoff_id: str) -> Optional[HandoffResponse]:
        """Check the status of a pending handoff.

        Args:
            handoff_id: The handoff to check

        Returns:
            Current handoff status
        """
        return self.handoff_client.get_handoff_status(handoff_id)


class TargetAgent:
    """Agent that receives and processes handoff requests.

    This represents a specialized agent that can accept handoffs
    from other agents and continue their tasks.
    """

    def __init__(
        self,
        agent_id: str,
        name: str,
        capabilities: list[str],
        handoff_client: HandoffClient
    ):
        """Initialize the target agent.

        Args:
            agent_id: Unique identifier for this agent
            name: Human-readable name
            capabilities: List of capabilities this agent offers
            handoff_client: Client for handoff operations
        """
        self.agent_id = agent_id
        self.name = name
        self.capabilities = AgentCapabilities(
            agent_id=agent_id,
            name=name,
            capabilities=capabilities
        )
        self.handoff_client = handoff_client
        self.active_handoffs: dict[str, HandoffContext] = {}

    def check_pending_handoffs(self) -> list[HandoffRequest]:
        """Check for pending handoff requests.

        Returns:
            List of pending handoff requests
        """
        pending = self.handoff_client.get_pending_handoffs(self.agent_id)
        print(f"\n[{self.name}] Found {len(pending)} pending handoffs")
        return pending

    def evaluate_handoff(self, request: HandoffRequest) -> tuple[bool, str]:
        """Evaluate whether to accept a handoff request.

        Args:
            request: The handoff request to evaluate

        Returns:
            Tuple of (should_accept, reason)
        """
        print(f"\n[{self.name}] Evaluating handoff from {request.from_agent}")
        print(f"  Reason: {request.reason}")
        print(f"  Required capabilities: {request.capabilities_required}")

        # Check capabilities
        if not self.capabilities.can_accept(request.capabilities_required):
            missing = set(request.capabilities_required) - set(self.capabilities.capabilities)
            if missing:
                return False, f"Missing capabilities: {missing}"
            else:
                return False, "At maximum capacity"

        return True, "Capabilities match and have capacity"

    def accept_handoff(self, handoff_id: str, request: HandoffRequest) -> HandoffContext:
        """Accept a handoff and restore context.

        Args:
            handoff_id: ID of the handoff to accept
            request: The original handoff request

        Returns:
            The restored handoff context
        """
        print(f"\n[{self.name}] Accepting handoff {handoff_id}")

        # Accept via client
        response = self.handoff_client.accept_handoff(handoff_id)
        print(f"  Status: {response.status.value}")

        # Deserialize context
        if request.context_snapshot:
            context = deserialize_context(request.context_snapshot)
            print(f"  Restored {len(context.conversation_history)} conversation turns")
            print(f"  Tool state keys: {list(context.tool_state.keys())}")
        else:
            context = HandoffContext()
            print("  No context to restore")

        # Track active handoff
        self.active_handoffs[handoff_id] = context
        self.capabilities.current_load += 1

        return context

    def reject_handoff(self, handoff_id: str, reason: str) -> HandoffResponse:
        """Reject a handoff request.

        Args:
            handoff_id: ID of the handoff to reject
            reason: Why the handoff is being rejected

        Returns:
            Updated handoff response
        """
        print(f"\n[{self.name}] Rejecting handoff {handoff_id}")
        print(f"  Reason: {reason}")

        response = self.handoff_client.reject_handoff(handoff_id, reason)
        print(f"  Status: {response.status.value}")

        return response

    def complete_handoff(self, handoff_id: str) -> HandoffResponse:
        """Mark a handoff as completed.

        Args:
            handoff_id: ID of the handoff to complete

        Returns:
            Updated handoff response
        """
        print(f"\n[{self.name}] Completing handoff {handoff_id}")

        response = self.handoff_client.complete_handoff(handoff_id)
        print(f"  Status: {response.status.value}")

        # Clean up
        if handoff_id in self.active_handoffs:
            del self.active_handoffs[handoff_id]
            self.capabilities.current_load -= 1

        return response

    def process_task(self, context: HandoffContext) -> dict[str, Any]:
        """Process a task using the restored context.

        Args:
            context: The restored handoff context

        Returns:
            Task result
        """
        print(f"\n[{self.name}] Processing task with restored context")

        # Show conversation context
        if context.conversation_history:
            print("  Recent conversation:")
            for turn in context.conversation_history[-3:]:
                print(f"    {turn['role']}: {turn['content'][:50]}...")

        # Simulate task processing
        time.sleep(0.1)

        result = {
            "status": "completed",
            "processed_by": self.agent_id,
            "conversation_turns_processed": len(context.conversation_history),
            "completed_at": int(time.time())
        }

        print(f"  Task completed successfully")
        return result


# ---------------------------------------------------------------------------
# Handoff Scenarios
# ---------------------------------------------------------------------------

def run_successful_handoff_scenario():
    """Demonstrate a successful handoff flow."""
    print("\n" + "=" * 70)
    print("SCENARIO 1: Successful Handoff")
    print("=" * 70)

    # Clear any existing handoff state
    HandoffClient.clear_all_handoffs()

    # Create shared handoff client
    client = HandoffClient()

    # Create agents
    general_agent = SourceAgent("general-agent-1", "General Assistant", client)
    code_agent = TargetAgent(
        "code-agent-1",
        "Code Specialist",
        ["code_review", "code_generation", "debugging"],
        client
    )

    # Simulate conversation in general agent
    general_agent.add_conversation_turn("user", "Can you help me review this Python code?")
    general_agent.add_conversation_turn(
        "assistant",
        "I'd be happy to help! Let me connect you with our code specialist."
    )
    general_agent.active_tools = {"file_reader": {"last_file": "main.py"}}

    # Request handoff
    response = general_agent.request_handoff(
        target_agent_id="code-agent-1",
        reason="User needs code review expertise",
        required_capabilities=["code_review"],
        preserve_history=True
    )

    # Code agent checks and accepts
    pending = code_agent.check_pending_handoffs()

    for request in pending:
        should_accept, reason = code_agent.evaluate_handoff(request)
        print(f"  Decision: {'Accept' if should_accept else 'Reject'} - {reason}")

        if should_accept:
            # Get handoff ID from the pending handoffs (match by from_agent)
            status = client.get_handoff_status(response.handoff_id)
            context = code_agent.accept_handoff(response.handoff_id, request)

            # Process the task
            result = code_agent.process_task(context)

            # Complete the handoff
            code_agent.complete_handoff(response.handoff_id)

            print(f"\n  Final result: {result}")

    print("\nHandoff completed successfully!")


def run_rejected_handoff_scenario():
    """Demonstrate a rejected handoff flow."""
    print("\n" + "=" * 70)
    print("SCENARIO 2: Rejected Handoff")
    print("=" * 70)

    HandoffClient.clear_all_handoffs()
    client = HandoffClient()

    # Create agents
    general_agent = SourceAgent("general-agent-2", "General Assistant", client)
    code_agent = TargetAgent(
        "code-agent-2",
        "Code Specialist",
        ["code_review"],  # Limited capabilities
        client
    )

    # Simulate conversation
    general_agent.add_conversation_turn("user", "I need help with database design")

    # Request handoff for capability the target doesn't have
    response = general_agent.request_handoff(
        target_agent_id="code-agent-2",
        reason="User needs database expertise",
        required_capabilities=["database_design", "schema_optimization"],
        preserve_history=True
    )

    # Code agent checks and rejects
    pending = code_agent.check_pending_handoffs()

    for request in pending:
        should_accept, reason = code_agent.evaluate_handoff(request)
        print(f"  Decision: {'Accept' if should_accept else 'Reject'} - {reason}")

        if not should_accept:
            code_agent.reject_handoff(response.handoff_id, reason)

    # Check final status
    final_status = general_agent.check_handoff_status(response.handoff_id)
    print(f"\n  Final status: {final_status.status.value}")
    print(f"  Rejection reason: {final_status.rejection_reason}")


def run_capability_matching_scenario():
    """Demonstrate capability-based agent selection."""
    print("\n" + "=" * 70)
    print("SCENARIO 3: Capability Matching")
    print("=" * 70)

    HandoffClient.clear_all_handoffs()
    client = HandoffClient()

    # Create a pool of specialized agents
    agents = [
        TargetAgent(
            "security-agent",
            "Security Specialist",
            ["security_audit", "vulnerability_scan", "penetration_test"],
            client
        ),
        TargetAgent(
            "performance-agent",
            "Performance Engineer",
            ["load_testing", "profiling", "optimization"],
            client
        ),
        TargetAgent(
            "data-agent",
            "Data Specialist",
            ["database_design", "schema_optimization", "data_migration"],
            client
        ),
    ]

    print("\nAvailable Agents:")
    for agent in agents:
        print(f"  {agent.name}: {agent.capabilities.capabilities}")

    # Find agent for specific task
    required = ["database_design", "schema_optimization"]
    print(f"\nLooking for agent with: {required}")

    matching_agent = None
    for agent in agents:
        if agent.capabilities.can_accept(required):
            matching_agent = agent
            break

    if matching_agent:
        print(f"  Found: {matching_agent.name}")
    else:
        print("  No matching agent found!")


def run_context_preservation_scenario():
    """Demonstrate context serialization and preservation."""
    print("\n" + "=" * 70)
    print("SCENARIO 4: Context Preservation")
    print("=" * 70)

    # Create a rich context
    context = HandoffContext(
        conversation_history=[
            {"role": "system", "content": "You are a helpful coding assistant."},
            {"role": "user", "content": "Help me write a Python function to calculate fibonacci."},
            {"role": "assistant", "content": "Here's a simple implementation:\n\ndef fib(n):..."},
            {"role": "user", "content": "Can you make it more efficient?"},
            {"role": "assistant", "content": "Let me connect you with our optimization specialist."},
        ],
        tool_state={
            "code_editor": {
                "open_files": ["main.py", "utils.py"],
                "cursor_position": {"line": 42, "column": 8}
            },
            "test_runner": {
                "last_run": "2024-01-15T10:30:00Z",
                "passed": 15,
                "failed": 2
            }
        },
        metadata={
            "session_id": "sess-12345",
            "user_preferences": {"theme": "dark", "language": "en"},
            "task_priority": "high"
        }
    )

    print("\nOriginal context:")
    print(f"  Conversation turns: {len(context.conversation_history)}")
    print(f"  Active tools: {list(context.tool_state.keys())}")
    print(f"  Metadata keys: {list(context.metadata.keys())}")

    # Serialize
    serialized = serialize_context(context)
    print(f"\nSerialized size: {len(serialized)} bytes")

    # Deserialize
    restored = deserialize_context(serialized)
    print("\nRestored context:")
    print(f"  Conversation turns: {len(restored.conversation_history)}")
    print(f"  Active tools: {list(restored.tool_state.keys())}")
    print(f"  Test runner state: {restored.tool_state.get('test_runner')}")

    # Verify integrity
    assert len(restored.conversation_history) == len(context.conversation_history)
    assert restored.tool_state == context.tool_state
    assert restored.metadata == context.metadata
    print("\n  Context integrity verified!")


def run_multi_agent_handoff_chain():
    """Demonstrate chained handoffs across multiple agents."""
    print("\n" + "=" * 70)
    print("SCENARIO 5: Multi-Agent Handoff Chain")
    print("=" * 70)

    HandoffClient.clear_all_handoffs()
    client = HandoffClient()

    # Create chain of agents
    initial_agent = SourceAgent("router-agent", "Task Router", client)

    # Simulate a task that requires multiple specialists
    print("\nTask: Complex code refactoring requiring:")
    print("  1. Code analysis")
    print("  2. Performance optimization")
    print("  3. Security review")

    # Simulate the handoff chain
    initial_agent.add_conversation_turn(
        "user",
        "Please refactor this legacy codebase for better performance and security"
    )

    # In a real scenario, each agent would hand off to the next
    # Here we just demonstrate the concept
    handoff_chain = [
        ("analyzer-agent", ["code_analysis", "refactoring"]),
        ("optimizer-agent", ["performance_optimization"]),
        ("security-agent", ["security_review"]),
    ]

    print("\nHandoff chain:")
    for i, (agent_id, capabilities) in enumerate(handoff_chain):
        print(f"  Step {i+1}: {agent_id} ({capabilities})")


def main() -> int:
    """Run all handoff examples."""
    print("\nSW4RM Agent Handoff Example")
    print("=" * 70)
    print("This demonstrates agent-to-agent task handoff with context preservation\n")

    # Run all scenarios
    run_successful_handoff_scenario()
    run_rejected_handoff_scenario()
    run_capability_matching_scenario()
    run_context_preservation_scenario()
    run_multi_agent_handoff_chain()

    print("\n" + "=" * 70)
    print("ALL HANDOFF SCENARIOS COMPLETED")
    print("=" * 70)
    print("\nKey takeaways:")
    print("1. Use HandoffClient.request_handoff() to initiate handoffs")
    print("2. Serialize context with HandoffContext for state preservation")
    print("3. Target agents can accept or reject based on capabilities")
    print("4. Check pending handoffs with get_pending_handoffs()")
    print("5. Complete the handoff lifecycle with complete_handoff()")
    print("6. Context includes conversation history, tool state, and metadata")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
