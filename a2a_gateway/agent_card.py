"""Generate A2A Agent Cards from SW4RM Registry agent descriptors.

An A2A Agent Card is a JSON document describing an agent's identity,
capabilities, skills, and endpoint. This module bridges SW4RM's
AgentDescriptor (from registry.proto) to A2A's AgentCard format.
"""

from typing import Any


# Default A2A protocol version we advertise
A2A_PROTOCOL_VERSION = "0.3"

# Default gateway version
GATEWAY_VERSION = "0.6.0"


def agent_descriptor_to_card(
    descriptor: dict[str, Any],
    gateway_url: str = "http://localhost:50054",
) -> dict[str, Any]:
    """Convert a SW4RM AgentDescriptor dict to an A2A AgentCard dict.

    Args:
        descriptor: SW4RM AgentDescriptor fields (agent_id, name,
            description, capabilities, modalities_supported, etc.)
        gateway_url: URL where this A2A gateway is reachable.

    Returns:
        A2A AgentCard as a JSON-serializable dict.
    """
    agent_id = descriptor.get("agent_id", "unknown")
    name = descriptor.get("name", agent_id)
    description = descriptor.get("description", f"SW4RM agent: {agent_id}")
    capabilities_list = descriptor.get("capabilities", [])
    modalities = descriptor.get("modalities_supported", [])

    # Map SW4RM capabilities to A2A skills
    skills = []
    for i, cap in enumerate(capabilities_list):
        skills.append({
            "id": f"skill-{i}",
            "name": cap.replace("-", " ").replace("_", " ").title(),
            "description": f"Agent capability: {cap}",
            "tags": [cap],
            "examples": [],
        })

    # Map SW4RM modalities to A2A content types
    content_types = modalities if modalities else ["text/plain", "application/json"]

    return {
        "name": name,
        "description": description,
        "url": f"{gateway_url}/agents/{agent_id}",
        "version": GATEWAY_VERSION,
        "protocolVersion": A2A_PROTOCOL_VERSION,
        "capabilities": {
            "streaming": True,  # SW4RM supports StreamIncoming
            "pushNotifications": False,  # Not yet implemented
            "stateTransitionHistory": True,  # Activity buffer provides this
        },
        "skills": skills,
        "supportedContentTypes": content_types,
    }


def make_gateway_card(
    gateway_url: str = "http://localhost:50054",
    agents: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Create an A2A Agent Card for the SW4RM gateway itself.

    The gateway card advertises the gateway as a meta-agent that can
    route to any registered SW4RM agent.

    Args:
        gateway_url: URL where the A2A gateway is reachable.
        agents: Optional list of registered agent descriptors to
            include as skills.

    Returns:
        A2A AgentCard for the gateway.
    """
    skills = []
    if agents:
        for agent in agents:
            aid = agent.get("agent_id", "unknown")
            skills.append({
                "id": f"agent-{aid}",
                "name": agent.get("name", aid),
                "description": agent.get("description", f"SW4RM agent: {aid}"),
                "tags": agent.get("capabilities", []),
                "examples": [f"Send a task to {aid}"],
            })

    return {
        "name": "SW4RM Gateway",
        "description": (
            "A2A-compatible gateway to a SW4RM agent swarm. "
            "Routes tasks to registered agents with scheduling, "
            "negotiation, and crash recovery guarantees."
        ),
        "url": gateway_url,
        "version": GATEWAY_VERSION,
        "protocolVersion": A2A_PROTOCOL_VERSION,
        "capabilities": {
            "streaming": True,
            "pushNotifications": False,
            "stateTransitionHistory": True,
        },
        "skills": skills,
        "supportedContentTypes": ["text/plain", "application/json"],
    }
