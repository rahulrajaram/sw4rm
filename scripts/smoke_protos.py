#!/usr/bin/env python3
"""
Smoke test: compile protobufs and import generated modules + protocol clients (Python SDK).

Usage:
  python scripts/smoke_protos.py

Exits non-zero on failure with a helpful message.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
# SDK sources live under sdks/py_sdk
SDK_ROOT = REPO_ROOT / "sdks" / "py_sdk"
PY_OUT = SDK_ROOT / "sw4rm" / "protos"
PROTO_DIR = REPO_ROOT / "protos"


def compile_protos() -> None:
    try:
        from grpc_tools import protoc  # type: ignore
        import pkg_resources  # type: ignore
    except Exception:
        print(
            "[smoke] Missing grpc_tools. Install dev extras: `python -m pip install -e \".[dev]\"`",
            file=sys.stderr,
        )
        sys.exit(2)

    PY_OUT.mkdir(parents=True, exist_ok=True)

    inc = pkg_resources.resource_filename("grpc_tools", "_proto")

    # Compile all .proto files in repo's protos/ directory
    protos = sorted(str(p) for p in PROTO_DIR.glob("*.proto"))
    args = [
        "protoc",
        f"-I{PROTO_DIR}",
        f"-I{inc}",
        f"--python_out={PY_OUT}",
        f"--grpc_python_out={PY_OUT}",
    ] + protos

    rc = protoc.main(args)
    if rc != 0:
        print(f"[smoke] protoc failed with code {rc}", file=sys.stderr)
        sys.exit(rc)

    # Fix relative imports in generated files (same as Makefile sed rule):
    # Only replace bare `import foo_pb2` lines, not `from google.protobuf import ...`
    import re
    _bare_import_re = re.compile(r"^import (.*_pb2)", re.MULTILINE)
    for p in list(PY_OUT.glob("*_pb2.py")) + list(PY_OUT.glob("*_pb2_grpc.py")):
        txt = p.read_text()
        txt = _bare_import_re.sub(r"from . import \1", txt)
        p.write_text(txt)


def import_generated_and_clients() -> None:
    # Ensure editable-style import from SDK root works
    sys.path.insert(0, str(SDK_ROOT))
    # Also add generated stubs directory for absolute imports like `import common_pb2`
    sys.path.insert(0, str(PY_OUT))

    try:
        # Generated modules
        from sw4rm.protos import (
            common_pb2,  # noqa: F401
            registry_pb2,  # noqa: F401
            registry_pb2_grpc,  # noqa: F401
            router_pb2,  # noqa: F401
            router_pb2_grpc,  # noqa: F401
        )
    except Exception as e:
        print(f"[smoke] Failed to import generated modules: {e}", file=sys.stderr)
        sys.exit(3)

    try:
        # SDK clients
        from sw4rm.clients.registry import RegistryClient  # noqa: F401
        from sw4rm.clients.router import RouterClient  # noqa: F401
        from sw4rm.clients.scheduler import SchedulerClient  # noqa: F401
        from sw4rm.clients.hitl import HitlClient  # noqa: F401
        from sw4rm.clients.worktree import WorktreeClient  # noqa: F401
        from sw4rm.clients.negotiation import NegotiationClient  # noqa: F401
        from sw4rm.clients.reasoning import ReasoningClient  # noqa: F401
        from sw4rm.clients.logging import LoggingClient  # noqa: F401
        from sw4rm.clients.tool import ToolClient  # noqa: F401
        from sw4rm.clients.connector import ConnectorClient  # noqa: F401
    except Exception as e:
        print(f"[smoke] Failed to import SDK clients: {e}", file=sys.stderr)
        sys.exit(4)

    # Light touch: instantiate a couple of stubs with a dummy channel
    try:
        dummy_channel = object()
        from sw4rm.clients.registry import RegistryClient
        from sw4rm.clients.router import RouterClient

        RegistryClient(dummy_channel)
        RouterClient(dummy_channel)
    except Exception as e:
        print(f"[smoke] Failed to instantiate clients: {e}", file=sys.stderr)
        sys.exit(5)


def main() -> int:
    print("[smoke] Compiling protobufs...")
    compile_protos()
    print("[smoke] Imports check...")
    import_generated_and_clients()
    print("[smoke] OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
