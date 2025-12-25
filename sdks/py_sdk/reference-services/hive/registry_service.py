#!/usr/bin/env python3
"""
Minimal Registry Service Implementation for SW4RM Protocol
Provides basic agent registration, heartbeat, and deregistration functionality.
"""

import asyncio
import os
import logging
import signal
import sys
import threading
import time
from concurrent import futures
from typing import Dict, Optional

import grpc

# Import the generated protobuf modules
# Prefer stubs from the installed SDK; fallback to local copies if unavailable
try:
    from sw4rm.protos import registry_pb2, registry_pb2_grpc, common_pb2
except Exception:  # SDK not installed; use local generated stubs
    import registry_pb2, registry_pb2_grpc, common_pb2


class RegistryServiceImpl(registry_pb2_grpc.RegistryServiceServicer):
    """Simple in-memory registry service implementation."""
    
    def __init__(self):
        self.agents: Dict[str, Dict] = {}
        self.agent_heartbeats: Dict[str, float] = {}
        self.lock = threading.RLock()
        # Agents that MUST NOT be removed by cleanup (e.g., scheduler)
        self.protected_agents = {"scheduler"}
        
        # Start heartbeat cleanup task
        self.cleanup_thread = threading.Thread(target=self._heartbeat_cleanup, daemon=True)
        self.cleanup_thread.start()
        
        logging.info("Registry service initialized")
    
    def RegisterAgent(self, request, context):
        """Register a new agent."""
        agent = request.agent
        agent_id = agent.agent_id
        
        with self.lock:
            if agent_id in self.agents:
                logging.warning(f"Agent {agent_id} already registered, updating")
            
            # Store agent information
            self.agents[agent_id] = {
                'agent_id': agent_id,
                'name': agent.name,
                'description': agent.description,
                'capabilities': list(agent.capabilities),
                'communication_class': agent.communication_class,
                'modalities_supported': list(agent.modalities_supported),
                'reasoning_connectors': list(agent.reasoning_connectors),
                'registered_at': time.time(),
                'last_heartbeat': time.time()
            }
            
            # Initialize heartbeat tracking
            self.agent_heartbeats[agent_id] = time.time()
            
            logging.info(f"Registered agent: {agent_id} ({agent.name})")
            
            return registry_pb2.RegisterAgentResponse(
                accepted=True,
                reason=f"Agent {agent_id} registered successfully"
            )
    
    def Heartbeat(self, request, context):
        """Process agent heartbeat."""
        agent_id = request.agent_id
        state = request.state
        health = dict(request.health)
        
        with self.lock:
            if agent_id not in self.agents:
                logging.warning(f"Heartbeat from unregistered agent: {agent_id}")
                return registry_pb2.HeartbeatResponse(ok=False)
            
            # Update heartbeat timestamp
            self.agent_heartbeats[agent_id] = time.time()
            
            # Update agent state if provided
            if 'state' not in self.agents[agent_id]:
                self.agents[agent_id]['state'] = state
                self.agents[agent_id]['health'] = health
            else:
                self.agents[agent_id]['state'] = state
                self.agents[agent_id]['health'].update(health)
            
            self.agents[agent_id]['last_heartbeat'] = time.time()
            
            logging.debug(f"Heartbeat from {agent_id}, state: {state}")
            
            return registry_pb2.HeartbeatResponse(ok=True)
    
    def DeregisterAgent(self, request, context):
        """Deregister an agent."""
        agent_id = request.agent_id
        reason = request.reason
        
        with self.lock:
            if agent_id in self.agents:
                del self.agents[agent_id]
                if agent_id in self.agent_heartbeats:
                    del self.agent_heartbeats[agent_id]
                
                logging.info(f"Deregistered agent: {agent_id}, reason: {reason}")
                return registry_pb2.DeregisterAgentResponse(ok=True)
            else:
                logging.warning(f"Attempted to deregister unknown agent: {agent_id}")
                return registry_pb2.DeregisterAgentResponse(ok=False)
    
    def _heartbeat_cleanup(self):
        """Remove agents that haven't sent heartbeats in a while."""
        HEARTBEAT_TIMEOUT = 300  # 5 minutes
        
        while True:
            try:
                time.sleep(60)  # Check every minute
                current_time = time.time()
                
                with self.lock:
                    expired_agents = []
                    for agent_id, last_heartbeat in self.agent_heartbeats.items():
                        if agent_id in self.protected_agents:
                            continue
                        if current_time - last_heartbeat > HEARTBEAT_TIMEOUT:
                            expired_agents.append(agent_id)
                    
                    for agent_id in expired_agents:
                        if agent_id in self.agents:
                            del self.agents[agent_id]
                        del self.agent_heartbeats[agent_id]
                        logging.info(f"Removed expired agent: {agent_id}")
                        
            except Exception as e:
                logging.error(f"Error in heartbeat cleanup: {e}")
    
    def get_registered_agents(self):
        """Get list of currently registered agents (for debugging)."""
        with self.lock:
            return dict(self.agents)


def serve():
    """Start the registry service."""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s'
    )
    
    # Create gRPC server
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    
    # Add our service to the server
    registry_service = RegistryServiceImpl()
    registry_pb2_grpc.add_RegistryServiceServicer_to_server(registry_service, server)
    
    # Listen on configurable port (default 50052)
    port = int(os.getenv('REGISTRY_PORT', '50052'))
    listen_addr = f'0.0.0.0:{port}'
    bound_port = server.add_insecure_port(listen_addr)
    if bound_port == 0:
        raise RuntimeError(f"Failed to bind Registry service to {listen_addr}. Is the port in use?")
    
    # Start server
    server.start()
    logging.info(f"Registry service started on {listen_addr}")
    
    # Handle graceful shutdown
    def signal_handler(signum, frame):
        logging.info(f"Received signal {signum}, shutting down...")
        agents = registry_service.get_registered_agents()
        logging.info(f"Final state: {len(agents)} registered agents")
        for agent_id, info in agents.items():
            logging.info(f"  - {agent_id}: {info.get('name', 'Unknown')}")
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
