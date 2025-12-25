# SW4RM Rust SDK Examples

This directory contains example code demonstrating various features of the SW4RM Agentic Protocol using the Rust SDK.

## Examples Overview

| Example | Description | Key Features |
|---------|-------------|--------------|
| [echo_agent.rs](echo_agent.rs) | Basic agent that echoes messages | Agent trait, EnvelopeBuilder, preemption |
| [activity_demo.rs](activity_demo.rs) | Activity buffer and persistence | ActivityBuffer, ACK lifecycle, persistence |
| [advanced_agent.rs](advanced_agent.rs) | Full-featured agent demonstration | Tool calls, HITL, negotiation, worktree |
| [negotiation_room.rs](negotiation_room.rs) | Producer-critic-coordinator pattern | Multi-agent voting, aggregation, decisions |
| [workflow.rs](workflow.rs) | DAG-based workflow orchestration | Workflow nodes, dependencies, execution |
| [handoff.rs](handoff.rs) | Agent-to-agent task handoff | Context transfer, capability matching |

## Prerequisites

1. **Rust toolchain** (1.70+)
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **Protocol Buffers compiler** (optional, for proto regeneration)
   ```bash
   # macOS
   brew install protobuf

   # Ubuntu/Debian
   sudo apt-get install protobuf-compiler
   ```

## Running Examples

### Basic Echo Agent

The simplest example demonstrating core SDK concepts:

```bash
cd /path/to/sigagent/sdks/rust_sdk
cargo run --example echo_agent
```

This example shows:
- Creating an agent with `AgentConfig`
- Implementing the `Agent` trait
- Handling different message types (DATA, CONTROL, TOOL_CALL)
- Using `EnvelopeBuilder` for message construction
- Cooperative preemption handling

### Activity Buffer Demo

Demonstrates message tracking and persistence:

```bash
cargo run --example activity_demo
```

This example shows:
- `PersistentActivityBuffer` for message tracking
- Recording incoming and outgoing messages
- ACK stage transitions
- Persistence to JSON files
- Message reconciliation

### Advanced Agent

A comprehensive example with all major features:

```bash
cargo run --example advanced_agent
```

This example shows:
- Full `Agent` trait implementation with all hooks
- `ActivityBuffer` integration
- `WorktreeState` management
- Tool call execution
- HITL message handling
- Negotiation participation
- Preemption-aware processing

### Negotiation Room

Demonstrates the producer-critic-coordinator pattern:

```bash
cargo run --example negotiation_room
```

This example shows:
- Submitting proposals for multi-agent review
- Critic agents evaluating artifacts
- Confidence-weighted vote aggregation
- Policy-based decision making
- Polarization detection (triggers HITL escalation)

**Note:** Uses stub implementations. Full `NegotiationRoomClient` implementation is planned for Phase 3.1.

### Workflow Orchestration

Demonstrates DAG-based workflow execution:

```bash
cargo run --example workflow
```

This example shows:
- Creating workflow definitions with nodes
- Dependency-based node scheduling
- Parallel execution of independent nodes
- Node status tracking
- Input/output mapping between nodes

**Note:** Uses stub implementations. Full `WorkflowClient` implementation is planned for Phase 3.3.

### Agent Handoff

Demonstrates agent-to-agent task delegation:

```bash
cargo run --example handoff
```

This example shows:
- Initiating handoff requests
- Capability-based acceptance/rejection
- Context snapshot and transfer
- Conversation history preservation
- Handoff lifecycle management

**Note:** Uses stub implementations. Full `HandoffClient` implementation is planned for Phase 3.2.

## Example Architecture

### Agent Pattern

All examples follow a consistent pattern for implementing agents:

```rust
use sw4rm_sdk::prelude::*;

struct MyAgent {
    config: AgentConfig,
    preemption: PreemptionManager,
    // ... agent state
}

#[async_trait]
impl Agent for MyAgent {
    async fn on_startup(&mut self) -> Result<()> {
        // Initialize resources
        Ok(())
    }

    async fn on_shutdown(&mut self) -> Result<()> {
        // Cleanup resources
        Ok(())
    }

    async fn on_message(&mut self, envelope: EnvelopeData) -> Result<()> {
        // Handle DATA messages
        Ok(())
    }

    async fn on_control(&mut self, envelope: EnvelopeData) -> Result<()> {
        // Handle CONTROL messages
        Ok(())
    }

    async fn on_tool_call(&mut self, envelope: EnvelopeData) -> Result<()> {
        // Handle TOOL_CALL messages
        Ok(())
    }

    fn config(&self) -> &AgentConfig {
        &self.config
    }

    fn preemption_manager(&self) -> &PreemptionManager {
        &self.preemption
    }
}
```

### Message Handling

Examples demonstrate different approaches to message processing:

```rust
// JSON payload extraction
if envelope.content_type == "application/json" {
    if let Ok(data) = envelope.json_payload::<serde_json::Value>() {
        tracing::info!("Received: {}", data);
    }
}

// Text payload
if let Ok(text) = envelope.string_payload() {
    tracing::info!("Text: {}", text);
}

// Raw bytes
let bytes = &envelope.payload;
```

### Envelope Construction

Building messages with `EnvelopeBuilder`:

```rust
use sw4rm_sdk::prelude::*;
use serde_json::json;

let envelope = EnvelopeBuilder::new(agent_id, constants::message_type::DATA)
    .with_json_payload(&json!({
        "action": "process",
        "data": { "key": "value" }
    }))
    .unwrap()
    .with_correlation_id(correlation_id)
    .build();
```

## Stub Implementations

The `negotiation_room.rs`, `workflow.rs`, and `handoff.rs` examples use stub implementations because the corresponding gRPC clients are not yet implemented in the Rust SDK. These stubs:

1. **Demonstrate the intended API** - Shows how the real clients will be used
2. **Are fully functional locally** - Work without network dependencies
3. **Match the proto definitions** - Use types aligned with the `.proto` files

When the real clients are implemented (see `IMPLEMENTATION_PLAN.md` Phase 3), the examples will be updated to use them.

## Connecting to Services

For examples that connect to actual SW4RM services:

1. **Start reference services:**
   ```bash
   cd ../../examples/reference-services/
   ./start_services_local.sh
   ```

2. **Configure endpoints:**
   ```rust
   let endpoints = Endpoints {
       registry: "http://localhost:50051".to_string(),
       router: "http://localhost:50052".to_string(),
       scheduler: "http://localhost:50053".to_string(),
       ..Default::default()
   };

   let config = AgentConfig::new(agent_id, name)
       .with_endpoints(endpoints);
   ```

3. **Run the agent:**
   ```bash
   cargo run --example echo_agent
   ```

## Testing Examples

Run all examples in sequence to verify they work:

```bash
# Run each example (they're designed to complete quickly)
cargo run --example echo_agent
cargo run --example activity_demo
cargo run --example advanced_agent
cargo run --example negotiation_room
cargo run --example workflow
cargo run --example handoff
```

## Troubleshooting

### Proto Compilation Errors

If you see proto-related errors:

```bash
# Clean and rebuild
cargo clean
cargo build
```

### Missing Dependencies

Ensure all dependencies are installed:

```bash
cargo fetch
cargo build
```

### Tracing Output

All examples use the `tracing` crate for logging. To see debug output:

```bash
RUST_LOG=debug cargo run --example echo_agent
```

## Further Reading

- [Rust SDK README](../README.md) - SDK overview and API documentation
- [Protocol Specification](../../../documentation/protocol/spec.md) - Full protocol specification
- [Implementation Plan](../../../docs/IMPLEMENTATION_PLAN.md) - SDK development roadmap
- [Python SDK Examples](../../py_sdk/examples/) - Equivalent Python implementations

## License

Apache License 2.0 - See [LICENSE](../../../LICENSE) for details.
