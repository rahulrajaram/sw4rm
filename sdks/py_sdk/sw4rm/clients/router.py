from __future__ import annotations

from typing import Any, Iterable


class RouterClient:
    """Client for the SW4RM Router Service.

    Provides message routing capabilities between agents. The router handles
    delivery of envelopes to their intended recipients and supports streaming
    for continuous message reception.

    Attributes:
        _channel: gRPC channel for service communication
        _stub: Generated gRPC stub for RouterService
    """

    def __init__(self, channel: Any) -> None:
        self._channel = channel
        try:
            from sw4rm.protos import router_pb2, router_pb2_grpc  # type: ignore
            self._pb2 = router_pb2
            self._stub = router_pb2_grpc.RouterServiceStub(channel)
        except Exception:
            self._pb2 = None
            self._stub = None

    def send_message(self, envelope: dict) -> Any:
        """Send a message envelope to its destination.

        Args:
            envelope: Dictionary with Envelope fields (producer_id, message_type, etc.)

        Returns:
            SendMessageResponse with delivery status
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        from sw4rm.protos import common_pb2
        envelope_msg = common_pb2.Envelope(**envelope)
        req = self._pb2.SendMessageRequest(msg=envelope_msg)
        return self._stub.SendMessage(req)

    def stream_incoming(self, agent_id: str) -> Iterable[Any]:
        """Stream incoming messages for an agent.

        Args:
            agent_id: ID of the agent to receive messages for

        Returns:
            Iterator of StreamResponse objects containing incoming envelopes
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.StreamRequest(agent_id=agent_id)
        return self._stub.StreamIncoming(req)

