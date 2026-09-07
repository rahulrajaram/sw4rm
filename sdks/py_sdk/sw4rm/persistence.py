from __future__ import annotations

import json
import os
import base64
from abc import ABC, abstractmethod
from dataclasses import dataclass, asdict, field
from pathlib import Path
from typing import Dict, List, Optional, Any, Protocol

from sw4rm.exceptions import SW4RMError


class ActivityBufferLoadError(SW4RMError):
    """Raised when activity-buffer persistence exists but cannot be loaded.

    A corrupted persistence file previously failed silently and reset the
    buffer to empty, erasing the recovery story. Callers now decide the
    policy (fail closed by default, or catch and degrade explicitly).
    """


_BYTE_FIELDS = ("payload", "audit_proof")
_BYTE_FIELDS_MARKER = "_bytes_fields"


def _encode_envelope(envelope: Any) -> Any:
    """Encode the byte fields in an envelope for JSON storage.

    The marker is deliberately part of the snapshot representation so an
    ordinary string payload remains a string when loaded.  ``payload`` and
    ``audit_proof`` are the protocol's canonical byte fields; other envelope
    values are left untouched.
    """
    if not isinstance(envelope, dict):
        return envelope

    encoded = envelope.copy()
    byte_fields = []
    for field_name in _BYTE_FIELDS:
        value = encoded.get(field_name)
        if isinstance(value, bytes):
            encoded[field_name] = base64.b64encode(value).decode("ascii")
            byte_fields.append(field_name)
    if byte_fields:
        encoded[_BYTE_FIELDS_MARKER] = byte_fields
    return encoded


def _decode_envelope(envelope: Any) -> Any:
    """Decode current and legacy base64 envelope byte fields.

    Older JSON snapshots used ``_payload_is_b64``.  Accept that marker while
    writing the shared ``_bytes_fields`` representation for both JSON and
    SQLite.  Invalid marked data is corruption and must fail loudly.
    """
    if not isinstance(envelope, dict):
        raise ValueError("envelope must be an object")

    decoded = envelope.copy()
    marked = decoded.pop(_BYTE_FIELDS_MARKER, [])
    if not isinstance(marked, list) or any(
        not isinstance(field_name, str) or field_name not in _BYTE_FIELDS
        for field_name in marked
    ):
        raise ValueError("invalid envelope byte-field marker")

    marked = list(marked)
    for field_name in _BYTE_FIELDS:
        legacy_marker = decoded.pop(f"_{field_name}_is_b64", False)
        if not isinstance(legacy_marker, bool):
            raise ValueError("invalid legacy byte-field marker")
        if legacy_marker:
            marked.append(field_name)

    for field_name in dict.fromkeys(marked):
        value = decoded.get(field_name)
        if not isinstance(value, str):
            raise ValueError(f"encoded envelope field {field_name!r} must be a string")
        try:
            decoded[field_name] = base64.b64decode(value, validate=True)
        except (ValueError, TypeError) as exc:
            raise ValueError(f"invalid base64 in envelope field {field_name!r}") from exc
    return decoded


def _validated_snapshot(data: Any) -> tuple[Dict[str, Dict[str, Any]], List[str]]:
    """Validate and decode an activity-buffer snapshot without dropping data."""
    if not isinstance(data, dict):
        raise ValueError("snapshot must be an object")
    if "records" not in data or "order" not in data:
        raise ValueError("snapshot requires records and order")

    records = data["records"]
    order = data["order"]
    if not isinstance(records, dict):
        raise ValueError("snapshot records must be an object")
    if not isinstance(order, list) or any(not isinstance(mid, str) for mid in order):
        raise ValueError("snapshot order must be a list of message IDs")
    if len(order) != len(set(order)):
        raise ValueError("snapshot order contains duplicate message IDs")

    decoded_records: Dict[str, Dict[str, Any]] = {}
    for message_id, record in records.items():
        if not isinstance(message_id, str) or not isinstance(record, dict):
            raise ValueError("snapshot records must map string IDs to objects")
        required = {"message_id", "direction", "envelope"}
        if not required.issubset(record):
            raise ValueError(f"record {message_id!r} is missing required fields")
        if record["message_id"] != message_id:
            raise ValueError(f"record key {message_id!r} does not match message_id")
        decoded = record.copy()
        decoded["envelope"] = _decode_envelope(decoded["envelope"])
        decoded_records[message_id] = decoded

    if set(order) != set(decoded_records):
        raise ValueError("snapshot order and records contain different message IDs")
    return decoded_records, order


class PersistenceBackend(Protocol):
    """Interface for activity buffer persistence backends."""

    def save_records(self, records: Dict[str, Dict[str, Any]], order: List[str]) -> None:
        """Save activity records and their ordering."""
        ...

    def load_records(self) -> tuple[Dict[str, Dict[str, Any]], List[str]]:
        """Load activity records and their ordering. Returns (records, order)."""
        ...

    def clear(self) -> None:
        """Clear all stored data."""
        ...


class JSONFilePersistence:
    """JSON file-based persistence for activity buffer."""

    def __init__(self, file_path: str = "sw4rm_activity.json"):
        self.file_path = Path(file_path)

    def save_records(self, records: Dict[str, Dict[str, Any]], order: List[str]) -> None:
        """Save records to JSON file with fsync-durable atomic write."""
        serializable_records = {
            message_id: {**record, "envelope": _encode_envelope(record["envelope"])}
            for message_id, record in records.items()
        }
        
        data = {
            "records": serializable_records,
            "order": order,
            "version": "1.0"
        }
        _validated_snapshot(data)
        
        # Durable atomic write: write temp -> fsync file -> rename -> fsync dir.
        temp_path = self.file_path.with_suffix('.tmp')
        try:
            with open(temp_path, 'w') as f:
                json.dump(data, f, indent=2)
                f.flush()
                os.fsync(f.fileno())
            temp_path.rename(self.file_path)
            # fsync the directory so the rename itself survives a crash.
            dir_fd = os.open(str(self.file_path.parent), os.O_RDONLY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except Exception:
            if temp_path.exists():
                temp_path.unlink()
            raise

    def load_records(self) -> tuple[Dict[str, Dict[str, Any]], List[str]]:
        """Load records from JSON file.

        Returns ({}, []) when the file does not exist (fresh start).
        Raises ActivityBufferLoadError on corruption — callers decide the
        failure policy; silent reset hides data loss.
        """
        if not self.file_path.exists():
            return {}, []

        try:
            with open(self.file_path) as f:
                data = json.load(f)
            
            return _validated_snapshot(data)
        except (ValueError, TypeError, KeyError, OSError) as e:
            raise ActivityBufferLoadError(
                f"Activity buffer persistence file is corrupted: {self.file_path}: {e}"
            ) from e

    def clear(self) -> None:
        """Remove the persistence file."""
        if self.file_path.exists():
            self.file_path.unlink()


# SQLitePersistence below is fully implemented (WAL, synchronous=FULL) but not yet
# wired as the default backend; JSONFilePersistence remains the default.


@dataclass
class PersistentActivityRecord:
    """Serializable activity record."""
    message_id: str
    direction: str
    envelope: Dict[str, Any]
    ts_ms: int = field(default_factory=lambda: int(__import__('time').time() * 1000))
    ack_stage: int = 0
    error_code: int = 0
    ack_note: str = ""

    def ack(self, stage: int, error_code: int = 0, note: str = "") -> None:
        """Update ACK information."""
        self.ack_stage = stage
        self.error_code = error_code
        self.ack_note = note

    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> PersistentActivityRecord:
        """Create from dictionary."""
        return cls(**data)
class SQLitePersistence:
    """SQLite-backed persistence for activity buffer.

    Stores one row per activity record, preserving insertion order via an
    auto-increment sequence. This implementation snapshots the full dataset
    on save (delete + bulk insert), which is acceptable for low write rates.

    Schema:
      activity_records(
        seq INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT UNIQUE NOT NULL,
        ts_ms INTEGER NOT NULL,
        direction TEXT NOT NULL,
        envelope_json TEXT NOT NULL,
        ack_stage INTEGER NOT NULL,
        error_code INTEGER NOT NULL,
        ack_note TEXT NOT NULL
      )
    """

    def __init__(self, db_path: str = "sw4rm_activity.sqlite3") -> None:
        self.db_path = db_path
        self._ensure_db()

    def _connect(self):
        import sqlite3  # Local import to avoid hard dependency where unavailable
        con = sqlite3.connect(self.db_path)
        # Safer defaults for durability and responsiveness in low-throughput use
        con.execute("PRAGMA journal_mode=WAL;")
        con.execute("PRAGMA synchronous=FULL;")
        con.execute("PRAGMA foreign_keys=ON;")
        con.execute("PRAGMA busy_timeout=5000;")
        return con

    def _ensure_db(self) -> None:
        con = self._connect()
        try:
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS activity_records (
                  seq INTEGER PRIMARY KEY AUTOINCREMENT,
                  message_id TEXT UNIQUE NOT NULL,
                  ts_ms INTEGER NOT NULL,
                  direction TEXT NOT NULL,
                  envelope_json TEXT NOT NULL,
                  ack_stage INTEGER NOT NULL,
                  error_code INTEGER NOT NULL,
                  ack_note TEXT NOT NULL
                );
                """
            )
            con.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_activity_message_id ON activity_records(message_id);"
            )
            con.commit()
        finally:
            con.close()

    def save_records(self, records: Dict[str, Dict[str, Any]], order: List[str]) -> None:
        """Persist the provided snapshot using a simple replace-all approach.

        For low write rates this favors simplicity and correctness. Order is
        preserved by inserting rows following the provided order list.
        """
        encoded_records = {
            message_id: {**record, "envelope": _encode_envelope(record["envelope"])}
            for message_id, record in records.items()
        }
        _validated_snapshot({"records": encoded_records, "order": order})
        con = self._connect()
        try:
            cur = con.cursor()
            cur.execute("BEGIN IMMEDIATE;")
            cur.execute("DELETE FROM activity_records;")

            for mid in order:
                rec = encoded_records[mid]
                cur.execute(
                    """
                    INSERT INTO activity_records (
                        message_id, ts_ms, direction, envelope_json,
                        ack_stage, error_code, ack_note
                    ) VALUES (?, ?, ?, ?, ?, ?, ?);
                    """,
                    (
                        str(rec.get("message_id", mid)),
                        int(rec.get("ts_ms", 0)),
                        str(rec.get("direction", "")),
                        json.dumps(rec.get("envelope", {})),
                        int(rec.get("ack_stage", 0)),
                        int(rec.get("error_code", 0)),
                        str(rec.get("ack_note", "")),
                    ),
                )
            con.commit()
        finally:
            con.close()

    def load_records(self) -> tuple[Dict[str, Dict[str, Any]], List[str]]:
        """Load records ordered by insertion sequence."""
        con = self._connect()
        try:
            cur = con.cursor()
            cur.execute(
                "SELECT message_id, ts_ms, direction, envelope_json, ack_stage, error_code, ack_note\n                 FROM activity_records ORDER BY seq ASC;"
            )
            rows = cur.fetchall()
        finally:
            con.close()

        records: Dict[str, Dict[str, Any]] = {}
        order: List[str] = []
        for (mid, ts_ms, direction, envelope_json, ack_stage, error_code, ack_note) in rows:
            try:
                envelope = _decode_envelope(json.loads(envelope_json))
            except (ValueError, TypeError) as exc:
                raise ActivityBufferLoadError(
                    f"Activity buffer SQLite record {mid!r} is corrupted: {exc}"
                ) from exc
            data = {
                "message_id": mid,
                "ts_ms": int(ts_ms),
                "direction": direction,
                "envelope": envelope,
                "ack_stage": int(ack_stage),
                "error_code": int(error_code),
                "ack_note": ack_note,
            }
            records[mid] = data
            order.append(mid)
        return records, order

    def clear(self) -> None:
        con = self._connect()
        try:
            con.execute("DELETE FROM activity_records;")
            con.commit()
        finally:
            con.close()
