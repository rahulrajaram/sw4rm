#!/usr/bin/env python3
"""
Test client for demonstrating agent interactions.

This script sends various message types to test the advanced_agent example,
showing how different SDK features work in practice.

Prerequisites:
  - Generate protobuf stubs: `make protos`
  - Install deps: `python -m pip install -e ".[dev]"`
  - Have advanced_agent.py running

Usage:
  python examples/test_client.py --router localhost:50051 --target-agent advanced-1
"""
from __future__ import annotations

import argparse
import json
import time
import uuid
from typing import Dict, Any

import grpc

from sigagent.clients.router import RouterClient
from sigagent.envelope import build_envelope
from sigagent import constants as C


class TestClient:
    """Client for testing agent functionality."""
    
    def __init__(self, router_addr: str, client_id: str = None):
        self.client_id = client_id or f"test-client-{uuid.uuid4().hex[:8]}"
        self.router_addr = router_addr
        
        # Connect to router
        self.channel = grpc.insecure_channel(router_addr)
        self.router = RouterClient(self.channel)
        
        print(f"[TestClient] Connected as {self.client_id} to {router_addr}")
    
    def send_message(self, message_type: int, payload: bytes, target_agent: str = None) -> bool:
        """Send a message and return success status."""
        envelope = build_envelope(
            producer_id=self.client_id,
            message_type=message_type,
            content_type="application/json" if message_type in [C.CONTROL, C.WORKTREE_CONTROL] else "application/octet-stream",
            payload=payload,
            correlation_id=str(uuid.uuid4())
        )
        
        try:
            response = self.router.send_message(envelope)
            accepted = getattr(response, 'accepted', False)
            reason = getattr(response, 'reason', '')
            
            print(f"[Send] Type {message_type}: accepted={accepted}, reason={reason}")
            return accepted
            
        except Exception as e:
            print(f"[Send] Failed: {e}")
            return False
    
    def test_data_message(self, target_agent: str) -> None:
        """Test DATA message handling."""
        print("\n=== Testing DATA Message ===")
        
        test_data = {
            "test_type": "data_message",
            "timestamp": int(time.time()),
            "content": "Hello from test client!",
            "target_agent": target_agent
        }
        
        payload = json.dumps(test_data).encode('utf-8')
        self.send_message(C.DATA, payload, target_agent)
    
    def test_control_status(self, target_agent: str) -> None:
        """Test CONTROL message - status request."""
        print("\n=== Testing CONTROL Message (Status) ===")
        
        control_data = {
            "command": "status",
            "requested_by": self.client_id,
            "timestamp": int(time.time())
        }
        
        payload = json.dumps(control_data).encode('utf-8')
        self.send_message(C.CONTROL, payload, target_agent)
    
    def test_control_reconcile(self, target_agent: str) -> None:
        """Test CONTROL message - reconcile request."""
        print("\n=== Testing CONTROL Message (Reconcile) ===")
        
        control_data = {
            "command": "reconcile",
            "requested_by": self.client_id,
            "timestamp": int(time.time())
        }
        
        payload = json.dumps(control_data).encode('utf-8')
        self.send_message(C.CONTROL, payload, target_agent)
    
    def test_worktree_bind(self, target_agent: str) -> None:
        """Test WORKTREE_CONTROL message - bind."""
        print("\n=== Testing WORKTREE_CONTROL Message (Bind) ===")
        
        worktree_data = {
            "action": "bind",
            "repo_id": "test-repo",
            "worktree_id": "feature-branch",
            "metadata": {
                "branch": "feature-123",
                "requested_by": self.client_id,
                "timestamp": int(time.time())
            }
        }
        
        payload = json.dumps(worktree_data).encode('utf-8')
        self.send_message(C.WORKTREE_CONTROL, payload, target_agent)
    
    def test_worktree_status(self, target_agent: str) -> None:
        """Test WORKTREE_CONTROL message - status."""
        print("\n=== Testing WORKTREE_CONTROL Message (Status) ===")
        
        worktree_data = {
            "action": "status",
            "requested_by": self.client_id
        }
        
        payload = json.dumps(worktree_data).encode('utf-8')
        self.send_message(C.WORKTREE_CONTROL, payload, target_agent)
    
    def test_control_bind_worktree(self, target_agent: str) -> None:
        """Test CONTROL message - bind worktree command."""
        print("\n=== Testing CONTROL Message (Bind Worktree) ===")
        
        control_data = {
            "command": "bind_worktree",
            "repo_id": "main-repo",
            "worktree_id": "main-branch",
            "metadata": {
                "branch": "main",
                "purpose": "testing",
                "requested_by": self.client_id
            },
            "timestamp": int(time.time())
        }
        
        payload = json.dumps(control_data).encode('utf-8')
        self.send_message(C.CONTROL, payload, target_agent)
    
    def test_unknown_message_type(self, target_agent: str) -> None:
        """Test unknown message type handling."""
        print("\n=== Testing Unknown Message Type ===")
        
        test_data = {
            "test_type": "unknown_message",
            "content": "This should trigger the default handler"
        }
        
        payload = json.dumps(test_data).encode('utf-8')
        # Use an undefined message type
        self.send_message(99, payload, target_agent)
    
    def run_all_tests(self, target_agent: str, delay: float = 2.0) -> None:
        """Run all tests with delays between them."""
        print(f"[TestClient] Running all tests against agent: {target_agent}")
        print(f"[TestClient] Delay between tests: {delay}s")
        
        tests = [
            self.test_data_message,
            self.test_control_status,
            self.test_worktree_bind,
            self.test_worktree_status,
            self.test_control_bind_worktree,
            self.test_control_reconcile,
            self.test_unknown_message_type,
        ]
        
        for i, test in enumerate(tests, 1):
            print(f"\n[TestClient] Running test {i}/{len(tests)}: {test.__name__}")
            test(target_agent)
            
            if i < len(tests):  # Don't wait after the last test
                time.sleep(delay)
        
        print("\n[TestClient] All tests completed!")


def parse_args() -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(description="Test client for SigAgent examples")
    parser.add_argument("--router", default="localhost:50051", help="Router address")
    parser.add_argument("--target-agent", default="advanced-1", help="Target agent ID")
    parser.add_argument("--client-id", help="Client ID (auto-generated if not provided)")
    parser.add_argument("--delay", type=float, default=2.0, help="Delay between tests")
    parser.add_argument("--test", choices=[
        "data", "status", "reconcile", "bind", "worktree-status", 
        "control-bind", "unknown", "all"
    ], default="all", help="Specific test to run")
    
    return parser.parse_args()


def main() -> int:
    """Main entry point."""
    args = parse_args()
    
    # Create test client
    client = TestClient(args.router, args.client_id)
    
    # Run specific test or all tests
    if args.test == "all":
        client.run_all_tests(args.target_agent, args.delay)
    elif args.test == "data":
        client.test_data_message(args.target_agent)
    elif args.test == "status":
        client.test_control_status(args.target_agent)
    elif args.test == "reconcile":
        client.test_control_reconcile(args.target_agent)
    elif args.test == "bind":
        client.test_worktree_bind(args.target_agent)
    elif args.test == "worktree-status":
        client.test_worktree_status(args.target_agent)
    elif args.test == "control-bind":
        client.test_control_bind_worktree(args.target_agent)
    elif args.test == "unknown":
        client.test_unknown_message_type(args.target_agent)
    
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())