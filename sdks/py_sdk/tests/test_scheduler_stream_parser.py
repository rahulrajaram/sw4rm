"""Regression tests for the reference scheduler's LLM stream parser.

R30 of the review triage: the post-loop reconstruction used to sit inside
the stream loop, so run_claude_stream_json returned (None, "") on the very
first stream line (dead primary path) and could deadlock on a full pipe.
These tests pin the fixed behavior with a fake `claude` process.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

HIVE_DIR = Path(__file__).resolve().parents[1] / "reference-services" / "hive"
if str(HIVE_DIR) not in sys.path:
    sys.path.insert(0, str(HIVE_DIR))

import scheduler_service as svc  # noqa: E402


class FakeProcess:
    def __init__(self, lines) -> None:
        self._lines = list(lines)
        self.wait_called = False

    @property
    def stdout(self):
        return iter(self._lines)

    def wait(self):
        self.wait_called = True


def _run(fake, monkeypatch) -> tuple:
    monkeypatch.setattr(svc.subprocess, "Popen", lambda *args, **kw: fake)
    monkeypatch.setattr(svc, "_log", lambda *args: None)
    monkeypatch.setattr(svc, "_transcript_append", lambda *args: None)
    monkeypatch.setattr(svc, "_read_session_id", lambda: None)
    return svc.run_claude_stream_json("build a demo")


def _delta_lines(text: str):
    yield json.dumps({"type": "stream_start"})
    yield json.dumps({
        "type": "content_block_start",
        "content_block": {"type": "text", "text": ""},
    })
    # Split into two deltas so the reconstruction concatenates them.
    half = len(text) // 2
    for frag in (text[:half], text[half:]):
        yield json.dumps({
            "type": "content_block_delta",
            "delta": {"type": "text_delta", "text": frag},
        })


def test_reconstructed_json_reaches_the_post_loop_path(monkeypatch) -> None:
    """No 'result' event: the post-loop JSON parse must reconstruct the text.

    Before R30 the function returned (None, \"\") on the first event line, so
    the reconstructed document was never returned.
    """
    payload = '{"decision": "approve", "n": 1}'
    fake = FakeProcess(_delta_lines(payload))
    result_obj, full_text = _run(fake, monkeypatch)
    assert fake.wait_called
    assert result_obj == {"decision": "approve", "n": 1}
    assert full_text == payload


def test_large_stream_is_not_truncated(monkeypatch) -> None:
    """A stream larger than a typical 64 KiB pipe still round-trips whole."""
    payload = '{"report": "' + ("x" * 200_000) + '"}'
    fake = FakeProcess(_delta_lines(payload))
    result_obj, full_text = _run(fake, monkeypatch)
    assert result_obj == json.loads(payload)
    assert full_text == payload


def test_empty_stream_returns_none_without_nameerror(monkeypatch) -> None:
    """An empty stdout must not raise NameError on the post-loop bind."""
    fake = FakeProcess([])
    result_obj, full_text = _run(fake, monkeypatch)
    assert fake.wait_called
    assert result_obj is None
    assert full_text == ""


def test_session_id_file_is_private_and_atomic(monkeypatch, tmp_path) -> None:
    """The session-id cache lives outside the package tree, is written 0600
    via exclusive creation, and never leaves a temp file behind (R35)."""
    monkeypatch.setattr(svc, "_session_dir", lambda: tmp_path)
    svc._write_session_id("session-abc")
    target = tmp_path / "scheduler_session_id"
    assert target.read_text(encoding="utf-8") == "session-abc"
    assert (target.stat().st_mode & 0o777) == 0o600
    leftovers = [p for p in tmp_path.iterdir() if p.name != "scheduler_session_id"]
    assert leftovers == [], f"temp files left behind: {leftovers}"
    assert svc._read_session_id() == "session-abc"


def test_plan_and_dispatch_generate_shared_path(monkeypatch) -> None:
    """R45: the seed and CONTROL handlers share one plan+dispatch helper."""
    sent = []
    monkeypatch.setattr(svc, "_send", lambda router, agent, mtype, ct, payload, corr: sent.append((ct, payload, corr)))
    monkeypatch.setattr(svc, "_transcript_append", lambda *args: None)
    monkeypatch.setattr(svc, "_log", lambda *args: None)
    monkeypatch.setattr(svc, "_log_error", lambda *args: None)

    result = {
        "frontend": {"prompt": "build the ui", "expected_artifacts": ["frontend/index.html"]},
        "backend": {"prompt": "build the api"},
        "commands": {"frontend": {"run_cmd": "serve 5173"}, "backend": {"run_cmd": "serve 8000"}},
    }
    sessions = {}
    ok = svc._plan_and_dispatch_generate(None, "agent-1", "corr-1", result, sessions)
    assert ok is True
    assert len(sent) == 2
    roles = {json.loads(p)["to"] for _, p, _ in sent}
    assert roles == {"frontend", "backend"}
    sess = sessions["corr-1"]
    assert sess["plan"]["frontend"]["prompt"].startswith("build the ui")
    assert "Respond with JSON ONLY" in json.loads(sent[0][1])["params"]["prompt"]
    assert sess["run_cmds"] == {"frontend": "serve 5173", "backend": "serve 8000"}

    bad = svc._plan_and_dispatch_generate(None, "agent-1", "corr-2", {"frontend": {"prompt": "x"}}, sessions)
    assert bad is False
    assert sent[-1][2] == "corr-1"
    assert len([p for _, p, c in sent if c == "corr-2"]) == 0


def test_auth_error_hint_is_logged(monkeypatch) -> None:
    """The auth diagnostic still fires on streamed error text."""
    hints = []
    monkeypatch.setattr(svc, "_log", hints.append)
    monkeypatch.setattr(svc, "_transcript_append", lambda *args: None)
    monkeypatch.setattr(svc, "_read_session_id", lambda: None)
    lines = [
        json.dumps({"type": "content_block_delta",
                    "delta": {"type": "text_delta",
                              "text": "Invalid API key: please log in"}}),
    ]
    fake = FakeProcess(lines)
    monkeypatch.setattr(svc.subprocess, "Popen", lambda *args, **kw: fake)
    result_obj, full_text = svc.run_claude_stream_json("ping")
    assert result_obj is None
    assert "Invalid API key" in full_text
    assert any("Invalid API key" in hint for hint in hints)