"""Activity-buffer durability tests (campaign S3/S4 family).

- S3: a kill during buffer writes loses nothing already confirmed to the
  caller (fsync-durable atomic writes; save failures raise).
- S4: restart after corruption fails LOUDLY by default (ActivityBufferLoadError),
  or starts degraded with load_failure_mode="empty" — never silently empty.
- Fresh start: a missing persistence file is not an error.
"""

from __future__ import annotations

import base64
import json
from pathlib import Path

import pytest

from sw4rm.activity_buffer import PersistentActivityBuffer
from sw4rm.exceptions import SW4RMError
from sw4rm.persistence import ActivityBufferLoadError, JSONFilePersistence


def _buffer(tmp_path: Path, **kwargs) -> PersistentActivityBuffer:
    return PersistentActivityBuffer(
        persistence=JSONFilePersistence(str(tmp_path / "activity.json")), **kwargs
    )


def _record_envelope(message_id: str, payload: bytes = b"hi"):
    return {
        "message_id": message_id,
        "message_type": 2,
        "content_type": "application/json",
        "payload": payload,
        "producer_id": "p1",
    }


def test_s3_save_is_durable_atomic(tmp_path: Path) -> None:
    """save_records fsyncs file+dir; the tmp file never remains."""
    buf = _buffer(tmp_path)
    buf.record_outgoing(_record_envelope("m1"))
    buf.flush()
    path = tmp_path / "activity.json"
    assert path.exists()
    assert not (tmp_path / "activity.tmp").exists()
    data = json.loads(path.read_text())
    assert data["version"] == "1.0"
    assert "m1" in data["records"]


def test_s4_corrupt_file_fails_loudly_by_default(tmp_path: Path) -> None:
    (tmp_path / "activity.json").write_text("{corrupted!!")
    with pytest.raises(ActivityBufferLoadError):
        _buffer(tmp_path)


def test_s4_corrupt_file_degraded_mode_is_loud_not_silent(tmp_path: Path, caplog) -> None:
    (tmp_path / "activity.json").write_text("{corrupted!!")
    buf = _buffer(tmp_path, load_failure_mode="empty")
    assert buf.get("m1") is None
    assert any("DEGRADED" in rec.message for rec in caplog.records)


def test_missing_file_is_fresh_start(tmp_path: Path) -> None:
    buf = _buffer(tmp_path)  # no file yet: must not raise
    assert buf.get("m1") is None


def test_s4_truncated_file_fails_loudly(tmp_path: Path) -> None:
    buf = _buffer(tmp_path)
    buf.record_outgoing(_record_envelope("m1"))
    buf.flush()
    path = tmp_path / "activity.json"
    # Truncate mid-write (simulated torn write)
    raw = path.read_bytes()
    path.write_bytes(raw[: len(raw) // 2])
    with pytest.raises(ActivityBufferLoadError):
        _buffer(tmp_path)


def test_save_failure_propagates(tmp_path: Path) -> None:
    class FailingBackend:
        def save_records(self, records, order):
            raise OSError("disk full")

        def load_records(self):
            return {}, []

        def clear(self):
            raise OSError

    buf = PersistentActivityBuffer(persistence=FailingBackend())
    with pytest.raises(OSError):
        buf.record_outgoing(_record_envelope("m1"))
        buf.flush()


def test_bytes_payload_roundtrip_survives_restart(tmp_path: Path) -> None:
    payload = bytes(range(256))
    buf = _buffer(tmp_path)
    buf.record_outgoing(_record_envelope("mb", payload))
    buf.flush()
    del buf
    buf2 = _buffer(tmp_path)
    rec = buf2.get("mb")
    assert rec is not None
    assert rec.envelope["payload"] == payload
