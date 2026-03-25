# SW4RM JavaScript SDK Examples

This directory contains runnable TypeScript examples for the SW4RM JS SDK. Some scripts connect to real SW4RM services, while others intentionally use mock flows so the example stays runnable without extra infrastructure.

## Prerequisites

- Node.js 20+
- `npm install` in `sdks/js_sdk`
- `npm run build` only if you want bundled output; `tsx` can run the examples directly
- SW4RM services running for the service-backed examples

## Example Matrix

| Example | What it shows | Fidelity |
|---|---|---|
| `echoAgent.ts` | Registry registration, router streaming, basic ACK flow | Service-backed |
| `advancedAgent.ts` | Activity buffer, worktree binding, persistence, shutdown cleanup | Service-backed |
| `negotiationRoomExample.ts` | Producer/critic/coordinator review loop with SDK `NegotiationRoomClient` | Local SDK client (in-memory store) |
| `workflowExample.ts` | DAG workflow orchestration and node state transitions with SDK `WorkflowClient` | Local SDK client (in-memory) |
| `handoffExample.ts` | Agent handoff lifecycle and context transfer with SDK `HandoffClient` | Local SDK client (in-memory) |
| `hitlEscalation.ts` | HITL escalation scenarios and client interface shape | Mock-backed with interface demo |
| `toolStreamingExample.ts` | Streaming tool calls, frame types, progress, and cancellation | Mock-backed with optional service path |
| `votingExample.ts` | Vote aggregation strategies, entropy, consensus, polarization analysis | Local SDK (in-memory) |
| `secretsExample.ts` | Scoped secret storage, resolver precedence, backend selection | Local SDK (file backend in tempdir) |

The coordination examples import the real `NegotiationRoomClient`, `WorkflowClient`, and `HandoffClient` from the SDK and exercise their public APIs with in-memory backends. No external services are required.

## Quick Start

From `sdks/js_sdk`:

```bash
npx tsx examples/echoAgent.ts --agent-id echo-1 --name EchoAgent
npx tsx examples/advancedAgent.ts --agent-id advanced-1 --name AdvancedAgent --data-dir ./agent_data
npx tsx examples/negotiationRoomExample.ts
npx tsx examples/workflowExample.ts
npx tsx examples/handoffExample.ts
npx tsx examples/hitlEscalation.ts
npx tsx examples/toolStreamingExample.ts
npx tsx examples/votingExample.ts
npx tsx examples/secretsExample.ts
```

## Notes

- `echoAgent.ts` and `advancedAgent.ts` are the best starting points for a real agent.
- The coordination examples use the real SDK client classes with in-memory storage, documenting the public API without requiring service orchestration.
- If you need a service-backed check, start with the router and registry services and then run `echoAgent.ts`.
