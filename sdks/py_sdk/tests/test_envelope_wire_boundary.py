"""The public builder must compose with the real generated protobuf serializer."""
from sw4rm.clients.router import RouterClient
from sw4rm.envelope import build_envelope
from sw4rm.protos import router_pb2


class RecordingChannel:
    def __init__(self):
        self.requests = []

    def unary_unary(self, path, request_serializer, response_deserializer, **options):
        def invoke(request, **call_options):
            # Use the serializers installed by the generated stub, not mocks of protobuf.
            wire = request_serializer(request)
            self.requests.append(router_pb2.SendMessageRequest.FromString(wire))
            return response_deserializer(router_pb2.SendMessageResponse(accepted=True).SerializeToString())
        return invoke

    def unary_stream(self, *args, **kwargs):
        return lambda *_args, **_kwargs: iter(())


def test_builder_to_router_preserves_parent_timestamp_and_payload():
    channel = RecordingChannel()
    client = RouterClient(channel)
    envelope = build_envelope(producer_id="sender", message_type=2,
                              parent_correlation_id="parent", payload=b"\x00\xff",
                              sequence_number=2**64 - 1, effective_policy_id="local-policy",
                              audit_proof=b"local-proof")
    assert client.send_message(envelope).accepted
    actual = channel.requests[0].msg
    assert actual.parent_correlation_id == "parent"
    assert actual.sequence_number == 2**64 - 1
    assert actual.payload == b"\x00\xff"
    assert actual.timestamp.seconds == envelope["timestamp"]["seconds"]
    assert actual.timestamp.nanos == envelope["timestamp"]["nanos"]
    assert envelope["audit_proof"] == b"local-proof"


def test_local_handoff_never_silently_ignores_a_remote_channel():
    import pytest
    from sw4rm.clients.handoff import HandoffClient
    with pytest.raises(ValueError, match="ProtocolClient"):
        HandoffClient(channel=RecordingChannel())
