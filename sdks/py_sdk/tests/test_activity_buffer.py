import os
import tempfile
from sw4rm.activity_buffer import ActivityBuffer, PersistentActivityBuffer
from sw4rm.persistence import JSONFilePersistence
from sw4rm import constants as C


def _env(message_id: str) -> dict:
    return {
        "message_id": message_id,
        "producer_id": "p",
        "correlation_id": "c",
        "sequence_number": 1,
        "retry_count": 0,
        "message_type": C.DATA,
        "content_type": "application/json",
        "content_length": 0,
        "repo_id": "",
        "worktree_id": "",
        "hlc_timestamp": "0",
        "ttl_ms": 0,
        "payload": b"",
    }


def test_activity_buffer_basic_flow():
    buf = ActivityBuffer(max_items=2)
    e1 = _env("m1")
    e2 = _env("m2")
    e3 = _env("m3")
    buf.record_outgoing(e1)
    buf.record_incoming(e2)
    # Trigger pruning by exceeding capacity
    buf.record_outgoing(e3)
    # Verify FIFO eviction of m1 by checking presence in internal index
    assert "m1" not in buf._by_id and "m2" in buf._by_id and "m3" in buf._by_id

    # Ack m2
    ack = {"ack_for_message_id": "m2", "ack_stage": C.RECEIVED, "error_code": 0}
    rec = buf.ack(ack)
    assert rec is not None and rec.ack_stage == C.RECEIVED


def test_persistent_activity_buffer_roundtrip(tmp_path):
    path = tmp_path / "abuf.json"
    p = JSONFilePersistence(str(path))
    pab = PersistentActivityBuffer(max_items=3, persistence=p)
    e1 = _env("mx1")
    pab.record_outgoing(e1)
    pab.flush()

    # Reload from disk
    pab2 = PersistentActivityBuffer(max_items=3, persistence=p)
    assert pab2.get("mx1") is not None
    # Ack and reconcile
    pab2.ack({"ack_for_message_id": "mx1", "ack_stage": C.RECEIVED, "error_code": 0})
    rec = pab2.get("mx1")
    assert rec and rec.ack_stage == C.RECEIVED
    unacked_out = pab2.reconcile()
    # After RECEIVED, still considered unacked for reconciliation (not yet fulfilled)
    assert any(r.message_id == "mx1" for r in unacked_out)
