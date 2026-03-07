# How SW4RM Coordinates Code-Writing Agents

**Issue:** I141

## Why Coordination Is Hard

Multi-agent coding teams rarely fail because no one is smart enough to write code.
They fail when communication, ownership, and task boundaries are unclear.

In SW4RM, we use explicit protocol-level coordination so agents stay autonomous without
becoming chaotic:

- each agent publishes/consumes standard envelopes,
- task ownership is explicit,
- state transitions are observable,
- and completion criteria are machine-checkable.

## How SW4RM Helps

SW4RM’s protocol design gives code-writing teams:

- a shared contract for routing and negotiation,
- deterministic handoff paths between agents,
- explicit heartbeat and recovery semantics,
- and extension points for tracing and observability.

That means a code-writing agent can hand a partial implementation to a reviewer,
where the reviewer can request targeted revision loops instead of re-deriving context.

## The “LLM Integration” Pattern

Across all SDKs, the LLM integration extension follows the same pattern:

1. Keep provider specifics behind a narrow adapter interface.
2. Route all orchestration requests through protocol messages, not out-of-band side channels.
3. Record agent decisions in extension state so future turns can continue from concrete artifacts.
4. Use metrics and trace signals to catch quality regressions early (retry spikes, queue delays, nacks).

For SW4RM today, this keeps “agent writes code” and “agent critiques code” in the same
coordinated loop with auditable inputs and repeatable exits.

## What We Changed in This Cycle

- Added production-capable metrics backend plumbing for Python SDK emitters (StatsD/Datadog path).
- Updated cross-SDK extension docs so the LLM Integration extension is tracked across all five SDKs.
- Continued hardening the production tranche queue so observability and operational readiness stay aligned.

## Why This Matters

When each SDK and agent follows the same coordination contract, we can scale code-writing effort safely.
The team gains:

- faster iteration with fewer blind spots,
- clearer recovery when one agent diverges,
- stronger governance through logged handoffs and metrics,
- and a reusable operating model for future autonomous coding tranches.

---

This post is the checkpoint write-up for I141 in the SW4RM execution stream.
