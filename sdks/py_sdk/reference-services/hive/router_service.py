#!/usr/bin/env python3
"""
Minimal Router Service Implementation for SW4RM Protocol
Provides basic message routing and streaming functionality.
"""

import asyncio
import os
import logging
import signal
import sys
import threading
import time
import uuid
from concurrent import futures
from typing import Dict, List, Set
import queue

import grpc

# Import the generated protobuf modules
# Prefer stubs from the installed SDK; fallback to local copies if unavailable
try:
    from sw4rm.protos import router_pb2, router_pb2_grpc, common_pb2
except Exception:  # SDK not installed; use local generated stubs
    import router_pb2, router_pb2_grpc, common_pb2


class RouterServiceImpl(router_pb2_grpc.RouterServiceServicer):
    """Simple in-memory router service implementation."""
    
    def __init__(self):
        self.agent_queues: Dict[str, queue.Queue] = {}
        self.active_streams: Dict[str, List] = {}
        self.message_log: List[Dict] = []
        self.lock = threading.RLock()
        
        logging.info("Router service initialized")
    
    def SendMessage(self, request, context):
        """Route a message to its destination."""
        envelope = request.msg
        message_id = envelope.message_id or str(uuid.uuid4())
        producer_id = envelope.producer_id
        
        # For demonstration, we'll route messages based on some simple logic
        # In a real implementation, you'd have more sophisticated routing
        
        with self.lock:
            # Log the message
            message_info = {
                'message_id': message_id,
                'producer_id': producer_id,
                'message_type': envelope.message_type,
                'content_type': envelope.content_type,
                'payload_size': len(envelope.payload),
                'timestamp': time.time(),
                'correlation_id': envelope.correlation_id,
                'sequence_number': envelope.sequence_number
            }
            self.message_log.append(message_info)
            
            # Simple routing: if no specific target, broadcast to all agents except sender
            target_agents = set(self.agent_queues.keys())
            if producer_id in target_agents:
                target_agents.remove(producer_id)
            
            # If this is an ACK message, route it to the original producer
            if envelope.message_type == common_pb2.MessageType.ACKNOWLEDGEMENT:
                # For ACKs, we could implement more sophisticated routing
                # For now, just accept them
                logging.info(f"Received ACK message {message_id} from {producer_id}")
                return router_pb2.SendMessageResponse(
                    accepted=True,
                    reason="ACK message accepted"
                )
            
            # Route to target agents
            delivered_count = 0
            for agent_id in target_agents:
                if agent_id in self.agent_queues:
                    try:
                        # Create a copy of the envelope for each recipient
                        stream_item = router_pb2.StreamItem(msg=envelope)
                        self.agent_queues[agent_id].put(stream_item, block=False)
                        delivered_count += 1
                        logging.debug(f"Routed message {message_id} to {agent_id}")
                    except queue.Full:
                        logging.warning(f"Queue full for agent {agent_id}, dropping message")
            
            if delivered_count > 0:
                logging.info(f"Message {message_id} delivered to {delivered_count} agents")
                return router_pb2.SendMessageResponse(
                    accepted=True,
                    reason=f"Message delivered to {delivered_count} recipients"
                )
            else:
                logging.warning(f"No recipients found for message {message_id}")
                return router_pb2.SendMessageResponse(
                    accepted=False,
                    reason="No recipients available"
                )
    
    def StreamIncoming(self, request, context):
        """Stream incoming messages for a specific agent."""
        agent_id = request.agent_id
        
        logging.info(f"Starting message stream for agent: {agent_id}")
        
        with self.lock:
            # Create a queue for this agent if it doesn't exist
            if agent_id not in self.agent_queues:
                self.agent_queues[agent_id] = queue.Queue(maxsize=100)
            
            # Track this stream
            if agent_id not in self.active_streams:
                self.active_streams[agent_id] = []
            self.active_streams[agent_id].append(context)
        
        try:
            # Stream messages to the agent
            while context.is_active():
                try:
                    # Get message from queue with timeout
                    stream_item = self.agent_queues[agent_id].get(timeout=1.0)
                    yield stream_item
                    logging.debug(f"Streamed message to {agent_id}")
                except queue.Empty:
                    # No messages, continue waiting
                    continue
                except Exception as e:
                    logging.error(f"Error streaming to {agent_id}: {e}")
                    break
                    
        except Exception as e:
            logging.error(f"Stream error for {agent_id}: {e}")
        finally:
            # Clean up when stream ends
            with self.lock:
                if agent_id in self.active_streams and context in self.active_streams[agent_id]:
                    self.active_streams[agent_id].remove(context)
                
                # If no more active streams, we could clean up the queue
                # but we'll keep it for potential reconnections
                
            logging.info(f"Stream ended for agent: {agent_id}")
    
    def get_status(self):
        """Get router status (for debugging)."""
        with self.lock:
            return {
                'active_agents': list(self.agent_queues.keys()),
                'total_messages': len(self.message_log),
                'active_streams': {
                    agent_id: len(streams) 
                    for agent_id, streams in self.active_streams.items()
                },
                'queue_sizes': {
                    agent_id: queue.qsize() 
                    for agent_id, queue in self.agent_queues.items()
                }
            }
    
    def get_recent_messages(self, limit=10):
        """Get recent messages (for debugging)."""
        with self.lock:
            return self.message_log[-limit:]


def serve():
    """Start the router service."""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s'
    )
    
    # Create gRPC server
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    
    # Add our service to the server
    router_service = RouterServiceImpl()
    router_pb2_grpc.add_RouterServiceServicer_to_server(router_service, server)
    
    # Listen on configurable port (default 50051)
    port = int(os.getenv('ROUTER_PORT', '50051'))
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
        server.stop(5)
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Keep server running
    try:
        server.wait_for_termination()
    except KeyboardInterrupt:
        logging.info("Shutting down...")
        server.stop(5)


if __name__ == '__main__':
    serve()
