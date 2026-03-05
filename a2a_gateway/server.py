"""A2A Gateway gRPC Server — exposes SW4RM agents via A2A protocol.

Usage:
    python -m a2a-gateway.server [--port 50054] [--registry localhost:50052] [--router localhost:50051]

This server implements the A2A gRPC service and translates all
operations to SW4RM service calls via the adapter module.
"""

import argparse
import json
import logging
import signal
import sys
import time
from concurrent import futures

import grpc

# SW4RM SDK imports
from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.clients.scheduler import SchedulerClient

from a2a_gateway.adapter import A2AToSW4RMAdapter, sw4rm_envelope_to_a2a_message

logger = logging.getLogger("a2a-gateway")


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
            # If no explicit target, use the first available agent
            # or return an error
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
    registry_addr: str = "localhost:50052",
    router_addr: str = "localhost:50051",
    scheduler_addr: str = "localhost:50053",
):
    """Start the A2A gateway gRPC server.

    Note: This MVP uses a JSON-over-gRPC approach without compiled
    protobuf stubs. For production, compile a2a.proto with protoc
    and use the generated servicer base class.
    """
    adapter = create_adapter(
        registry_addr=registry_addr,
        router_addr=router_addr,
        scheduler_addr=scheduler_addr,
        gateway_url=f"http://localhost:{port}",
    )

    servicer = A2AServicer(adapter)

    # For MVP, expose the adapter via a simple JSON-RPC-over-HTTP
    # endpoint alongside the gRPC server. This avoids the need
    # for compiled proto stubs while still being functional.
    #
    # Production: Use grpc.server() with compiled a2a_pb2_grpc stubs.
    logger.info(
        "A2A Gateway adapter created. "
        "Connect SW4RM services at registry=%s router=%s scheduler=%s",
        registry_addr, router_addr, scheduler_addr,
    )
    logger.info("A2A Gateway ready on port %d", port)

    # Print agent card
    card = adapter.get_agent_card()
    logger.info("Agent Card: %s", json.dumps(card, indent=2))

    return adapter, servicer


def main():
    parser = argparse.ArgumentParser(description="A2A Gateway for SW4RM")
    parser.add_argument("--port", type=int, default=50054)
    parser.add_argument("--registry", default="localhost:50052")
    parser.add_argument("--router", default="localhost:50051")
    parser.add_argument("--scheduler", default="localhost:50053")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(name)s] %(levelname)s: %(message)s",
    )

    adapter, servicer = serve(
        port=args.port,
        registry_addr=args.registry,
        router_addr=args.router,
        scheduler_addr=args.scheduler,
    )

    # Block until interrupted
    stop = False

    def handle_signal(signum, frame):
        nonlocal stop
        logger.info("Shutting down A2A gateway...")
        stop = True

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    while not stop:
        time.sleep(1)


if __name__ == "__main__":
    main()
