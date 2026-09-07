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

"""Kill-9 crash-injection conformance harness for SW4RM reference services.

Encodes the campaign's documented-behavior contract as executable checks.
Each scenario spawns real reference services as subprocesses, drives
traffic over gRPC, SIGKILLs processes mid-flight, restarts them, and
asserts the durability invariants the documentation promises.

Scorecard: every scenario records PASS/FAIL into a machine-readable
scorecard (artifacts/crash-conformance/crash_scorecard.json). Red rows are expected
and useful — the suite is the honesty instrument, not a green gate.
"""

from __future__ import annotations

import os
import select
import signal
import socket
import sqlite3
import subprocess
import sys
import tempfile
import textwrap
import time
from dataclasses import dataclass
from contextlib import closing
from pathlib import Path
from typing import Dict, Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
PY_SDK = REPO_ROOT / "sdks" / "py_sdk"

_RESULT_SCHEMA_VERSION = 1


@dataclass
class ScenarioResult:
    name: str
    invariant: str
    status: str  # "pass" | "fail" | "skip"
    detail: str = ""
    duration_s: float = 0.0


def _wait_ready(port: int, proc: subprocess.Popen, timeout: float = 20.0) -> bool:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            return False
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.2)
    return False


def _kill9(proc: subprocess.Popen) -> None:
    if proc.poll() is None:
        proc.send_signal(signal.SIGKILL)
        proc.wait(timeout=10)


def _free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def read_child_line(proc: subprocess.Popen, timeout: float) -> str:
    """Read one bounded UTF-8 line from an unbuffered binary child pipe.

    Reading only one byte at a time leaves subsequent events in the pipe,
    so readiness checks cannot miss data prefetched by a text wrapper.
    The deadline also covers a child that stops in the middle of a line.
    """
    if proc.stdout is None:
        raise RuntimeError("child stdout is not captured")
    deadline = time.monotonic() + timeout
    data = bytearray()
    while len(data) < 8192:
        remaining = deadline - time.monotonic()
        if remaining <= 0 or not select.select([proc.stdout], [], [], remaining)[0]:
            raise RuntimeError("child event deadline exceeded")
        byte = os.read(proc.stdout.fileno(), 1)
        if not byte:
            raise RuntimeError("child exited before completing an event")
        if byte == b"\n":
            return data.decode("utf-8")
        data.extend(byte)
    raise RuntimeError("child event exceeds 8192 bytes")


class CrashHarness:
    """Spawns/kills/restarts the Python reference services for scenarios."""

    ROUTER_PORT_ENV = "SW4RM_CRASH_ROUTER_PORT"
    ROOM_PORT_ENV = "SW4RM_CRASH_ROOM_PORT"

    def __init__(self, workdir: Optional[Path] = None):
        self._temporary = tempfile.TemporaryDirectory(prefix="sw4rm-crash-") if workdir is None else None
        self._workdir = Path(self._temporary.name if self._temporary else workdir)
        self._workdir.mkdir(parents=True, exist_ok=True)
        self._procs: Dict[str, subprocess.Popen] = {}
        self._ports: Dict[str, int] = {}

    # -- service lifecycle ------------------------------------------------

    def _env(self) -> Dict[str, str]:
        env = os.environ.copy()
        env["PYTHONPATH"] = f"{PY_SDK}:{env.get('PYTHONPATH', '')}".rstrip(":")
        env["PYTHONUNBUFFERED"] = "1"
        return env

    def _readiness_error(self, service: str, port: int) -> str:
        """Return a bounded child diagnostic when a service is not ready."""
        proc = self._procs.get(service)
        if proc is None or proc.poll() is None:
            return f"{service} child still running; no READY on {port}"
        output, _ = proc.communicate(timeout=1)
        return f"{service} child exited {proc.returncode}: {output[-1000:]}"

    def start_router(self, db_path: Optional[str] = None) -> int:
        port = _free_port()
        db = db_path or str(self._workdir / "router.sqlite3")
        script = textwrap.dedent(
            f"""
            import os, sys, time, signal
            sys.path.insert(0, {str(REPO_ROOT / 'sdks' / 'py_sdk' / 'reference-services' / 'hive')!r})
            port = int(os.environ['SW4RM_CRASH_ROUTER_PORT'])
            from router_service import RouterServiceImpl
            from sw4rm.protos import router_pb2_grpc as grpc_mod
            impl = RouterServiceImpl(db_path=os.environ['SW4RM_DB_PATH'])
            from concurrent import futures
            import grpc
            server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
            grpc_mod.add_RouterServiceServicer_to_server(impl, server)
            server.add_insecure_port('127.0.0.1:' + str(port))
            server.start()
            print('READY', flush=True)
            signal.signal(signal.SIGTERM, lambda *_: (server.stop(0.1), sys.exit(0)))
            while True:
                time.sleep(3600)
            """
        )
        path = self._workdir / "router_launch.py"
        path.write_text(script)
        env = self._env()
        env[self.ROUTER_PORT_ENV] = str(port)
        env["SW4RM_DB_PATH"] = db or str(self._workdir / "router.sqlite3")
        proc = subprocess.Popen(
            [sys.executable, str(path)], cwd=str(self._workdir), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        self._procs["router"] = proc
        self._ports["router"] = port
        if not _wait_ready(port, proc):
            raise RuntimeError(self._readiness_error("router", port))
        return port

    def start_room(self, db_path: Optional[str] = None) -> int:
        port = _free_port()
        db = db_path or str(self._workdir / "negotiation_room.sqlite3")
        script = textwrap.dedent(
            f"""
            import os, sys, time, signal
            sys.path.insert(0, {str(REPO_ROOT / 'sdks' / 'py_sdk' / 'reference-services' / 'coordination')!r})
            sys.path.insert(0, {str(REPO_ROOT / 'sdks' / 'py_sdk')!r})
            port = int(os.environ['SW4RM_CRASH_ROOM_PORT'])
            os.environ.setdefault('SW4RM_NEGOTIATION_ROOM_DB', {str(db)!r})
            from negotiation_room_service import NegotiationRoomServiceImpl
            from sw4rm.protos import negotiation_room_pb2_grpc as grpc_mod
            from concurrent import futures
            import grpc
            impl = NegotiationRoomServiceImpl(db_path=os.environ['SW4RM_NEGOTIATION_ROOM_DB'])
            server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
            grpc_mod.add_NegotiationRoomServiceServicer_to_server(impl, server)
            server.add_insecure_port('127.0.0.1:' + str(port))
            server.start()
            print('READY', flush=True)
            signal.signal(signal.SIGTERM, lambda *_: (server.stop(0.1), sys.exit(0)))
            while True:
                time.sleep(3600)
            """
        )
        path = self._workdir / "room_launch.py"
        path.write_text(script)
        env = self._env()
        env[self.ROOM_PORT_ENV] = str(port)
        env["SW4RM_NEGOTIATION_ROOM_DB"] = db
        proc = subprocess.Popen(
            [sys.executable, str(path)], cwd=str(self._workdir), env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
        )
        self._procs["room"] = proc
        self._ports["room"] = port
        if not _wait_ready(port, proc):
            raise RuntimeError(self._readiness_error("room", port))
        return port

    def kill9(self, service: str) -> None:
        proc = self._procs[service]
        if proc.poll() is None:
            proc.send_signal(signal.SIGKILL)
        proc.wait(timeout=10)
        if proc.stdout is not None:
            proc.stdout.close()

    def wait_for_router_agent(self, agent_id: str, timeout: float = 5.0) -> None:
        """Observe the queue-registration commit before sending test traffic."""
        deadline = time.monotonic() + timeout
        with closing(sqlite3.connect(f"{self.router_db.resolve().as_uri()}?mode=ro", uri=True)) as connection:
            while time.monotonic() < deadline:
                row = connection.execute(
                    "SELECT 1 FROM router_agents WHERE agent_id = ?", (agent_id,)
                ).fetchone()
                if row is not None:
                    return
                time.sleep(0.01)
        raise RuntimeError(f"router did not register consumer {agent_id}")

    def stop_all(self) -> None:
        for proc in self._procs.values():
            if proc.poll() is None:
                proc.terminate()
        for proc in self._procs.values():
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
            if proc.stdout is not None:
                proc.stdout.close()
        self._procs.clear()
        if self._temporary is not None:
            self._temporary.cleanup()

    @property
    def workdir(self) -> Path:
        return self._workdir

    @property
    def router_port(self) -> int:
        return self._ports["router"]

    @property
    def room_port(self) -> int:
        return self._ports["room"]

    @property
    def router_db(self) -> Path:
        return self._workdir / "router.sqlite3"

    @property
    def room_db(self) -> Path:
        return self._workdir / "negotiation_room.sqlite3"
