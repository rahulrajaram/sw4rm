#!/usr/bin/env python3
"""Generate Python gRPC stubs into sdks/py_sdk/sw4rm/protos using repo venv.

Usage:
  venv/bin/python scripts/gen_protos.py
"""
from __future__ import annotations

from pathlib import Path
import sys


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    py_out = repo_root / "sdks" / "py_sdk" / "sw4rm" / "protos"
    protos = [
        "common.proto",
        "registry.proto",
        "router.proto",
        "scheduler.proto",
        "hitl.proto",
        "worktree.proto",
        "tool.proto",
        "connector.proto",
        "negotiation.proto",
        "reasoning.proto",
        "logging.proto",
    ]

    try:
        from grpc_tools import protoc  # type: ignore
        import pkg_resources  # type: ignore
    except Exception as e:
        print("[gen_protos] Missing grpc_tools; install dev deps (.[dev])", file=sys.stderr)
        print(f"[gen_protos] Details: {e}", file=sys.stderr)
        return 2

    py_out.mkdir(parents=True, exist_ok=True)
    inc = pkg_resources.resource_filename("grpc_tools", "_proto")

    args = [
        "protoc",
        f"-I{(repo_root / "protos").as_posix()}",
        f"-I{inc}",
        f"--python_out={py_out}",
        f"--grpc_python_out={py_out}",
        f"--pyi_out={py_out}",
        *[(repo_root / "protos" / p).as_posix() for p in protos],
    ]

    rc = protoc.main(args)
    if rc != 0:
        print(f"[gen_protos] protoc failed with code {rc}", file=sys.stderr)
        return rc

    # Fix relative imports in generated files (same as Makefile sed rule):
    # Only replace bare `import foo_pb2` lines, not `from google.protobuf import ...`
    import re
    _bare_import_re = re.compile(r"^import (.*_pb2)", re.MULTILINE)
    for p in list(py_out.glob("*_pb2.py")) + list(py_out.glob("*_pb2_grpc.py")):
        txt = p.read_text()
        txt = _bare_import_re.sub(r"from . import \1", txt)
        p.write_text(txt)

    print(f"[gen_protos] Generated stubs in {py_out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

