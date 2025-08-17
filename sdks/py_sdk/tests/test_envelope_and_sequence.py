from sw4rm.envelope import build_envelope, SequenceTracker, make_idempotency_token
from sw4rm import constants as C


def test_build_envelope_sets_defaults_and_lengths():
    payload = b"abc"
    env = build_envelope(
        producer_id="p1",
        message_type=C.DATA,
        content_type="application/octet-stream",
        payload=payload,
    )
    assert env["producer_id"] == "p1"
    assert env["message_type"] == C.DATA
    assert env["content_length"] == len(payload)
    assert env["message_id"] and env["correlation_id"]
    assert isinstance(env["sequence_number"], int)


def test_sequence_tracker_increments():
    seq = SequenceTracker(start=10)
    assert seq.next() == 10
    assert seq.next() == 11
    assert seq.next() == 12


def test_idempotency_token_format():
    tok = make_idempotency_token("prod", "op", "hash")
    assert tok == "prod:op:hash"

