#!/usr/bin/env python3
"""
Minimal Registry Service Implementation for SW4RM Protocol
Provides basic agent registration, heartbeat, and deregistration functionality.
"""

import logging
import os
import signal
import sys
import threading
import time
from concurrent import futures
from pathlib import Path
from typing import Dict, Optional

import grpc

# Import the generated protobuf modules
# Prefer stubs from the installed SDK; fallback to local generated stubs
try:
    from sw4rm.protos import registry_pb2, registry_pb2_grpc, common_pb2
except Exception:  # SDK not installed; use local generated stubs
    import registry_pb2, registry_pb2_grpc, common_pb2

from state_store import RegistryStateStore
from reference_auth_middleware import build_auth_interceptors
from reference_logging import configure_reference_service_logging
from reference_config import (
    ReferenceServiceConfig,
    ReferenceServiceConfigWatcher,
    load_reference_service_config,
    start_reference_service_config_watcher,
)
from health_service import add_reference_health_service
from graceful_shutdown import ReferenceServiceShutdownCoordinator


_DEFAULT_DB_DIR = str(Path.cwd() / ".reference_services_state")


def _default_db_path(env_var: str, filename: str) -> str:
    explicit = os.getenv(env_var)
    if explicit:
        return explicit
    return str(Path(_DEFAULT_DB_DIR) / filename)


class RegistryServiceImpl(registry_pb2_grpc.RegistryServiceServicer):
    """Simple registry service with optional SQLite persistence."""

    def __init__(
        self,
        db_path: Optional[str] = None,
        heartbeat_timeout_seconds: int = 300,
        cleanup_interval_seconds: int = 60,
        shutdown_manager: Optional[ReferenceServiceShutdownCoordinator] = None,
        config_watcher: Optional[ReferenceServiceConfigWatcher] = None,
    ):
        self._config_watcher = config_watcher
        base_config = (
            config_watcher.config
            if config_watcher is not None
            else load_reference_service_config("registry")
        )

        self.db_path = db_path or base_config.registry_db_path
        self.state = RegistryStateStore(self.db_path)
        self.agents: Dict[str, Dict] = dict(self.state.load_agents())
        self.agent_heartbeats: Dict[str, float] = {}
        for agent_id, info in self.agents.items():
            self.agent_heartbeats[agent_id] = float(info.get("last_heartbeat", 0.0))
        self.lock = threading.RLock()
        self._heartbeat_timeout_seconds = heartbeat_timeout_seconds
        self._cleanup_interval_seconds = cleanup_interval_seconds
        self._apply_runtime_config(base_config)
        self._shutdown_manager = (
            shutdown_manager
            or ReferenceServiceShutdownCoordinator(
                "registry-service",
                grace_period_seconds=base_config.shutdown_grace_seconds,
            )
        )
        # Agents that MUST NOT be removed by cleanup (e.g., scheduler)
        self.protected_agents = {"scheduler"}

        # Start heartbeat cleanup task
        self.cleanup_thread = threading.Thread(target=self._heartbeat_cleanup, daemon=True)
        self.cleanup_thread.start()

        logging.info("Registry service initialized")

    def _apply_runtime_config(self, config: ReferenceServiceConfig) -> None:
        heartbeat_timeout = max(0.0, config.registry_heartbeat_timeout_seconds)
        cleanup_interval = max(0.1, config.registry_cleanup_interval_seconds)
        self._heartbeat_timeout_seconds = heartbeat_timeout
        self._cleanup_interval_seconds = cleanup_interval

    def _refresh_runtime_config(self) -> None:
        if self._config_watcher is None:
            return
        self._apply_runtime_config(self._config_watcher.config)

    def RegisterAgent(self, request, context):
        """Register a new agent."""
        if self._shutdown_manager.is_draining:
            return registry_pb2.RegisterAgentResponse(
                accepted=False,
                reason="Registry service is shutting down",
            )

        self._refresh_runtime_config()
        with self._shutdown_manager.track_request("RegisterAgent"):
            agent = request.agent
            agent_id = agent.agent_id

            now = time.time()
            with self.lock:
                if agent_id in self.agents:
                    logging.warning(f"Agent {agent_id} already registered, updating")

                record = {
                    "agent_id": agent_id,
                    "name": agent.name,
                    "description": agent.description,
                    "capabilities": list(agent.capabilities),
                    "communication_class": int(agent.communication_class),
                    "modalities_supported": list(agent.modalities_supported),
                    "reasoning_connectors": list(agent.reasoning_connectors),
                    "registered_at": now,
                    "last_heartbeat": now,
                    "state": int(request.agent.state) if hasattr(agent, "state") else 0,
                    "health": {},
                }

                self.agents[agent_id] = record
                self.agent_heartbeats[agent_id] = now
                self.state.save_agent(
                    agent_id,
                    record,
                    registered_at=now,
                    last_heartbeat=now,
                )

                logging.info(f"Registered agent: {agent_id} ({agent.name})")

                return registry_pb2.RegisterAgentResponse(
                    accepted=True,
                    reason=f"Agent {agent_id} registered successfully",
                )

    def Heartbeat(self, request, context):
        """Process agent heartbeat."""
        if self._shutdown_manager.is_draining:
            return registry_pb2.HeartbeatResponse(ok=False)

        self._refresh_runtime_config()
        with self._shutdown_manager.track_request("Heartbeat"):
            agent_id = request.agent_id
            state = request.state
            health = dict(request.health)

            with self.lock:
                if agent_id not in self.agents:
                    logging.warning(f"Heartbeat from unregistered agent: {agent_id}")
                    return registry_pb2.HeartbeatResponse(ok=False)

                now = time.time()
                self.agent_heartbeats[agent_id] = now

                info = self.agents[agent_id]
                existing_health = info.get("health")
                if not isinstance(existing_health, dict):
                    existing_health = {}
                existing_health.update(health)

                info["state"] = state
                info["health"] = existing_health
                info["last_heartbeat"] = now
                self.state.save_agent(
                    agent_id,
                    info,
                    registered_at=float(info.get("registered_at", now)),
                    last_heartbeat=now,
                )

                logging.debug(f"Heartbeat from {agent_id}, state: {state}")
                return registry_pb2.HeartbeatResponse(ok=True)

    def DeregisterAgent(self, request, context):
        """Deregister an agent."""
        if self._shutdown_manager.is_draining:
            return registry_pb2.DeregisterAgentResponse(ok=False)

        self._refresh_runtime_config()
        with self._shutdown_manager.track_request("DeregisterAgent"):
            agent_id = request.agent_id
            reason = request.reason

            with self.lock:
                if agent_id in self.agents:
                    del self.agents[agent_id]
                    if agent_id in self.agent_heartbeats:
                        del self.agent_heartbeats[agent_id]
                    self.state.delete_agent(agent_id)

                    logging.info(f"Deregistered agent: {agent_id}, reason: {reason}")
                    return registry_pb2.DeregisterAgentResponse(ok=True)
                else:
                    logging.warning(f"Attempted to deregister unknown agent: {agent_id}")
                    return registry_pb2.DeregisterAgentResponse(ok=False)

    def _heartbeat_cleanup(self):
        """Remove agents that haven't sent heartbeats in a while."""
        while True:
            if self._shutdown_manager.is_draining:
                return
            try:
                self._refresh_runtime_config()
                time.sleep(self._cleanup_interval_seconds)
                now = time.time()

                with self.lock:
                    expired_agents = []
                    for agent_id, last_heartbeat in list(self.agent_heartbeats.items()):
                        if agent_id in self.protected_agents:
                            continue
                        if now - last_heartbeat > self._heartbeat_timeout_seconds:
                            expired_agents.append(agent_id)

                    for agent_id in expired_agents:
                        if agent_id in self.agents:
                            del self.agents[agent_id]
                        self.agent_heartbeats.pop(agent_id, None)
                        self.state.delete_agent(agent_id)
                        logging.info(f"Removed expired agent: {agent_id}")
            except Exception as e:
                logging.error(f"Error in heartbeat cleanup: {e}")

    def get_registered_agents(self):
        """Get list of currently registered agents (for debugging)."""
        with self.lock:
            return dict(self.agents)


def serve():
    """Start the registry service."""
    config_watcher = start_reference_service_config_watcher("registry")
    config = config_watcher.config

    configure_reference_service_logging(
        service_name="registry-service",
        level=os.getenv("REFERENCE_LOG_LEVEL", "INFO"),
    )

    # Create gRPC server
    server = grpc.server(
        futures.ThreadPoolExecutor(max_workers=10),
        interceptors=list(build_auth_interceptors(service_name="registry")),
    )

    # Add our service to the server
    registry_service = RegistryServiceImpl(
        config_watcher=config_watcher,
        db_path=config.registry_db_path,
        heartbeat_timeout_seconds=config.registry_heartbeat_timeout_seconds,
        cleanup_interval_seconds=config.registry_cleanup_interval_seconds,
        shutdown_manager=ReferenceServiceShutdownCoordinator(
            "registry-service",
            grace_period_seconds=config.shutdown_grace_seconds,
        ),
    )
    registry_pb2_grpc.add_RegistryServiceServicer_to_server(registry_service, server)
    try:
        registry_service_name = registry_pb2.DESCRIPTOR.services_by_name[
            "RegistryService"
        ].full_name
    except Exception:
        registry_service_name = "sw4rm.registry.RegistryService"
    add_reference_health_service(server, service_names=(registry_service_name,))

    # Listen on configurable port (default 50052)
    port = int(config.registry_port)
    listen_addr = f"0.0.0.0:{port}"
    bound_port = server.add_insecure_port(listen_addr)
    if bound_port == 0:
        raise RuntimeError(f"Failed to bind Registry service to {listen_addr}. Is the port in use?")

    # Start server
    server.start()
    logging.info(f"Registry service started on {listen_addr}")

    # Handle graceful shutdown
    def signal_handler(signum, frame):
        logging.info(f"Received signal {signum}, shutting down...")
        agents = registry_service.get_registered_agents()
        logging.info(f"Final state: {len(agents)} registered agents")
        for agent_id, info in agents.items():
            logging.info(f"  - {agent_id}: {info.get('name', 'Unknown')}")
        registry_service._shutdown_manager.stop_server(
            server,
            logger=logging.getLogger("registry.service"),
            pre_stop_hook=lambda: logging.info("Registry service entering graceful drain mode"),
        )

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Keep server running
    try:
        server.wait_for_termination()
    except KeyboardInterrupt:
        logging.info("Shutting down...")
        registry_service._shutdown_manager.stop_server(
            server,
            logger=logging.getLogger("registry.service"),
            pre_stop_hook=lambda: logging.info("Registry service entering graceful drain mode"),
        )
    finally:
        config_watcher.close()


if __name__ == '__main__':
    serve()
