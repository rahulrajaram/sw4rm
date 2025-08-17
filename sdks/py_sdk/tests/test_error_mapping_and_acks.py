import json
from sw4rm import constants as C
from sw4rm.error_mapping import DictErrorCodeMapper, DEFAULT_EXCEPTION_MAPPING, map_exception_to_error_code
from sw4rm.acks import build_ack, build_ack_envelope, ack_for_send_result


def test_error_mapping_defaults_and_mro():
    mapper = DictErrorCodeMapper(DEFAULT_EXCEPTION_MAPPING)
    assert mapper.map_exception(ValueError("bad")) == C.VALIDATION_ERROR
    assert mapper.map_exception(PermissionError("no")) == C.PERMISSION_DENIED
    # Inheritance: ConnectionRefusedError is a ConnectionError
    assert mapper.map_exception(ConnectionRefusedError()) == C.AGENT_UNAVAILABLE
    assert map_exception_to_error_code(TimeoutError()) == C.ACK_TIMEOUT


def test_ack_builders():
    ack = build_ack(ack_for_message_id="m1", ack_stage=C.RECEIVED, note="ok")
    assert ack["ack_for_message_id"] == "m1"
    assert ack["ack_stage"] == C.RECEIVED
    env = build_ack_envelope(producer_id="p", ack_for_message_id="m1", ack_stage=C.RECEIVED)
    assert env["message_type"] == C.ACKNOWLEDGEMENT
    assert env["content_type"] == "application/json"
    payload = json.loads(env["payload"].decode("utf-8"))
    assert payload["ack_for_message_id"] == "m1"

    e2 = ack_for_send_result(producer_id="p", original_msg_id="m2", accepted=False, reason="bad")
    p2 = json.loads(e2["payload"].decode("utf-8"))
    assert p2["ack_for_message_id"] == "m2" and p2["ack_stage"] == C.REJECTED

