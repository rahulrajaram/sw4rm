import base64

def test_protos_imports():
    # Ensure generated stubs can be imported
    import sw4rm.protos.common_pb2  # type: ignore
    import sw4rm.protos.registry_pb2  # type: ignore
    import sw4rm.protos.router_pb2  # type: ignore
    import sw4rm.protos.scheduler_pb2  # type: ignore
    import sw4rm.protos.scheduler_policy_pb2  # type: ignore
    import sw4rm.protos.policy_pb2  # type: ignore
    import sw4rm.protos.activity_pb2  # type: ignore


def test_clients_construct():
    # Construct clients with a local channel (no calls made)
    import grpc  # type: ignore
    from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
    from sw4rm.clients.activity import ActivityClient

    ch = grpc.insecure_channel("localhost:9")
    sp = SchedulerPolicyClient(ch)
    act = ActivityClient(ch)

    # Accessing attributes to ensure initialization completed
    assert hasattr(sp, "_stub")
    assert hasattr(act, "_stub")


def test_negotiation_event_helpers():
    from sw4rm.negotiation_events import parse_negotiation_event, decode_b64

    evt = parse_negotiation_event('{"kind":"propose","from":"a","ct":"text/plain","payload_b64":"SGk="}')
    assert evt.get("kind") == "propose"
    data = decode_b64(evt.get("payload_b64"))
    assert data == base64.b64decode("SGk=")

