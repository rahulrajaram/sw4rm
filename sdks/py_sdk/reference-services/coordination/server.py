#!/usr/bin/env python3

# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
SW4RM Coordination Services Server.

This module provides a unified gRPC server that hosts all three coordination
services:
- HandoffService (port: base)
- WorkflowService (port: base)
- NegotiationRoomService (port: base)

All services run on the same port and can be accessed by any SDK client
(Python, Rust, TypeScript).

Usage:
    # Run with default settings (port 50060)
    python -m reference_services.coordination.server

    # Run with custom port
    python -m reference_services.coordination.server --port 50061

    # Run with environment variable
    COORDINATION_PORT=50062 python -m reference_services.coordination.server

Environment variables:
    COORDINATION_PORT: gRPC server port (default: 50060)
    COORDINATION_WORKERS: Max thread pool workers (default: 10)
"""

import argparse
import logging
import os
import signal
import sys
import threading
from concurrent import futures
from typing import Optional

import grpc

# Add parent directories to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

from sw4rm.protos import (
    handoff_pb2_grpc,
    workflow_pb2_grpc,
    negotiation_room_pb2_grpc,
)

from coordination.handoff_service import HandoffServiceImpl
from coordination.workflow_service import WorkflowServiceImpl
from coordination.negotiation_room_service import NegotiationRoomServiceImpl

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger("coordination.server")

# Default configuration
DEFAULT_PORT = 50060
DEFAULT_WORKERS = 10


class CoordinationServer:
    """
    Unified gRPC server for SW4RM coordination services.

    Hosts HandoffService, WorkflowService, and NegotiationRoomService
    on a single gRPC server instance.

    Attributes:
        port: The port number the server is listening on
        handoff_service: The HandoffServiceImpl instance
        workflow_service: The WorkflowServiceImpl instance
        negotiation_room_service: The NegotiationRoomServiceImpl instance
    """

    def __init__(
        self,
        port: int = DEFAULT_PORT,
        max_workers: int = DEFAULT_WORKERS
    ):
        """
        Initialize the coordination server.

        Args:
            port: Port number to listen on
            max_workers: Maximum number of thread pool workers
        """
        self.port = port
        self.max_workers = max_workers
        self._server: Optional[grpc.Server] = None
        self._shutdown_event = threading.Event()

        # Initialize services
        self.handoff_service = HandoffServiceImpl()
        self.workflow_service = WorkflowServiceImpl()
        self.negotiation_room_service = NegotiationRoomServiceImpl()

        logger.info(f"CoordinationServer initialized (port={port}, workers={max_workers})")

    def start(self) -> None:
        """
        Start the gRPC server.

        Creates a new gRPC server, registers all services, and starts
        listening on the configured port.
        """
        self._server = grpc.server(
            futures.ThreadPoolExecutor(max_workers=self.max_workers),
            options=[
                ('grpc.max_send_message_length', 50 * 1024 * 1024),
                ('grpc.max_receive_message_length', 50 * 1024 * 1024),
            ]
        )

        # Register all services
        handoff_pb2_grpc.add_HandoffServiceServicer_to_server(
            self.handoff_service,
            self._server
        )
        workflow_pb2_grpc.add_WorkflowServiceServicer_to_server(
            self.workflow_service,
            self._server
        )
        negotiation_room_pb2_grpc.add_NegotiationRoomServiceServicer_to_server(
            self.negotiation_room_service,
            self._server
        )

        # Bind to port
        address = f"0.0.0.0:{self.port}"
        self._server.add_insecure_port(address)

        # Start server
        self._server.start()
        logger.info(f"Coordination server started on {address}")
        logger.info("Services registered:")
        logger.info("  - HandoffService")
        logger.info("  - WorkflowService")
        logger.info("  - NegotiationRoomService")

    def stop(self, grace: float = 5.0) -> None:
        """
        Stop the gRPC server gracefully.

        Args:
            grace: Grace period in seconds for pending RPCs to complete
        """
        if self._server:
            logger.info(f"Stopping server (grace={grace}s)...")
            self._server.stop(grace)
            self._shutdown_event.set()
            logger.info("Server stopped")

    def wait_for_termination(self, timeout: Optional[float] = None) -> bool:
        """
        Block until the server terminates.

        Args:
            timeout: Optional timeout in seconds

        Returns:
            True if server terminated, False if timeout occurred
        """
        if self._server:
            self._server.wait_for_termination(timeout)
        return self._shutdown_event.is_set()

    def clear_all_state(self) -> None:
        """Clear all service state (for testing)."""
        self.handoff_service.clear_all()
        self.workflow_service.clear_all()
        self.negotiation_room_service.clear_all()
        logger.info("All service state cleared")


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="SW4RM Coordination Services Server",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Run with default port (50060)
  python -m coordination.server

  # Run with custom port
  python -m coordination.server --port 50061

  # Run with more workers
  python -m coordination.server --workers 20

Environment Variables:
  COORDINATION_PORT    Port number (default: 50060)
  COORDINATION_WORKERS Max worker threads (default: 10)
        """
    )

    parser.add_argument(
        "--port", "-p",
        type=int,
        default=int(os.getenv("COORDINATION_PORT", str(DEFAULT_PORT))),
        help=f"Port to listen on (default: {DEFAULT_PORT})"
    )

    parser.add_argument(
        "--workers", "-w",
        type=int,
        default=int(os.getenv("COORDINATION_WORKERS", str(DEFAULT_WORKERS))),
        help=f"Max thread pool workers (default: {DEFAULT_WORKERS})"
    )

    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Enable verbose logging"
    )

    return parser.parse_args()


def main() -> int:
    """Main entry point for the coordination server."""
    args = parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Create and start server
    server = CoordinationServer(
        port=args.port,
        max_workers=args.workers
    )

    # Set up signal handlers for graceful shutdown
    def handle_signal(signum, frame):
        logger.info(f"Received signal {signum}, shutting down...")
        server.stop()

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    try:
        server.start()
        server.wait_for_termination()
    except Exception as e:
        logger.error(f"Server error: {e}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
