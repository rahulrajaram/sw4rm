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
INTERNAL_ERROR = 99

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
