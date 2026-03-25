# SW4RM Elixir SDK Examples

This directory contains runnable Elixir reference examples for the SW4RM SDK. The examples emphasize local coordination primitives and protocol wiring, with optional service-backed steps where the example benefits from them.

## Prerequisites

- Elixir 1.16+
- `mix deps.get` from `sdks/ex_sdk`
- `mix proto.gen` only if you need to regenerate protobuf stubs

## Example Matrix

| Example | What it shows | Fidelity |
|---|---|---|
| `reference_demo.exs` | Self-contained agent lifecycle, envelopes, state machine, activity buffer, negotiation flow | Local demo |
| `basic_agent.exs` | Basic lifecycle, sequence tracking, envelopes, and activity buffer | Local demo |
| `handoff.exs` | Inter-swarm handoff, budget envelopes, delegation, cancellation, gateway routing | Local reference demo |
| `negotiation_flow.exs` | Negotiation room flow, voting, and event emission | Local reference demo |
| `tool_execution.exs` | Interceptors, ACK tracking, worktree state, and tool-call envelope flow | Local demo with optional service path |
| `activity_walkthrough.exs` | Focused activity buffer, envelope lifecycle, state machine transitions | Local demo |
| `workflow.exs` | DAG workflow orchestration, dependency tracking, failure and cancellation | Local demo |

HITL is available as a service-backed client (`Sw4rm.Clients.Hitl.decide/2`); no standalone demo is included because the client requires a running gRPC service.

## Quick Start

From `sdks/ex_sdk`:

```bash
mix deps.get
mix run examples/reference_demo.exs
mix run examples/basic_agent.exs
mix run examples/handoff.exs
mix run examples/negotiation_flow.exs
mix run examples/tool_execution.exs
mix run examples/activity_walkthrough.exs
mix run examples/workflow.exs
```

## Notes

- `reference_demo.exs` is the cleanest end-to-end tour of the Elixir SDK.
- `tool_execution.exs` explicitly notes where live gRPC would be required if you want to turn the demo into an integration run.
- The remaining scripts are designed to stay understandable without needing a full service stack.
