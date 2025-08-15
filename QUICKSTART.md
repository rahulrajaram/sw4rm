# SW4RM Agentic Protocol — Quickstart (Python SDK)

Get up and running with the SW4RM Agentic Protocol using the reference Python SDK. This guide walks you through creating your first production-ready agent with persistent state.

> Note: Higher-level ACK lifecycle helpers are still maturing; behavior may differ by router implementation. The examples here focus on concepts and may require adaptation.

## Step 1: Installation

Install the SDK in development mode to get all tools and dependencies:

```bash
# Clone or navigate to the SW4RM repository
cd /path/to/sw4rm-sdk

# Install with development dependencies
python -m pip install -e ".[dev]"

# Generate protocol buffer stubs
make protos
```

Verify installation:
```bash
python -c "import sw4rm; print('SW4RM protocol SDK installed successfully')"
```

Tip: running examples without installing the package
```bash
# Run example modules by pointing PYTHONPATH at the SDK source tree
PYTHONPATH=sdks/py_sdk python examples/echo_agent.py
```

## Step 2: Basic Agent Setup

Create your first agent (`my_first_agent.py`):

```python
#!/usr/bin/env python3
"""
My first SW4RM — demonstrates core protocol + SDK features.
"""
import grpc
import json
import signal
import sys
from pathlib import Path

from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.activity_buffer import PersistentActivityBuffer
from sw4rm.ack_integration import ACKLifecycleManager, MessageProcessor
from sw4rm import constants as C

class MyFirstAgent:
    def __init__(self, agent_id: str):
        self.agent_id = agent_id
        self.stop_requested = False
        
        # Initialize persistent activity buffer
        self.buffer = PersistentActivityBuffer(max_items=500)
        
    def connect(self, router_addr: str, registry_addr: str):
        """Connect to SW4RM services."""
        print(f"Connecting to router: {router_addr}, registry: {registry_addr}")
        
        # Create gRPC connections
        router_ch = grpc.insecure_channel(router_addr)
        registry_ch = grpc.insecure_channel(registry_addr)
        
        # Initialize clients
        self.registry = RegistryClient(registry_ch)
        self.router = RouterClient(router_ch)
        
        # Set up ACK lifecycle management
        self.ack_manager = ACKLifecycleManager(
            router_client=self.router,
            activity_buffer=self.buffer,
            agent_id=self.agent_id
        )
        
        # Set up message processor
        self.processor = MessageProcessor(self.ack_manager)
        self.processor.register_handler(C.DATA, self.handle_data)
        self.processor.set_default_handler(self.handle_unknown)
    
    def handle_data(self, envelope):
        """Handle DATA messages."""
        message_id = envelope.get("message_id", "")
        payload = envelope.get("payload", b"")
        
        print(f"📨 Processing DATA message {message_id}")
        print(f"   Payload size: {len(payload)} bytes")
        
        # Echo back with processing info
        response = {
            "original_id": message_id,
            "agent_id": self.agent_id,
            "status": "processed",
            "payload_size": len(payload)
        }
        
        # Send response using ACK manager
        from sw4rm.envelope import build_envelope
        response_env = build_envelope(
            producer_id=self.agent_id,
            message_type=C.DATA,
            content_type="application/json", 
            payload=json.dumps(response).encode()
        )
        
        result = self.ack_manager.send_message_with_ack(response_env)
        print(f"✅ Response sent: {result.success}")
        
        return "data_processed"
    
    def handle_unknown(self, envelope):
        """Handle unknown message types."""
        msg_type = envelope.get("message_type", "unknown")
        print(f"❓ Unknown message type: {msg_type}")
        return "unknown_handled"
    
    def register(self):
        """Register with the registry service."""
        descriptor = {
            "agent_id": self.agent_id,
            "name": "MyFirstAgent",
            "description": "Learning the SW4RM SDK",
            "capabilities": ["echo", "processing"],
            "communication_class": C.STANDARD,
            "modalities_supported": ["application/json"],
        }
        
        try:
            response = self.registry.register(descriptor)
            accepted = getattr(response, 'accepted', False)
            reason = getattr(response, 'reason', '')
            
            if accepted:
                print(f"✅ Registered successfully: {reason}")
            else:
                print(f"❌ Registration failed: {reason}")
            
            return accepted
        except Exception as e:
            print(f"❌ Registration error: {e}")
            return False
    
    def run(self):
        """Main message processing loop."""
        print(f"🚀 Starting message loop for {self.agent_id}")
        
        try:
            for item in self.router.stream_incoming(self.agent_id):
                if self.stop_requested:
                    break
                
                # Convert protobuf message to dict
                envelope_msg = getattr(item, "msg", item)
                envelope = {
                    "message_id": getattr(envelope_msg, "message_id", ""),
                    "message_type": getattr(envelope_msg, "message_type", 0),
                    "content_type": getattr(envelope_msg, "content_type", ""),
                    "payload": getattr(envelope_msg, "payload", b""),
                    "producer_id": getattr(envelope_msg, "producer_id", ""),
                }
                
                # Process with automatic ACK handling
                result = self.processor.process_message(envelope)
                print(f"📋 Processed: {result.success}")
                
        except KeyboardInterrupt:
            print("🛑 Stopped by user")
        except Exception as e:
            print(f"❌ Error in message loop: {e}")
    
    def shutdown(self):
        """Clean shutdown."""
        print("🔄 Shutting down...")
        self.stop_requested = True
        
        # Save state
        self.buffer.flush()
        
        # Deregister
        try:
            self.registry.deregister(self.agent_id, reason="shutdown")
            print("✅ Deregistered successfully")
        except Exception as e:
            print(f"⚠️  Deregister failed: {e}")
        
        # Show final stats
        total = len(self.buffer._by_id)
        unacked = len(self.buffer.unacked())
        print(f"📊 Final stats: {total} total messages, {unacked} unacked")


def main():
    agent = MyFirstAgent("quickstart-agent")
    
    # Handle shutdown signals
    def signal_handler(signum, frame):
        print(f"\\n📡 Received signal {signum}")
        agent.shutdown()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Connect and run
    # Use centralized defaults (overridable via env vars)
    agent.connect(C.get_default_router_addr(), C.get_default_registry_addr())
    
    if agent.register():
        agent.run()
    else:
        print("❌ Failed to register, exiting")
    
    agent.shutdown()

if __name__ == "__main__":
    main()
```

## Step 3: Test Your Agent

Create a simple test script (`test_my_agent.py`):

```python
#!/usr/bin/env python3
"""Test script for my first agent."""
import grpc
import json
from sw4rm.clients.router import RouterClient
from sw4rm.envelope import build_envelope
from sw4rm import constants as C

def test_agent():
    # Connect to router
    channel = grpc.insecure_channel("localhost:50051")
    router = RouterClient(channel)
    
    # Send test message
    test_data = {"message": "Hello from test!", "timestamp": 123456}
    envelope = build_envelope(
        producer_id="test-client",
        message_type=C.DATA,
        content_type="application/json",
        payload=json.dumps(test_data).encode()
    )
    
    # Send message
    response = router.send_message(envelope)
    accepted = getattr(response, 'accepted', False)
    reason = getattr(response, 'reason', '')
    
    print(f"Message sent: accepted={accepted}, reason={reason}")

if __name__ == "__main__":
    test_agent()
```

## Step 4: Run Your Agent

**Terminal 1 - Start your agent:**
```bash
python my_first_agent.py
```

You should see:
```
Connecting to router: localhost:50051, registry: localhost:50052
✅ Registered successfully: 
🚀 Starting message loop for quickstart-agent
```

**Terminal 2 - Test your agent:**
```bash
python test_my_agent.py
```

**Back in Terminal 1**, you should see your agent processing the message:
```
📨 Processing DATA message msg-123
   Payload size: 45 bytes
✅ Response sent: True
📋 Processed: True
```

## Step 5: Add Persistence

Let's enhance your agent with persistent state that survives restarts.

Update `my_first_agent.py` to add worktree management:

```python
# Add this import at the top
from sw4rm.worktree_state import PersistentWorktreeState

# In __init__, add:
def __init__(self, agent_id: str, data_dir: str = "./agent_data"):
    self.agent_id = agent_id
    self.stop_requested = False
    self.data_dir = Path(data_dir)
    self.data_dir.mkdir(exist_ok=True)
    
    # Initialize persistent components
    from sw4rm.persistence import JSONFilePersistence
    activity_persistence = JSONFilePersistence(str(self.data_dir / "activity.json"))
    self.buffer = PersistentActivityBuffer(
        max_items=500,
        persistence=activity_persistence
    )
    
    # Add worktree management
    from sw4rm.worktree_policies import WorktreePersistence
    worktree_persistence = WorktreePersistence(str(self.data_dir / "worktree.json"))
    self.worktree = PersistentWorktreeState(persistence=worktree_persistence)

# Add new handler for control messages
def handle_control(self, envelope):
    """Handle CONTROL messages."""
    try:
        payload = envelope.get("payload", b"")
        command_data = json.loads(payload.decode())
        command = command_data.get("command", "")
        
        if command == "status":
            status = {
                "agent_id": self.agent_id,
                "worktree": self.worktree.status(),
                "activity_stats": {
                    "total": len(self.buffer._by_id),
                    "unacked": len(self.buffer.unacked())
                }
            }
            print(f"📊 Status: {json.dumps(status, indent=2)}")
            return "status_provided"
            
        elif command == "bind_worktree":
            repo_id = command_data.get("repo_id", "")
            worktree_id = command_data.get("worktree_id", "")
            success = self.worktree.bind(repo_id, worktree_id)
            print(f"🔗 Worktree bind: {success}")
            return "bind_attempted"
            
    except Exception as e:
        print(f"❌ Control command error: {e}")
    
    return "control_handled"

# Register the new handler in connect():
self.processor.register_handler(C.CONTROL, self.handle_control)
```

## Step 6: Test Persistence

Create an enhanced test script (`test_persistence.py`):

```python
#!/usr/bin/env python3
"""Test persistence features."""
import grpc
import json
import time
from sw4rm.clients.router import RouterClient
from sw4rm.envelope import build_envelope
from sw4rm import constants as C

def send_control_command(router, command_data):
    """Send a CONTROL message."""
    envelope = build_envelope(
        producer_id="test-client",
        message_type=C.CONTROL,
        content_type="application/json",
        payload=json.dumps(command_data).encode()
    )
    
    response = router.send_message(envelope)
    print(f"Control '{command_data.get('command')}': {getattr(response, 'accepted', False)}")

def main():
    channel = grpc.insecure_channel("localhost:50051")
    router = RouterClient(channel)
    
    print("🧪 Testing persistence features...")
    
    # Test 1: Send data message
    test_data = {"test": "persistence", "timestamp": int(time.time())}
    envelope = build_envelope(
        producer_id="test-client",
        message_type=C.DATA,
        payload=json.dumps(test_data).encode()
    )
    router.send_message(envelope)
    print("✅ Sent data message")
    
    time.sleep(1)
    
    # Test 2: Request status
    send_control_command(router, {"command": "status"})
    
    time.sleep(1)
    
    # Test 3: Bind worktree
    send_control_command(router, {
        "command": "bind_worktree",
        "repo_id": "test-repo",
        "worktree_id": "main-branch"
    })
    
    time.sleep(1)
    
    # Test 4: Check status again
    send_control_command(router, {"command": "status"})
    
    print("🎉 Test completed! Check agent_data/ directory for persistent files")

if __name__ == "__main__":
    main()
```

Run the test:
```bash
python test_persistence.py
```

Check the persistent files:
```bash
ls agent_data/
cat agent_data/activity.json
cat agent_data/worktree.json
```

## Step 7: Test Restart Recovery

1. **Stop your agent** (Ctrl+C in Terminal 1)
2. **Restart it:**
   ```bash
   python my_first_agent.py
   ```
3. **Notice the recovery logs:**
   ```
   [ActivityBuffer] Loaded 3 records from persistence
   [Worktree] Restored binding to test-repo/main-branch
   ```

Your agent now has persistent state that survives restarts! 🎉

## Next Steps

Congratulations! You've built a production-ready agent with:
- ✅ Message processing with automatic ACKs
- ✅ Persistent activity buffer
- ✅ Worktree state management
- ✅ Error handling and graceful shutdown
- ✅ Cross-restart state recovery

### Advanced Features to Explore

1. **Custom Worktree Policies**: Implement validation rules for repository access
2. **Message Handler Patterns**: Build sophisticated routing based on message content
3. **Reconciliation**: Handle network failures and message retry scenarios
4. **Multiple Persistence Backends**: Use databases instead of JSON files
5. **Monitoring and Metrics**: Add observability to your agents

### Learn More

- Check out `examples/advanced_agent.py` for more sophisticated patterns
- Read the full API documentation in `README.md`
- Explore `examples/README.md` for detailed feature explanations

### Common Issues

**"Protobuf stubs not generated"**
```bash
make protos
```

**"Connection refused"**
- Ensure SW4RM services are running on the expected ports
- Or modify the connection addresses in your code

**"Permission denied on agent_data/"**
```bash
mkdir -p agent_data
chmod 755 agent_data
```

Happy agent building! 🤖

## Config & Env Vars

- `SW4RM_ROUTER_ADDR`: router address (default `localhost:50051`)
- `SW4RM_REGISTRY_ADDR`: registry address (default `localhost:50052`)

You can override CLI defaults by exporting these before running your agent:
```bash
export SW4RM_ROUTER_ADDR=router.example.com:50051
export SW4RM_REGISTRY_ADDR=registry.example.com:50052
```


## Bee Shell and TUI

### New Slash Commands and Shortcuts

- `/from <agent_id>`: Set default agent (affects scheduler commands and events).
- `/use <negotiation_id>`: Select active negotiation.
- `/bind <lane>` or `/switch <lane>`: Set the current scheduler lane.
- `/submit <task_id> [priority=N] [scope=<lane>] [json <payload>] [ct=<type>] [agent=<id>]`: Submit a task via scheduler.
- `/preempt <task_id> [reason=txt] [agent=<id>]`: Request preemption for a task.
- `/events on|off` (non-TUI): Tail incoming events for the selected agent.
- `/history [N]` (non-TUI): Show the last N commands (persisted across sessions).
- `/search <term>` (non-TUI): Search recent history.

TUI enhancements:
- Status line shows `model:- lane:<lane> events:on|off from:<agent> cost:—`.
- Ctrl-R: Toggle incremental history search; type to filter, Enter to accept.

History is persisted to `BEE_HOME/history.jsonl` (rotated); content may include sensitive commands. Ensure `BEE_HOME` is secured.
