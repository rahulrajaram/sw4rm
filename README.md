# SW4RM Agentic Protocol

[![Python CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-python.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-python.yml)
[![Rust CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-rust.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-rust.yml)
[![JS CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-js.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-js.yml)
[![Common Lisp CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-lisp.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-lisp.yml)

SW4RM is an open agentic protocol for building message-driven agents with guaranteed delivery, persistent state, and rich observability. This repository provides four SDKs that implement the protocol — Python, Rust, JavaScript, and Common Lisp — including clients, lightweight runtimes, and helpers for ACK lifecycle, worktree/state handling, and more.

## SDKs

| SDK | Directory | README |
|-----|-----------|--------|
| Python | [`sdks/py_sdk`](sdks/py_sdk) | [`sdks/py_sdk/README.md`](sdks/py_sdk/README.md) |
| Rust | [`sdks/rust_sdk`](sdks/rust_sdk) | [`sdks/rust_sdk/README.md`](sdks/rust_sdk/README.md) |
| JavaScript/TypeScript | [`sdks/js_sdk`](sdks/js_sdk) | [`sdks/js_sdk/README.md`](sdks/js_sdk/README.md) |
| Common Lisp | [`sdks/cl_sdk`](sdks/cl_sdk) | [`sdks/cl_sdk/README.md`](sdks/cl_sdk/README.md) |

## CI Workflows

| Workflow | What it does |
|----------|-------------|
| Python CI | Python 3.12, installs `.[dev]`, runs `scripts/smoke_protos.py`, then `pytest -q sdks/py_sdk/tests` |
| Rust CI | Installs `protoc`, runs `cargo test --all --locked` in `sdks/rust_sdk` |
| JS CI | Node 20, runs `npm ci && npm run build && npm test` in `sdks/js_sdk` |
| Common Lisp CI | SBCL + Quicklisp, loads `:sw4rm-sdk`, runs FiveAM test suite in `sdks/cl_sdk` |

### Reproduce locally

- **Python**: `python -m pip install -e ".[dev]" && pytest -q sdks/py_sdk/tests`
- **Rust**: `cd sdks/rust_sdk && cargo test --all --locked`
- **JS**: `cd sdks/js_sdk && npm ci && npm run build && npm test`
- **Common Lisp**: `cd sdks/cl_sdk && sbcl --load ~/quicklisp/setup.lisp --eval '(push (truename ".") asdf:*central-registry*)' --eval '(ql:quickload :sw4rm-sdk)' --eval '(load "test/suite.lisp")' --eval '(fiveam:run! (quote sw4rm-test::sw4rm-suite))'`

## Installation

### Python

Prerequisites: Python >= 3.9. Optionally create a virtual environment first.

```bash
# Dev install (with codegen)
python -m pip install -e ".[dev]"

# Runtime-only install
python -m pip install .

# Generate protobuf stubs (requires grpcio-tools)
make protos
```

### Rust

Add to your `Cargo.toml`:

```toml
[dependencies]
sw4rm-sdk = "0.5.0"
tokio = { version = "1.0", features = ["full"] }
```

### JavaScript / TypeScript

```bash
npm install @sw4rm/js-sdk
```

### Common Lisp

Requires [SBCL](http://www.sbcl.org/) and [Quicklisp](https://www.quicklisp.org/).

```lisp
;; Ensure sdks/cl_sdk/ is on your ASDF load path, e.g.:
;; (push (truename "sdks/cl_sdk/") asdf:*central-registry*)

(ql:quickload :sw4rm-sdk)
```

## Core Features

- **Persistent Activity Buffer**: Track messages across restarts with reconciliation
- **Worktree Management**: Policy-driven binding with persistent state
- **ACK Lifecycle**: Automatic acknowledgment handling with router integration
- **Message Processing**: Handler-based routing with built-in error handling
- **Multiple Persistence**: JSON file and pluggable storage backends
- **Production Ready**: Comprehensive error handling, logging, and state management

## Quick Start

Looking for a local all-in-one stack? See the comprehensive getting started guide:

- Getting Started Guide: [`documentation/quickstart/`](documentation/quickstart/index.md) with a 5-minute quick start section

### Python

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

### Advanced Python Agent with Persistence
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
    # Extract envelope from stream item (protobuf -> dict)
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

### Rust

Minimal echo agent (see [`sdks/rust_sdk/examples/echo_agent.rs`](sdks/rust_sdk/examples/echo_agent.rs) for the full example):

```rust
use sw4rm_sdk::*;
use async_trait::async_trait;

struct EchoAgent {
    config: AgentConfig,
    preemption: PreemptionManager,
}

#[async_trait]
impl Agent for EchoAgent {
    async fn on_message(&mut self, envelope: EnvelopeData) -> Result<()> {
        if let Ok(text) = envelope.string_payload() {
            println!("Echo: {}", text);
        }
        Ok(())
    }

    fn config(&self) -> &AgentConfig { &self.config }
    fn preemption_manager(&self) -> &PreemptionManager { &self.preemption }
}

#[tokio::main]
async fn main() -> Result<()> {
    let config = AgentConfig::new("echo-1".into(), "Echo Agent".into());
    let agent = EchoAgent { config: config.clone(), preemption: PreemptionManager::new() };
    AgentRuntime::new(config).run(agent).await
}
```

### JavaScript / TypeScript

Minimal echo agent (see [`sdks/js_sdk/examples/echoAgent.ts`](sdks/js_sdk/examples/echoAgent.ts) for the full example):

```typescript
import { RegistryClient, RouterClient, buildEnvelope, MessageType, AgentState, CommunicationClass } from '@sw4rm/js-sdk';

const registry = new RegistryClient('localhost:50052');
const router = new RouterClient({ address: 'localhost:50051' });

// Register
await registry.registerAgent({
  agent_id: 'echo-1',
  name: 'EchoAgent',
  capabilities: ['echo'],
  communication_class: CommunicationClass.STANDARD,
});

// Echo incoming messages
const stream = router.streamIncoming('echo-1');
for await (const item of stream) {
  const reply = buildEnvelope({
    producer_id: 'echo-1',
    message_type: MessageType.DATA,
    payload: item.msg.payload,
    content_type: 'application/json',
  });
  await router.sendMessage(reply);
}
```

### Common Lisp

Minimal echo agent (see [`sdks/cl_sdk/examples/echo-agent.lisp`](sdks/cl_sdk/examples/echo-agent.lisp) for the full example):

```lisp
(ql:quickload :sw4rm-sdk)
(use-package :sw4rm-sdk)

;; Configure
(defvar *config*
  (make-agent-config
   :agent-id "echo-1"
   :name "EchoAgent"
   :capabilities '("echo")
   :endpoints (make-default-endpoints)))

;; Build and send an envelope
(defvar *envelope*
  (make-envelope
   :producer-id (agent-config-agent-id *config*)
   :message-type +data+
   :content-type "application/json"
   :payload (map 'vector #'char-code "{\"echo\":\"hello\"}")
   :sequence-number 1))

;; Error handling uses CL condition/restart system
(with-sw4rm-error-handling ()
  (let ((client (make-instance 'router-client
                 :address (endpoints-router
                           (agent-config-endpoints *config*)))))
    (send-envelope client *envelope*)))
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

Each SDK ships its own examples under its directory:

### Python
- **Echo agent**: [`sdks/py_sdk/examples/echo_agent.py`](sdks/py_sdk/examples/echo_agent.py)
- **Test client**: [`sdks/py_sdk/examples/test_client.py`](sdks/py_sdk/examples/test_client.py)
- **Voting**: [`sdks/py_sdk/examples/voting_example.py`](sdks/py_sdk/examples/voting_example.py)
- **Workflow orchestration**: [`sdks/py_sdk/examples/workflow_orchestration_example.py`](sdks/py_sdk/examples/workflow_orchestration_example.py)
- **Negotiation debate**: [`sdks/py_sdk/examples/negotiation_debate_example.py`](sdks/py_sdk/examples/negotiation_debate_example.py)
- **HITL escalation**: [`sdks/py_sdk/examples/hitl_escalation_example.py`](sdks/py_sdk/examples/hitl_escalation_example.py)
- **Handoff**: [`sdks/py_sdk/examples/handoff_example.py`](sdks/py_sdk/examples/handoff_example.py)
- **Tool streaming**: [`sdks/py_sdk/examples/tool_streaming_example.py`](sdks/py_sdk/examples/tool_streaming_example.py)
- **Three-ID demo**: [`sdks/py_sdk/examples/three_id_demo.py`](sdks/py_sdk/examples/three_id_demo.py)

### Rust
- **Echo agent**: [`sdks/rust_sdk/examples/echo_agent.rs`](sdks/rust_sdk/examples/echo_agent.rs)
- **Advanced agent**: [`sdks/rust_sdk/examples/advanced_agent.rs`](sdks/rust_sdk/examples/advanced_agent.rs)
- **Handoff**: [`sdks/rust_sdk/examples/handoff.rs`](sdks/rust_sdk/examples/handoff.rs)
- **Workflow**: [`sdks/rust_sdk/examples/workflow.rs`](sdks/rust_sdk/examples/workflow.rs)
- **Negotiation room**: [`sdks/rust_sdk/examples/negotiation_room.rs`](sdks/rust_sdk/examples/negotiation_room.rs)
- **Activity demo**: [`sdks/rust_sdk/examples/activity_demo.rs`](sdks/rust_sdk/examples/activity_demo.rs)

### JavaScript / TypeScript
- **Echo agent**: [`sdks/js_sdk/examples/echoAgent.ts`](sdks/js_sdk/examples/echoAgent.ts)
- **Advanced agent**: [`sdks/js_sdk/examples/advancedAgent.ts`](sdks/js_sdk/examples/advancedAgent.ts)
- **HITL escalation**: [`sdks/js_sdk/examples/hitlEscalation.ts`](sdks/js_sdk/examples/hitlEscalation.ts)
- **Handoff**: [`sdks/js_sdk/examples/handoffExample.ts`](sdks/js_sdk/examples/handoffExample.ts)
- **Workflow**: [`sdks/js_sdk/examples/workflowExample.ts`](sdks/js_sdk/examples/workflowExample.ts)
- **Negotiation room**: [`sdks/js_sdk/examples/negotiationRoomExample.ts`](sdks/js_sdk/examples/negotiationRoomExample.ts)

### Common Lisp
- **Echo agent**: [`sdks/cl_sdk/examples/echo-agent.lisp`](sdks/cl_sdk/examples/echo-agent.lisp)
- **Negotiation voting**: [`sdks/cl_sdk/examples/negotiation-voting.lisp`](sdks/cl_sdk/examples/negotiation-voting.lisp)
- **Secret management**: [`sdks/cl_sdk/examples/secret-management.lisp`](sdks/cl_sdk/examples/secret-management.lisp)

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
- Twine >= 5.x and pkginfo >= 1.10 are recommended to support modern `Metadata-Version` (e.g., 2.4).
- See `docs/PROGRESS_REPORT.md` for a detailed Release Checklist.

### Testing

- Unified: `make test` (runs Python, Rust, JS, and Common Lisp tests)
- Python only: `make test-python`
- Rust only: `make test-rust` (requires `protoc`)
- JS only: `make test-js` (Node >= 20)
- Common Lisp only: `make test-lisp` (requires SBCL + Quicklisp)

```bash
# Run all SDK tests
make test

# Run examples against local services
# See documentation/quickstart/index.md for setup instructions
python sdks/py_sdk/examples/echo_agent.py --router localhost:50051 --registry localhost:50052
python sdks/py_sdk/examples/test_client.py --router localhost:50051 --registry localhost:50052
```

## Architecture

All four SDKs follow the same layered architecture:

1. **Protocol Layer**: Generated protobuf stubs / wire format
2. **Client Layer**: Type-safe service clients (Registry, Router, Scheduler, HITL, Worktree, Tool, Connector, Negotiation, Reasoning, Logging)
3. **Runtime Layer**: Core functionality (activity buffer, worktree state, state machine)
4. **Integration Layer**: High-level APIs (ACK lifecycle, message processing, workflows)
5. **Utility Layer**: Helpers (envelope builders, constants, error handling)

Each SDK adapts this pattern to its language idioms — Python uses classes and context managers, Rust uses async/await traits, JS uses Promises and streams, and Common Lisp uses the condition/restart system.

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

- Versioning: Keep all four SDKs in lockstep with the protocol spec. The single source of truth is `documentation/protocol/spec.md` line `Version: X.Y.Z (...)`. Python (`pyproject.toml`), JS (`sdks/js_sdk/package.json`), Rust (`sdks/rust_sdk/Cargo.toml`), and Common Lisp (`sdks/cl_sdk/sw4rm-sdk.asd`) must equal the spec version.
- Pre-commit hook: Local guard that blocks commits if versions aren't SemVer or out of sync; also requires a bump when protocol/protos or an SDK changes.
  - Enable once per clone: `git config core.hooksPath .githooks && chmod +x .githooks/pre-commit`
- Bump script: Updates spec + all SDKs together.
  - `python scripts/bump_version.py X.Y.Z [--stage]`
- PR checks: CI enforces the same rules and does preflight builds.
  - Workflow: `.github/workflows/version-guard.yml`
- Release tags: Publishing is tag-driven per language and runs in GitHub Actions.
  - PyPI: `git tag py-vX.Y.Z && git push origin py-vX.Y.Z`
  - npm: `git tag npm-vX.Y.Z && git push origin npm-vX.Y.Z`
  - crates.io: `git tag rs-vX.Y.Z && git push origin rs-vX.Y.Z`
  - Common Lisp releases are tracked via the spec version in `sw4rm-sdk.asd`; Quicklisp distribution is manual.
- Release scripts: Create tags locally (publishing happens in Actions).
  - One SDK: `python scripts/release.py [py|npm|rs] X.Y.Z --push`
  - All SDKs: `python scripts/release_all.py X.Y.Z --push`
- Secrets storage: Use a GitHub Actions Environment named `production` for publish tokens.
  - Add environment secrets: `PYPI_API_TOKEN`, `NPM_TOKEN`, `CRATES_IO_TOKEN` under Settings > Environments > production.
  - Release workflows target this environment: `.github/workflows/release-*.yml`.
- Tag prefixes and SemVer:
  - Tags must use `py-v`, `npm-v`, `rs-v` followed by `X.Y.Z` that matches all manifests and the spec.
  - SemVer only (no suffixes). CI and hooks will fail on mismatch.

  - Optionally install template and hooks via script: `./scripts/install_git_hooks.sh`
- Hooks enforce:
  - Subject: non-empty, <=50 chars, imperative, no trailing period
  - Blank line after subject
  - Body lines wrapped at 72 characters (links exempt)
  - Pre-commit will block if `core.hooksPath` is misconfigured; bypass once with
    `ALLOW_HOOKS_PATH_MISMATCH=1 git commit` or `git commit --no-verify`.
