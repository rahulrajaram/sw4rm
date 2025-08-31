# SW4RM Agentic Protocol

[![Python CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-python.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-python.yml)
[![Rust CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-rust.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-rust.yml)
[![JS CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-js.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-js.yml)
[![Examples: ACK Demo](https://github.com/rahulrajaram/sw4rm/actions/workflows/examples-sdk-usage.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/examples-sdk-usage.yml)

SW4RM is an open agentic protocol for building message-driven agents with guaranteed delivery, persistent state, and rich observability. This repository provides three SDKs that implement the protocol — Python, Rust, and JavaScript — including clients, lightweight runtimes, and helpers for ACK lifecycle, worktree/state handling, and more.

SDKs
- Python: `sdks/py_sdk` — see `sdks/py_sdk/README.md`
- Rust: `sdks/rust_sdk` — see `sdks/rust_sdk/README.md`
- JavaScript: `sdks/js_sdk` — see `sdks/js_sdk/README.md`

## CI Workflows

- Python CI: Python 3.12, installs `.[dev]`, runs `scripts/smoke_protos.py`, then `pytest -q sdks/py_sdk/tests`.
- Rust CI: Installs `protoc`, runs `cargo test --all --locked` in `sdks/rust_sdk`.
- JS CI: Node 20, runs `npm ci && npm run build && npm test` in `sdks/js_sdk`.
- Examples ACK Demo: Runs `examples/sdk-usage/run_all.sh ack-demo` which auto-starts local JS reference services, launches an ACK agent, and exercises router send/receive with ACKs.

Reproduce locally
- Python: `python -m pip install -e ".[dev]" && pytest -q sdks/py_sdk/tests`
- Rust: `cd sdks/rust_sdk && cargo test --all --locked`
- JS: `cd sdks/js_sdk && npm ci && npm run build && npm test`
- ACK demo: `bash examples/sdk-usage/run_all.sh ack-demo` (uses defaults `localhost:{50051,50052,50053}` via `SW4RM_*` envs)

## Python SDK Installation
- Prerequisites:
  - Python >= 3.9
  - Optional: create and activate a virtual environment
    - `python3 -m venv venv && source venv/bin/activate`
- Runtime install (local):
  - `python -m pip install .`
- Dev install (with codegen):
  - `python -m pip install -e ".[dev]"`
  - Generate stubs: `make protos` (requires `grpcio-tools`)
    - Stubs are generated under `sdks/py_sdk/sw4rm/protos`

## Core Features

- **Persistent Activity Buffer**: Track messages across restarts with reconciliation
- **Worktree Management**: Policy-driven binding with persistent state
- **ACK Lifecycle**: Automatic acknowledgment handling with router integration
- **Message Processing**: Handler-based routing with built-in error handling
- **Multiple Persistence**: JSON file and pluggable storage backends
- **Production Ready**: Comprehensive error handling, logging, and state management

## Quick Start

Looking for a local all-in-one stack? See the DevCore Quickstart to run in-repo Registry, Router, Scheduler, and Negotiation services:

- DevCore Quickstart: `QUICKSTART.md` (section "DevCore (Rust) Quickstart")

### Basic Agent
```python
import grpc
from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.protos import common_pb2 as common

# Connect to services
router_ch = grpc.insecure_channel("localhost:50051")
registry_ch = grpc.insecure_channel("localhost:50052")
registry = RegistryClient(registry_ch)
router = RouterClient(router_ch)

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
from sw4rm import constants as C
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

processor.register_handler(C.DATA, handle_data)

# Process incoming messages with automatic ACKs
for item in router.stream_incoming("my-agent"):
    # Extract envelope from stream item (protobuf → dict)
    envelope_msg = getattr(item, "msg", item)
    envelope = {
        "message_id": getattr(envelope_msg, "message_id", ""),
        "message_type": getattr(envelope_msg, "message_type", 0),
        "content_type": getattr(envelope_msg, "content_type", ""),
        "payload": getattr(envelope_msg, "payload", b""),
        "producer_id": getattr(envelope_msg, "producer_id", ""),
        "correlation_id": getattr(envelope_msg, "correlation_id", ""),
        "sequence_number": getattr(envelope_msg, "sequence_number", 0),
    }
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
from sw4rm.worktree_state import PersistentWorktreeState

# Minimal custom policy implementing the expected hooks
class MyPolicy:
    def __init__(self, allowed_repos=None):
        self.allowed_repos = set(allowed_repos or [])

    def before_bind(self, repo_id, worktree_id, current):
        # Allow only specific repos
        return (not self.allowed_repos) or (repo_id in self.allowed_repos)

    def after_bind(self, binding):
        print(f"Bound to {binding.repo_id}/{binding.worktree_id}")

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
from sw4rm import constants as C

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
from sw4rm import constants as C

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
from sw4rm.protos import common_pb2 as common

registry = RegistryClient(grpc_channel)

# Register agent
response = registry.register({
    "agent_id": "my-agent",
    "name": "My Agent",
    "capabilities": ["processing", "analysis"],
    "communication_class": common.CommunicationClass.STANDARD
})

# Send heartbeat
registry.heartbeat("my-agent", state=common.AgentState.RUNNING)

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
C.HEARTBEAT              # Heartbeat
C.NOTIFICATION           # Notification
C.HITL_INVOCATION        # HITL invocation
C.NEGOTIATION            # Negotiation
C.TOOL_CALL              # Tool call
C.TOOL_RESULT            # Tool result
C.TOOL_ERROR             # Tool error

# ACK stages
C.RECEIVED               # Message received
C.READ                   # Message read/parsed
C.FULFILLED              # Processing completed
C.REJECTED               # Processing rejected
C.FAILED                 # Processing failed
C.TIMED_OUT              # Processing timed out

# Error codes
C.VALIDATION_ERROR       # Invalid message format
C.PERMISSION_DENIED      # Unauthorized operation
C.INTERNAL_ERROR         # Internal processing error
C.ACK_TIMEOUT            # ACK not received in time
C.AGENT_UNAVAILABLE      # Agent not reachable
C.AGENT_SHUTDOWN         # Agent shutting down
C.NO_ROUTE               # No route to target
C.OVERSIZE_PAYLOAD       # Payload too large
C.TOOL_TIMEOUT           # Tool call timed out
C.FORCED_PREEMPTION      # Scheduler forced preemption
C.TTL_EXPIRED            # Message TTL expired
```

## Message Semantics
- Required fields: `message_id`, `producer_id`, `correlation_id`, `sequence_number`, `message_type`, `content_type`, `payload`.
- Correlation: For negotiation flows, `correlation_id` equals the negotiation ID (per protocol spec).
- Optional fields: `idempotency_token`, `repo_id`, `worktree_id`, `ttl_ms`, `content_length`, `hlc_timestamp`.
- Envelope builder returns a dict matching proto fields; adapt to protobuf classes if stubs are present.

## Examples

### Complete Examples
- **Basic echo agent**: `examples/echo_agent.py` - Simple registration and message echoing
- **Advanced agent**: `examples/advanced_agent.py` - Full SDK feature demonstration
- **Test client**: `examples/test_client.py` - Client for testing agent functionality

### Running Examples
```bash
# Start advanced agent
python examples/advanced_agent.py --router localhost:50051 --registry localhost:50052 --data-dir ./my_agent_data

# Test the agent (in another terminal)
python examples/test_client.py --router localhost:50051 --registry localhost:50052 --target-agent advanced-1

# Run specific test
python examples/test_client.py --router localhost:50051 --registry localhost:50052 --test data --target-agent advanced-1
```

See `examples/README.md` for detailed example documentation.

For TypeScript/JS usage examples and an ACK flow demo, see `examples/sdk-usage/README.md`.

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
- Unified: `make test` (runs Python, Rust, JS tests + JS ACK demo)
- Python only: `make test-python`
- Rust only: `make test-rust` (requires `protoc`)
- JS only: `make test-js` (Node >= 20)
- Examples demo: `make demo-examples` (runs `examples/sdk-usage/run_all.sh ack-demo`)

```bash
# Run all tests and the ACK demo
make test

# Run examples against local services
# See QUICKSTART.md for how to start the in-repo services
python examples/advanced_agent.py --router localhost:50051 --registry localhost:50052
python examples/test_client.py --router localhost:50051 --registry localhost:50052
```

## Architecture

The Python SDK is organized into layers:

1. **Protocol Layer**: Generated protobuf stubs (`sw4rm.protos`)
2. **Client Layer**: Service clients (`sw4rm.clients`) 
3. **Runtime Layer**: Core functionality (`sw4rm.activity_buffer`, `sw4rm.worktree_state`)
4. **Integration Layer**: High-level APIs (`sw4rm.ack_integration`)
5. **Utility Layer**: Helpers (`sw4rm.envelope`, `sw4rm.acks`)

Protocol highlights
- Cooperative preemption and urgent lane semantics defined by Scheduler and CommunicationClass (see spec).
- HITL escalation reasons and Reasoning Engine participation are supported via dedicated services.
- Activity buffer persists advisory task/message context and supports reconciliation.

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

## Git Commit Hooks

To enforce consistent commit messages across the repo:

- Recommended setup:
  - Set versioned hooks path once per clone: `git config core.hooksPath scripts/git-hooks`

## Contributing

- Versioning: Keep all SDKs in lockstep with the protocol spec. The single source of truth is `documentation/protocol/spec.md` line `Version: X.Y.Z (...)`. Python (`pyproject.toml`), JS (`sdks/js_sdk/package.json`), and Rust (`sdks/rust_sdk/Cargo.toml`) must equal the spec version.
- Pre-commit hook: Local guard that blocks commits if versions aren’t SemVer or out of sync; also requires a bump when protocol/protos or an SDK changes.
  - Enable once per clone: `git config core.hooksPath .githooks && chmod +x .githooks/pre-commit`
- Bump script: Updates spec + all SDKs together.
  - `python scripts/bump_version.py X.Y.Z [--stage]`
- PR checks: CI enforces the same rules and does preflight builds.
  - Workflow: `.github/workflows/version-guard.yml`
- Release tags: Publishing is tag-driven per language and runs in GitHub Actions.
  - PyPI: `git tag py-vX.Y.Z && git push origin py-vX.Y.Z`
  - npm: `git tag npm-vX.Y.Z && git push origin npm-vX.Y.Z`
  - crates.io: `git tag rs-vX.Y.Z && git push origin rs-vX.Y.Z`
- Release scripts: Create tags locally (publishing happens in Actions).
  - One SDK: `python scripts/release.py [py|npm|rs] X.Y.Z --push`
  - All SDKs: `python scripts/release_all.py X.Y.Z --push`
- Secrets storage: Use a GitHub Actions Environment named `production` for publish tokens.
  - Add environment secrets: `PYPI_API_TOKEN`, `NPM_TOKEN`, `CRATES_IO_TOKEN` under Settings → Environments → production.
  - Release workflows target this environment: `.github/workflows/release-*.yml`.
- Tag prefixes and SemVer:
  - Tags must use `py-v`, `npm-v`, `rs-v` followed by `X.Y.Z` that matches all manifests and the spec.
  - SemVer only (no suffixes). CI and hooks will fail on mismatch.

  - Optionally install template and hooks via script: `./scripts/install_git_hooks.sh`
- Hooks enforce:
  - Subject: non-empty, ≤50 chars, imperative, no trailing period
  - Blank line after subject
  - Body lines wrapped at 72 characters (links exempt)
  - Pre-commit will block if `core.hooksPath` is misconfigured; bypass once with
    `ALLOW_HOOKS_PATH_MISMATCH=1 git commit` or `git commit --no-verify`.
