# SW4-006: Resource-Aware Scheduling

**Status:** Rejected
**Date:** 2026-03-26

## Abstract

Proposal to add host-level resource awareness (RAM, CPU, swap, PSI backpressure) to the SW4RM coordination protocol, triggered by a host paralysis incident (load avg 143, swap 99.5%, 43 uncoordinated test workers).

## Verdict: Out of Scope

SW4RM is a coordination protocol, not a resource manager. Every primitive operates at the logical level — task priority, message delivery, agent state, token/time budgets. Host resource management is a fundamentally different concern.

### Why It Does Not Belong

1. **Layer violation.** SW4RM sits above the process model. It does not own agent lifecycles. Monitoring `/proc/[pid]/statm` or PSI assumes shared-host Linux deployment — the protocol is deliberately deployment-agnostic.

2. **Deployment model mismatch.** Agents can be local processes, containers, Lambda functions, or remote APIs. Resource awareness requires deployment topology knowledge — that is orchestration infrastructure (K8s, systemd), not protocol.

3. **The incident was not a protocol failure.** Uncoordinated non-SW4RM agents exhausted a host. The fix is process supervision and resource limits (cgroups, ulimits, container caps), not protocol-level scheduling.

4. **BudgetEnvelope is logical, not physical.** SW4-004 tracks tokens and wall-time — task-scoped constraints that travel with delegation. Mixing in RAM/CPU would muddy a clean abstraction.

### Why Even Advisory Metadata Does Not Belong

The heartbeat state machine is already the correct abstraction. An agent reports IDLE, BUSY, PROCESSING, FAILED_STATE, SHUTTING_DOWN. The protocol does not care *why* — only *that* the state changed. SW4-005 already filters non-serving states from routing.

Adding resource pressure metadata (even advisory) bleeds implementation into pure coordination. The spec would have opinions about memory, CPU, and swap — concepts that do not exist for a serverless agent or remote API.

### The Clean Model

An external health provider (deepmetrics, cgroup monitor, K8s liveness probes) observes system health and **drives agent state transitions** through the existing heartbeat mechanism. The protocol consumes the verdict; it does not interpret the evidence.

## Concern Mapping

| Concern | In SW4RM? | Where It Belongs |
|---------|-----------|------------------|
| Token/time budgets | Yes | SW4-004 BudgetEnvelope |
| Task priority preemption | Yes | Core Scheduler |
| Agent health/liveness | Yes | Core Heartbeat + SW4-003 |
| Host RAM/swap monitoring | No | OS / container runtime |
| PSI-based backpressure | No | Deployment orchestration |
| Process kill ordering | No | OOM killer / cgroup policy |
| Agent self-reported pressure | No | External health provider drives heartbeat state transitions |

## Action

No spec changes. No implementation. The protocol is complete for this concern. External health providers drive agent state transitions through the existing heartbeat mechanism.
