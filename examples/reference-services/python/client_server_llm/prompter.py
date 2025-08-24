#!/usr/bin/env python3
"""
Prompter for the Python reference demo (CONTROL-only).

Single command usage:
  python prompter.py --file plan_prompt.txt
  python prompter.py --file run_trigger.txt

Behavior:
- If the file parses as JSON and looks like a scheduler CONTROL run
  (has {"to":"scheduler", "stage":"run", ...}), it is sent as CONTROL
  with content type application/vnd.sw4rm.scheduler.command+json;v=1.
- Otherwise, the file content is wrapped as CONTROL stage=prompt to the
  scheduler with the same content type.
"""
import json
import os
import sys
import grpc

# Add SDK to path when running from this directory
sys.path.append(os.path.join(os.path.dirname(__file__), "..", "..", "..", "sdks", "py_sdk"))

from sw4rm.clients.router import RouterClient
from sw4rm.envelope import build_envelope
from sw4rm import constants as C


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--file", required=True, help="Path to the plan or run file")
    args = ap.parse_args()

    file_path = args.file
    if not os.path.isfile(file_path):
        print(f"file not found: {file_path}")
        return 2

    router_host = os.getenv("ROUTER_HOST", "localhost")
    router_port = int(os.getenv("ROUTER_PORT", "50051"))
    channel = grpc.insecure_channel(f"{router_host}:{router_port}")
    router = RouterClient(channel)

    raw = open(file_path, "r", encoding="utf-8").read()
    try:
        obj = json.loads(raw)
    except Exception:
        obj = None

    if isinstance(obj, dict) and (obj.get("to") in (None, "scheduler")) and obj.get("stage") == "run":
        payload = raw.encode("utf-8")
        env = build_envelope(
            producer_id="prompter",
            message_type=C.CONTROL,
            content_type="application/vnd.sw4rm.scheduler.command+json;v=1",
            payload=payload,
        )
    else:
        payload = json.dumps({
            "schema_version": 1,
            "to": "scheduler",
            "stage": "prompt",
            "params": {"prompt": raw},
        }).encode("utf-8")
        env = build_envelope(
            producer_id="prompter",
            message_type=C.CONTROL,
            content_type="application/vnd.sw4rm.scheduler.command+json;v=1",
            payload=payload,
        )

    try:
        resp = router.send_message(env)
        accepted = getattr(resp, "accepted", False)
        reason = getattr(resp, "reason", "")
        print("accepted=", accepted, "reason=", reason)
        return 0 if accepted else 1
    except Exception as e:
        print("send failed:", e)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
