# SW4RM Elixir SDK

Elixir SDK for the SW4RM Agentic Protocol. Provides typed gRPC clients for all 13 protocol services, conformance-tested proto stubs, and local coordination primitives (NegotiationRoom, Delegation, Cancellation).

## Install

Add `sw4rm` to your `mix.exs` dependencies:

```elixir
def deps do
  [{:sw4rm, "~> 0.1.0"}]
end
```

## Quick Start

```elixir
alias Sw4rm.Clients.Registry

# Register an agent
{:ok, _} = Registry.register_agent(%{
  agent_id: "my-agent",
  name: "My Agent",
  capabilities: ["code_review"],
  communication_class: :STANDARD
})

# Send heartbeat
{:ok, _} = Registry.heartbeat(%{agent_id: "my-agent", state: :RUNNING})

# Open a negotiation room
alias Sw4rm.NegotiationRoom
alias Sw4rm.NegotiationRoom.{Proposal, Critique}

{:ok, room} = NegotiationRoom.start_link(room_id: "room-1")

NegotiationRoom.submit_proposal(room, %Proposal{
  artifact_id: "art-1",
  producer_id: "my-agent",
  artifact: "code payload"
})

NegotiationRoom.add_critique(room, "art-1", %Critique{
  critic_id: "reviewer-1",
  score: 8.5,
  passed: true
})
```

## Features

- 13 gRPC service clients (Registry, Router, Scheduler, Negotiation, NegotiationRoom, Handoff, Workflow, Tool, HITL, Worktree, Connector, Reasoning, Activity)
- SchedulerPolicy and Logging service clients
- Local NegotiationRoom GenServer with Store registry
- Quorum policies and vote collection timeouts (SW4-001)
- Per-service timeout profiles with clamping (SW4-002)
- Delegation and Cancellation coordination primitives
- Conformance test suite with protocol-level vectors
- Interceptor hooks on Transport.Client
- Envelope construction with Three-ID model (UUIDv4, correlation, idempotency)

## Spec Compliance

- SW4RM Core Spec (all 13 services)
- SW4-001: Failure Semantics (quorum, vote collection timeout)
- SW4-002: Timeout Profiles (per-service timeouts)
- SW4-004: Connector Extension
- SW4-005: Reasoning Proxy Extension

## Running Tests

```bash
mix test
```

Or via Docker (no local Elixir required):

```bash
docker run --rm -v $(pwd)/../..:/app -w /app/sdks/ex_sdk elixir:1.16 bash -c \
  "mix local.hex --force && mix local.rebar --force && mix deps.get && mix test"
```

## Links

- [Operational Contracts](../docs/OPERATIONAL_CONTRACTS.md)
- [SW4RM Protocol Spec](../../documentation/protocol/)
- [JavaScript SDK](../js_sdk/README.md)
- [Python SDK](../py_sdk/README.md)
- [Rust SDK](../rust_sdk/README.md)

## License

MIT
