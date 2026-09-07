"""A localhost serialization oracle, not an implementation of SW4RM services.

Every RPC checks its request against canonical fixtures and returns the expected
response. Real router semantics are tested separately by reference_router_server.
"""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from importlib import import_module
import gzip
import json
from pathlib import Path
import signal
import threading

import grpc
from google.protobuf import descriptor_pool, message_factory

ROOT = Path(__file__).resolve().parents[2]
with gzip.open(ROOT / "tests/conformance_vectors/wire_vectors.json.gz", "rt") as _handle:
    CONTRACT = json.load(_handle)
VECTORS = {vector["id"]: vector for vector in CONTRACT["vectors"]}


def load_pool():
    for source in sorted((ROOT / "protos").glob("*.proto")):
        import_module(f"sw4rm.protos.{source.stem}_pb2")
    return descriptor_pool.Default()


POOL = load_pool()


def message_type(name):
    return message_factory.GetMessageClass(POOL.FindMessageTypeByName(name))


def fixture_message(name, variant="sample"):
    return message_type(name).FromString(bytes.fromhex(VECTORS[f"{name}:{variant}"]["wire_hex"]))


def handler_for(rpc):
    def check(request_bytes, context):
        metadata = dict(context.invocation_metadata())
        if metadata.get("sw4rm-error"):
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "requested conformance error")
        if delay := metadata.get("sw4rm-delay-ms"):
            cancelled = threading.Event()
            context.add_callback(cancelled.set)
            cancelled.wait(min(int(delay), 5000) / 1000)
        variant = metadata.get("sw4rm-vector", "sample")
        actual = message_type(rpc["request"]).FromString(request_bytes)
        expected = fixture_message(rpc["request"], variant)
        if actual != expected:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, f"request differs from {rpc['request']}:{variant}")
        return variant

    def unary(request, context):
        variant = check(request, context)
        return fixture_message(rpc["response"], variant).SerializeToString()

    def stream(request, context):
        check(request, context)
        for variant in ("sample", "edge"):
            yield fixture_message(rpc["response"], variant).SerializeToString()
            if dict(context.invocation_metadata()).get("sw4rm-hold-stream"):
                cancelled = threading.Event()
                context.add_callback(cancelled.set)
                cancelled.wait(5)
                return

    return (grpc.unary_stream_rpc_method_handler(stream) if rpc["server_streaming"]
            else grpc.unary_unary_rpc_method_handler(unary))


@contextmanager
def serve():
    server = grpc.server(ThreadPoolExecutor(max_workers=4))
    for service in CONTRACT["services"]:
        methods = {rpc["path"].rsplit("/", 1)[1]: handler_for(rpc) for rpc in CONTRACT["rpcs"]
                   if rpc["path"].split("/")[1] == service}
        server.add_generic_rpc_handlers((grpc.method_handlers_generic_handler(service, methods),))
    port = server.add_insecure_port("127.0.0.1:0")
    if port == 0:
        raise RuntimeError("Cannot bind the local conformance server")
    server.start()
    try:
        yield port
    finally:
        server.stop(0).wait()


if __name__ == "__main__":
    stopped = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stopped.set())
    signal.signal(signal.SIGINT, lambda *_: stopped.set())
    with serve() as port:
        print(json.dumps({"ready": True, "port": port}), flush=True)
        stopped.wait()
