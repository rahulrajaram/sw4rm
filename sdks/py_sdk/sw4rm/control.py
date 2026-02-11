"""Control message types for SW4RM scheduler orchestration.

This module provides structured data types for CONTROL-only orchestration
messages used between the scheduler and agents.  It defines two message
formats:

* ``SchedulerCommandV1`` -- issued by the scheduler to direct an agent
  through stages (prompt, plan, run).
* ``AgentReportV1`` -- sent by an agent back to the scheduler to report
  results, logs, file artifacts, and errors.

Content type constants are re-exported here for convenience; the canonical
string values also live in :pymod:`sw4rm.content_types`.

All dataclasses support round-trip JSON serialisation via ``to_bytes`` /
``from_bytes`` class methods so they can be embedded directly in envelope
payloads.
"""
from __future__ import annotations

import enum
import json
from dataclasses import dataclass
from typing import Any, Dict, List, Optional


# ---------------------------------------------------------------------------
# Content type constants (must match Rust SDK and content_types.py)
# ---------------------------------------------------------------------------

CT_SCHEDULER_COMMAND_V1: str = (
    "application/vnd.sw4rm.scheduler.command+json;v=1"
)
"""MIME content type for scheduler command messages (v1)."""

CT_AGENT_REPORT_V1: str = (
    "application/vnd.sw4rm.agent.report+json;v=1"
)
"""MIME content type for agent report messages (v1)."""


# ---------------------------------------------------------------------------
# SchedulerStage enum
# ---------------------------------------------------------------------------

class SchedulerStage(enum.Enum):
    """Stages supported by scheduler CONTROL commands.

    Each stage corresponds to a phase in the agent execution lifecycle
    driven by the scheduler:

    Attributes:
        PROMPT: Initial prompt delivery phase.
        PLAN:   Planning / decomposition phase.
        RUN:    Execution phase.
    """

    PROMPT = "prompt"
    PLAN = "plan"
    RUN = "run"


# ---------------------------------------------------------------------------
# SchedulerCommandV1
# ---------------------------------------------------------------------------

@dataclass
class SchedulerCommandV1:
    """Scheduler CONTROL command (v1).

    Represents a directive from the scheduler telling an agent which stage
    to enter, with an optional JSON-serialisable input payload.

    Attributes:
        stage: The scheduler stage the agent should transition to.
        input: Optional arbitrary JSON-serialisable data accompanying the
            command.  When serialised, ``None`` is omitted from the JSON
            output.

    Example::

        cmd = SchedulerCommandV1(stage=SchedulerStage.RUN)
        cmd = SchedulerCommandV1(
            stage=SchedulerStage.PLAN,
            input={"task": "implement feature X"},
        )
        payload = cmd.to_bytes()
        restored = SchedulerCommandV1.from_bytes(payload)
    """

    stage: SchedulerStage
    input: Optional[Dict[str, Any]] = None

    # -- Serialisation helpers ------------------------------------------------

    def to_dict(self) -> Dict[str, Any]:
        """Convert to a plain dictionary suitable for JSON encoding.

        Returns:
            Dictionary with ``"stage"`` (string) and optionally ``"input"``.
        """
        d: Dict[str, Any] = {"stage": self.stage.value}
        if self.input is not None:
            d["input"] = self.input
        return d

    def to_bytes(self) -> bytes:
        """Serialise to compact JSON bytes.

        Returns:
            UTF-8 encoded JSON bytes.
        """
        return json.dumps(self.to_dict(), separators=(",", ":")).encode("utf-8")

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> SchedulerCommandV1:
        """Construct from a plain dictionary.

        Args:
            data: Dictionary with at least a ``"stage"`` key whose value is
                one of ``"prompt"``, ``"plan"``, or ``"run"``.

        Returns:
            A new ``SchedulerCommandV1`` instance.

        Raises:
            KeyError: If ``"stage"`` is missing.
            ValueError: If the stage value is not a valid ``SchedulerStage``.
        """
        return cls(
            stage=SchedulerStage(data["stage"]),
            input=data.get("input"),
        )

    @classmethod
    def from_bytes(cls, raw: bytes) -> SchedulerCommandV1:
        """Deserialise from JSON bytes.

        Args:
            raw: UTF-8 encoded JSON bytes.

        Returns:
            A new ``SchedulerCommandV1`` instance.

        Raises:
            json.JSONDecodeError: If *raw* is not valid JSON.
            KeyError: If required fields are missing.
            ValueError: If field values are invalid.
        """
        return cls.from_dict(json.loads(raw))


# ---------------------------------------------------------------------------
# AgentReportFileV1
# ---------------------------------------------------------------------------

@dataclass
class AgentReportFileV1:
    """A single file artifact attached to an agent report.

    Files are transported as base64-encoded blobs so they can be embedded
    inside JSON payloads without binary-framing concerns.

    Attributes:
        path: Relative POSIX-style file path (forward slashes).
        b64:  Base64-encoded file content.
    """

    path: str
    b64: str

    def to_dict(self) -> Dict[str, str]:
        """Convert to a plain dictionary.

        Returns:
            Dictionary with ``"path"`` and ``"b64"`` keys.
        """
        return {"path": self.path, "b64": self.b64}

    @classmethod
    def from_dict(cls, data: Dict[str, str]) -> AgentReportFileV1:
        """Construct from a plain dictionary.

        Args:
            data: Dictionary with ``"path"`` and ``"b64"`` keys.

        Returns:
            A new ``AgentReportFileV1`` instance.

        Raises:
            KeyError: If required fields are missing.
        """
        return cls(path=data["path"], b64=data["b64"])


# ---------------------------------------------------------------------------
# AgentReportV1
# ---------------------------------------------------------------------------

@dataclass
class AgentReportV1:
    """Agent report with optional base64 file artifacts (v1).

    Sent by an agent back to the scheduler to communicate execution results.
    All fields are optional to support incremental / partial reports.

    Attributes:
        agent_id: Identifier of the reporting agent.
        stage:    Free-form stage label (e.g. ``"generate"``, ``"test"``).
        success:  Whether the reported operation succeeded.
        files:    List of file artifacts produced by the agent.
        logs:     List of log lines captured during execution.
        error:    Human-readable error description, if any.

    Example::

        report = AgentReportV1(
            agent_id="agent-42",
            stage="generate",
            success=True,
            files=[AgentReportFileV1(path="src/main.py", b64="...")],
        )
        report.normalize_paths()
        payload = report.to_bytes()
    """

    agent_id: Optional[str] = None
    stage: Optional[str] = None
    success: Optional[bool] = None
    files: Optional[List[AgentReportFileV1]] = None
    logs: Optional[List[str]] = None
    error: Optional[str] = None

    # -- Path normalisation ---------------------------------------------------

    def normalize_paths(self) -> None:
        """Normalize file paths to POSIX style and collapse redundancies.

        Performs the following transformations on each file path in
        :pyattr:`files`:

        * Replaces backslashes with forward slashes.
        * Collapses ``//`` sequences.
        * Resolves ``.`` (current directory) components.
        * Resolves ``..`` (parent directory) components.

        This method mutates the ``files`` list in place.
        """
        if self.files is None:
            return
        for f in self.files:
            replaced = f.path.replace("\\", "/")
            f.path = _normalize_posix_path(replaced)

    # -- Serialisation helpers ------------------------------------------------

    def to_dict(self) -> Dict[str, Any]:
        """Convert to a plain dictionary, omitting ``None`` fields.

        Returns:
            Dictionary representation suitable for JSON encoding.
        """
        d: Dict[str, Any] = {}
        if self.agent_id is not None:
            d["agent_id"] = self.agent_id
        if self.stage is not None:
            d["stage"] = self.stage
        if self.success is not None:
            d["success"] = self.success
        if self.files is not None:
            d["files"] = [f.to_dict() for f in self.files]
        if self.logs is not None:
            d["logs"] = self.logs
        if self.error is not None:
            d["error"] = self.error
        return d

    def to_bytes(self) -> bytes:
        """Serialise to compact JSON bytes.

        Returns:
            UTF-8 encoded JSON bytes.
        """
        return json.dumps(self.to_dict(), separators=(",", ":")).encode("utf-8")

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> AgentReportV1:
        """Construct from a plain dictionary.

        Args:
            data: Dictionary with optional report fields.

        Returns:
            A new ``AgentReportV1`` instance.
        """
        files_raw = data.get("files")
        files: Optional[List[AgentReportFileV1]] = None
        if files_raw is not None:
            files = [AgentReportFileV1.from_dict(f) for f in files_raw]

        return cls(
            agent_id=data.get("agent_id"),
            stage=data.get("stage"),
            success=data.get("success"),
            files=files,
            logs=data.get("logs"),
            error=data.get("error"),
        )

    @classmethod
    def from_bytes(cls, raw: bytes) -> AgentReportV1:
        """Deserialise from JSON bytes.

        Args:
            raw: UTF-8 encoded JSON bytes.

        Returns:
            A new ``AgentReportV1`` instance.

        Raises:
            json.JSONDecodeError: If *raw* is not valid JSON.
        """
        return cls.from_dict(json.loads(raw))


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _normalize_posix_path(p: str) -> str:
    """Collapse a POSIX-style path, resolving `.`, `..`, and duplicate slashes.

    This is a pure string operation -- no filesystem access is performed.

    Args:
        p: A forward-slash-separated path string.

    Returns:
        The collapsed path with no leading slash.
    """
    out: List[str] = []
    for part in p.split("/"):
        if part in ("", "."):
            continue
        if part == "..":
            if out:
                out.pop()
        else:
            out.append(part)
    return "/".join(out)
