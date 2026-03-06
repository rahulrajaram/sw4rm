"""A2A Gateway Server — exposes SW4RM agents via A2A protocol.

Usage:
    python -m a2a_gateway.server [--port 50054] [--http-port 8080] \
        [--registry localhost:50052] [--router localhost:50051]

This server implements both:
  - A gRPC servicer for A2A operations (port 50054)
  - An HTTP server with .well-known/agent.json and JSON-RPC 2.0 (port 8080)
"""

import argparse
import json
import logging
import os
import signal
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import grpc

# SW4RM SDK imports
from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.clients.scheduler import SchedulerClient

from a2a_gateway.adapter import A2AToSW4RMAdapter

logger = logging.getLogger("a2a-gateway")


# --- gRPC Servicer ---

class A2AServicer:
    """gRPC servicer implementing the A2A protocol via SW4RM adapter.

    This is a pure-Python servicer that does NOT depend on generated
    protobuf stubs. It uses the generic gRPC service handler pattern
    to avoid requiring `protoc` compilation of a2a.proto.

    For production use, compile a2a.proto and use generated stubs.
    """

    def __init__(self, adapter: A2AToSW4RMAdapter):
        self.adapter = adapter

    def GetAgentCard(self, request_json: dict, context) -> dict:
        """Return the gateway's A2A Agent Card."""
        return self.adapter.get_agent_card()

    def SendMessage(self, request_json: dict, context) -> dict:
        """Handle A2A SendMessage — route to SW4RM agent."""
        message = request_json.get("message", {})
        metadata = message.get("metadata", {})

        # Determine target agent from metadata or default routing
        target_agent = metadata.get("sw4rm.target_agent")
        if not target_agent:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details(
                "Missing sw4rm.target_agent in message metadata. "
                "Specify which SW4RM agent should handle this task."
            )
            return {}

        context_id = message.get("context_id")

        task = self.adapter.send_message(
            message=message,
            target_agent_id=target_agent,
            context_id=context_id,
        )

        return {"task": task}

    def GetTask(self, request_json: dict, context) -> dict:
        """Handle A2A GetTask — return task state."""
        task_id = request_json.get("task_id")
        if not task_id:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details("task_id is required")
            return {}

        task = self.adapter.get_task(task_id)
        if task is None:
            context.set_code(grpc.StatusCode.NOT_FOUND)
            context.set_details(f"Task {task_id} not found")
            return {}

        return {"task": task}

    def CancelTask(self, request_json: dict, context) -> dict:
        """Handle A2A CancelTask — preempt via SW4RM."""
        task_id = request_json.get("task_id")
        if not task_id:
            context.set_code(grpc.StatusCode.INVALID_ARGUMENT)
            context.set_details("task_id is required")
            return {}

        task = self.adapter.cancel_task(task_id)
        if task is None:
            context.set_code(grpc.StatusCode.NOT_FOUND)
            context.set_details(f"Task {task_id} not found")
            return {}

        return {"task": task}


# --- HTTP / JSON-RPC 2.0 Handler ---

class A2AHTTPHandler(BaseHTTPRequestHandler):
    """HTTP handler serving .well-known/agent.json and JSON-RPC 2.0.

    Endpoints:
        GET  /.well-known/agent.json  → Agent Card JSON
        POST /                        → JSON-RPC 2.0 dispatch
    """

    # Set by the factory; shared across all requests
    adapter: A2AToSW4RMAdapter = None  # type: ignore[assignment]

    def log_message(self, format, *args):
        logger.debug("HTTP %s", format % args)

    def _send_json(self, status: int, body: dict) -> None:
        payload = json.dumps(body).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/.well-known/agent.json":
            card = self.adapter.get_agent_card()
            self._send_json(200, card)
        else:
            self._send_json(404, {"error": "Not Found"})

    def do_POST(self):
        if self.path != "/":
            self._send_json(404, {"error": "Not Found"})
            return

        # Read body
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length == 0:
            self._send_json(200, _jsonrpc_error(
                None, -32700, "Parse error: empty body",
            ))
            return

        raw = self.rfile.read(content_length)
        try:
            request = json.loads(raw)
        except json.JSONDecodeError:
            self._send_json(200, _jsonrpc_error(
                None, -32700, "Parse error: invalid JSON",
            ))
            return

        # Validate JSON-RPC envelope
        if not isinstance(request, dict) or request.get("jsonrpc") != "2.0":
            self._send_json(200, _jsonrpc_error(
                request.get("id") if isinstance(request, dict) else None,
                -32600, "Invalid Request: missing jsonrpc 2.0",
            ))
            return

        req_id = request.get("id")
        method = request.get("method", "")
        params = request.get("params", {})

        result = _dispatch(self.adapter, method, params)
        if result is None:
            self._send_json(200, _jsonrpc_error(
                req_id, -32601, f"Method not found: {method}",
            ))
            return

        self._send_json(200, {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": result,
        })


def _jsonrpc_error(req_id, code: int, message: str) -> dict:
    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": code, "message": message},
    }


def _dispatch(adapter: A2AToSW4RMAdapter, method: str, params: dict):
    """Dispatch a JSON-RPC method to the adapter. Returns None for unknown methods."""
    if method == "SendMessage":
        message = params.get("message", {})
        metadata = message.get("metadata", {})
        target_agent = metadata.get("sw4rm.target_agent")
        if not target_agent:
            return {"error": "Missing sw4rm.target_agent in message metadata"}
        task = adapter.send_message(
            message=message,
            target_agent_id=target_agent,
            context_id=message.get("context_id"),
        )
        return {"task": task}

    if method == "GetTask":
        task_id = params.get("task_id")
        if not task_id:
            return {"error": "task_id is required"}
        task = adapter.get_task(task_id)
        if task is None:
            return {"error": f"Task {task_id} not found"}
        return {"task": task}

    if method == "CancelTask":
        task_id = params.get("task_id")
        if not task_id:
            return {"error": "task_id is required"}
        task = adapter.cancel_task(task_id)
        if task is None:
            return {"error": f"Task {task_id} not found"}
        return {"task": task}

    if method == "GetAgentCard":
        agent_id = params.get("agent_id")
        return adapter.get_agent_card(agent_id=agent_id)

    return None  # Unknown method


def make_http_handler(adapter: A2AToSW4RMAdapter):
    """Create an A2AHTTPHandler class bound to the given adapter."""

    class BoundHandler(A2AHTTPHandler):
        pass

    BoundHandler.adapter = adapter
    return BoundHandler


def start_http_server(adapter: A2AToSW4RMAdapter, port: int = 8080) -> HTTPServer:
    """Start the A2A HTTP server in a background daemon thread."""
    handler_class = make_http_handler(adapter)
    server = HTTPServer(("0.0.0.0", port), handler_class)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    logger.info("A2A HTTP server listening on http://0.0.0.0:%d", port)
    return server


# --- Adapter Factory ---

def create_adapter(
    registry_addr: str = "localhost:50052",
    router_addr: str = "localhost:50051",
    scheduler_addr: str = "localhost:50053",
    gateway_url: str = "http://localhost:50054",
) -> A2AToSW4RMAdapter:
    """Create an A2A adapter with SW4RM client connections."""
    reg_channel = grpc.insecure_channel(registry_addr)
    rtr_channel = grpc.insecure_channel(router_addr)
    sch_channel = grpc.insecure_channel(scheduler_addr)

    return A2AToSW4RMAdapter(
        registry_client=RegistryClient(reg_channel),
        router_client=RouterClient(rtr_channel),
        scheduler_client=SchedulerClient(sch_channel),
        gateway_url=gateway_url,
    )


def serve(
    port: int = 50054,
    http_port: int = 8080,
    registry_addr: str = "localhost:50052",
    router_addr: str = "localhost:50051",
    scheduler_addr: str = "localhost:50053",
):
    """Start the A2A gateway (gRPC adapter + HTTP server)."""
    adapter = create_adapter(
        registry_addr=registry_addr,
        router_addr=router_addr,
        scheduler_addr=scheduler_addr,
        gateway_url=f"http://localhost:{port}",
    )

    servicer = A2AServicer(adapter)

    logger.info(
        "A2A Gateway adapter created. "
        "Connect SW4RM services at registry=%s router=%s scheduler=%s",
        registry_addr, router_addr, scheduler_addr,
    )

    # Start HTTP server for .well-known/agent.json and JSON-RPC
    http_server = start_http_server(adapter, http_port)

    # Print agent card
    card = adapter.get_agent_card()
    logger.info("Agent Card: %s", json.dumps(card, indent=2))
    logger.info("A2A Gateway ready — gRPC port %d, HTTP port %d", port, http_port)

    return adapter, servicer, http_server


def main():
    parser = argparse.ArgumentParser(description="A2A Gateway for SW4RM")
    parser.add_argument("--port", type=int, default=50054)
    parser.add_argument("--http-port", type=int, default=8080)
    parser.add_argument("--registry", default=os.environ.get("REGISTRY_ADDR", "localhost:50052"))
    parser.add_argument("--router", default=os.environ.get("ROUTER_ADDR", "localhost:50051"))
    parser.add_argument("--scheduler", default=os.environ.get("SCHEDULER_ADDR", "localhost:50053"))
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )

    adapter, servicer, http_server = serve(
        port=args.port,
        http_port=args.http_port,
        registry_addr=args.registry,
        router_addr=args.router,
        scheduler_addr=args.scheduler,
    )

    # Block until interrupted
    stop = False

    def handle_signal(signum, frame):
        nonlocal stop
        logger.info("Shutting down A2A gateway...")
        http_server.shutdown()
        stop = True

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    while not stop:
        time.sleep(1)


if __name__ == "__main__":
    main()
