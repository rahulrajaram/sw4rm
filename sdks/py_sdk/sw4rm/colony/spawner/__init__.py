"""SW4RM agent spawning module.

This package provides pluggable backends for dynamically spawning
and terminating agents within a SW4RM cluster.

Core types:
- SpawnerConfig: Configuration for spawning a new agent
- AgentHandle: Handle to a spawned agent instance
- AgentStatus: Lifecycle status enum
- SpawnMode: Backend mode enum (THREAD, PROCESS, CONTAINER)

Exceptions:
- SpawnError: Base exception for spawn operations
- SpawnTimeoutError: Spawn operation timed out
- SpawnResourceError: Insufficient resources
- SpawnConfigError: Invalid configuration

Backends:
- ThreadSpawner: In-process threading (dev/testing)
"""

from sw4rm.colony.spawner.base import (
    AgentHandle,
    AgentStatus,
    ResourceLimits,
    SpawnConfigError,
    SpawnError,
    Spawner,
    SpawnerConfig,
    SpawnMode,
    SpawnResourceError,
    SpawnTimeoutError,
    TimeoutSettings,
    generate_agent_id,
)
from sw4rm.colony.spawner.thread_spawner import ThreadSpawner

__all__ = [
    # Core types
    "SpawnerConfig",
    "AgentHandle",
    "AgentStatus",
    "SpawnMode",
    "ResourceLimits",
    "TimeoutSettings",
    # Protocol
    "Spawner",
    # Exceptions
    "SpawnError",
    "SpawnTimeoutError",
    "SpawnResourceError",
    "SpawnConfigError",
    # Backends
    "ThreadSpawner",
    # Utilities
    "generate_agent_id",
]
