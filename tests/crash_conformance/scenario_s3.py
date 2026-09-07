# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""S3 crash-conformance scenario for activity-buffer interrupted writes."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import textwrap
import time
from pathlib import Path

from harness import CrashHarness, read_child_line


_CONFIRMED_ID = "s3-confirmed"
_INTERRUPTED_ID = "s3-interrupted"
_FILE_NAME = "s3-activity.json"


def _child_env() -> dict[str, str]:
    sdk = Path(__file__).resolve().parents[2] / "sdks" / "py_sdk"
    env = os.environ.copy()
    env["PYTHONPATH"] = f"{sdk}:{env.get('PYTHONPATH', '')}".rstrip(":")
    env["PYTHONUNBUFFERED"] = "1"
    return env


def _read_until(proc: subprocess.Popen, expected: str, timeout: float) -> str:
    deadline = time.monotonic() + timeout
    observed: list[str] = []
    while time.monotonic() < deadline:
        remaining = max(0.01, deadline - time.monotonic())
        line = read_child_line(proc, remaining)
        observed.append(line)
        if line == expected or line.startswith(expected):
            return line
    raise RuntimeError(f"expected {expected!r}; observed {observed[-3:]!r}")


def _writer_script(path: Path) -> str:
    return textwrap.dedent(
        f"""
        import builtins
        from sw4rm.activity_buffer import PersistentActivityBuffer
        from sw4rm.persistence import JSONFilePersistence

        path = {str(path)!r}
        temp_path = path.rsplit(".", 1)[0] + ".tmp"
        persistence = JSONFilePersistence(path)
        buffer = PersistentActivityBuffer(persistence=persistence)
        buffer.record_outgoing({{
            "message_id": "{_CONFIRMED_ID}",
            "message_type": 2,
            "content_type": "application/json",
            "payload": b"confirmed-before-kill",
            "producer_id": "s3-test",
        }})
        buffer.flush()
        print("CONFIRMED", flush=True)
        if input().strip() != "GO":
            raise RuntimeError("parent did not authorize the interrupted write")

        buffer.record_outgoing({{
            "message_id": "{_INTERRUPTED_ID}",
            "message_type": 2,
            "content_type": "application/json",
            "payload": b"must-not-appear",
            "producer_id": "s3-test",
        }})
        original_open = builtins.open

        def synchronized_open(file, *args, **kwargs):
            handle = original_open(file, *args, **kwargs)
            if str(file) in (path, temp_path) and args and args[0] == "w":
                # Opening a live file with mode='w' truncates it before this
                # marker. Atomic implementations open only their temp file.
                print("BOUNDARY:" + str(file), flush=True)
                input()
            return handle

        builtins.open = synchronized_open
        buffer.flush()
        print("UNEXPECTED-COMPLETE", flush=True)
        """
    )


def _reader_script(path: Path) -> str:
    return textwrap.dedent(
        f"""
        from sw4rm.activity_buffer import PersistentActivityBuffer
        from sw4rm.persistence import JSONFilePersistence

        buffer = PersistentActivityBuffer(persistence=JSONFilePersistence({str(path)!r}))
        record = buffer.get({_CONFIRMED_ID!r})
        order = list(buffer._order)
        if record is None or order != [{_CONFIRMED_ID!r}]:
            raise SystemExit("confirmed record or order did not survive restart")
        if record.envelope["payload"] != b"confirmed-before-kill":
            raise SystemExit("confirmed payload did not survive restart")
        if buffer.get({_INTERRUPTED_ID!r}) is not None:
            raise SystemExit("interrupted record became durable")
        print("RESTORED", flush=True)
        """
    )


def scenario_s3_buffer_write_survives_kill(h: CrashHarness) -> tuple[str, str]:
    """S3: SIGKILL during a write preserves the last confirmed buffer state."""
    workdir = h.workdir
    path = workdir / _FILE_NAME
    writer_path = workdir / "s3_writer.py"
    writer_path.write_text(_writer_script(path))

    child = subprocess.Popen(
        [sys.executable, str(writer_path)],
        cwd=str(workdir),
        env=_child_env(),
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )
    baseline: bytes | None = None
    try:
        if _read_until(child, "CONFIRMED", 10.0) != "CONFIRMED":
            return "fail", "writer did not confirm the baseline persistence write"
        try:
            baseline = path.read_bytes()
            confirmed = json.loads(baseline)
        except (OSError, json.JSONDecodeError) as error:
            return "fail", f"writer confirmed unreadable baseline persistence: {error}"
        if list(confirmed.get("order", [])) != [_CONFIRMED_ID]:
            return "fail", "writer confirmed an unexpected baseline order"
        if _CONFIRMED_ID not in confirmed.get("records", {}):
            return "fail", "writer confirmed a baseline without the expected record"

        child.stdin.write(b"GO\n")
        child.stdin.flush()
        boundary = _read_until(child, "BOUNDARY:", 10.0)
        expected_boundaries = {"BOUNDARY:" + str(path), "BOUNDARY:" + str(path.with_suffix('.tmp'))}
        if boundary not in expected_boundaries:
            return "fail", f"writer reached an unexpected boundary: {boundary}"

        child.send_signal(signal.SIGKILL)
        child.wait(timeout=10)
        if child.returncode != -signal.SIGKILL:
            return "fail", f"writer did not terminate by SIGKILL (returncode={child.returncode})"
    finally:
        if child.poll() is None:
            child.kill()
            child.wait(timeout=10)
        if child.stdin is not None:
            child.stdin.close()
        if child.stdout is not None:
            child.stdout.close()

    try:
        after_kill = path.read_bytes()
    except OSError as error:
        return "fail", f"confirmed persistence file disappeared after SIGKILL: {error}"
    if after_kill != baseline:
        return "fail", "confirmed persistence bytes changed during interrupted write"

    reader = subprocess.run(
        [sys.executable, "-c", _reader_script(path)],
        cwd=str(workdir),
        env=_child_env(),
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
    )
    if reader.returncode != 0:
        detail = (reader.stdout + reader.stderr).strip().splitlines()
        return "fail", "fresh interpreter could not restore confirmed state: " + (
            detail[-1] if detail else f"exit {reader.returncode}"
        )
    return "pass", "confirmed activity-buffer bytes and order survived SIGKILL at write boundary"
