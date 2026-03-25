# SW4RM Rust SDK Examples

This directory contains runnable examples for the Rust SDK. The local demos show the runtime and state-management patterns, while the coordination examples use the real SDK client classes with in-memory backends.

## Prerequisites

- Rust 1.70+
- `cargo` in your PATH
- `protoc` only if you plan to regenerate protobufs

## Example Matrix

| Example | What it shows | Fidelity |
|---|---|---|
| `echo_agent.rs` | Core agent trait, envelope construction, preemption-aware processing | Local runtime demo |
| `activity_demo.rs` | Persistent activity buffer and ACK lifecycle | Local persistence demo |
| `advanced_agent.rs` | Full agent hooks, activity tracking, worktree, HITL, negotiation | Local runtime demo |
| `negotiation_room.rs` | Producer/critic/coordinator negotiation flow with SDK `NegotiationRoomClient` | Local SDK client (shared `InMemoryNegotiationRoomStore`) |
| `workflow.rs` | DAG workflow orchestration with SDK `WorkflowClient` and `resume_workflow` | Local SDK client (in-memory) |
| `handoff.rs` | Handoff lifecycle and capability matching with SDK `HandoffClient` | Local SDK client (in-memory) |
| `tool_streaming.rs` | Streaming tool calls, frame types, progress, and cancellation | Mock-backed with optional service path |
| `voting.rs` | Vote aggregation strategies, entropy, consensus, polarization analysis | Local SDK (in-memory) |
| `secrets.rs` | Scoped secret storage, resolver precedence, backend selection | Local SDK (file backend in tempdir) |

The coordination examples import the real `NegotiationRoomClient`, `WorkflowClient`, and `HandoffClient` from the SDK and exercise their public APIs with in-memory backends. No external services are required.

## Quick Start

From `sdks/rust_sdk`:

```bash
cargo run --example echo_agent
cargo run --example activity_demo
cargo run --example advanced_agent
cargo run --example negotiation_room
cargo run --example workflow
cargo run --example handoff
cargo run --example tool_streaming
cargo run --example voting
cargo run --example secrets
```

## Notes

- `echo_agent.rs` and `advanced_agent.rs` are the best entry points for understanding the Rust runtime.
- `activity_demo.rs` is the cleanest example of persistence and recovery.
- The coordination examples use the real SDK client classes with in-memory storage, documenting the public API without requiring service orchestration.
