#!/usr/bin/env python3
"""
Minimal echo agent example using AgentOS SDK clients.

Prereqs:
  - Generate protobuf stubs: `make protos`
  - Install deps: `python -m pip install -e ".[dev]"`

Run:
  python examples/echo_agent.py --agent-id echo-1 --name EchoAgent \
    --router localhost:50051 --registry localhost:50052
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from typing import Optional

import grpc

from sigagent.clients.registry import RegistryClient
from sigagent.clients.router import RouterClient
from sigagent.envelope import build_envelope


def parse_args(argv: Optional[list[str]] = None) -> argparse.Namespace:
    p = argparse.ArgumentParser()
    p.add_argument("--agent-id", required=False, default=os.getenv("AGENT_ID", "echo-1"))
    p.add_argument("--name", required=False, default=os.getenv("AGENT_NAME", "EchoAgent"))
    p.add_argument("--router", required=False, default=os.getenv("AGENTOS_ROUTER_ADDR", "localhost:50051"))
    p.add_argument("--registry", required=False, default=os.getenv("AGENTOS_REGISTRY_ADDR", "localhost:50052"))
    return p.parse_args(argv)


def main() -> int:
    args = parse_args()

    # In simple setups, router and registry may share the same host:port.
    router_ch = grpc.insecure_channel(args.router)
    registry_ch = grpc.insecure_channel(args.registry)

    registry = RegistryClient(registry_ch)
    router = RouterClient(router_ch)

    # Register this agent
    descriptor = {
        "agent_id": args.agent_id,
        "name": args.name,
        "description": "Echoes incoming DATA messages back to router.",
        "capabilities": ["echo"],
        "communication_class": 2,  # STANDARD
        "modalities_supported": ["text/plain", "application/json"],
        "reasoning_connectors": [],
        # public_key omitted
    }
    try:
        reg = registry.register(descriptor)
        print(f"[register] accepted={getattr(reg, 'accepted', None)} reason={getattr(reg, 'reason', None)}")
    except Exception as e:
        print("Failed to register agent:", e, file=sys.stderr)

    stop = False

    def _sigint(_sig, _frm):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, _sigint)

    print(f"[stream] starting for agent {args.agent_id} against {args.router}")
    try:
        for item in router.stream_incoming(args.agent_id):
            if stop:
                break
            msg = getattr(item, "msg", item)
            mt = getattr(msg, "message_type", None)
            payload = getattr(msg, "payload", b"")
            print(f"[recv] type={mt} len={len(payload)} id={getattr(msg, 'message_id', None)}")

            # Echo back DATA messages with same payload as a new message
            if mt == 2:  # DATA
                env = build_envelope(
                    producer_id=args.agent_id,
                    message_type=2,
                    content_type=getattr(msg, "content_type", "application/octet-stream"),
                    payload=bytes(payload),
                )
                try:
                    resp = router.send_message(env)
                    print(f"[echo] accepted={getattr(resp, 'accepted', None)} reason={getattr(resp, 'reason', None)}")
                except Exception as e:
                    print("[echo] send failed:", e, file=sys.stderr)
    except KeyboardInterrupt:
        pass
    finally:
        print("[shutdown] deregistering...")
        try:
            registry.deregister(args.agent_id, reason="shutdown")
        except Exception:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
