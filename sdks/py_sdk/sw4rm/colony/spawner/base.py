"""Base types and protocol for SW4RM agent spawning.

This module defines the core types, exceptions, and protocol interface
for agent spawning backends. The Spawner protocol supports pluggable
backends including thread-based, process-based, and container-based
spawning strategies.
"""

from __future__ import annotations

import uuid
from abc import abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum, auto
from typing import TYPE_CHECKING, Optional, Protocol, Set

if TYPE_CHECKING:
    pass


class SpawnMode(Enum):
    """Backend mode for agent spawning."""

    THREAD = auto()  # In-process threading (dev/testing)
    PROCESS = auto()  # Subprocess via fork/exec
    CONTAINER = auto()  # Docker/Kubernetes container


class AgentStatus(Enum):
    """Status of a spawned agent."""

    SPAWNING = auto()  # Spawn in progress
    STARTING = auto()  # Agent initializing
    READY = auto()  # Agent registered and ready for tasks
    BUSY = auto()  # Agent executing tasks
    UNHEALTHY = auto()  # Failed health checks
    TERMINATING = auto()  # Shutdown in progress
    TERMINATED = auto()  # Agent stopped
    FAILED = auto()  # Spawn or runtime failure


# --- Exceptions ---


class SpawnError(Exception):
    """Base exception for spawn operations."""

    pass


class SpawnTimeoutError(SpawnError):
    """Spawn operation timed out."""

    pass


class SpawnResourceError(SpawnError):
    """Insufficient resources for spawn."""

    pass


class SpawnConfigError(SpawnError):
    """Invalid spawn configuration."""

    pass


# --- Configuration Types ---


@dataclass
class ResourceLimits:
    """Resource constraints for spawned agents.

    All limits are advisory for THREAD mode, enforced for PROCESS/CONTAINER.
    """

    memory_mb: int = 512  # Memory limit in megabytes
    cpu_millicores: int = 1000  # CPU limit (1000 = 1 core)
    max_concurrent_tasks: int = 1  # Max parallel tasks per agent

    def __post_init__(self) -> None:
        if self.memory_mb < 64:
            raise ValueError("memory_mb must be >= 64")
        if self.cpu_millicores < 100:
            raise ValueError("cpu_millicores must be >= 100")
        if self.max_concurrent_tasks < 1:
            raise ValueError("max_concurrent_tasks must be >= 1")


@dataclass
class TimeoutSettings:
    """Timeout configuration for spawn operations."""

    spawn_timeout_s: float = 30.0  # Max time to wait for agent ready
    startup_timeout_s: float = 10.0  # Max time for agent initialization
    shutdown_timeout_s: float = 30.0  # Grace period for shutdown
    heartbeat_interval_s: float = 5.0  # Health check frequency
    heartbeat_timeout_s: float = 15.0  # Miss threshold before marking unhealthy


@dataclass
class SpawnerConfig:
    """Configuration for spawning a new agent.

    Attributes:
        agent_role: Semantic role identifier (e.g., "worker", "coordinator")
        agent_type: Agent class to instantiate (fully qualified name or alias)
        capabilities: List of capability tags for routing/matching
        resource_limits: Memory/CPU/concurrency constraints
        timeouts: Spawn and lifecycle timeout settings
        container_image: Docker image (required for CONTAINER mode)
        environment: Environment variables to pass to the agent
        labels: Metadata labels for filtering and organization
        ephemeral: If True, agent self-terminates after task completion
        parent_swarm: ID of the swarm this agent belongs to
    """

    agent_role: str
    agent_type: str
    capabilities: list[str] = field(default_factory=list)
    resource_limits: ResourceLimits = field(default_factory=ResourceLimits)
    timeouts: TimeoutSettings = field(default_factory=TimeoutSettings)
    container_image: Optional[str] = None
    environment: dict[str, str] = field(default_factory=dict)
    labels: dict[str, str] = field(default_factory=dict)
    ephemeral: bool = False
    parent_swarm: Optional[str] = None

    def validate(self, mode: SpawnMode) -> None:
        """Validate configuration for the given spawn mode.

        Args:
            mode: The spawn mode to validate against

        Raises:
            ValueError: If configuration is invalid for the mode
        """
        if not self.agent_role:
            raise ValueError("agent_role is required")
        if not self.agent_type:
            raise ValueError("agent_type is required")
        if mode == SpawnMode.CONTAINER and not self.container_image:
            raise ValueError("container_image required for CONTAINER mode")


# --- Agent Handle ---


@dataclass
class AgentHandle:
    """Handle to a spawned agent instance.

    Provides identity, status, and control over the agent lifecycle.
    The handle remains valid even after the agent terminates, allowing
    status queries and cleanup.

    Attributes:
        agent_id: Unique identifier assigned at spawn time
        config: The SpawnerConfig used to create this agent
        status: Current lifecycle status
        spawn_time: When the spawn was initiated
        ready_time: When the agent became ready (None if not yet ready)
        pid: Process ID for PROCESS mode (None otherwise)
        container_id: Container ID for CONTAINER mode (None otherwise)
        error: Error message if status is FAILED
    """

    agent_id: str
    config: SpawnerConfig
    status: AgentStatus
    spawn_time: datetime
    ready_time: Optional[datetime] = None
    pid: Optional[int] = None
    container_id: Optional[str] = None
    error: Optional[str] = None

    def is_alive(self) -> bool:
        """Check if the agent is still running."""
        return self.status in (
            AgentStatus.SPAWNING,
            AgentStatus.STARTING,
            AgentStatus.READY,
            AgentStatus.BUSY,
            AgentStatus.UNHEALTHY,
        )

    def is_ready(self) -> bool:
        """Check if the agent is ready to accept tasks."""
        return self.status == AgentStatus.READY

    def is_terminal(self) -> bool:
        """Check if the agent has reached a terminal state."""
        return self.status in (AgentStatus.TERMINATED, AgentStatus.FAILED)


# --- Spawner Protocol ---


class Spawner(Protocol):
    """Protocol for agent spawning backends.

    Implementations must be thread-safe. All methods may be called
    concurrently from multiple threads.
    """

    @abstractmethod
    def spawn_agent(self, config: SpawnerConfig) -> AgentHandle:
        """Spawn a new agent instance.

        Creates a new agent according to the provided configuration.
        Blocks until the agent reaches READY status or spawn times out.

        Args:
            config: Configuration for the new agent

        Returns:
            AgentHandle for the spawned agent

        Raises:
            SpawnConfigError: Invalid configuration
            SpawnResourceError: Insufficient resources
            SpawnTimeoutError: Spawn timed out waiting for ready
            SpawnError: Other spawn failures
        """
        ...

    @abstractmethod
    def spawn_agent_async(self, config: SpawnerConfig) -> AgentHandle:
        """Spawn a new agent asynchronously.

        Initiates spawn and returns immediately with a handle in
        SPAWNING status. Use get_agent_status() or wait_ready()
        to track progress.

        Args:
            config: Configuration for the new agent

        Returns:
            AgentHandle in SPAWNING status

        Raises:
            SpawnConfigError: Invalid configuration
            SpawnResourceError: Insufficient resources (pre-check)
        """
        ...

    @abstractmethod
    def wait_ready(
        self,
        agent_id: str,
        timeout_s: Optional[float] = None,
    ) -> AgentHandle:
        """Wait for an agent to reach READY status.

        Args:
            agent_id: ID of the agent to wait for
            timeout_s: Max seconds to wait (None = use config default)

        Returns:
            Updated AgentHandle

        Raises:
            SpawnTimeoutError: Timeout waiting for ready
            KeyError: Unknown agent_id
        """
        ...

    @abstractmethod
    def terminate_agent(
        self,
        agent_id: str,
        reason: str = "",
        force: bool = False,
    ) -> bool:
        """Terminate a spawned agent.

        Initiates graceful shutdown. If force=True, kills immediately
        without waiting for cleanup.

        Args:
            agent_id: ID of the agent to terminate
            reason: Human-readable termination reason
            force: If True, force-kill without grace period

        Returns:
            True if termination initiated, False if already terminated

        Raises:
            KeyError: Unknown agent_id
        """
        ...

    @abstractmethod
    def list_agents(
        self,
        status_filter: Optional[Set[AgentStatus]] = None,
        label_filter: Optional[dict[str, str]] = None,
    ) -> list[AgentHandle]:
        """List all spawned agents.

        Args:
            status_filter: If provided, only return agents with these statuses
            label_filter: If provided, only return agents matching all labels

        Returns:
            List of AgentHandle for matching agents
        """
        ...

    @abstractmethod
    def get_agent_status(self, agent_id: str) -> AgentStatus:
        """Get current status of an agent.

        Args:
            agent_id: ID of the agent to query

        Returns:
            Current AgentStatus

        Raises:
            KeyError: Unknown agent_id
        """
        ...

    @abstractmethod
    def get_agent(self, agent_id: str) -> AgentHandle:
        """Get full handle for an agent.

        Args:
            agent_id: ID of the agent to retrieve

        Returns:
            AgentHandle with current state

        Raises:
            KeyError: Unknown agent_id
        """
        ...

    @abstractmethod
    def cleanup_terminated(self, max_age_s: float = 3600.0) -> int:
        """Clean up handles for terminated agents.

        Removes handles for agents that have been in a terminal state
        (TERMINATED or FAILED) for longer than max_age_s.

        Args:
            max_age_s: Max age in seconds for terminated handles

        Returns:
            Number of handles cleaned up
        """
        ...


def generate_agent_id() -> str:
    """Generate a unique agent ID."""
    return f"agent-{uuid.uuid4().hex[:12]}"
