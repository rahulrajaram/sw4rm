from __future__ import annotations

import json
import os
import base64
from abc import ABC, abstractmethod
from dataclasses import dataclass, asdict, field
from pathlib import Path
from typing import Dict, List, Optional, Any, Protocol


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
        """Save records to JSON file."""
        # Convert bytes to base64 for JSON serialization
        serializable_records = {}
        for msg_id, record in records.items():
            serializable_record = record.copy()
            # Handle bytes payload in envelope
            if 'envelope' in serializable_record and isinstance(serializable_record['envelope'], dict):
                envelope = serializable_record['envelope'].copy()
                if 'payload' in envelope and isinstance(envelope['payload'], bytes):
                    envelope['payload'] = base64.b64encode(envelope['payload']).decode('utf-8')
                    envelope['_payload_is_b64'] = True
                serializable_record['envelope'] = envelope
            serializable_records[msg_id] = serializable_record
        
        data = {
            "records": serializable_records,
            "order": order,
            "version": "1.0"
        }
        
        # Atomic write: write to temp file, then rename
        temp_path = self.file_path.with_suffix('.tmp')
        try:
            with open(temp_path, 'w') as f:
                json.dump(data, f, indent=2)
            temp_path.rename(self.file_path)
        except Exception:
            if temp_path.exists():
                temp_path.unlink()
            raise

    def load_records(self) -> tuple[Dict[str, Dict[str, Any]], List[str]]:
        """Load records from JSON file."""
        if not self.file_path.exists():
            return {}, []

        try:
            with open(self.file_path) as f:
                data = json.load(f)
            
            records = data.get("records", {})
            order = data.get("order", [])
            
            # Convert base64 back to bytes for payload
            for msg_id, record in records.items():
                if 'envelope' in record and isinstance(record['envelope'], dict):
                    envelope = record['envelope']
                    if envelope.get('_payload_is_b64') and 'payload' in envelope:
                        envelope['payload'] = base64.b64decode(envelope['payload'])
                        del envelope['_payload_is_b64']
            
            # Validate data consistency
            valid_order = [mid for mid in order if mid in records]
            
            return records, valid_order
        except (json.JSONDecodeError, KeyError, OSError):
            # If file is corrupted, start fresh
            return {}, []

    def clear(self) -> None:
        """Remove the persistence file."""
        if self.file_path.exists():
            self.file_path.unlink()


# SQLite persistence would go here, but sqlite3 is not available in this environment


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
        con = self._connect()
        try:
            cur = con.cursor()
            cur.execute("BEGIN IMMEDIATE;")
            cur.execute("DELETE FROM activity_records;")

            for mid in order:
                rec = records.get(mid)
                if not rec:
                    continue
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
                envelope = json.loads(envelope_json) if envelope_json else {}
            except Exception:
                envelope = {}
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
