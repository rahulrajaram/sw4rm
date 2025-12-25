"""SW4RM client modules for interacting with protocol services.

This package provides client classes for all SW4RM protocol services:
- ActivityClient: Activity logging and tracking
- ConnectorClient: Agent-to-agent connections
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
- WorktreeClient: Worktree management
"""

__all__ = [
    "ActivityClient",
    "ConnectorClient",
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
    "WorktreeClient",
]

from sw4rm.clients.activity import ActivityClient
from sw4rm.clients.connector import ConnectorClient
from sw4rm.clients.hitl import HitlClient
from sw4rm.clients.logging import LoggingClient
from sw4rm.clients.negotiation import NegotiationClient
from sw4rm.clients.negotiation_room import NegotiationRoomClient
from sw4rm.clients.reasoning import ReasoningClient
from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.clients.scheduler import SchedulerClient
from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
from sw4rm.clients.tool import ToolClient
from sw4rm.clients.worktree import WorktreeClient
