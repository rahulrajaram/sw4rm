from __future__ import annotations

from dataclasses import asdict
from typing import Any


class RegistryClient:
    """Client for the SW4RM Registry Service.

    Manages agent registration, heartbeats, and deregistration. The registry
    maintains the catalog of active agents and their capabilities for routing
    and scheduling decisions.

    Attributes:
        _channel: gRPC channel for service communication
        _stub: Generated gRPC stub for RegistryService
    """

    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import registry_pb2, registry_pb2_grpc  # type: ignore
            self._pb2 = registry_pb2
            self._stub = registry_pb2_grpc.RegistryServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def register(self, agent_descriptor: dict) -> Any:
        """Register an agent with the registry.

        Args:
            agent_descriptor: Dictionary with agent details (agent_id, name,
                capabilities, communication_class, etc.)

        Returns:
            RegisterAgentResponse with registration status
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.RegisterAgentRequest(
            agent=self._pb2.AgentDescriptor(**agent_descriptor)
        )
        return self._stub.RegisterAgent(req)

    def heartbeat(self, agent_id: str, state: int, health: dict[str, str] | None = None) -> Any:
        """Send a heartbeat to keep registration alive.

        Args:
            agent_id: ID of the agent sending the heartbeat
            state: Current agent state (see constants.AgentState)
            health: Optional health metrics as key-value pairs

        Returns:
            HeartbeatResponse with acknowledgment
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.HeartbeatRequest(agent_id=agent_id, state=state, health=health or {})
        return self._stub.Heartbeat(req)

    def deregister(self, agent_id: str, reason: str = "") -> Any:
        """Deregister an agent from the registry.

        Args:
            agent_id: ID of the agent to deregister
            reason: Optional reason for deregistration

        Returns:
            DeregisterAgentResponse with confirmation
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.DeregisterAgentRequest(agent_id=agent_id, reason=reason)
        return self._stub.DeregisterAgent(req)

