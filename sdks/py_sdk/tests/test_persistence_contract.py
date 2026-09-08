"""Persistence must retain ordinary wire payloads and reject damaged snapshots."""

import json
import sqlite3

import pytest

from sw4rm.persistence import ActivityBufferLoadError, JSONFilePersistence, SQLitePersistence
from sw4rm.activity_buffer import PersistentActivityBuffer


def record(message_id="m1", **envelope):
    return dict(message_id=message_id, direction="in", envelope=envelope, ts_ms=1,
                ack_stage=0, error_code=0, ack_note="")


@pytest.fixture(params=[JSONFilePersistence, SQLitePersistence])
def backend(request, tmp_path):
    return request.param(str(tmp_path / "state"))


def test_snapshot_roundtrip_preserves_order_and_bytes_without_mutation(backend):
    records = {
        "m1": record(payload=bytes(range(256)), audit_proof=b"\x00\xff"),
        "m2": record("m2", payload="ordinary string"),
    }
    backend.save_records(records, ["m2", "m1"])
    assert backend.load_records() == (records, ["m2", "m1"])
    assert isinstance(records["m1"]["envelope"]["payload"], bytes)
    assert "_bytes_fields" not in records["m1"]["envelope"]


def test_failed_save_retains_previous_snapshot(backend):
    previous = {"m1": record(payload=b"confirmed")}
    backend.save_records(previous, ["m1"])
    with pytest.raises(TypeError):
        backend.save_records({"m2": record("m2", unsupported=object())}, ["m2"])
    assert backend.load_records() == (previous, ["m1"])


@pytest.mark.parametrize("direction", ["incoming", "outgoing"])
def test_repeated_message_and_full_buffer_remain_restorable(backend, direction):
    buffer = PersistentActivityBuffer(persistence=backend, max_items=1)
    write = getattr(buffer, f"record_{direction}")
    write({"message_id": "m1", "payload": b"first"})
    write({"message_id": "m1", "payload": b"retry"})
    buffer.flush()
    restarted = PersistentActivityBuffer(persistence=backend, max_items=1)
    assert [r.message_id for r in restarted.recent()] == ["m1"]
    assert restarted.get("m1").envelope["payload"] == b"retry"


@pytest.mark.parametrize("snapshot", [
    {}, [], {"records": {}}, {"records": {}, "order": ["lost"]},
    {"records": {"m1": record()}, "order": []},
    {"records": {"m1": record()}, "order": ["m1", "m1"]},
    {"records": {"m1": record("wrong")}, "order": ["m1"]},
    {"records": {"m1": record(payload="!invalid!", _bytes_fields=["payload"])}, "order": ["m1"]},
    {"records": {"m1": record(payload="!invalid!", _payload_is_b64=True)}, "order": ["m1"]},
    {"records": {"m1": record(_bytes_fields=None)}, "order": ["m1"]},
])
def test_malformed_json_snapshot_is_a_load_error(tmp_path, snapshot):
    path = tmp_path / "state.json"
    path.write_text(json.dumps(snapshot))
    with pytest.raises(ActivityBufferLoadError):
        JSONFilePersistence(str(path)).load_records()


def test_legacy_payload_marker_remains_readable(tmp_path):
    path = tmp_path / "state.json"
    path.write_text(json.dumps({"records": {"m1": record(payload="aGk=", _payload_is_b64=True)}, "order": ["m1"]}))
    records, order = JSONFilePersistence(str(path)).load_records()
    assert records["m1"]["envelope"] == {"payload": b"hi"}
    assert order == ["m1"]


def test_corrupt_sqlite_envelope_is_not_replaced_with_empty(tmp_path):
    path = tmp_path / "state.sqlite"
    backend = SQLitePersistence(str(path))
    backend.save_records({"m1": record(payload=b"hi")}, ["m1"])
    with sqlite3.connect(path) as connection:
        connection.execute("UPDATE activity_records SET envelope_json = ?", ("{broken",))
    with pytest.raises(ActivityBufferLoadError):
        backend.load_records()
