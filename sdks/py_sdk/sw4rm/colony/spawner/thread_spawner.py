"""ThreadSpawner implementation for in-process agent spawning.

This module provides a thread-based spawner implementation suitable
for development, testing, and single-process deployments.
"""

from __future__ import annotations

import logging
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from dataclasses import replace
from datetime import datetime, timezone
from typing import Any, Callable, Optional, Set

from sw4rm.colony.spawner.base import (
    AgentHandle,
    AgentStatus,
    SpawnConfigError,
    SpawnError,
    SpawnerConfig,
    SpawnMode,
    SpawnResourceError,
    SpawnTimeoutError,
    generate_agent_id,
)

logger = logging.getLogger(__name__)


AgentFactory = Callable[[SpawnerConfig], Any]
"""Type alias for agent factory functions.

A factory takes a SpawnerConfig and returns an agent instance.
"""


class ThreadSpawner:
    """Spawn agents as threads within the current process.

    Advantages:
    - Fast spawn time (~1ms)
    - Shared memory for debugging
    - No IPC overhead

    Limitations:
    - Resource limits are advisory only
    - GIL contention for CPU-bound agents
    - Crash in one agent affects all

    Use cases:
    - Unit testing
    - Local development
    - Prototyping

    Thread-safety: All public methods are thread-safe.
    """

    def __init__(
        self,
        max_agents: int = 100,
        agent_factory: Optional[AgentFactory] = None,
    ) -> None:
        """Initialize ThreadSpawner.

        Args:
            max_agents: Maximum concurrent agents
            agent_factory: Optional factory for creating agent instances.
                          If not provided, agents are simulated (for testing).
        """
        self._max_agents = max_agents
        self._agent_factory = agent_factory
        self._agents: dict[str, AgentHandle] = {}
        self._agent_threads: dict[str, threading.Thread] = {}
        self._agent_stop_events: dict[str, threading.Event] = {}
        self._executor = ThreadPoolExecutor(max_workers=max_agents)
        self._lock = threading.RLock()
        self._mode = SpawnMode.THREAD
        logger.info(
            "ThreadSpawner initialized with max_agents=%d, factory=%s",
            max_agents,
            "provided" if agent_factory else "simulated",
        )

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
        handle = self.spawn_agent_async(config)
        return self.wait_ready(handle.agent_id, config.timeouts.spawn_timeout_s)

    def spawn_agent_async(self, config: SpawnerConfig) -> AgentHandle:
        """Spawn a new agent asynchronously.

        Initiates spawn and returns immediately with a handle in
        SPAWNING status.

        Args:
            config: Configuration for the new agent

        Returns:
            AgentHandle in SPAWNING status

        Raises:
            SpawnConfigError: Invalid configuration
            SpawnResourceError: Insufficient resources (pre-check)
        """
        # Validate configuration
        try:
            config.validate(self._mode)
        except ValueError as e:
            raise SpawnConfigError(str(e)) from e

        with self._lock:
            # Check resource availability
            active_count = sum(
                1 for h in self._agents.values() if h.is_alive()
            )
            if active_count >= self._max_agents:
                raise SpawnResourceError(
                    f"Max agents ({self._max_agents}) reached"
                )

            # Create agent handle
            agent_id = generate_agent_id()
            now = datetime.now(timezone.utc)
            handle = AgentHandle(
                agent_id=agent_id,
                config=config,
                status=AgentStatus.SPAWNING,
                spawn_time=now,
            )
            self._agents[agent_id] = handle

            # Create stop event for this agent
            stop_event = threading.Event()
            self._agent_stop_events[agent_id] = stop_event

            logger.info(
                "Spawning agent %s with role=%s, type=%s",
                agent_id,
                config.agent_role,
                config.agent_type,
            )

        # Start agent in background thread
        self._executor.submit(self._run_agent, agent_id, config, stop_event)

        return handle

    def _run_agent(
        self,
        agent_id: str,
        config: SpawnerConfig,
        stop_event: threading.Event,
    ) -> None:
        """Run the agent lifecycle in a background thread.

        Args:
            agent_id: The agent's unique ID
            config: Configuration for the agent
            stop_event: Event to signal graceful shutdown
        """
        try:
            # Transition to STARTING
            self._update_status(agent_id, AgentStatus.STARTING)
            logger.debug("Agent %s: STARTING", agent_id)

            # Create agent instance if factory provided
            agent_instance = None
            if self._agent_factory:
                try:
                    agent_instance = self._agent_factory(config)
                except Exception as e:
                    logger.error("Agent %s: factory failed: %s", agent_id, e)
                    self._update_status(
                        agent_id, AgentStatus.FAILED, error=str(e)
                    )
                    return

            # Simulate startup delay (or actual startup)
            startup_delay = 0.01  # 10ms for fast testing
            if not stop_event.wait(startup_delay):
                # Transition to READY
                now = datetime.now(timezone.utc)
                with self._lock:
                    if agent_id in self._agents:
                        self._agents[agent_id] = replace(
                            self._agents[agent_id],
                            status=AgentStatus.READY,
                            ready_time=now,
                        )
                logger.info("Agent %s: READY", agent_id)

                # Run until stop requested
                while not stop_event.is_set():
                    # Agent main loop - would call agent_instance.run() if real
                    if not stop_event.wait(0.1):
                        continue

            # Graceful shutdown
            self._update_status(agent_id, AgentStatus.TERMINATING)
            logger.debug("Agent %s: TERMINATING", agent_id)

            # Cleanup
            if agent_instance and hasattr(agent_instance, "cleanup"):
                try:
                    agent_instance.cleanup()
                except Exception as e:
                    logger.warning("Agent %s cleanup error: %s", agent_id, e)

            self._update_status(agent_id, AgentStatus.TERMINATED)
            logger.info("Agent %s: TERMINATED", agent_id)

        except Exception as e:
            logger.exception("Agent %s: unhandled error", agent_id)
            self._update_status(agent_id, AgentStatus.FAILED, error=str(e))

    def _update_status(
        self,
        agent_id: str,
        status: AgentStatus,
        error: Optional[str] = None,
    ) -> None:
        """Update an agent's status in the registry.

        Args:
            agent_id: The agent's unique ID
            status: New status value
            error: Optional error message (for FAILED status)
        """
        with self._lock:
            if agent_id in self._agents:
                handle = self._agents[agent_id]
                if error:
                    self._agents[agent_id] = replace(
                        handle, status=status, error=error
                    )
                else:
                    self._agents[agent_id] = replace(handle, status=status)

    def wait_ready(
        self,
        agent_id: str,
        timeout_s: Optional[float] = None,
    ) -> AgentHandle:
        """Wait for an agent to reach READY status.

        Args:
            agent_id: ID of the agent to wait for
            timeout_s: Max seconds to wait (None = 30s default)

        Returns:
            Updated AgentHandle

        Raises:
            SpawnTimeoutError: Timeout waiting for ready
            KeyError: Unknown agent_id
        """
        if timeout_s is None:
            timeout_s = 30.0

        with self._lock:
            if agent_id not in self._agents:
                raise KeyError(f"Unknown agent_id: {agent_id}")

        deadline = time.monotonic() + timeout_s
        poll_interval = 0.01  # 10ms polling

        while time.monotonic() < deadline:
            with self._lock:
                handle = self._agents.get(agent_id)
                if handle is None:
                    raise KeyError(f"Unknown agent_id: {agent_id}")

                if handle.status == AgentStatus.READY:
                    return handle

                if handle.status == AgentStatus.FAILED:
                    raise SpawnError(
                        f"Agent {agent_id} failed: {handle.error}"
                    )

                if handle.is_terminal():
                    raise SpawnError(
                        f"Agent {agent_id} reached terminal state: {handle.status.name}"
                    )

            time.sleep(poll_interval)

        # Timeout reached - mark as failed and cleanup
        with self._lock:
            handle = self._agents.get(agent_id)
            if handle and not handle.is_terminal():
                self._agents[agent_id] = replace(
                    handle,
                    status=AgentStatus.FAILED,
                    error="Spawn timeout",
                )
                # Signal stop
                stop_event = self._agent_stop_events.get(agent_id)
                if stop_event:
                    stop_event.set()

        raise SpawnTimeoutError(
            f"Agent {agent_id} did not reach READY within {timeout_s}s"
        )

    def terminate_agent(
        self,
        agent_id: str,
        reason: str = "",
        force: bool = False,
    ) -> bool:
        """Terminate a spawned agent.

        Initiates graceful shutdown. If force=True, kills immediately.

        Args:
            agent_id: ID of the agent to terminate
            reason: Human-readable termination reason
            force: If True, force-kill without grace period

        Returns:
            True if termination initiated, False if already terminated

        Raises:
            KeyError: Unknown agent_id
        """
        with self._lock:
            if agent_id not in self._agents:
                raise KeyError(f"Unknown agent_id: {agent_id}")

            handle = self._agents[agent_id]

            if handle.is_terminal():
                logger.debug(
                    "Agent %s already in terminal state: %s",
                    agent_id,
                    handle.status.name,
                )
                return False

            logger.info(
                "Terminating agent %s (reason=%s, force=%s)",
                agent_id,
                reason or "none",
                force,
            )

            # Signal stop to the agent thread
            stop_event = self._agent_stop_events.get(agent_id)
            if stop_event:
                stop_event.set()

            if force:
                # Force immediate termination
                self._agents[agent_id] = replace(
                    handle, status=AgentStatus.TERMINATED
                )
            else:
                # Graceful - let the thread handle transition
                self._agents[agent_id] = replace(
                    handle, status=AgentStatus.TERMINATING
                )

            return True

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
        with self._lock:
            result = []
            for handle in self._agents.values():
                # Apply status filter
                if status_filter and handle.status not in status_filter:
                    continue

                # Apply label filter
                if label_filter:
                    labels = handle.config.labels
                    if not all(
                        labels.get(k) == v for k, v in label_filter.items()
                    ):
                        continue

                result.append(handle)

            return result

    def get_agent_status(self, agent_id: str) -> AgentStatus:
        """Get current status of an agent.

        Args:
            agent_id: ID of the agent to query

        Returns:
            Current AgentStatus

        Raises:
            KeyError: Unknown agent_id
        """
        with self._lock:
            if agent_id not in self._agents:
                raise KeyError(f"Unknown agent_id: {agent_id}")
            return self._agents[agent_id].status

    def get_agent(self, agent_id: str) -> AgentHandle:
        """Get full handle for an agent.

        Args:
            agent_id: ID of the agent to retrieve

        Returns:
            AgentHandle with current state

        Raises:
            KeyError: Unknown agent_id
        """
        with self._lock:
            if agent_id not in self._agents:
                raise KeyError(f"Unknown agent_id: {agent_id}")
            return self._agents[agent_id]

    def cleanup_terminated(self, max_age_s: float = 3600.0) -> int:
        """Clean up handles for terminated agents.

        Removes handles for agents that have been in a terminal state
        (TERMINATED or FAILED) for longer than max_age_s.

        Args:
            max_age_s: Max age in seconds for terminated handles

        Returns:
            Number of handles cleaned up
        """
        now = datetime.now(timezone.utc)
        cleaned = 0

        with self._lock:
            to_remove = []
            for agent_id, handle in self._agents.items():
                if handle.is_terminal():
                    age = (now - handle.spawn_time).total_seconds()
                    if age > max_age_s:
                        to_remove.append(agent_id)

            for agent_id in to_remove:
                del self._agents[agent_id]
                self._agent_stop_events.pop(agent_id, None)
                cleaned += 1
                logger.debug("Cleaned up terminated agent %s", agent_id)

        if cleaned > 0:
            logger.info("Cleaned up %d terminated agent handles", cleaned)

        return cleaned

    def shutdown(self, wait: bool = True, _timeout: float = 10.0) -> None:
        """Shutdown the spawner and terminate all agents.

        Args:
            wait: If True, wait for agents to terminate gracefully
            _timeout: Max seconds to wait for graceful shutdown (reserved for future use)
        """
        logger.info("Shutting down ThreadSpawner")

        # Signal all agents to stop
        with self._lock:
            for stop_event in self._agent_stop_events.values():
                stop_event.set()

        # Shutdown executor
        self._executor.shutdown(wait=wait, cancel_futures=not wait)

        logger.info("ThreadSpawner shutdown complete")
