#!/usr/bin/env python3
"""
Minimal Router Service Implementation for SW4RM Protocol
Provides basic message routing and streaming functionality.
"""

import logging
import os
import queue
import signal
import sys
import threading
import time
import uuid
from concurrent import futures
from pathlib import Path
from typing import Dict, List, Optional

import grpc

# Import the generated protobuf modules
# Prefer stubs from the installed SDK; fallback to local generated stubs
try:
    from sw4rm.protos import router_pb2, router_pb2_grpc, common_pb2
except Exception:  # SDK not installed; use local generated stubs
    import router_pb2, router_pb2_grpc, common_pb2

from state_store import RouterStateStore
from reference_auth_middleware import build_auth_interceptors
from reference_logging import configure_reference_service_logging
from reference_config import (
    ReferenceServiceConfig,
    ReferenceServiceConfigWatcher,
    load_reference_service_config,
    start_reference_service_config_watcher,
)
from health_service import add_reference_health_service
from graceful_shutdown import (
    ReferenceServiceShutdownCoordinator,
)


_DEFAULT_DB_DIR = str(Path.cwd() / ".reference_services_state")


def _default_db_path(env_var: str, filename: str) -> str:
    explicit = os.getenv(env_var)
    if explicit:
        return explicit
    return str(Path(_DEFAULT_DB_DIR) / filename)


class RouterServiceImpl(router_pb2_grpc.RouterServiceServicer):
    """Persistent router service implementation."""

    def __init__(
        self,
        db_path: Optional[str] = None,
        max_queue_size: int = 100,
        shutdown_manager: Optional[ReferenceServiceShutdownCoordinator] = None,
        config_watcher: Optional[ReferenceServiceConfigWatcher] = None,
    ):
        self._config_watcher = config_watcher
        base_config = (
            config_watcher.config
            if config_watcher is not None
            else load_reference_service_config("router")
        )

        self.max_queue_size = max(1, int(max_queue_size))
        self.db_path = db_path or base_config.router_db_path
        self._state_store = RouterStateStore(self.db_path)
        self._shutdown_manager = (
            shutdown_manager
            or ReferenceServiceShutdownCoordinator(
                "router-service",
                grace_period_seconds=base_config.shutdown_grace_seconds,
            )
        )

        self._apply_runtime_config(base_config)
        self.agent_queues: Dict[str, queue.Queue] = {}
        self._queue_index_map: Dict[str, Dict[int, None]] = {}
        self.active_streams: Dict[str, List] = {}
        self.message_log: List[Dict] = []
        self.lock = threading.RLock()

        self._restore_state()
        logging.info("Router service initialized")

    def _apply_runtime_config(self, config: ReferenceServiceConfig) -> None:
        self.max_queue_size = max(1, int(config.router_max_queue_size))

    def _refresh_runtime_config(self) -> None:
        if self._config_watcher is None:
            return
        self._apply_runtime_config(self._config_watcher.config)

    def _restore_state(self) -> None:
        for agent_id in self._state_store.list_agents():
            self._ensure_agent_queue(agent_id)

        for agent_id, items in self._state_store.load_pending_messages().items():
            self._ensure_agent_queue(agent_id)
            for seq, envelope_blob in items:
                envelope = common_pb2.Envelope()
                try:
                    envelope.ParseFromString(envelope_blob)
                except Exception:
                    continue
                try:
                    self.agent_queues[agent_id].put_nowait((seq, envelope))
                    self._queue_index_map[agent_id][seq] = None
                except queue.Full:
                    logging.warning(f"Restored queue full for {agent_id}; dropping stale message {seq}")
                    self._state_store.dequeue_message(seq)

        # message log is reconstructed from durable rows for status introspection
        for entry in self._state_store.load_message_log():
            envelope = common_pb2.Envelope()
            try:
                envelope.ParseFromString(entry.get("envelope_blob", b""))
            except Exception:
                continue
            self.message_log.append(
                {
                    "message_id": entry.get("message_id", ""),
                    "producer_id": entry.get("producer_id", ""),
                    "message_type": int(getattr(envelope, "message_type", 0)),
                    "content_type": entry.get("content_type", ""),
                    "payload_size": entry.get("payload_size", 0),
                    "timestamp": entry.get("timestamp", 0),
                    "correlation_id": entry.get("correlation_id", ""),
                    "sequence_number": entry.get("sequence_number", 0),
                }
            )

    def _ensure_agent_queue(self, agent_id: str) -> None:
        if agent_id not in self.agent_queues:
            self._state_store.ensure_agent(agent_id)
            self.agent_queues[agent_id] = queue.Queue(maxsize=self.max_queue_size)
            self._queue_index_map[agent_id] = {}

    def SendMessage(self, request, context):
        """Route a message to its destination."""
        if self._shutdown_manager.is_draining:
            return router_pb2.SendMessageResponse(
                accepted=False,
                reason="Router service is shutting down",
            )

        self._refresh_runtime_config()
        envelope = request.msg
        message_id = envelope.message_id or str(uuid.uuid4())
        producer_id = envelope.producer_id
        envelope.message_id = message_id
        envelope_blob = envelope.SerializeToString()
        payload_size = len(envelope.payload)

        with self._shutdown_manager.track_request("SendMessage"):
            with self.lock:
                # Log the message
                self._state_store.record_message(envelope, payload_size)
                self.message_log.append(
                    {
                        "message_id": message_id,
                        "producer_id": producer_id,
                        "message_type": envelope.message_type,
                        "content_type": envelope.content_type,
                        "payload_size": payload_size,
                        "timestamp": time.time(),
                        "correlation_id": envelope.correlation_id,
                        "sequence_number": envelope.sequence_number,
                    }
                )

                target_agents = set(self.agent_queues.keys())
                if producer_id in target_agents:
                    target_agents.remove(producer_id)

                if envelope.message_type == common_pb2.MessageType.ACKNOWLEDGEMENT:
                    logging.info(f"Received ACK message {message_id} from {producer_id}")
                    return router_pb2.SendMessageResponse(accepted=True, reason="ACK message accepted")

                delivered_count = 0
                for agent_id in target_agents:
                    try:
                        seq = self._state_store.enqueue_message(
                            agent_id,
                            envelope_blob,
                            message_id,
                        )
                        self.agent_queues[agent_id].put_nowait((seq, envelope))
                        self._queue_index_map[agent_id][seq] = None
                        delivered_count += 1
                        logging.debug(f"Routed message {message_id} to {agent_id}")
                    except queue.Full:
                        self._state_store.dequeue_message(seq)
                        logging.warning(f"Queue full for agent {agent_id}, dropping message")

                if delivered_count > 0:
                    logging.info(f"Message {message_id} delivered to {delivered_count} agents")
                    return router_pb2.SendMessageResponse(
                        accepted=True,
                        reason=f"Message delivered to {delivered_count} recipients",
                    )
                logging.warning(f"No recipients found for message {message_id}")
                return router_pb2.SendMessageResponse(
                    accepted=False,
                    reason="No recipients available",
                )

    def StreamIncoming(self, request, context):
        """Stream incoming messages for a specific agent."""
        agent_id = request.agent_id

        if self._shutdown_manager.is_draining:
            return

        logging.info(f"Starting message stream for agent: {agent_id}")

        with self._shutdown_manager.track_request("StreamIncoming"):
            with self.lock:
                self._ensure_agent_queue(agent_id)
                if agent_id not in self.active_streams:
                    self.active_streams[agent_id] = []
                self.active_streams[agent_id].append(context)

            try:
                while context.is_active():
                    if self._shutdown_manager.is_draining:
                        with self.lock:
                            queue_empty = self.agent_queues[agent_id].empty()
                        if queue_empty:
                            break
                    try:
                        seq, envelope = self.agent_queues[agent_id].get(timeout=1.0)
                        stream_item = router_pb2.StreamItem(msg=envelope)
                        yield stream_item
                        self._state_store.dequeue_message(seq)
                        self._queue_index_map[agent_id].pop(seq, None)
                        logging.debug(f"Streamed message to {agent_id}")
                    except queue.Empty:
                        continue
                    except Exception as e:
                        logging.error(f"Error streaming to {agent_id}: {e}")
                        break
            finally:
                with self.lock:
                    if agent_id in self.active_streams and context in self.active_streams[agent_id]:
                        self.active_streams[agent_id].remove(context)
                logging.info(f"Stream ended for agent: {agent_id}")

    def get_status(self):
        """Get router status (for debugging)."""
        with self.lock:
            return {
                "active_agents": list(self.agent_queues.keys()),
                "total_messages": len(self.message_log),
                "active_streams": {
                    agent_id: len(streams)
                    for agent_id, streams in self.active_streams.items()
                },
                "queue_sizes": {
                    agent_id: queue.qsize()
                    for agent_id, queue in self.agent_queues.items()
                },
            }

    def get_recent_messages(self, limit=10):
        """Get recent messages (for debugging)."""
        with self.lock:
            return self.message_log[-limit:]


def serve():
    """Start the router service."""
    config_watcher = start_reference_service_config_watcher("router")
    config = config_watcher.config

    configure_reference_service_logging(
        service_name="router-service",
        level=os.getenv("REFERENCE_LOG_LEVEL", "INFO"),
    )

    # Create gRPC server
    server = grpc.server(
        futures.ThreadPoolExecutor(max_workers=10),
        interceptors=list(build_auth_interceptors(service_name="router")),
    )

    # Add our service to the server
    router_service = RouterServiceImpl(
        config_watcher=config_watcher,
        db_path=config.router_db_path,
        max_queue_size=config.router_max_queue_size,
        shutdown_manager=ReferenceServiceShutdownCoordinator(
            "router-service",
            grace_period_seconds=config.shutdown_grace_seconds,
        ),
    )
    router_pb2_grpc.add_RouterServiceServicer_to_server(router_service, server)
    try:
        router_service_name = router_pb2.DESCRIPTOR.services_by_name["RouterService"].full_name
    except Exception:
        router_service_name = "sw4rm.router.RouterService"
    add_reference_health_service(server, service_names=(router_service_name,))

    # Listen on configurable port (default 50051)
    port = int(config.router_port)
    listen_addr = f'0.0.0.0:{port}'
    bound_port = server.add_insecure_port(listen_addr)
    if bound_port == 0:
        raise RuntimeError(f"Failed to bind Router service to {listen_addr}. Is the port in use?")

    # Start server
    server.start()
    logging.info(f"Router service started on {listen_addr}")

    # Handle graceful shutdown
    def signal_handler(signum, frame):
        logging.info(f"Received signal {signum}, shutting down...")
        status = router_service.get_status()
        logging.info(f"Final state: {status}")
        recent_messages = router_service.get_recent_messages(5)
        for msg in recent_messages:
            logging.info(f"  Recent message: {msg['message_id']} from {msg['producer_id']}")
        router_service._shutdown_manager.stop_server(
            server,
            logger=logging.getLogger("router.service"),
            pre_stop_hook=lambda: logging.info("Router service entering graceful drain mode"),
        )

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # Keep server running
    try:
        server.wait_for_termination()
    except KeyboardInterrupt:
        logging.info("Shutting down...")
        router_service._shutdown_manager.stop_server(
            server,
            logger=logging.getLogger("router.service"),
            pre_stop_hook=lambda: logging.info("Router service entering graceful drain mode"),
        )
    finally:
        config_watcher.close()


if __name__ == '__main__':
    serve()
