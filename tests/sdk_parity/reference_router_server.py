#!/usr/bin/env python3
"""Disposable Python reference Router used by JS SDK parity tests.

The process owns one temporary SQLite-backed RouterServiceImpl, pre-seeds one
consumer queue, prints a JSON readiness record, and exits on SIGTERM. It is
intentionally a test fixture rather than a second reference-service launcher.
"""

from __future__ import annotations

import argparse
import json
import signal
import threading
from concurrent import futures

import grpc

from sw4rm.protos import common_pb2, router_pb2, router_pb2_grpc
from router_service import RouterServiceImpl


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", required=True)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--agent", default="consumer-1")
    parser.add_argument("--producer", default="producer-1")
    parser.add_argument("--message-id", default="js-parity-message")
    args = parser.parse_args()

    router = RouterServiceImpl(db_path=args.db, max_queue_size=16)
    router._ensure_agent_queue(args.agent)
    router._ensure_agent_queue(args.producer)
    response = router.SendMessage(
        router_pb2.SendMessageRequest(
            msg=common_pb2.Envelope(
                message_id=args.message_id,
                producer_id=args.producer,
                message_type=common_pb2.MessageType.DATA,
                content_type="application/json",
                payload=b'{"source":"python-reference"}',
            )
        ),
        None,
    )
    if not response.accepted:
        raise RuntimeError(f"failed to preseed router queue: {response.reason}")

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=8))
    router_pb2_grpc.add_RouterServiceServicer_to_server(router, server)
    bound_port = server.add_insecure_port(f"127.0.0.1:{args.port}")
    if not bound_port:
        raise RuntimeError("failed to bind disposable reference router")

    stopped = threading.Event()

    def stop(*_args) -> None:
        stopped.set()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)
    server.start()
    print(
        json.dumps(
            {
                "ready": True,
                "port": bound_port,
                "agent": args.agent,
                "message_id": args.message_id,
            }
        ),
        flush=True,
    )
    try:
        stopped.wait()
    finally:
        router._sweeper_stop.set()
        server.stop(0).wait()


if __name__ == "__main__":
    main()
