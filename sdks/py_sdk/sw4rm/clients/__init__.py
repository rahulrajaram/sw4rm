"""SW4RM client modules for interacting with protocol services.

This package provides client classes for all SW4RM protocol services:
- ActivityClient: Activity logging and tracking
- ConnectorClient: Agent-to-agent connections
- HandoffClient: Agent-to-agent task handoffs
- HITLClient: Human-in-the-loop interactions
- LoggingClient: Logging service
- NegotiationClient: Negotiation protocol
- NegotiationRoomClient: Multi-agent artifact review (Negotiation Room pattern)
- ReasoningClient: Reasoning and decision logging
- RegistryClient: Agent registry
- RouterClient: Message routing
- SchedulerClient: Task scheduling
- SchedulerPolicyClient: Policy management
- ToolClient: Tool execution
- WorkflowClient: DAG-based workflow orchestration (alias for WorkflowEngine)
- WorktreeClient: Worktree management

Storage backends (core):
- NegotiationRoomStore: Protocol for negotiation room storage backends
- InMemoryNegotiationRoomStore: Thread-safe in-memory storage

For persistent storage backends (JSON file, Redis, PostgreSQL), see colony/stores.
"""

__all__ = [
    "ActivityClient",
    "ConnectorClient",
    "HandoffClient",
    "HitlClient",
    "LoggingClient",
    "NegotiationClient",
    "NegotiationRoomClient",
    "ReasoningClient",
    "RegistryClient",
    "RouterClient",
    "SchedulerClient",
    "SchedulerPolicyClient",
    "ToolClient",
    "WorkflowClient",
    "WorktreeClient",
    # Storage backends (core only - see colony/stores for persistence)
    "NegotiationRoomStore",
    "InMemoryNegotiationRoomStore",
    "get_default_negotiation_room_store",
    "reset_default_negotiation_room_store",
]

from sw4rm.clients.activity import ActivityClient
from sw4rm.clients.connector import ConnectorClient
from sw4rm.clients.handoff import HandoffClient
from sw4rm.clients.hitl import HitlClient
from sw4rm.clients.logging import LoggingClient
from sw4rm.clients.negotiation import NegotiationClient
from sw4rm.clients.negotiation_room import NegotiationRoomClient
from sw4rm.clients.negotiation_room_store import (
    NegotiationRoomStore,
    InMemoryNegotiationRoomStore,
    get_default_store as get_default_negotiation_room_store,
    reset_default_store as reset_default_negotiation_room_store,
)
from sw4rm.clients.reasoning import ReasoningClient
from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.clients.scheduler import SchedulerClient
from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
from sw4rm.clients.tool import ToolClient
from sw4rm.clients.workflow import WorkflowClient
from sw4rm.clients.worktree import WorktreeClient
