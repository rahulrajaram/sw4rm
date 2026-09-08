from __future__ import annotations

from typing import Any, Iterable

from sw4rm import tracing


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

        current_trace = tracing.get_current_trace()
        if current_trace is None:
            base_trace = tracing.trace_context_from_envelope_metadata(envelope)
        else:
            base_trace = current_trace
        if base_trace is None:
            base_trace = tracing.create_trace(metadata={"operation": "router_send"})

        request_trace = tracing.create_child_span(base_trace, metadata={"operation": "router_send"})
        outbound_envelope = tracing.add_trace_context_to_envelope(envelope, request_trace)
        outbound_envelope, _ = tracing.strip_trace_context_from_envelope(outbound_envelope)

        # These documented SDK-local annotations have no canonical wire fields.
        local_fields = {"effective_policy_id", "audit_proof", "audit_policy_id"}
        envelope_msg = common_pb2.Envelope(**{
            key: value for key, value in outbound_envelope.items() if key not in local_fields
        })
        req = self._pb2.SendMessageRequest(msg=envelope_msg)

        metadata = tracing.trace_context_to_metadata(request_trace)
        with tracing.with_trace_context(request_trace):
            return self._stub.SendMessage(req, metadata=tuple(metadata.items()))

    def stream_incoming(self, agent_id: str) -> Iterable[Any]:
        """Stream incoming messages for an agent.

        Each yielded item is a StreamItem with ``msg`` (the envelope) and
        ``seq`` (the router's pending-row id). Pass ``seq`` to
        :meth:`ack_delivery` to release the row; unacked rows are
        redelivered after the router's ack lease expires.

        Args:
            agent_id: ID of the agent to receive messages for

        Returns:
            Iterator of StreamItem objects containing incoming envelopes
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        req = self._pb2.StreamRequest(agent_id=agent_id)
        return self._stub.StreamIncoming(req)

    def ack_delivery(
        self,
        agent_id: str,
        seq: int,
        message_id: str = "",
        permanent_failure: bool = False,
    ) -> Any:
        """Acknowledge delivery of a streamed message by sequence number.

        Consumer-side call required by the at-least-once delivery contract:
        the router releases the pending row on ack and redelivers rows that
        are never acked (after the lease expires). Callers that receive a
        message but cannot process it should ack with ``permanent_failure=True``
        so the row is released without retry.

        Args:
            agent_id: The receiving agent's ID (as used for stream_incoming)
            seq: The StreamItem.seq value from the delivered message
            message_id: Optional message_id for router-side logging
            permanent_failure: True when the consumer will never process it

        Returns:
            DeliveryAckResponse (recorded=False when already acked/expired)
        """
        if not self._stub:
            raise RuntimeError("Protobuf stubs not generated. Run `make protos`.")
        outcome = (
            self._pb2.DELIVERY_ACK_OUTCOME_PERMANENT_FAILURE
            if permanent_failure
            else self._pb2.DELIVERY_ACK_OUTCOME_DELIVERED
        )
        req = self._pb2.DeliveryAckRequest(
            agent_id=agent_id,
            seq=int(seq),
            message_id=message_id,
            outcome=outcome,
        )
        return self._stub.AckDelivery(req)
