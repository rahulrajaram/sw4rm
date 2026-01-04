# SW4RM JavaScript SDK Examples

This directory contains comprehensive examples demonstrating the SW4RM Agentic Protocol JavaScript/TypeScript SDK.

## Prerequisites

Before running the examples, ensure you have:

1. **Node.js 20+** installed
2. **Dependencies installed**: `npm install` in the `js_sdk` directory
3. **SDK built**: `npm run build` (optional for ts-node/tsx execution)
4. **SW4RM services running** (for examples that connect to real services)

## Quick Start

All examples can be run directly using `tsx`:

```bash
# From the js_sdk directory
npx tsx examples/echoAgent.ts
npx tsx examples/advancedAgent.ts
npx tsx examples/negotiationRoomExample.ts
npx tsx examples/workflowExample.ts
npx tsx examples/handoffExample.ts
npx tsx examples/hitlEscalation.ts
```

Or using the npm script:

```bash
npm run example examples/echoAgent.ts
```

## Examples Overview

### 1. echoAgent.ts - Basic Agent

**Demonstrates:**
- Agent registration with `RegistryClient`
- Message receiving via `RouterClient.streamIncoming()`
- Echoing DATA messages back
- Basic ACK lifecycle (RECEIVED stage)
- Graceful deregistration on shutdown

**Run:**
```bash
npx tsx examples/echoAgent.ts --agent-id echo-1 --name EchoAgent
```

**Environment Variables:**
- `SW4RM_ROUTER_ADDR` - Router service address (default: `localhost:50051`)
- `SW4RM_REGISTRY_ADDR` - Registry service address (default: `localhost:50052`)
- `AGENT_ID` - Agent identifier (default: `echo-1`)
- `AGENT_NAME` - Agent display name (default: `EchoAgent`)

**Requirements:**
- Running SW4RM Router service
- Running SW4RM Registry service

---

### 2. advancedAgent.ts - Full SDK Features

**Demonstrates:**
- `ActivityBuffer` for tracking agent activities
- `WorktreeClient` for worktree binding and state management
- Full `ACKLifecycleManager` with all stages (RECEIVED, READ, FULFILLED, FAILED)
- Message processing with type-based handlers
- Persistent state across restarts (JSON file persistence)
- Graceful shutdown with state preservation

**Run:**
```bash
npx tsx examples/advancedAgent.ts --agent-id advanced-1 --name AdvancedAgent --data-dir ./agent_data
```

**Environment Variables:**
- `SW4RM_ROUTER_ADDR` - Router service address
- `SW4RM_REGISTRY_ADDR` - Registry service address
- `DATA_DIR` - Directory for persistent state (default: `./agent_data`)

**State Files Created:**
- `activity.json` - Activity buffer records
- `ack_state.json` - ACK lifecycle states
- `worktree.json` - Current worktree binding

---

### 3. negotiationRoomExample.ts - Producer-Critic-Coordinator Pattern

**Demonstrates:**
- Producer agent submitting artifacts for review
- Multiple critic agents voting on artifacts
- Coordinator aggregating votes and deciding
- Confidence-weighted scoring
- Policy-based approval thresholds
- HITL escalation for edge cases

**Run:**
```bash
npx tsx examples/negotiationRoomExample.ts
```

**Note:** This example uses mock implementations as `NegotiationRoomClient` is not yet implemented in the SDK. See Phase 2.1 in `IMPLEMENTATION_PLAN.md`.

**Key Concepts:**
- `ArtifactType`: REQUIREMENTS, PLAN, CODE, DEPLOYMENT
- `DecisionOutcome`: APPROVED, REVISION_REQUESTED, ESCALATED_TO_HITL
- Aggregation: mean, weighted mean, standard deviation
- Policy thresholds for auto-approval

---

### 4. workflowExample.ts - DAG-Based Workflow Orchestration

**Demonstrates:**
- Creating workflow definitions with nodes and dependencies
- Starting workflows and monitoring execution
- Handling node completion and state transitions
- Passing context between workflow nodes
- Parallel execution of independent branches
- DAG validation (cycle detection)

**Run:**
```bash
npx tsx examples/workflowExample.ts
```

**Note:** This example uses mock implementations as `WorkflowClient` is not yet implemented. See Phase 2.3 in `IMPLEMENTATION_PLAN.md`.

**Example Workflow (CI/CD Pipeline):**
```
build -> test -> (security_scan, quality_check) -> deploy
              \                               /
               '--- parallel execution ------'
```

**Key Concepts:**
- `NodeStatus`: PENDING, READY, RUNNING, COMPLETED, FAILED, SKIPPED
- `TriggerType`: EVENT, SCHEDULE, MANUAL, DEPENDENCY
- Input/output mapping between nodes
- Workflow state management

---

### 5. handoffExample.ts - Agent-to-Agent Task Handoff

**Demonstrates:**
- Requesting handoff when capabilities are lacking
- Accepting or rejecting handoffs based on agent state
- Context preservation during handoff
- Completing handoffs with proper lifecycle

**Run:**
```bash
npx tsx examples/handoffExample.ts
```

**Note:** This example uses mock implementations as `HandoffClient` is not yet implemented. See Phase 2.2 in `IMPLEMENTATION_PLAN.md`.

**Scenarios Covered:**
1. Successful handoff (code agent -> security agent)
2. Rejected handoff (missing capabilities)
3. Rejected handoff (busy agent)
4. Context preservation during transfer

**Key Concepts:**
- `HandoffStatus`: PENDING, ACCEPTED, REJECTED, COMPLETED, EXPIRED
- Capability-based routing
- Context snapshot transfer
- Priority handling

---

### 6. hitlEscalation.ts - Human-in-the-Loop Escalation

**Demonstrates:**
- Triggering HITL when agent confidence is low
- Handling HITL decisions for unresolved conflicts
- DEBATE_DEADLOCK handling for failed multi-agent debates
- High-risk action approval workflows
- Integration with SDK `HITLClient`

**Run:**
```bash
npx tsx examples/hitlEscalation.ts
```

**Scenarios Covered:**
1. Uncertainty escalation (low confidence classification)
2. Multi-agent conflict resolution
3. Debate deadlock breaking
4. High-risk action approval

**HITL Reason Types:**
| Type | Description |
|------|-------------|
| TASK_ESCALATION | Agent confidence below threshold |
| SECURITY_APPROVAL | Action requires explicit approval |
| CONFLICT | Agents cannot agree |
| DEBATE_DEADLOCK | Multi-round debate failed |
| MANUAL_OVERRIDE | Human requested a direct decision |
| WORKTREE_OVERRIDE | Worktree operations need approval |
| TOOL_PRIVILEGE_ESCALATION | Tool privilege escalation requested |
| CONNECTOR_APPROVAL | Connector approval required |

---

## Feature Matrix

| Example | Registry | Router | Worktree | Activity | ACK | HITL | Negotiation | Workflow | Handoff |
|---------|----------|--------|----------|----------|-----|------|-------------|----------|---------|
| echoAgent | Yes | Yes | - | - | Basic | - | - | - | - |
| advancedAgent | Yes | Yes | Yes | Yes | Full | - | - | - | - |
| negotiationRoom | - | - | - | - | - | - | Yes (mock) | - | - |
| workflowExample | - | - | - | - | - | - | - | Yes (mock) | - |
| handoffExample | - | - | - | - | - | - | - | - | Yes (mock) |
| hitlEscalation | - | - | - | - | - | Yes | - | - | - |

## SDK Components Used

### Clients
- `RegistryClient` - Agent registration and heartbeat
- `RouterClient` - Message sending and streaming
- `WorktreeClient` - Worktree binding and state
- `HITLClient` - Human-in-the-loop decisions

### Runtime Components
- `ActivityBuffer` - Activity tracking with pruning strategies
- `ACKLifecycleManager` - Message acknowledgment state machine
- `buildEnvelope()` - Envelope construction helper

### Types
- `AgentDescriptor` - Agent registration descriptor
- `EnvelopeBuilt` - Constructed message envelope
- `MessageType` - Message type enumeration
- `AckStage` - ACK lifecycle stages

## Troubleshooting

### Connection Errors

If you see connection errors, ensure SW4RM services are running:

```bash
# Check if services are accessible
nc -zv localhost 50051  # Router
nc -zv localhost 50052  # Registry
```

### TypeScript Errors

If you see TypeScript errors, ensure the SDK is built:

```bash
cd sdks/js_sdk
npm run build
```

### Missing Proto Files

If proto-related errors occur, regenerate proto stubs:

```bash
cd sdks/js_sdk
npm run build:proto
```

## Contributing

When adding new examples:

1. Follow the existing file naming convention (`camelCase.ts`)
2. Include comprehensive JSDoc comments
3. Add a shebang for direct execution (`#!/usr/bin/env npx tsx`)
4. Update this README with the new example
5. Include both mock and real service options where applicable

## Related Documentation

- [SW4RM Protocol Specification](../../../documentation/protocol/spec.md)
- [JavaScript SDK README](../README.md)
- [Implementation Plan](../../../docs/IMPLEMENTATION_PLAN.md)
- [Python SDK Examples](../../../examples/)
