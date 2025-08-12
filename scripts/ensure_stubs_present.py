#!/usr/bin/env python3
from __future__ import annotations

import glob
import os
import sys


def main() -> int:
    base = os.path.join(os.path.dirname(__file__), "..", "sdks", "py_sdk", "sw4rm", "protos")
    base = os.path.abspath(base)
    patterns = [os.path.join(base, "*_pb2.py"), os.path.join(base, "*_pb2_grpc.py")]
    missing = []
    found_any = False
    for pat in patterns:
        matches = glob.glob(pat)
        if matches:
            found_any = True
        else:
            missing.append(pat)

    if not found_any:
        print("[error] No protobuf stubs found. Run `make protos` before building.")
        print("Expected files like:")
        for m in missing:
            print(" -", m)
        return 1

    print("[ok] Protobuf stubs present in:", base)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

