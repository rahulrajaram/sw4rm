from sw4rm.persistence import JSONFilePersistence


def test_json_persistence_roundtrip_bytes(tmp_path):
    p = JSONFilePersistence(str(tmp_path / "state.json"))
    records = {
        "m1": {"message_id": "m1", "direction": "out", "envelope": {"payload": b"hi"}, "ts_ms": 1, "ack_stage": 0, "error_code": 0, "ack_note": ""}
    }
    order = ["m1"]
    p.save_records(records, order)
    loaded_records, loaded_order = p.load_records()
    assert loaded_order == ["m1"]
    assert loaded_records["m1"]["envelope"]["payload"] == b"hi"

