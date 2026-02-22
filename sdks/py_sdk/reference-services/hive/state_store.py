from __future__ import annotations

import json
import sqlite3
import time
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple


def _connect(path: Path) -> sqlite3.Connection:
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(str(path))
    con.execute("PRAGMA journal_mode=WAL;")
    con.execute("PRAGMA synchronous=NORMAL;")
    con.execute("PRAGMA foreign_keys=ON;")
    con.execute("PRAGMA busy_timeout=5000;")
    return con


def _loads_json(value: Optional[str]) -> dict:
    if not value:
        return {}
    try:
        payload = json.loads(value)
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def _dumps_json(value: dict) -> str:
    return json.dumps(value, sort_keys=True)


def _to_int(value: object, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _to_float(value: object, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


class RegistryStateStore:
    """Persistence helper for registry service state."""

    def __init__(self, db_path: str):
        self.path = Path(db_path)
        con = _connect(self.path)
        try:
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS registry_agents (
                    agent_id TEXT PRIMARY KEY,
                    state_json TEXT NOT NULL,
                    registered_at REAL NOT NULL,
                    last_heartbeat REAL NOT NULL
                );
                """
            )
            con.commit()
        finally:
            con.close()

    def load_agents(self) -> Dict[str, dict]:
        con = _connect(self.path)
        try:
            rows = con.execute(
                "SELECT agent_id, state_json, registered_at, last_heartbeat FROM registry_agents"
            ).fetchall()
            result: Dict[str, dict] = {}
            for agent_id, state_json, registered_at, last_heartbeat in rows:
                record = _loads_json(state_json)
                record["registered_at"] = _to_float(registered_at, 0.0)
                record["last_heartbeat"] = _to_float(last_heartbeat, 0.0)
                result[agent_id] = record
            return result
        finally:
            con.close()

    def save_agent(self, agent_id: str, state: dict, registered_at: float, last_heartbeat: float) -> None:
        con = _connect(self.path)
        try:
            con.execute(
                """
                INSERT INTO registry_agents (agent_id, state_json, registered_at, last_heartbeat)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(agent_id) DO UPDATE SET
                    state_json = excluded.state_json,
                    registered_at = excluded.registered_at,
                    last_heartbeat = excluded.last_heartbeat
                """,
                (agent_id, _dumps_json(state), registered_at, last_heartbeat),
            )
            con.commit()
        finally:
            con.close()

    def delete_agent(self, agent_id: str) -> None:
        con = _connect(self.path)
        try:
            con.execute("DELETE FROM registry_agents WHERE agent_id = ?", (agent_id,))
            con.commit()
        finally:
            con.close()


class RouterStateStore:
    """Persistence helper for router queues and message log."""

    def __init__(self, db_path: str):
        self.path = Path(db_path)
        con = _connect(self.path)
        try:
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS router_agents (
                    agent_id TEXT PRIMARY KEY,
                    created_at REAL NOT NULL
                );
                """
            )
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS router_message_log (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    message_id TEXT NOT NULL,
                    message_blob BLOB NOT NULL,
                    producer_id TEXT NOT NULL,
                    content_type TEXT NOT NULL,
                    correlation_id TEXT NOT NULL,
                    sequence_number INTEGER NOT NULL,
                    payload_size INTEGER NOT NULL,
                    created_at REAL NOT NULL
                );
                """
            )
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS router_pending_messages (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    agent_id TEXT NOT NULL,
                    message_id TEXT NOT NULL,
                    message_blob BLOB NOT NULL,
                    created_at REAL NOT NULL,
                    FOREIGN KEY(agent_id) REFERENCES router_agents(agent_id) ON DELETE CASCADE
                );
                """
            )
            con.execute("CREATE INDEX IF NOT EXISTS idx_router_pending_agent_seq ON router_pending_messages(agent_id, seq)")
            con.commit()
        finally:
            con.close()

    def ensure_agent(self, agent_id: str) -> None:
        now = time.time()
        con = _connect(self.path)
        try:
            con.execute(
                "INSERT OR IGNORE INTO router_agents(agent_id, created_at) VALUES (?, ?)",
                (agent_id, now),
            )
            con.commit()
        finally:
            con.close()

    def list_agents(self) -> List[str]:
        con = _connect(self.path)
        try:
            rows = con.execute("SELECT agent_id FROM router_agents ORDER BY created_at ASC, agent_id ASC").fetchall()
            return [row[0] for row in rows]
        finally:
            con.close()

    def load_message_log(self, limit: Optional[int] = None) -> List[dict]:
        con = _connect(self.path)
        try:
            if limit and limit > 0:
                rows = con.execute(
                    "SELECT message_id, producer_id, content_type, correlation_id, sequence_number, payload_size, message_blob, created_at FROM router_message_log ORDER BY seq DESC LIMIT ?",
                    (limit,),
                ).fetchall()
            else:
                rows = con.execute(
                    "SELECT message_id, producer_id, content_type, correlation_id, sequence_number, payload_size, message_blob, created_at FROM router_message_log ORDER BY seq DESC"
                ).fetchall()

            records: List[dict] = []
            for (
                message_id,
                producer_id,
                content_type,
                correlation_id,
                sequence_number,
                payload_size,
                message_blob,
                created_at,
            ) in rows:
                records.append(
                    {
                        "message_id": message_id,
                        "producer_id": producer_id,
                        "content_type": content_type,
                        "payload_size": _to_int(payload_size),
                        "correlation_id": correlation_id,
                        "sequence_number": _to_int(sequence_number),
                        "timestamp": _to_float(created_at),
                        "envelope_blob": bytes(message_blob or b""),
                    }
                )
            return records
        finally:
            con.close()

    def enqueue_message(self, agent_id: str, envelope_message_bytes: bytes, message_id: str) -> int:
        now = time.time()
        con = _connect(self.path)
        try:
            cur = con.cursor()
            cur.execute(
                "INSERT INTO router_pending_messages (agent_id, message_id, message_blob, created_at) VALUES (?, ?, ?, ?)",
                (agent_id, message_id, sqlite3.Binary(envelope_message_bytes), now),
            )
            con.commit()
            return int(cur.lastrowid)
        finally:
            con.close()

    def dequeue_message(self, seq: int) -> None:
        con = _connect(self.path)
        try:
            con.execute("DELETE FROM router_pending_messages WHERE seq = ?", (seq,))
            con.commit()
        finally:
            con.close()

    def load_pending_messages(self) -> Dict[str, List[Tuple[int, bytes]]]:
        con = _connect(self.path)
        try:
            rows = con.execute(
                "SELECT seq, agent_id, message_blob FROM router_pending_messages ORDER BY seq ASC"
            ).fetchall()
            pending: Dict[str, List[Tuple[int, bytes]]] = {}
            for seq, agent_id, message_blob in rows:
                if message_blob is None:
                    continue
                pending.setdefault(agent_id, []).append((int(seq), bytes(message_blob)))
            return pending
        finally:
            con.close()

    def record_message(self, envelope, envelope_payload_size: int) -> None:
        now = time.time()
        con = _connect(self.path)
        try:
            con.execute(
                """
                INSERT INTO router_message_log (
                    message_id,
                    message_blob,
                    producer_id,
                    content_type,
                    correlation_id,
                    sequence_number,
                    payload_size,
                    created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(envelope.message_id or ""),
                    sqlite3.Binary(envelope.SerializeToString()),
                    str(envelope.producer_id),
                    str(envelope.content_type),
                    str(envelope.correlation_id),
                    _to_int(envelope.sequence_number, 0),
                    envelope_payload_size,
                    now,
                ),
            )
            con.commit()
        finally:
            con.close()


class SchedulerStateStore:
    """Persistence helper for scheduler tasks and activity entries."""

    def __init__(self, db_path: str):
        self.path = Path(db_path)
        con = _connect(self.path)
        try:
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS scheduler_tasks (
                    task_id TEXT PRIMARY KEY,
                    agent_id TEXT NOT NULL,
                    priority INTEGER NOT NULL,
                    content_type TEXT NOT NULL,
                    params BLOB NOT NULL,
                    scope TEXT NOT NULL,
                    status TEXT NOT NULL,
                    submitted_at REAL NOT NULL,
                    preempt_reason TEXT NOT NULL,
                    updated_at REAL NOT NULL
                );
                """
            )
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS scheduler_activity (
                    seq INTEGER PRIMARY KEY AUTOINCREMENT,
                    agent_id TEXT NOT NULL,
                    task_id TEXT NOT NULL,
                    repo_id TEXT NOT NULL,
                    worktree_id TEXT NOT NULL,
                    branch TEXT NOT NULL,
                    description TEXT NOT NULL,
                    timestamp TEXT NOT NULL
                );
                """
            )
            con.execute("CREATE INDEX IF NOT EXISTS idx_scheduler_task_agent ON scheduler_activity(agent_id, task_id)")
            con.commit()
        finally:
            con.close()

    def load_state(self) -> Tuple[Dict[str, dict], Dict[str, List[dict]]]:
        con = _connect(self.path)
        try:
            task_rows = con.execute(
                "SELECT task_id, agent_id, priority, content_type, params, scope, status, submitted_at, preempt_reason FROM scheduler_tasks"
            ).fetchall()
            tasks: Dict[str, dict] = {}
            for row in task_rows:
                params = row[4] if row[4] is not None else b""
                tasks[str(row[0])] = {
                    "agent_id": row[1],
                    "task_id": str(row[0]),
                    "priority": _to_int(row[2]),
                    "content_type": row[3] or "",
                    "params": params,
                    "scope": row[5] or "",
                    "status": row[6] or "pending",
                    "submitted_at": _to_float(row[7]),
                    "preempt_reason": row[8] or "",
                }

            activity_rows = con.execute(
                "SELECT agent_id, task_id, repo_id, worktree_id, branch, description, timestamp FROM scheduler_activity ORDER BY seq ASC"
            ).fetchall()
            activity: Dict[str, List[dict]] = {}
            for agent_id, task_id, repo_id, worktree_id, branch, description, timestamp in activity_rows:
                activity.setdefault(agent_id, []).append(
                    {
                        "task_id": task_id,
                        "repo_id": repo_id or "",
                        "worktree_id": worktree_id or "",
                        "branch": branch or "",
                        "description": description or "",
                        "timestamp": timestamp or "",
                    }
                )

            return tasks, activity
        finally:
            con.close()

    def save_task(self, task_id: str, task: dict) -> None:
        now = time.time()
        con = _connect(self.path)
        try:
            con.execute(
                """
                INSERT INTO scheduler_tasks (
                    task_id,
                    agent_id,
                    priority,
                    content_type,
                    params,
                    scope,
                    status,
                    submitted_at,
                    preempt_reason,
                    updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(task_id) DO UPDATE SET
                    agent_id = excluded.agent_id,
                    priority = excluded.priority,
                    content_type = excluded.content_type,
                    params = excluded.params,
                    scope = excluded.scope,
                    status = excluded.status,
                    preempt_reason = excluded.preempt_reason,
                    updated_at = excluded.updated_at
                """,
                (
                    task_id,
                    task.get("agent_id", ""),
                    _to_int(task.get("priority", 0)),
                    task.get("content_type", ""),
                    sqlite3.Binary(task.get("params", b"")),
                    task.get("scope", ""),
                    task.get("status", "pending"),
                    _to_float(task.get("submitted_at", now)),
                    task.get("preempt_reason", ""),
                    now,
                ),
            )
            con.commit()
        finally:
            con.close()

    def update_task_status(self, task_id: str, status: str, preempt_reason: Optional[str] = None) -> None:
        now = time.time()
        con = _connect(self.path)
        try:
            updates = "status = ?, updated_at = ?"
            args = [status, now, task_id]
            if preempt_reason is not None:
                updates = "status = ?, preempt_reason = ?, updated_at = ?"
                args = [status, preempt_reason, now, task_id]
            con.execute(f"UPDATE scheduler_tasks SET {updates} WHERE task_id = ?", args)
            con.commit()
        finally:
            con.close()

    def append_activity(self, agent_id: str, entry: dict) -> None:
        con = _connect(self.path)
        try:
            con.execute(
                """
                INSERT INTO scheduler_activity (
                    agent_id,
                    task_id,
                    repo_id,
                    worktree_id,
                    branch,
                    description,
                    timestamp
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    agent_id,
                    entry.get("task_id", ""),
                    entry.get("repo_id", ""),
                    entry.get("worktree_id", ""),
                    entry.get("branch", ""),
                    entry.get("description", ""),
                    entry.get("timestamp", ""),
                ),
            )
            con.commit()
        finally:
            con.close()

    def clear_activity(self, agent_id: str, task_ids: Optional[Sequence[str]]) -> int:
        con = _connect(self.path)
        try:
            if not task_ids:
                purged = con.execute(
                    "SELECT COUNT(*) FROM scheduler_activity WHERE agent_id = ?",
                    (agent_id,),
                ).fetchone()[0]
                con.execute("DELETE FROM scheduler_activity WHERE agent_id = ?", (agent_id,))
                con.commit()
                return int(purged)

            placeholders = ",".join("?" for _ in task_ids)
            params = [agent_id, *task_ids]
            purged = con.execute(
                f"SELECT COUNT(*) FROM scheduler_activity WHERE agent_id = ? AND task_id IN ({placeholders})",
                params,
            ).fetchone()[0]
            con.execute(
                f"DELETE FROM scheduler_activity WHERE agent_id = ? AND task_id IN ({placeholders})",
                params,
            )
            con.commit()
            return int(purged)
        finally:
            con.close()
