#!/usr/bin/env python3
"""
Advanced agent example demonstrating all SW4RM SDK features.

This example shows:
- Persistent activity buffer with cross-restart reconciliation
- Worktree binding with policy hooks and persistent state
- Automatic ACK lifecycle management
- Message processing with handlers
- Graceful shutdown with state preservation

Prerequisites:
  - Generate protobuf stubs: `make protos`
  - Install deps: `python -m pip install -e ".[dev]"`

Run:
  python examples/advanced_agent.py --agent-id advanced-1 --name AdvancedAgent \
    --router localhost:50051 --registry localhost:50052 \
    --data-dir ./agent_data
"""
from __future__ import annotations

import argparse
import json
import os
import signal
import sys
import time
from pathlib import Path
from typing import Optional, Dict, Any

import grpc

from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.activity_buffer import PersistentActivityBuffer
from sw4rm.persistence import JSONFilePersistence
from sw4rm.worktree_state import PersistentWorktreeState, DefaultWorktreePolicy, WorktreePersistence
from sw4rm.ack_integration import ACKLifecycleManager, MessageProcessor
from sw4rm.envelope import build_envelope
from sw4rm import constants as C


class CustomWorktreePolicy(DefaultWorktreePolicy):
    """Custom worktree policy with additional validation."""
    
    def __init__(self, allowed_repos: list[str] = None):
        super().__init__(allow_rebinding=True, max_binding_age_hours=24)
        self.allowed_repos = allowed_repos or []
    
    def before_bind(self, repo_id: str, worktree_id: str, current_binding) -> bool:
        # Check allowed repositories
        if self.allowed_repos and repo_id not in self.allowed_repos:
            print(f"[Policy] Rejected binding to unauthorized repo: {repo_id}")
            return False
        
        # Call parent validation
        return super().before_bind(repo_id, worktree_id, current_binding)
    
    def after_bind(self, binding) -> None:
        print(f"[Policy] Successfully bound to {binding.repo_id}/{binding.worktree_id}")
        print(f"[Policy] Metadata: {binding.metadata}")


class AdvancedAgent:
    """Advanced agent with full SDK feature demonstration."""
    
    def __init__(self, agent_id: str, name: str, data_dir: Path):
        self.agent_id = agent_id
        self.name = name
        self.data_dir = data_dir
        self.stop_requested = False
        
        # Ensure data directory exists
        self.data_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize persistence components
        activity_persistence = JSONFilePersistence(str(data_dir / "activity.json"))
        self.activity_buffer = PersistentActivityBuffer(
            max_items=1000, 
            persistence=activity_persistence
        )
        
        worktree_persistence = WorktreePersistence(str(data_dir / "worktree.json"))
        self.worktree_state = PersistentWorktreeState(
            persistence=worktree_persistence,
            policy=CustomWorktreePolicy(allowed_repos=["main-repo", "test-repo"])
        )
        
        # These will be initialized in connect()
        self.registry: Optional[RegistryClient] = None
        self.router: Optional[RouterClient] = None
        self.ack_manager: Optional[ACKLifecycleManager] = None
        self.processor: Optional[MessageProcessor] = None
        
    def connect(self, router_addr: str, registry_addr: str) -> None:
        """Connect to SW4RM services."""
        print(f"[Connect] Router: {router_addr}, Registry: {registry_addr}")
        
        # Create gRPC channels
        router_ch = grpc.insecure_channel(router_addr)
        registry_ch = grpc.insecure_channel(registry_addr)
        
        # Initialize clients
        self.registry = RegistryClient(registry_ch)
        self.router = RouterClient(router_ch)
        
        # Initialize ACK lifecycle management
        self.ack_manager = ACKLifecycleManager(
            router_client=self.router,
            activity_buffer=self.activity_buffer,
            agent_id=self.agent_id,
            auto_ack=True,
            ack_timeout_seconds=30
        )
        
        # Initialize message processor
        self.processor = MessageProcessor(self.ack_manager)
        self._register_message_handlers()
        
    def _register_message_handlers(self) -> None:
        """Register handlers for different message types."""
        self.processor.register_handler(C.DATA, self._handle_data)
        self.processor.register_handler(C.CONTROL, self._handle_control)
        self.processor.register_handler(C.WORKTREE_CONTROL, self._handle_worktree)
        self.processor.set_default_handler(self._handle_unknown)
    
    def _handle_data(self, envelope: Dict[str, Any]) -> str:
        """Handle DATA messages - echo back with processing info."""
        message_id = envelope.get("message_id", "")
        payload = envelope.get("payload", b"")
        
        print(f"[Data] Processing message {message_id}, payload size: {len(payload)}")
        
        # Create response payload
        response_data = {
            "original_id": message_id,
            "processed_at": int(time.time()),
            "agent_id": self.agent_id,
            "payload_size": len(payload),
            "worktree": self.worktree_state.status()
        }
        
        # Send echo response
        response_env = build_envelope(
            producer_id=self.agent_id,
            message_type=C.DATA,
            content_type="application/json",
            payload=json.dumps(response_data).encode('utf-8')
        )
        
        result = self.ack_manager.send_message_with_ack(response_env)
        print(f"[Data] Echo sent: {result.success}, accepted: {result.accepted}")
        
        return "data_processed"
    
    def _handle_control(self, envelope: Dict[str, Any]) -> str:
        """Handle CONTROL messages."""
        message_id = envelope.get("message_id", "")
        payload = envelope.get("payload", b"")
        
        try:
            control_data = json.loads(payload.decode('utf-8'))
            command = control_data.get("command", "")
            
            print(f"[Control] Command: {command}")
            
            if command == "status":
                return self._handle_status_request()
            elif command == "reconcile":
                return self._handle_reconcile_request()
            elif command == "bind_worktree":
                return self._handle_bind_worktree(control_data)
            else:
                print(f"[Control] Unknown command: {command}")
                return "unknown_command"
                
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            print(f"[Control] Invalid control message: {e}")
            return "invalid_control"
    
    def _handle_worktree(self, envelope: Dict[str, Any]) -> str:
        """Handle WORKTREE_CONTROL messages."""
        message_id = envelope.get("message_id", "")
        payload = envelope.get("payload", b"")
        
        try:
            wt_data = json.loads(payload.decode('utf-8'))
            action = wt_data.get("action", "")
            
            if action == "bind":
                repo_id = wt_data.get("repo_id", "")
                worktree_id = wt_data.get("worktree_id", "")
                metadata = wt_data.get("metadata", {})
                
                success = self.worktree_state.bind(repo_id, worktree_id, metadata)
                return "bind_success" if success else "bind_failed"
                
            elif action == "unbind":
                success = self.worktree_state.unbind()
                return "unbind_success" if success else "unbind_failed"
                
            elif action == "status":
                status = self.worktree_state.status()
                print(f"[Worktree] Status: {status}")
                return "status_provided"
                
            else:
                return "unknown_worktree_action"
                
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            print(f"[Worktree] Invalid worktree message: {e}")
            return "invalid_worktree"
    
    def _handle_unknown(self, envelope: Dict[str, Any]) -> str:
        """Handle unknown message types."""
        message_type = envelope.get("message_type", "unknown")
        print(f"[Unknown] Received message type: {message_type}")
        return "unknown_handled"
    
    def _handle_status_request(self) -> str:
        """Handle status request - show agent state."""
        status = {
            "agent_id": self.agent_id,
            "worktree": self.worktree_state.status(),
            "activity_buffer": {
                "total_records": len(self.activity_buffer._by_id),
                "unacked": len(self.activity_buffer.unacked()),
                "recent": len(self.activity_buffer.recent(10))
            },
            "uptime": time.time()
        }
        print(f"[Status] {json.dumps(status, indent=2)}")
        return "status_provided"
    
    def _handle_reconcile_request(self) -> str:
        """Handle reconcile request - check for stale ACKs."""
        unacked_outgoing = self.ack_manager.get_unacked_outgoing()
        pending_acks = self.ack_manager.get_pending_acks()
        stale_records = self.ack_manager.reconcile_acks()
        
        print(f"[Reconcile] Unacked outgoing: {len(unacked_outgoing)}")
        print(f"[Reconcile] Pending ACKs: {len(pending_acks)}")
        print(f"[Reconcile] Stale records: {len(stale_records)}")
        
        for record in stale_records[:5]:  # Show first 5 stale records
            print(f"[Reconcile] Stale: {record.message_id} ({record.direction}) age: {int(time.time() * 1000) - record.ts_ms}ms")
        
        return "reconcile_completed"
    
    def _handle_bind_worktree(self, control_data: Dict[str, Any]) -> str:
        """Handle worktree bind command."""
        repo_id = control_data.get("repo_id", "")
        worktree_id = control_data.get("worktree_id", "") 
        metadata = control_data.get("metadata", {})
        
        success = self.worktree_state.bind(repo_id, worktree_id, metadata)
        return "bind_success" if success else "bind_failed"
    
    def register(self) -> bool:
        """Register this agent with the registry."""
        descriptor = {
            "agent_id": self.agent_id,
            "name": self.name,
            "description": "Advanced agent demonstrating full SW4RM SDK capabilities",
            "capabilities": ["echo", "control", "worktree", "persistence", "ack_lifecycle"],
            "communication_class": C.STANDARD,
            "modalities_supported": ["application/json", "text/plain"],
            "reasoning_connectors": []
        }
        
        try:
            response = self.registry.register(descriptor)
            accepted = getattr(response, 'accepted', False)
            reason = getattr(response, 'reason', '')
            
            print(f"[Register] Accepted: {accepted}, Reason: {reason}")
            return accepted
            
        except Exception as e:
            print(f"[Register] Failed: {e}")
            return False
    
    def run_message_loop(self) -> None:
        """Main message processing loop."""
        print(f"[Loop] Starting message loop for {self.agent_id}")
        
        try:
            for item in self.router.stream_incoming(self.agent_id):
                if self.stop_requested:
                    break
                    
                # Extract envelope from stream item
                envelope_msg = getattr(item, "msg", item)
                
                # Convert protobuf message to dict
                envelope = {
                    "message_id": getattr(envelope_msg, "message_id", ""),
                    "message_type": getattr(envelope_msg, "message_type", 0),
                    "content_type": getattr(envelope_msg, "content_type", ""),
                    "payload": getattr(envelope_msg, "payload", b""),
                    "producer_id": getattr(envelope_msg, "producer_id", ""),
                    "correlation_id": getattr(envelope_msg, "correlation_id", ""),
                    "sequence_number": getattr(envelope_msg, "sequence_number", 0),
                }
                
                print(f"[Loop] Received: {envelope['message_type']} from {envelope['producer_id']}")
                
                # Process with automatic ACK handling
                result = self.processor.process_message(envelope)
                print(f"[Loop] Processed: {result.success}")
                
        except KeyboardInterrupt:
            print("[Loop] Interrupted by user")
        except Exception as e:
            print(f"[Loop] Error: {e}")
        finally:
            print("[Loop] Message loop ended")
    
    def shutdown(self) -> None:
        """Graceful shutdown with state preservation."""
        print("[Shutdown] Starting graceful shutdown...")
        
        self.stop_requested = True
        
        # Flush all persistent state
        print("[Shutdown] Saving activity buffer...")
        self.activity_buffer.flush()
        
        # Deregister from registry
        if self.registry:
            try:
                print("[Shutdown] Deregistering agent...")
                self.registry.deregister(self.agent_id, reason="graceful_shutdown")
            except Exception as e:
                print(f"[Shutdown] Deregister failed: {e}")
        
        # Show final status
        unacked = len(self.activity_buffer.unacked())
        total = len(self.activity_buffer._by_id)
        worktree_status = self.worktree_state.status()
        
        print(f"[Shutdown] Final state:")
        print(f"  Activity buffer: {total} total, {unacked} unacked")
        print(f"  Worktree: {worktree_status}")
        print("[Shutdown] Complete")


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Advanced SW4RM SDK example")
    parser.add_argument("--agent-id", default="advanced-1", help="Agent ID")
    parser.add_argument("--name", default="AdvancedAgent", help="Agent name")
    parser.add_argument("--router", default="localhost:50051", help="Router address")
    parser.add_argument("--registry", default="localhost:50052", help="Registry address")
    parser.add_argument("--data-dir", default="./agent_data", help="Data directory for persistence")
    
    return parser.parse_args()


def main() -> int:
    """Main entry point."""
    args = parse_args()
    
    # Create agent
    agent = AdvancedAgent(
        agent_id=args.agent_id,
        name=args.name,
        data_dir=Path(args.data_dir)
    )
    
    # Set up signal handlers
    def signal_handler(signum, frame):
        print(f"\n[Signal] Received signal {signum}")
        agent.shutdown()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Connect and register
    agent.connect(args.router, args.registry)
    
    if not agent.register():
        print("[Main] Registration failed, exiting")
        return 1
    
    # Show initial state
    print(f"[Main] Agent {args.agent_id} ready")
    print(f"[Main] Data directory: {args.data_dir}")
    print(f"[Main] Worktree state: {agent.worktree_state.status()}")
    
    # Start processing messages
    try:
        agent.run_message_loop()
    finally:
        agent.shutdown()
    
    return 0


if __name__ == "__main__":
    sys.exit(main())