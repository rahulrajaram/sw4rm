# Handoff Context Serialization

This document specifies the serialization format for agent handoff contexts, including the JSON schema, serialization functions, request/response types, and agent hooks.

## Overview

Agent handoffs transfer execution context from one agent to another. The handoff context includes:

- **Conversation History:** Prior messages in the interaction
- **Tool State:** Active tool calls, cached results, configurations
- **Metadata:** Timestamps, capabilities, resource allocations

**Source Files:**

- `sdks/py_sdk/sw4rm/handoff/context.py` - Context and serialization
- `sdks/py_sdk/sw4rm/handoff/types.py` - Request/Response types

## HandoffContext

The `HandoffContext` dataclass captures all state needed for a receiving agent to continue execution:

```python
from dataclasses import dataclass, field
from typing import Any

@dataclass
class HandoffContext:
    """Context data for an agent handoff.

    Attributes:
        conversation_history: List of messages in the conversation history.
            Each message is a dict with 'role', 'content', and optional metadata.
        tool_state: Current state of tools, including active tool calls,
            cached results, and tool configurations.
        metadata: Additional metadata like timestamps, agent capabilities,
            resource allocations, etc.
    """
    conversation_history: list[dict[str, Any]] = field(default_factory=list)
    tool_state: dict[str, Any] = field(default_factory=dict)
    metadata: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """Convert the context to a dictionary."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> HandoffContext:
        """Create a HandoffContext from a dictionary."""
        return cls(
            conversation_history=data.get("conversation_history", []),
            tool_state=data.get("tool_state", {}),
            metadata=data.get("metadata", {})
        )
```

### JSON Schema

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "HandoffContext",
  "type": "object",
  "properties": {
    "conversation_history": {
      "type": "array",
      "description": "Prior messages in the conversation",
      "items": {
        "type": "object",
        "properties": {
          "role": {
            "type": "string",
            "description": "Message role (user, assistant, system, tool)"
          },
          "content": {
            "type": "string",
            "description": "Message content"
          },
          "timestamp": {
            "type": "string",
            "format": "date-time",
            "description": "ISO 8601 timestamp"
          },
          "metadata": {
            "type": "object",
            "description": "Optional message metadata"
          }
        },
        "required": ["role", "content"]
      }
    },
    "tool_state": {
      "type": "object",
      "description": "Current tool state including active calls and cached results",
      "additionalProperties": true
    },
    "metadata": {
      "type": "object",
      "description": "Additional context metadata",
      "additionalProperties": true
    }
  },
  "required": ["conversation_history", "tool_state", "metadata"]
}
```

### Conversation History Entry

Each entry in `conversation_history` should include:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `role` | `string` | Yes | Message role: `"user"`, `"assistant"`, `"system"`, `"tool"` |
| `content` | `string` | Yes | Message content |
| `timestamp` | `string` | No | ISO 8601 timestamp |
| `tool_call_id` | `string` | No | For tool responses, the call ID |
| `name` | `string` | No | For tool calls, the tool name |
| `metadata` | `object` | No | Additional message metadata |

Example:

```python
conversation_history = [
    {
        "role": "user",
        "content": "Analyze the sales data for Q3",
        "timestamp": "2025-01-15T10:30:00Z"
    },
    {
        "role": "assistant",
        "content": "I'll analyze the Q3 sales data for you.",
        "timestamp": "2025-01-15T10:30:01Z"
    },
    {
        "role": "tool",
        "name": "query_database",
        "tool_call_id": "call_abc123",
        "content": '{"total_sales": 1500000, "growth": 0.12}',
        "timestamp": "2025-01-15T10:30:05Z"
    }
]
```

### Tool State

The `tool_state` dictionary can contain:

| Key | Type | Description |
|-----|------|-------------|
| `active_calls` | `list` | Currently executing tool calls |
| `cached_results` | `dict` | Cached tool outputs by call ID |
| `configurations` | `dict` | Tool-specific configurations |
| `pending_approvals` | `list` | Tools awaiting HITL approval |

Example:

```python
tool_state = {
    "active_calls": [
        {"call_id": "call_xyz789", "tool": "long_running_query", "started_at": "..."}
    ],
    "cached_results": {
        "call_abc123": {"total_sales": 1500000, "growth": 0.12}
    },
    "configurations": {
        "database": {"connection_string": "...", "timeout_ms": 30000}
    }
}
```

## Serialization Functions

### serialize_context(context)

```python
def serialize_context(context: HandoffContext) -> bytes:
    """Serialize HandoffContext to compact JSON bytes.

    Uses UTF-8 encoding with compact separators (',', ':') to minimize size.

    Args:
        context: The HandoffContext to serialize

    Returns:
        JSON-encoded bytes representation of the context

    Raises:
        ValueError: If the context cannot be serialized (e.g., non-JSON-serializable values)
    """
```

Example:

```python
from sw4rm.handoff.context import HandoffContext, serialize_context

context = HandoffContext(
    conversation_history=[
        {"role": "user", "content": "Hello"},
        {"role": "assistant", "content": "Hi there!"}
    ],
    tool_state={},
    metadata={"agent_id": "agent-1"}
)

data = serialize_context(context)
# b'{"conversation_history":[{"role":"user","content":"Hello"},...],...}'
```

### deserialize_context(data)

```python
def deserialize_context(data: bytes) -> HandoffContext:
    """Deserialize bytes to a HandoffContext.

    Args:
        data: JSON-encoded bytes representation of a context

    Returns:
        HandoffContext instance

    Raises:
        ValueError: If the data cannot be deserialized
            - Invalid JSON
            - Invalid UTF-8 encoding
            - Missing required fields
    """
```

Example:

```python
from sw4rm.handoff.context import deserialize_context

data = b'{"conversation_history":[],"tool_state":{},"metadata":{}}'
context = deserialize_context(data)
```

## HandoffRequest

A request to hand off execution to another agent:

```python
from dataclasses import dataclass, field
from typing import Optional, Any

@dataclass
class HandoffRequest:
    """Request to hand off execution to another agent.

    Attributes:
        from_agent: ID of the agent initiating the handoff
        to_agent: ID of the agent that should receive the handoff
        reason: Human-readable explanation of why the handoff is needed
        context_snapshot: Serialized HandoffContext (from serialize_context)
        preserve_history: Whether to preserve conversation history (default: True)
        capabilities_required: List of capabilities the target agent must have
        metadata: Additional metadata for the handoff
    """
    from_agent: str
    to_agent: str
    reason: str
    context_snapshot: Optional[bytes] = None
    preserve_history: bool = True
    capabilities_required: list[str] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `from_agent` | `str` | Required | Source agent ID |
| `to_agent` | `str` | Required | Target agent ID |
| `reason` | `str` | Required | Human-readable handoff reason |
| `context_snapshot` | `bytes` | `None` | Serialized HandoffContext |
| `preserve_history` | `bool` | `True` | Include conversation history |
| `capabilities_required` | `list[str]` | `[]` | Required target capabilities |
| `metadata` | `dict` | `{}` | Additional handoff metadata |

## HandoffResponse

Response to a handoff request:

```python
from dataclasses import dataclass, field
from typing import Optional, Any
from enum import Enum

class HandoffStatus(Enum):
    """Status of a handoff request."""
    PENDING = "PENDING"
    ACCEPTED = "ACCEPTED"
    REJECTED = "REJECTED"
    COMPLETED = "COMPLETED"

@dataclass
class HandoffResponse:
    """Response to a handoff request.

    Attributes:
        accepted: Whether the handoff was accepted
        handoff_id: Unique identifier for the handoff transaction
        rejection_reason: Explanation if the handoff was rejected
        status: Current status of the handoff
        metadata: Additional metadata about the handoff
    """
    accepted: bool
    handoff_id: str
    rejection_reason: Optional[str] = None
    status: HandoffStatus = HandoffStatus.PENDING
    metadata: dict[str, Any] = field(default_factory=dict)
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `accepted` | `bool` | Required | Whether handoff was accepted |
| `handoff_id` | `str` | Required | Unique handoff transaction ID |
| `rejection_reason` | `str` | `None` | Reason if rejected |
| `status` | `HandoffStatus` | `PENDING` | Current handoff status |
| `metadata` | `dict` | `{}` | Additional response metadata |

### HandoffStatus Values

| Status | Description |
|--------|-------------|
| `PENDING` | Handoff requested, awaiting response |
| `ACCEPTED` | Target agent accepted the handoff |
| `REJECTED` | Target agent rejected the handoff |
| `COMPLETED` | Handoff completed successfully |

## Agent Hooks

Override these methods in your `Agent` subclass to handle handoffs:

### on_handoff_request(request)

```python
def on_handoff_request(self, request: HandoffRequest) -> HandoffResponse:
    """Called when another agent requests handoff to this agent.

    Override to implement acceptance logic based on:
    - capabilities_required matching your agent's capabilities
    - Current agent load/state (are you available?)
    - Policy checks (is this handoff allowed?)

    Args:
        request: HandoffRequest from the requesting agent

    Returns:
        HandoffResponse indicating acceptance or rejection
    """
```

Example implementation:

```python
class SpecialistAgent(Agent):
    CAPABILITIES = ["code_review", "security_analysis"]

    def on_handoff_request(self, request: HandoffRequest) -> HandoffResponse:
        # Check capabilities
        for cap in request.capabilities_required:
            if cap not in self.CAPABILITIES:
                return HandoffResponse(
                    accepted=False,
                    handoff_id=str(uuid.uuid4()),
                    rejection_reason=f"Missing capability: {cap}",
                    status=HandoffStatus.REJECTED
                )

        # Check availability
        if self.state != AgentState.RUNNABLE:
            return HandoffResponse(
                accepted=False,
                handoff_id=str(uuid.uuid4()),
                rejection_reason=f"Agent busy: {self.state_name}",
                status=HandoffStatus.REJECTED
            )

        # Accept handoff
        return HandoffResponse(
            accepted=True,
            handoff_id=str(uuid.uuid4()),
            status=HandoffStatus.ACCEPTED,
            metadata={"capabilities": self.CAPABILITIES}
        )
```

### on_handoff_received(context)

```python
def on_handoff_received(self, context: HandoffContext) -> None:
    """Called after handoff is accepted and context is received.

    Override to restore state from context:
    - Conversation history for continuity
    - Tool state for resuming operations
    - Session metadata for context awareness

    Args:
        context: HandoffContext with conversation history, tool state, etc.
    """
```

Example implementation:

```python
class SpecialistAgent(Agent):
    def on_handoff_received(self, context: HandoffContext) -> None:
        # Restore conversation history
        self.conversation_history = context.conversation_history
        self.logger.info(f"Received {len(self.conversation_history)} history entries")

        # Restore tool state
        if context.tool_state.get("active_calls"):
            for call in context.tool_state["active_calls"]:
                self._resume_tool_call(call)

        # Apply metadata
        self.session_metadata = context.metadata
        self.logger.info(f"Handoff received from: {context.metadata.get('agent_id')}")
```

## Usage Examples

### Basic Handoff with History Preservation

```python
from sw4rm.handoff import HandoffRequest, HandoffContext
from sw4rm.handoff.context import serialize_context

# Source agent initiates handoff
context = HandoffContext(
    conversation_history=[
        {"role": "user", "content": "Review this code for security issues"},
        {"role": "assistant", "content": "I'll need to hand this off to a specialist."}
    ],
    tool_state={},
    metadata={"original_request_id": "req-123"}
)

request = HandoffRequest(
    from_agent="general-agent-1",
    to_agent="security-specialist-1",
    reason="Task requires specialized security analysis capabilities",
    context_snapshot=serialize_context(context),
    preserve_history=True,
    capabilities_required=["security_analysis"],
    metadata={"urgency": "high"}
)

# Send request via HandoffClient
response = handoff_client.request_handoff(request)

if response.accepted:
    print(f"Handoff accepted: {response.handoff_id}")
else:
    print(f"Handoff rejected: {response.rejection_reason}")
```

### Capability-Based Routing

```python
class CapabilityRouter:
    """Route handoffs based on required capabilities."""

    def __init__(self, registry_client):
        self.registry = registry_client

    def find_capable_agent(self, capabilities: list[str]) -> Optional[str]:
        """Find an agent with all required capabilities."""
        agents = self.registry.list_agents()

        for agent in agents:
            agent_caps = set(agent.capabilities)
            if all(cap in agent_caps for cap in capabilities):
                if agent.state == "RUNNABLE":
                    return agent.agent_id

        return None

    def route_handoff(self, request: HandoffRequest) -> HandoffResponse:
        """Route a handoff to an appropriate agent."""
        if not request.to_agent:
            # Find suitable agent
            target = self.find_capable_agent(request.capabilities_required)
            if not target:
                return HandoffResponse(
                    accepted=False,
                    handoff_id=str(uuid.uuid4()),
                    rejection_reason="No capable agent available",
                    status=HandoffStatus.REJECTED
                )
            request.to_agent = target

        return self.handoff_client.request_handoff(request)
```

### Handoff Rejection Handling

```python
def initiate_handoff_with_fallback(
    from_agent: str,
    context: HandoffContext,
    preferred_agents: list[str],
    capabilities: list[str]
) -> HandoffResponse:
    """Try handoff to preferred agents with fallback."""

    for agent_id in preferred_agents:
        request = HandoffRequest(
            from_agent=from_agent,
            to_agent=agent_id,
            reason="Task delegation",
            context_snapshot=serialize_context(context),
            capabilities_required=capabilities
        )

        response = handoff_client.request_handoff(request)

        if response.accepted:
            return response

        print(f"Agent {agent_id} rejected: {response.rejection_reason}")

    # All preferred agents rejected
    return HandoffResponse(
        accepted=False,
        handoff_id=str(uuid.uuid4()),
        rejection_reason="All preferred agents unavailable",
        status=HandoffStatus.REJECTED
    )
```

## Context Size Considerations

Large handoff contexts can impact performance. Consider these guidelines:

| Factor | Recommendation |
|--------|----------------|
| **Conversation History** | Limit to last N relevant messages (e.g., 50) |
| **Tool State** | Only include active/pending, not completed calls |
| **Binary Data** | Use references (URLs, IDs) rather than embedding |
| **Compression** | Consider gzip for contexts > 100KB |

### Trimming Large Contexts

```python
def prepare_handoff_context(
    full_history: list[dict],
    tool_state: dict,
    max_history: int = 50
) -> HandoffContext:
    """Prepare a size-optimized handoff context."""

    # Trim history to recent messages
    trimmed_history = full_history[-max_history:]

    # Remove completed tool results
    active_tool_state = {
        "active_calls": tool_state.get("active_calls", []),
        "pending_approvals": tool_state.get("pending_approvals", []),
        # Omit cached_results to save space
    }

    return HandoffContext(
        conversation_history=trimmed_history,
        tool_state=active_tool_state,
        metadata={
            "original_history_length": len(full_history),
            "trimmed": len(full_history) > max_history
        }
    )
```

## See Also

- [Handoff Client](../clients/handoff.md) - Client API for handoffs
- [Agent Runtime](../architecture/state-machines.md) - Agent lifecycle and hooks
- [Registry Client](../clients/registry.md) - Agent discovery for routing
