"""Protocol constants and defaults.

This module mirrors enum values from ``common.proto`` so the reference SDK can
be imported without generated stubs present. When pb2 modules are available,
prefer using those enums directly. Values must match ``common.proto``.

It also centralizes default service endpoints and environment variable names,
so examples and apps have a single source of truth.
"""
from __future__ import annotations

import os

# MessageType
MESSAGE_TYPE_UNSPECIFIED = 0
CONTROL = 1
DATA = 2
HEARTBEAT = 3
NOTIFICATION = 4
ACKNOWLEDGEMENT = 5
HITL_INVOCATION = 6
WORKTREE_CONTROL = 7
NEGOTIATION = 8
TOOL_CALL = 9
TOOL_RESULT = 10
TOOL_ERROR = 11

# AckStage
ACK_STAGE_UNSPECIFIED = 0
RECEIVED = 1
READ = 2
FULFILLED = 3
REJECTED = 4
FAILED = 5
TIMED_OUT = 6

# ErrorCode
ERROR_CODE_UNSPECIFIED = 0
BUFFER_FULL = 1
NO_ROUTE = 2
ACK_TIMEOUT = 3
AGENT_UNAVAILABLE = 4
AGENT_SHUTDOWN = 5
VALIDATION_ERROR = 6
PERMISSION_DENIED = 7
UNSUPPORTED_MESSAGE_TYPE = 8
OVERSIZE_PAYLOAD = 9
TOOL_TIMEOUT = 10
PARTIAL_DELIVERY = 11  # reserved
FORCED_PREEMPTION = 12
TTL_EXPIRED = 13
DUPLICATE_DETECTED = 14  # idempotency: duplicate request detected
INTERNAL_ERROR = 99

# CommunicationClass (spec section 7.3)
COMMUNICATION_CLASS_UNSPECIFIED = 0
PRIVILEGED = 1
STANDARD = 2
BULK = 3

# DebateIntensity (spec section 17)
DEBATE_INTENSITY_UNSPECIFIED = 0
LOWEST = 1
LOW = 2
MEDIUM = 3
HIGH = 4
HIGHEST = 5

# HitlReasonType (spec section 15)
HITL_REASON_UNSPECIFIED = 0
UNCERTAINTY_HIGH = 1
RISK_HIGH = 2
POLICY_REQUIRED = 3
USER_REQUESTED = 4
CONFLICT_UNRESOLVED = 5
BUDGET_EXCEEDED = 6
DEBATE_DEADLOCK = 7
SECURITY_APPROVAL = 8

# AgentState (spec section 8)
AGENT_STATE_UNSPECIFIED = 0
INITIALIZING = 1
RUNNABLE = 2
SCHEDULED = 3
RUNNING = 4
WAITING = 5
WAITING_RESOURCES = 6
SUSPENDED = 7
RESUMED = 8
COMPLETED = 9
FAILED = 10
SHUTTING_DOWN = 11
RECOVERING = 12

# WorktreeState (spec section 16)
WORKTREE_STATE_UNSPECIFIED = 0
UNBOUND = 1
BOUND_HOME = 2
SWITCH_PENDING = 3
BOUND_NON_HOME = 4
BIND_FAILED = 5

# EnvelopeState (Three-ID model)
ENVELOPE_STATE_UNSPECIFIED = 0
CREATED = 1
PENDING = 2
RUNNING_ENVELOPE = 3  # avoid collision with AgentState.RUNNING
FULFILLED_ENVELOPE = 4  # avoid collision with AckStage.FULFILLED
REJECTED_ENVELOPE = 5  # avoid collision with AckStage.REJECTED
FAILED_ENVELOPE = 6  # avoid collision with AckStage.FAILED
TIMED_OUT_ENVELOPE = 7  # avoid collision with AckStage.TIMED_OUT

# ---------------------------------------------------------------------------
# Default endpoints and environment variables
# ---------------------------------------------------------------------------

# Env var names (unified under SW4RM_*)
ENV_ROUTER_ADDR = "SW4RM_ROUTER_ADDR"
ENV_REGISTRY_ADDR = "SW4RM_REGISTRY_ADDR"

# Default host:port for local development
DEFAULT_ROUTER_ADDR = "localhost:50051"
DEFAULT_REGISTRY_ADDR = "localhost:50052"


def get_default_router_addr() -> str:
    """Return router address, honoring env override.

    Uses ``SW4RM_ROUTER_ADDR`` if set, otherwise ``DEFAULT_ROUTER_ADDR``.
    """
    return os.getenv(ENV_ROUTER_ADDR, DEFAULT_ROUTER_ADDR)


def get_default_registry_addr() -> str:
    """Return registry address, honoring env override.

    Uses ``SW4RM_REGISTRY_ADDR`` if set, otherwise ``DEFAULT_REGISTRY_ADDR``.
    """
    return os.getenv(ENV_REGISTRY_ADDR, DEFAULT_REGISTRY_ADDR)
