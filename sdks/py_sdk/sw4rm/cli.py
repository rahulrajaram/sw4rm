from __future__ import annotations

import json
import sys
from typing import Any

from . import constants as C


def _check_stubs() -> dict[str, Any]:
    try:
        from .protos import common_pb2  # type: ignore
        # Access a known symbol to verify it exists
        _ = common_pb2.Envelope
        return {"stubs_present": True, "details": ["common_pb2.Envelope available"]}
    except Exception as e:  # pragma: no cover
        return {"stubs_present": False, "error": str(e)}


def main(argv: list[str] | None = None) -> int:
    info = {
        "router_addr": C.get_default_router_addr(),
        "registry_addr": C.get_default_registry_addr(),
    }
    stubs = _check_stubs()
    info.update(stubs)
    print(json.dumps(info, indent=2))
    return 0 if stubs.get("stubs_present") else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

