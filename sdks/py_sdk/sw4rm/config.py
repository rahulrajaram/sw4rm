from __future__ import annotations

"""SDK configuration primitives.

Provides typed configuration objects and helpers to centralize service
endpoints, agent metadata, and basic runtime knobs. Defaults are sourced from
``sw4rm.constants`` so applications and examples have a single source of truth.
"""

from dataclasses import dataclass, field
from typing import Optional

from . import constants as C


@dataclass
class Endpoints:
    """Addresses for SW4RM services.

    Only router and registry are required for the reference examples. Additional
    services can be added here as the SDK grows.
    """

    router_addr: str = field(default_factory=C.get_default_router_addr)
    registry_addr: str = field(default_factory=C.get_default_registry_addr)


@dataclass
class RetryPolicy:
    """Simple retry policy for unary calls."""

    max_attempts: int = 3
    initial_backoff_s: float = 0.2
    max_backoff_s: float = 2.0
    backoff_multiplier: float = 2.0


@dataclass
class AgentConfig:
    """Agent runtime configuration.

    - ``agent_id`` and ``name`` identify the agent.
    - ``endpoints`` provides service addresses.
    - ``request_timeout_s`` applies to unary calls unless overridden.
    - ``retry`` controls basic retry for transient failures.
    """

    agent_id: str = "agent-1"
    name: str = "Agent"
    endpoints: Endpoints = field(default_factory=Endpoints)
    request_timeout_s: float = 10.0
    stream_keepalive_s: float = 60.0
    retry: RetryPolicy = field(default_factory=RetryPolicy)
    description: Optional[str] = None


def from_env() -> AgentConfig:
    """Construct ``AgentConfig`` using environment overrides where available.

    Uses ``AGENT_ID`` and ``AGENT_NAME`` if set, and respects the endpoint
    environment variables defined in ``sw4rm.constants``.
    """

    import os

    agent_id = os.getenv("AGENT_ID", "agent-1")
    name = os.getenv("AGENT_NAME", "Agent")
    endpoints = Endpoints()  # picks up env via default_factory
    return AgentConfig(agent_id=agent_id, name=name, endpoints=endpoints)

