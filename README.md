<h1 align="left"><span style="color: rgb(8, 145, 178); font-family: 'Space Grotesk', sans-serif;">SW4RM Agentic Protocol</span></h1>

[![Python CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-python.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-python.yml)
[![Rust CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-rust.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-rust.yml)
[![JS CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-js.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-js.yml)
[![Elixir CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-elixir.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-elixir.yml)
[![Common Lisp CI](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-lisp.yml/badge.svg)](https://github.com/rahulrajaram/sw4rm/actions/workflows/ci-lisp.yml)

SW4RM is an open coordination protocol for agent swarms. It provides guaranteed message delivery, persistent scheduling, multi-agent negotiation, crash-safe handoffs, and rich observability -- the runtime layer that sits between your agents and lets them work together reliably.

This repository contains five SDKs (Python, Rust, JavaScript, Elixir, Common Lisp), three reference services (Registry, Router, Scheduler), an A2A protocol gateway, and a Docker Compose stack that brings everything up in one command.

## Try It in 2 Minutes

```bash
git clone https://github.com/rahulrajaram/sw4rm.git && cd sw4rm

# Start the full stack (Registry, Router, Scheduler, A2A Gateway)
docker compose up --build -d

# Verify the A2A gateway is running
curl http://localhost:8080/.well-known/agent.json

# Run the quickstart demo (registers agents, sends messages, heartbeats)
./quickstart.sh --local
```

Or use the JSON-RPC interface:

```bash
curl -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"GetAgentCard","params":{},"id":1}'
```

## SDKs

| SDK | Directory | Tests | README |
|-----|-----------|-------|--------|
| Python | [`sdks/py_sdk`](sdks/py_sdk) | 770 | [`README`](sdks/py_sdk/README.md) |
| Rust | [`sdks/rust_sdk`](sdks/rust_sdk) | 329 | [`README`](sdks/rust_sdk/README.md) |
| JavaScript/TypeScript | [`sdks/js_sdk`](sdks/js_sdk) | 410 | [`README`](sdks/js_sdk/README.md) |
| Elixir | [`sdks/ex_sdk`](sdks/ex_sdk) | 331 | [`README`](sdks/ex_sdk/README.md) |
| Common Lisp | [`sdks/cl_sdk`](sdks/cl_sdk) | 87+333 | [`README`](sdks/cl_sdk/README.md) |

All SDKs implement the same protocol (17 proto3 service definitions) and follow the same layered architecture adapted to language idioms.

## A2A Gateway

The [`a2a_gateway/`](a2a_gateway/) module exposes any SW4RM agent swarm via the [A2A (Agent-to-Agent) protocol](https://a2a-protocol.org/). External A2A clients see standard Agent Cards and JSON-RPC 2.0; internally, SW4RM handles scheduling, negotiation, and crash recovery.

| Endpoint | Description |
|----------|-------------|
| `GET /.well-known/agent.json` | A2A Agent Card for the gateway |
| `POST /` (JSON-RPC) `SendMessage` | Route a message to a SW4RM agent |
| `POST /` (JSON-RPC) `GetTask` | Query task state |
| `POST /` (JSON-RPC) `CancelTask` | Cancel via Scheduler preemption |
| `POST /` (JSON-RPC) `GetAgentCard` | Get agent card by ID |

See [`a2a_gateway/README.md`](a2a_gateway/README.md) for details.

## Core Features

- **Guaranteed Delivery**: Router with persistent message queues, ACK lifecycle (received/read/fulfilled/rejected/failed/timed_out), and automatic reconciliation
- **Scheduling and Preemption**: Priority-based task scheduling with cooperative preemption, urgent lane semantics, and activity buffer persistence
- **Multi-Agent Negotiation**: Proposal/vote/decision protocol with configurable quorum policies, confidence-weighted vote aggregation, and timeout profiles
- **Crash-Safe Handoffs**: Structured agent-to-agent work transfer with context serialization, capability matching, and full audit trail
- **Worktree Isolation**: Policy-driven worktree binding with persistent state across restarts
- **A2A Interoperability**: Gateway translates between A2A protocol and SW4RM, with `.well-known/agent.json` discovery
- **Five SDKs**: Python, Rust, JavaScript/TypeScript, Elixir, Common Lisp -- all wire-compatible

## Installation

### Python

```bash
pip install sw4rm-sdk
# or from source:
pip install -e ".[dev]"
```

### Rust

```toml
[dependencies]
sw4rm-sdk = "0.6.0"
tokio = { version = "1.0", features = ["full"] }
```

### JavaScript / TypeScript

```bash
npm install @sw4rm/js-sdk
```

### Elixir

```elixir
# mix.exs
defp deps do
  [{:sw4rm, "~> 0.6.0"}]
end
```

### Common Lisp

Requires [SBCL](http://www.sbcl.org/) and [Quicklisp](https://www.quicklisp.org/).

```lisp
(push (truename "sdks/cl_sdk/") asdf:*central-registry*)
(ql:quickload :sw4rm-sdk)
```

## Quick Start

### Python

```python
import grpc
from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient

# Connect to services
registry_ch = grpc.insecure_channel("localhost:50052")
router_ch = grpc.insecure_channel("localhost:50051")
registry = RegistryClient(registry_ch)
router = RouterClient(router_ch)

# Register agent
registry.register({
    "agent_id": "my-agent",
    "name": "My Agent",
    "capabilities": ["processing"],
})

# Send message
router.send_message({
    "producer_id": "my-agent",
    "consumer_id": "target-agent",
    "message_type": 2,  # DATA
    "payload": b"hello",
    "content_type": "text/plain",
    "correlation_id": "req-001",
})

# Heartbeat and deregister
registry.heartbeat(agent_id="my-agent", state=1)
registry.deregister(agent_id="my-agent")
```

### Rust

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

```typescript
import { RegistryClient, RouterClient, buildEnvelope, MessageType, CommunicationClass } from '@sw4rm/js-sdk';

const registry = new RegistryClient('localhost:50052');
const router = new RouterClient({ address: 'localhost:50051' });

await registry.registerAgent({
  agent_id: 'echo-1',
  name: 'EchoAgent',
  capabilities: ['echo'],
  communication_class: CommunicationClass.STANDARD,
});

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

### Elixir

```elixir
# Register and send a message
{:ok, channel} = GRPC.Stub.connect("localhost:50052")
Sw4rm.Transport.Client.register(channel, %{agent_id: "my-agent", capabilities: ["echo"]})
```

See [`sdks/ex_sdk/examples/reference_demo.exs`](sdks/ex_sdk/examples/reference_demo.exs) for a full demo exercising all 12 SDK features.

## Reference Services

Three reference service implementations run the SW4RM protocol:

| Service | Port | Metrics | Description |
|---------|------|---------|-------------|
| Registry | 50052 | 9100 | Agent discovery, heartbeat, deregistration |
| Router | 50051 | 9101 | Message routing, delivery queues, streaming |
| Scheduler | 50053 | 9102 | Task scheduling, preemption, activity buffer |

Start locally:

```bash
cd sdks/py_sdk/reference-services
bash start_services.sh --local
```

Or via Docker:

```bash
docker compose up --build -d
```

## Examples

### Tutorials

- **Code-Agent Tutorial**: 3-agent code review swarm (writer + reviewers + deployer) using negotiation and handoff -- [`code_agent_tutorial.py`](sdks/py_sdk/examples/code_agent_tutorial.py) | [`walkthrough`](sdks/py_sdk/examples/CODE_AGENT_TUTORIAL.md)

### Python

- [`echo_agent.py`](sdks/py_sdk/examples/echo_agent.py) -- Minimal echo agent
- [`voting_example.py`](sdks/py_sdk/examples/voting_example.py) -- Multi-reviewer voting
- [`negotiation_debate_example.py`](sdks/py_sdk/examples/negotiation_debate_example.py) -- Negotiation room debate
- [`handoff_example.py`](sdks/py_sdk/examples/handoff_example.py) -- Agent-to-agent handoff
- [`hitl_escalation_example.py`](sdks/py_sdk/examples/hitl_escalation_example.py) -- Human-in-the-loop
- [`workflow_orchestration_example.py`](sdks/py_sdk/examples/workflow_orchestration_example.py) -- Multi-step workflow
- [`tool_streaming_example.py`](sdks/py_sdk/examples/tool_streaming_example.py) -- Tool call streaming
- [`three_id_demo.py`](sdks/py_sdk/examples/three_id_demo.py) -- Three-ID correlation

### Rust

- [`echo_agent.rs`](sdks/rust_sdk/examples/echo_agent.rs) -- Minimal echo agent
- [`advanced_agent.rs`](sdks/rust_sdk/examples/advanced_agent.rs) -- Full-featured agent
- [`handoff.rs`](sdks/rust_sdk/examples/handoff.rs) -- Agent handoff
- [`workflow.rs`](sdks/rust_sdk/examples/workflow.rs) -- Workflow orchestration
- [`negotiation_room.rs`](sdks/rust_sdk/examples/negotiation_room.rs) -- Negotiation room
- [`activity_demo.rs`](sdks/rust_sdk/examples/activity_demo.rs) -- Activity buffer

### JavaScript / TypeScript

- [`echoAgent.ts`](sdks/js_sdk/examples/echoAgent.ts) -- Minimal echo agent
- [`advancedAgent.ts`](sdks/js_sdk/examples/advancedAgent.ts) -- Full-featured agent
- [`handoffExample.ts`](sdks/js_sdk/examples/handoffExample.ts) -- Agent handoff
- [`workflowExample.ts`](sdks/js_sdk/examples/workflowExample.ts) -- Workflow orchestration
- [`negotiationRoomExample.ts`](sdks/js_sdk/examples/negotiationRoomExample.ts) -- Negotiation room
- [`hitlEscalation.ts`](sdks/js_sdk/examples/hitlEscalation.ts) -- Human-in-the-loop

### Elixir

- [`reference_demo.exs`](sdks/ex_sdk/examples/reference_demo.exs) -- Full SDK feature demo
- [`basic_agent.exs`](sdks/ex_sdk/examples/basic_agent.exs) -- Minimal agent
- [`negotiation_flow.exs`](sdks/ex_sdk/examples/negotiation_flow.exs) -- Negotiation flow
- [`handoff.exs`](sdks/ex_sdk/examples/handoff.exs) -- Agent handoff
- [`tool_execution.exs`](sdks/ex_sdk/examples/tool_execution.exs) -- Tool execution

### Common Lisp

- [`echo-agent.lisp`](sdks/cl_sdk/examples/echo-agent.lisp) -- Minimal echo agent
- [`negotiation-voting.lisp`](sdks/cl_sdk/examples/negotiation-voting.lisp) -- Negotiation voting
- [`secret-management.lisp`](sdks/cl_sdk/examples/secret-management.lisp) -- Secret management
- [`tool-streaming.lisp`](sdks/cl_sdk/examples/tool-streaming.lisp) -- Tool streaming

## Architecture

All five SDKs follow the same layered architecture:

```
+---------------------------+
|   Integration Layer       |  ACK lifecycle, message processing, workflows
+---------------------------+
|   Client Layer            |  Registry, Router, Scheduler, HITL, Negotiation,
|                           |  Handoff, Tool, Worktree, Connector, Reasoning
+---------------------------+
|   Protocol Layer          |  Proto3 wire format (17 service definitions)
+---------------------------+
|   Runtime Layer           |  Activity buffer, worktree state, state machine
+---------------------------+
```

Each SDK adapts this to language idioms: Python uses classes and context managers, Rust uses async/await traits, JavaScript uses Promises and async iterators, Elixir uses GenServers and supervisors, and Common Lisp uses the condition/restart system.

## CI Workflows

| Workflow | What it does |
|----------|-------------|
| Python CI | Python 3.12, `pytest`, smoke tests |
| Rust CI | `cargo test --all --locked` with `protoc` |
| JS CI | Node 20, `npm ci && npm run build && npm test` |
| Elixir CI | Elixir 1.16 / OTP 26, `mix test` + reference demo |
| Common Lisp CI | SBCL + Quicklisp, FiveAM test suite |
| Proto Check | Protocol file validation |
| Version Guard | Cross-SDK version consistency |
| Secrets Scan | Trufflehog credential scanning |

### Reproduce locally

```bash
# All SDKs
make test

# Individual
make test-python    # pytest -q sdks/py_sdk/tests
make test-rust      # cd sdks/rust_sdk && cargo test --all --locked
make test-js        # cd sdks/js_sdk && npm ci && npm run build && npm test
make test-lisp      # cd sdks/cl_sdk && sbcl --load test/suite.lisp

# Elixir (Docker, no local Elixir required)
docker run --rm -v $(pwd):/app -w /app/sdks/ex_sdk elixir:1.16 \
  bash -c "mix local.hex --force && mix local.rebar --force && mix deps.get && mix test"
```

## Development

### Generate Protocol Buffers

```bash
pip install -e ".[dev]"
make protos
```

### Smoke Test

```bash
# Local mode (starts services, runs checks, cleans up)
./scripts/smoke_test.sh

# Docker mode (includes A2A gateway checks)
./scripts/smoke_test.sh --docker
```

## Release

Publishing is tag-driven per language via GitHub Actions:

```bash
# Python → PyPI
git tag py-v0.6.0 && git push origin py-v0.6.0

# JavaScript → npm
git tag npm-v0.6.0 && git push origin npm-v0.6.0

# Rust → crates.io
git tag rs-v0.6.0 && git push origin rs-v0.6.0
```

Requires environment secrets (`PYPI_API_TOKEN`, `NPM_TOKEN`, `CRATES_IO_TOKEN`) in the `production` GitHub Actions Environment.

See [`CONTRIBUTING.md`](CONTRIBUTING.md) for versioning policy, commit hooks, and PR guidelines.

## License

[Apache License 2.0](LICENSE)
