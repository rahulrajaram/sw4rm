"""A2A-to-SW4RM adapter — maps A2A operations to SW4RM service calls.

This module implements the core translation between A2A protocol
concepts (Tasks, Messages, Parts) and SW4RM concepts (Envelopes,
Scheduler Tasks, Registry Agents).

Mapping:
    A2A SendMessage   → SW4RM Router.SendMessage + Scheduler.SubmitTask
    A2A GetTask        → SW4RM Scheduler.PollActivityBuffer (task state)
    A2A CancelTask     → SW4RM Scheduler.RequestPreemption
    A2A SubscribeToTask → SW4RM Router.StreamIncoming (filtered)
    A2A GetAgentCard   → SW4RM Registry agent descriptors → AgentCard
"""

import json
import sqlite3
import time
import uuid
from pathlib import Path
from typing import Any

from a2a_gateway.agent_card import agent_descriptor_to_card, make_gateway_card


# --- A2A TaskState enum (string form) ---

class TaskState:
    SUBMITTED = "submitted"
    WORKING = "working"
    INPUT_REQUIRED = "input_required"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELED = "canceled"


# --- Task Store (in-memory for MVP) ---

class TaskStore:
    """In-memory store mapping A2A task IDs to SW4RM state."""

    def __init__(self):
        self._tasks: dict[str, dict[str, Any]] = {}

    def create_task(
        self,
        target_agent_id: str,
        message: dict[str, Any],
        context_id: str | None = None,
    ) -> dict[str, Any]:
        """Create a new A2A task backed by SW4RM operations."""
        task_id = str(uuid.uuid4())
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

        task = {
            "id": task_id,
            "context_id": context_id or str(uuid.uuid4()),
            "target_agent_id": target_agent_id,
            "status": {
                "state": TaskState.SUBMITTED,
                "timestamp": now,
                "message": None,
            },
            "artifacts": [],
            "history": [message],
            "metadata": {
                "sw4rm.target_agent": target_agent_id,
                "sw4rm.created_at": now,
            },
        }
        self._tasks[task_id] = task
        return task

    def get_task(self, task_id: str) -> dict[str, Any] | None:
        return self._tasks.get(task_id)

    def update_state(
        self,
        task_id: str,
        state: str,
        message: dict[str, Any] | None = None,
    ) -> dict[str, Any] | None:
        task = self._tasks.get(task_id)
        if task is None:
            return None
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        task["status"] = {
            "state": state,
            "timestamp": now,
            "message": message,
        }
        return task

    def add_artifact(
        self,
        task_id: str,
        artifact: dict[str, Any],
    ) -> dict[str, Any] | None:
        task = self._tasks.get(task_id)
        if task is None:
            return None
        task["artifacts"].append(artifact)
        return task

    def list_tasks(
        self,
        context_id: str | None = None,
        limit: int = 50,
    ) -> list[dict[str, Any]]:
        tasks = list(self._tasks.values())
        if context_id:
            tasks = [t for t in tasks if t["context_id"] == context_id]
        return tasks[:limit]


# --- SQLite Task Store ---

def _loads_json(value: str | None) -> Any:
    if not value:
        return None
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return None


def _dumps_json(value: Any) -> str:
    return json.dumps(value, sort_keys=True)


class SqliteTaskStore:
    """SQLite-backed store mapping A2A task IDs to SW4RM state.

    Drop-in replacement for TaskStore with persistence across restarts.
    Uses WAL mode and busy_timeout for concurrent access.
    """

    def __init__(self, db_path: str = "a2a_tasks.db"):
        self._path = Path(db_path)
        self._path.parent.mkdir(parents=True, exist_ok=True)
        con = self._connect()
        try:
            con.execute(
                """
                CREATE TABLE IF NOT EXISTS tasks (
                    id TEXT PRIMARY KEY,
                    context_id TEXT NOT NULL,
                    target_agent_id TEXT NOT NULL,
                    status_state TEXT NOT NULL,
                    status_timestamp TEXT NOT NULL,
                    status_message_json TEXT,
                    artifacts_json TEXT NOT NULL DEFAULT '[]',
                    history_json TEXT NOT NULL DEFAULT '[]',
                    metadata_json TEXT NOT NULL DEFAULT '{}'
                )
                """
            )
            con.commit()
        finally:
            con.close()

    def _connect(self) -> sqlite3.Connection:
        con = sqlite3.connect(str(self._path))
        con.execute("PRAGMA journal_mode=WAL;")
        con.execute("PRAGMA synchronous=NORMAL;")
        con.execute("PRAGMA busy_timeout=5000;")
        return con

    def _row_to_task(self, row: tuple) -> dict[str, Any]:
        (
            task_id, context_id, target_agent_id,
            status_state, status_timestamp, status_message_json,
            artifacts_json, history_json, metadata_json,
        ) = row
        return {
            "id": task_id,
            "context_id": context_id,
            "target_agent_id": target_agent_id,
            "status": {
                "state": status_state,
                "timestamp": status_timestamp,
                "message": _loads_json(status_message_json),
            },
            "artifacts": json.loads(artifacts_json) if artifacts_json else [],
            "history": json.loads(history_json) if history_json else [],
            "metadata": json.loads(metadata_json) if metadata_json else {},
        }

    def create_task(
        self,
        target_agent_id: str,
        message: dict[str, Any],
        context_id: str | None = None,
    ) -> dict[str, Any]:
        task_id = str(uuid.uuid4())
        ctx = context_id or str(uuid.uuid4())
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        metadata = {
            "sw4rm.target_agent": target_agent_id,
            "sw4rm.created_at": now,
        }

        con = self._connect()
        try:
            con.execute(
                """
                INSERT INTO tasks (
                    id, context_id, target_agent_id,
                    status_state, status_timestamp, status_message_json,
                    artifacts_json, history_json, metadata_json
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    task_id, ctx, target_agent_id,
                    TaskState.SUBMITTED, now, None,
                    _dumps_json([]), _dumps_json([message]),
                    _dumps_json(metadata),
                ),
            )
            con.commit()
        finally:
            con.close()

        return {
            "id": task_id,
            "context_id": ctx,
            "target_agent_id": target_agent_id,
            "status": {"state": TaskState.SUBMITTED, "timestamp": now, "message": None},
            "artifacts": [],
            "history": [message],
            "metadata": metadata,
        }

    def get_task(self, task_id: str) -> dict[str, Any] | None:
        con = self._connect()
        try:
            row = con.execute(
                "SELECT id, context_id, target_agent_id, status_state, status_timestamp, "
                "status_message_json, artifacts_json, history_json, metadata_json "
                "FROM tasks WHERE id = ?",
                (task_id,),
            ).fetchone()
            if row is None:
                return None
            return self._row_to_task(row)
        finally:
            con.close()

    def update_state(
        self,
        task_id: str,
        state: str,
        message: dict[str, Any] | None = None,
    ) -> dict[str, Any] | None:
        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        msg_json = _dumps_json(message) if message else None
        con = self._connect()
        try:
            cur = con.execute(
                "UPDATE tasks SET status_state = ?, status_timestamp = ?, "
                "status_message_json = ? WHERE id = ?",
                (state, now, msg_json, task_id),
            )
            con.commit()
            if cur.rowcount == 0:
                return None
        finally:
            con.close()
        return self.get_task(task_id)

    def add_artifact(
        self,
        task_id: str,
        artifact: dict[str, Any],
    ) -> dict[str, Any] | None:
        con = self._connect()
        try:
            row = con.execute(
                "SELECT artifacts_json FROM tasks WHERE id = ?", (task_id,),
            ).fetchone()
            if row is None:
                return None
            artifacts = json.loads(row[0]) if row[0] else []
            artifacts.append(artifact)
            con.execute(
                "UPDATE tasks SET artifacts_json = ? WHERE id = ?",
                (_dumps_json(artifacts), task_id),
            )
            con.commit()
        finally:
            con.close()
        return self.get_task(task_id)

    def list_tasks(
        self,
        context_id: str | None = None,
        limit: int = 50,
    ) -> list[dict[str, Any]]:
        con = self._connect()
        try:
            if context_id:
                rows = con.execute(
                    "SELECT id, context_id, target_agent_id, status_state, status_timestamp, "
                    "status_message_json, artifacts_json, history_json, metadata_json "
                    "FROM tasks WHERE context_id = ? LIMIT ?",
                    (context_id, limit),
                ).fetchall()
            else:
                rows = con.execute(
                    "SELECT id, context_id, target_agent_id, status_state, status_timestamp, "
                    "status_message_json, artifacts_json, history_json, metadata_json "
                    "FROM tasks LIMIT ?",
                    (limit,),
                ).fetchall()
            return [self._row_to_task(r) for r in rows]
        finally:
            con.close()


# --- Message <-> Envelope Translation ---

def a2a_message_to_sw4rm_envelope(
    message: dict[str, Any],
    target_agent_id: str,
    task_id: str,
) -> dict[str, Any]:
    """Convert an A2A Message to a SW4RM Envelope dict.

    A2A Messages contain Parts (text, file, data). We serialize
    the parts list as JSON in the envelope payload.

    Args:
        message: A2A Message dict with role, parts, etc.
        target_agent_id: The SW4RM agent_id to route to.
        task_id: The A2A task ID for correlation.

    Returns:
        SW4RM Envelope dict ready for RouterClient.send_message().
    """
    # Extract sender from metadata or default to "a2a-client"
    sender = message.get("metadata", {}).get("sw4rm.sender", "a2a-gateway")

    # Serialize parts as JSON payload
    parts = message.get("parts", [])
    payload_dict = {
        "a2a_task_id": task_id,
        "role": message.get("role", "user"),
        "parts": parts,
        "message_id": message.get("message_id", str(uuid.uuid4())),
    }
    payload_bytes = json.dumps(payload_dict).encode("utf-8")

    return {
        "producer_id": sender,
        "consumer_id": target_agent_id,
        "message_type": 2,  # DATA
        "content_type": "application/json",
        "correlation_id": task_id,
        "payload": payload_bytes,
    }


def sw4rm_envelope_to_a2a_message(
    envelope: dict[str, Any],
) -> dict[str, Any]:
    """Convert a SW4RM Envelope dict to an A2A Message dict.

    Args:
        envelope: SW4RM Envelope dict from StreamIncoming.

    Returns:
        A2A Message dict.
    """
    payload = envelope.get("payload", b"")

    # Try to parse as JSON (our format)
    parts = []
    try:
        if isinstance(payload, bytes):
            payload_str = payload.decode("utf-8")
        else:
            payload_str = str(payload)
        payload_dict = json.loads(payload_str)
        parts = payload_dict.get("parts", [])
        if not parts:
            # Wrap raw payload as text part
            parts = [{"text": {"text": payload_str}}]
    except (json.JSONDecodeError, UnicodeDecodeError):
        # Binary payload — wrap as file part
        parts = [{"file": {"bytes": payload, "mime_type": "application/octet-stream"}}]

    return {
        "role": "agent",
        "parts": parts,
        "message_id": envelope.get("message_id", str(uuid.uuid4())),
        "task_id": envelope.get("correlation_id"),
        "metadata": {
            "sw4rm.producer_id": envelope.get("producer_id", ""),
            "sw4rm.message_type": str(envelope.get("message_type", 0)),
        },
    }


# --- SW4RM AgentState → A2A TaskState ---

# Maps SW4RM AgentState enum values to A2A TaskState
_AGENT_STATE_TO_TASK_STATE = {
    0: TaskState.SUBMITTED,    # UNSPECIFIED
    1: TaskState.SUBMITTED,    # INITIALIZING
    2: TaskState.WORKING,      # RUNNABLE
    3: TaskState.WORKING,      # SCHEDULED
    4: TaskState.WORKING,      # RUNNING
    5: TaskState.INPUT_REQUIRED,  # WAITING
    6: TaskState.INPUT_REQUIRED,  # WAITING_RESOURCES
    7: TaskState.WORKING,      # SUSPENDED
    8: TaskState.WORKING,      # RESUMED
    9: TaskState.COMPLETED,    # COMPLETED
    10: TaskState.FAILED,      # FAILED_STATE
    11: TaskState.CANCELED,    # SHUTTING_DOWN
    12: TaskState.WORKING,     # RECOVERING
}


def sw4rm_agent_state_to_a2a_task_state(agent_state: int) -> str:
    """Map a SW4RM AgentState enum value to an A2A TaskState string."""
    return _AGENT_STATE_TO_TASK_STATE.get(agent_state, TaskState.WORKING)


# --- Adapter Class ---

class A2AToSW4RMAdapter:
    """Stateful adapter bridging A2A protocol to SW4RM services.

    This adapter holds references to SW4RM clients (Registry, Router,
    Scheduler) and translates A2A operations into SW4RM calls.

    Usage:
        adapter = A2AToSW4RMAdapter(registry, router, scheduler)
        task = adapter.send_message(a2a_message, target_agent="my-agent")
        status = adapter.get_task(task["id"])
    """

    def __init__(
        self,
        registry_client=None,
        router_client=None,
        scheduler_client=None,
        gateway_url: str = "http://localhost:50054",
        task_store=None,
    ):
        self.registry = registry_client
        self.router = router_client
        self.scheduler = scheduler_client
        self.gateway_url = gateway_url
        self.task_store = task_store or TaskStore()

    def get_agent_card(
        self,
        agent_id: str | None = None,
    ) -> dict[str, Any]:
        """Get A2A Agent Card for a specific agent or the gateway.

        If agent_id is provided, returns a card for that specific
        SW4RM agent. Otherwise returns the gateway's own card.
        """
        if agent_id is None:
            # Return gateway card (optionally with registered agents)
            return make_gateway_card(
                gateway_url=self.gateway_url,
            )

        # Build card from SW4RM agent descriptor
        # In a real implementation, this would query the Registry
        descriptor = {
            "agent_id": agent_id,
            "name": agent_id,
            "capabilities": [],
        }
        return agent_descriptor_to_card(descriptor, self.gateway_url)

    def send_message(
        self,
        message: dict[str, Any],
        target_agent_id: str,
        context_id: str | None = None,
    ) -> dict[str, Any]:
        """Handle A2A SendMessage — create task + route to SW4RM agent.

        1. Creates an A2A Task in the task store
        2. Converts the A2A Message to a SW4RM Envelope
        3. Sends via SW4RM Router
        4. Optionally submits as a Scheduler task

        Args:
            message: A2A Message dict.
            target_agent_id: SW4RM agent to route to.
            context_id: Optional context for grouping related tasks.

        Returns:
            A2A Task dict with status SUBMITTED or WORKING.
        """
        # Create task
        task = self.task_store.create_task(
            target_agent_id=target_agent_id,
            message=message,
            context_id=context_id,
        )
        task_id = task["id"]

        # Convert to SW4RM envelope and send
        envelope = a2a_message_to_sw4rm_envelope(
            message=message,
            target_agent_id=target_agent_id,
            task_id=task_id,
        )

        try:
            if self.router:
                self.router.send_message(envelope)
            # Update task state to WORKING
            self.task_store.update_state(task_id, TaskState.WORKING)
        except Exception as e:
            # Update task state to FAILED
            error_message = {
                "role": "agent",
                "parts": [{"text": {"text": f"Routing failed: {e}"}}],
            }
            self.task_store.update_state(
                task_id, TaskState.FAILED, message=error_message,
            )

        # Optionally submit to scheduler for priority tracking
        if self.scheduler:
            try:
                self.scheduler.submit_task(
                    agent_id=target_agent_id,
                    task_id=task_id,
                    priority=0,
                    params=envelope.get("payload", b""),
                    content_type="application/json",
                )
            except Exception:
                pass  # Scheduler integration is best-effort

        return self.task_store.get_task(task_id)

    def get_task(self, task_id: str) -> dict[str, Any] | None:
        """Handle A2A GetTask — return current task state."""
        return self.task_store.get_task(task_id)

    def cancel_task(self, task_id: str) -> dict[str, Any] | None:
        """Handle A2A CancelTask — preempt via SW4RM Scheduler."""
        task = self.task_store.get_task(task_id)
        if task is None:
            return None

        target = task.get("metadata", {}).get("sw4rm.target_agent")

        if self.scheduler and target:
            try:
                self.scheduler.request_preemption(
                    agent_id=target,
                    task_id=task_id,
                    reason="A2A CancelTask request",
                )
            except Exception:
                pass  # Best-effort

        self.task_store.update_state(task_id, TaskState.CANCELED)
        return self.task_store.get_task(task_id)
