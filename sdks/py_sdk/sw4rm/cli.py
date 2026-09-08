from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from . import constants as C


def _check_stubs() -> dict[str, Any]:
    try:
        from .protos import common_pb2, router_pb2  # type: ignore
        # Access a known symbol to verify it exists
        _ = common_pb2.Envelope
        _ = router_pb2.StreamItem.DESCRIPTOR.fields_by_name["seq"]
        _ = router_pb2.DESCRIPTOR.services_by_name["RouterService"].methods_by_name["AckDelivery"]
        return {"stubs_present": True, "details": ["Envelope and consumer delivery ACK bindings available"]}
    except Exception as e:  # pragma: no cover
        return {"stubs_present": False, "error": str(e)}


def main(argv: list[str] | None = None) -> int:
    from . import __version__
    parser = argparse.ArgumentParser(prog="sw4rm-doctor", description="Check local SDK bindings and configured service addresses; does not contact servers.")
    parser.add_argument("--version", action="version", version=__version__)
    parser.parse_args(argv)
    info = {"version": __version__,
        "router_addr": C.get_default_router_addr(),
        "registry_addr": C.get_default_registry_addr(),
    }
    stubs = _check_stubs()
    info.update(stubs)
    print(json.dumps(info, indent=2))
    return 0 if stubs.get("stubs_present") else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

