from __future__ import annotations

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

    def __init__(self, channel: Any, timeout: float = 30.0) -> None:
        """Initialize the RegistryClient.

        Args:
            channel: gRPC channel for service communication
            timeout: Default timeout in seconds for RPC calls (default: 30.0)
        """
        self._channel = channel
        self._timeout = timeout
        try:
            from sw4rm.protos import registry_pb2, registry_pb2_grpc  # type: ignore
            self._pb2 = registry_pb2
            self._stub = registry_pb2_grpc.RegistryServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def register(self, agent_descriptor: dict, timeout: float | None = None) -> Any:
        """Register an agent with the registry.

        Args:
            agent_descriptor: Dictionary with agent details (agent_id, name,
                capabilities, communication_class, etc.)
            timeout: Optional timeout in seconds (uses default if not specified)

        Returns:
            RegisterAgentResponse with registration status
        """
        if not self._stub or not self._pb2:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.RegisterAgentRequest(
            agent=self._pb2.AgentDescriptor(**agent_descriptor)
        )
        return self._stub.RegisterAgent(req, timeout=timeout or self._timeout)

    def heartbeat(self, agent_id: str, state: int, health: dict[str, str] | None = None, timeout: float | None = None) -> Any:
        """Send a heartbeat to keep registration alive.

        Args:
            agent_id: ID of the agent sending the heartbeat
            state: Current agent state (see constants.AgentState)
            health: Optional health metrics as key-value pairs
            timeout: Optional timeout in seconds (uses default if not specified)

        Returns:
            HeartbeatResponse with acknowledgment
        """
        if not self._stub or not self._pb2:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.HeartbeatRequest(agent_id=agent_id, state=state, health=health or {})
        return self._stub.Heartbeat(req, timeout=timeout or self._timeout)

    def deregister(self, agent_id: str, reason: str = "", timeout: float | None = None) -> Any:
        """Deregister an agent from the registry.

        Args:
            agent_id: ID of the agent to deregister
            reason: Optional reason for deregistration
            timeout: Optional timeout in seconds (uses default if not specified)

        Returns:
            DeregisterAgentResponse with confirmation
        """
        if not self._stub or not self._pb2:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.DeregisterAgentRequest(agent_id=agent_id, reason=reason)
        return self._stub.DeregisterAgent(req, timeout=timeout or self._timeout)

