# SW4RM Agentic Protocol

SW4RM is an open agentic protocol for building message-driven agents with guaranteed delivery, persistent state, and rich observability. This repository provides the reference Python SDK that implements the protocol: clients, a lightweight runtime, and helpers for ACK lifecycle, worktree/state handling, and more.

## Install
- Runtime only:
  - `python -m pip install .`
- Dev (with codegen):
  - `python -m pip install -e ".[dev]"`
  - Generate stubs: `make protos` (requires `grpcio-tools`).

## Before You Start
- For local development, install dev deps and generate protobuf stubs:
  - `python -m pip install -e ".[dev]"`
  - `make protos`
  - Stubs are generated under `sdks/py_sdk/sw4rm/protos`.

## Core Features

- **Persistent Activity Buffer**: Track messages across restarts with reconciliation
- **Worktree Management**: Policy-driven binding with persistent state
- **ACK Lifecycle**: Automatic acknowledgment handling with router integration
- **Message Processing**: Handler-based routing with built-in error handling
- **Multiple Persistence**: JSON file and pluggable storage backends
- **Production Ready**: Comprehensive error handling, logging, and state management

## Quick Start

### Basic Agent
```python
import grpc
from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.protos import common_pb2 as common

# Connect to services
channel = grpc.insecure_channel("localhost:50051")
registry = RegistryClient(channel)
router = RouterClient(channel)

# Register agent
response = registry.register({
    "agent_id": "my-agent",
    "name": "MyAgent",
    "description": "Example agent",
    "capabilities": ["processing"],
    "communication_class": common.CommunicationClass.STANDARD,
})
```

### Advanced Agent with Persistence
```python
from sw4rm.activity_buffer import PersistentActivityBuffer
from sw4rm.worktree_state import PersistentWorktreeState
from sw4rm.ack_integration import ACKLifecycleManager, MessageProcessor

# Initialize persistent components
buffer = PersistentActivityBuffer(max_items=1000)
worktree = PersistentWorktreeState()
ack_manager = ACKLifecycleManager(router, buffer, "my-agent")
processor = MessageProcessor(ack_manager)

# Register message handlers
def handle_data(envelope):
    print(f"Processing: {envelope['message_id']}")
    return "processed"

processor.register_handler(common.MessageType.DATA, handle_data)

# Process incoming messages with automatic ACKs
for item in router.stream_incoming("my-agent"):
    envelope = convert_to_dict(item.msg)  # Convert protobuf to dict
    result = processor.process_message(envelope)
```

## API Reference

### Core Components

#### PersistentActivityBuffer
Tracks messages with persistent storage across restarts.

```python
from sw4rm.activity_buffer import PersistentActivityBuffer
from sw4rm.persistence import JSONFilePersistence

# Initialize with custom persistence
buffer = PersistentActivityBuffer(
    max_items=1000,
    persistence=JSONFilePersistence("my_activity.json")
)

# Track messages
record = buffer.record_outgoing(envelope)
buffer.ack(ack_message)

# Query state
unacked = buffer.unacked()
recent = buffer.recent(50)
needs_retry = buffer.reconcile()
```

#### PersistentWorktreeState
Manages worktree bindings with policy validation.

```python
from sw4rm.worktree_state import PersistentWorktreeState, DefaultWorktreePolicy

# Custom policy
class MyPolicy(DefaultWorktreePolicy):
    def before_bind(self, repo_id, worktree_id, current):
        return repo_id in self.allowed_repos

# Initialize with policy
worktree = PersistentWorktreeState(
    policy=MyPolicy(allowed_repos=["main-repo", "test-repo"])
)

# Manage bindings
success = worktree.bind("main-repo", "feature-branch", {"version": "1.2.3"})
current = worktree.current()
status = worktree.status()
```

#### ACKLifecycleManager
Automatic acknowledgment handling with router integration.

```python
from sw4rm.ack_integration import ACKLifecycleManager

manager = ACKLifecycleManager(
    router_client=router,
    activity_buffer=buffer,
    agent_id="my-agent",
    auto_ack=True
)

# Send with automatic ACK tracking
result = manager.send_message_with_ack(envelope)

# Manual ACK sending
manager.send_ack(message_id, stage=C.FULFILLED, note="Processed successfully")

# Reconciliation
stale_messages = manager.reconcile_acks()
```

#### MessageProcessor
Handler-based message processing with automatic ACKs.

```python
from sw4rm.ack_integration import MessageProcessor

processor = MessageProcessor(ack_manager)

# Register handlers
def handle_data(envelope):
    # Process DATA messages
    return "success"

def handle_control(envelope):
    # Process CONTROL messages  
    command = json.loads(envelope['payload'])
    return f"executed_{command['action']}"

processor.register_handler(C.DATA, handle_data)
processor.register_handler(C.CONTROL, handle_control)
processor.set_default_handler(lambda env: "unknown_message")

# Process with automatic ACK lifecycle
result = processor.process_message(envelope)
```

### Client APIs

#### RegistryClient
```python
from sw4rm.clients.registry import RegistryClient

registry = RegistryClient(grpc_channel)

# Register agent
response = registry.register({
    "agent_id": "my-agent",
    "name": "My Agent",
    "capabilities": ["processing", "analysis"],
    "communication_class": 2  # STANDARD
})

# Send heartbeat
registry.heartbeat("my-agent", state=4)  # RUNNING

# Deregister
registry.deregister("my-agent", reason="shutdown")
```

#### RouterClient
```python
from sw4rm.clients.router import RouterClient

router = RouterClient(grpc_channel)

# Send message
response = router.send_message(envelope_dict)

# Stream incoming messages
for item in router.stream_incoming("my-agent"):
    envelope = item.msg
    # Process envelope...
```

### Utility Functions

#### Envelope Building
```python
from sw4rm.envelope import build_envelope

envelope = build_envelope(
    producer_id="my-agent",
    message_type=C.DATA,
    content_type="application/json",
    payload=json.dumps(data).encode(),
    correlation_id="optional-correlation-id"
)
```

#### ACK Building
```python
from sw4rm.acks import build_ack_envelope

ack = build_ack_envelope(
    producer_id="my-agent",
    ack_for_message_id="original-msg-id",
    ack_stage=C.FULFILLED,
    note="Processing completed"
)
```

### Constants
```python
from sw4rm import constants as C

# Message types
C.DATA                    # Data message
C.CONTROL                 # Control message
C.ACKNOWLEDGEMENT        # ACK message
C.WORKTREE_CONTROL       # Worktree operation

# ACK stages
C.RECEIVED               # Message received
C.READ                   # Message read/parsed
C.FULFILLED              # Processing completed
C.REJECTED               # Processing rejected
C.FAILED                 # Processing failed

# Error codes
C.VALIDATION_ERROR       # Invalid message format
C.PERMISSION_DENIED      # Unauthorized operation
C.INTERNAL_ERROR         # Internal processing error
```

## Examples

### Complete Examples
- **Basic echo agent**: `examples/echo_agent.py` - Simple registration and message echoing
- **Advanced agent**: `examples/advanced_agent.py` - Full SDK feature demonstration
- **Test client**: `examples/test_client.py` - Client for testing agent functionality

### Running Examples
```bash
# Start advanced agent
python examples/advanced_agent.py --data-dir ./my_agent_data

# Test the agent (in another terminal)
python examples/test_client.py --target-agent advanced-1

# Run specific test
python examples/test_client.py --test data --target-agent advanced-1
```

See `examples/README.md` for detailed example documentation.

## Development

### Generate Protocol Buffers
```bash
python -m pip install -e ".[dev]"
make protos
```

### Build Package
```bash
python -m pip install build twine
python -m build
python -m twine upload dist/*
```

## Release

Use the provided Makefile targets for a reproducible release process.

- Prerequisites
  - Install dev tooling: `python -m pip install -e ".[dev]"`
  - Generate protobuf stubs: `make protos`

- Build artifacts
  - `make release` — generates stubs, verifies presence, builds wheel/sdist

- Verify artifacts
  - `make release-verify` — validates wheel/sdist metadata and runs `twine check`
  - `make smoke-wheel` — reinstalls latest wheel into the repo venv and runs `sw4rm-doctor`

- Optional: TestPyPI / PyPI
  - `make publish-test` — upload to TestPyPI (requires credentials)
  - `make publish` — upload to PyPI (requires credentials)

- Tagging
  - `make tag && make tag-push` — create and push an annotated git tag from `pyproject.toml` version

Notes
- Twine ≥ 5.x and pkginfo ≥ 1.10 are recommended to support modern `Metadata-Version` (e.g., 2.4).
- See `docs/PROGRESS_REPORT.md` for a detailed Release Checklist.

### Testing
```bash
# Run examples against mock services
python examples/advanced_agent.py --router mock:50051
python examples/test_client.py --router mock:50051
```

## Architecture

The SDK is organized into layers:

1. **Protocol Layer**: Generated protobuf stubs (`sw4rm.protos`)
2. **Client Layer**: Service clients (`sw4rm.clients`) 
3. **Runtime Layer**: Core functionality (`sw4rm.activity_buffer`, `sw4rm.worktree_state`)
4. **Integration Layer**: High-level APIs (`sw4rm.ack_integration`)
5. **Utility Layer**: Helpers (`sw4rm.envelope`, `sw4rm.acks`)

## Production Considerations

### State Management
- Activity buffer automatically prunes old records (configurable limit)
- Worktree state persists binding information across restarts
- All persistence uses atomic file writes for consistency

### Error Handling
- Network failures trigger automatic retries where appropriate
- Invalid messages are rejected with proper ACKs
- Persistence failures fall back to in-memory operation

### Performance
- Activity buffer uses efficient in-memory indexing
- Persistence operations are batched and asynchronous
- Message processing uses handler-based dispatch

### Monitoring
- Built-in logging for all major operations
- Activity buffer provides reconciliation API
- Worktree policies support custom validation hooks
