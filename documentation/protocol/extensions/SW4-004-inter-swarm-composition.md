# SW4-004: Inter-Swarm Composition Extension

**Status:** Draft
**Version:** 0.3.0
**Date:** 2026-02-15
**Spec Release:** v0.6.0 — Implementation profiles (§9.4) and conformance test outline (§10) added in this version.
**Extends:** Core Spec §4 (Architecture), §7.2 (Cooperative Preemption), §11 (Message Lifecycle), §17.6 (Agent Handoff Protocol), §18.6 (Streaming Tool Cancellation), SW4-002 (Timeout Profiles), SW4-003 (Observability)

## Abstract

This extension defines how one SW4RM swarm composes with another swarm without introducing subtype-heavy schemas or service sprawl. A swarm is exposed as a normal agent via a **Gateway Agent** contract (`SWARM_GATEWAY` registration type), and cross-swarm delegation reuses existing Handoff + Envelope primitives with minimal additive fields. The extension adds explicit inter-swarm budgeting, parent-child trace linkage, cancellation semantics, and first-class overload signaling (`OVERLOADED`) so systems can scale while preserving correctness, repairability, and bounded coordination cost.

## Motivation

The core specification already supports handoff, workflow, and routed message lifecycles, but lacks normative guidance for **inter-swarm connectivity**. Without this, implementations drift toward:

- topology leakage (parents addressing internal nodes of child swarms),
- ad-hoc retry/backpressure behavior,
- stage-specific data entities that inflate schema complexity,
- runaway nested calls that reduce correctness and repairability.

This extension standardizes a minimal composition model that preserves genericity:

- one external interface shape for both agents and swarms,
- one delegation lifecycle (handoff),
- one acknowledgment model (ACK/NACK with existing stages),
- one small set of generic persistent entities.

## Design Goals

1. Preserve substitutability: parent orchestration treats swarms and agents uniformly.
2. Keep persistence generic: avoid SDLC-specific table proliferation.
3. Bound recursion and call fanout: explicit budgets, depth limits, and backpressure.
4. Improve repairability: deterministic lineage and cancellation semantics.
5. Add overload handling now: distinguish "busy" from "failed".

## Non-Goals

- No peer-to-peer mesh between sibling swarms.
- No mandatory new services.
- No mandatory new storage engines or table families.
- No requirement to expose internal child-swarm topology to parent callers.

## 1. Inter-Swarm Connectivity Model

### 1.1 Gateway Agent Rule

A swarm participating in external coordination MUST register as a normal agent endpoint and MUST expose exactly one external delegation ingress for that swarm boundary (the **Gateway Agent**). Multiple replicas of the same logical gateway are permitted for load distribution; each replica shares the same `agent_id` and registration metadata.

Implementations conforming to SW4-004 MUST support a registration discriminator:

```protobuf
enum RegistrationType {
  REGISTRATION_TYPE_UNSPECIFIED = 0;
  STANDARD_AGENT = 1;
  SWARM_GATEWAY = 2;
}
```

Additive registry fields:

```protobuf
message AgentDescriptor {
  // existing fields...
  RegistrationType registration_type = 100;      // default STANDARD_AGENT
  uint32 max_concurrent_delegations = 101;       // see below
}
```

For agents registered as `SWARM_GATEWAY`, `max_concurrent_delegations` is **normative**: the gateway MUST reject delegations that would exceed this limit with `error_code=OVERLOADED` and SHOULD include `retry_after_ms`. For `STANDARD_AGENT`, this field is advisory (a capacity hint for callers) and carries no enforcement obligation.

### 1.2 Topology Constraints

Implementations MUST enforce hierarchical delegation:

- Parent swarm/agent MAY delegate only to Gateway Agents of child swarms.
- Child swarm internals MUST NOT be directly addressable by external callers.
- Sibling swarms MUST NOT directly delegate to each other except through a shared parent or scheduler route.

This preserves the hub-and-spoke model from Core §4 at every nested level.

### 1.3 Nesting Limits

Implementations MUST enforce `max_delegation_depth` with a default of `3`. If depth is exceeded, the receiver MUST reject delegation with `error_code=VALIDATION_ERROR` (or a stricter local policy code) and MUST include actionable diagnostics.

The receiving gateway MUST independently validate the current delegation depth by inspecting the `parent_correlation_id` chain or its own depth counter. Receivers MUST NOT trust the caller-supplied `current_depth` value without independent verification, as a misbehaving or compromised caller could understate depth to bypass limits.

## 2. Cross-Swarm Delegation Contract

SW4-004 reuses Handoff lifecycle and augments it with budget and policy envelopes.

### 2.1 Budget Envelope (Required for Cross-Swarm Delegation)

```protobuf
message BudgetEnvelope {
  uint64 token_budget_remaining = 1;
  uint64 wall_time_remaining_ms = 2;
  uint64 deadline_epoch_ms = 3;
  uint32 current_depth = 4;
  uint32 max_delegation_depth = 5;
}
```

Normative rules:

1. `deadline_epoch_ms` MUST be present for cross-swarm delegation.
2. Budget values MUST be monotonic decreasing across boundaries.
3. A callee MAY tighten inherited budgets but MUST NOT increase them.
4. Every agent in the call chain MUST check `now_ms > deadline_epoch_ms` before starting new model/tool work; if exceeded, it MUST fail fast with timeout semantics.
5. `token_budget_remaining` counts **combined LLM input + output tokens** consumed across the delegation subtree. Callers MUST subtract their own token usage before propagating the budget to callees.
6. Agents MUST check the cancellation flag (§5) at the same checkpoints where they check `deadline_epoch_ms`. Both checks MUST occur before starting new model inference or tool invocations.

### 2.2 Delegation Policy (Optional but Recommended)

```protobuf
message SwarmDelegationPolicy {
  uint32 max_retries_on_overloaded = 1;
  uint64 initial_backoff_ms = 2;
  double backoff_multiplier = 3;
  uint64 max_backoff_ms = 4;
  bool allow_spillover_routing = 5;
}
```

When `allow_spillover_routing` is `true`, the caller permits the target gateway to redirect the delegation to an equivalent peer gateway when the primary gateway is overloaded or approaching capacity limits. The specific mechanics of peer discovery and redirect signaling are implementation-defined in this version of the spec. A future extension (SW4-005) may formalize spillover routing semantics including peer advertisement, health-aware selection, and redirect message types.

### 2.3 Handoff Message Additions

```protobuf
message HandoffRequest {
  // existing fields...
  BudgetEnvelope budget = 100;
  SwarmDelegationPolicy delegation_policy = 101;
}

message HandoffResponse {
  // existing fields...
  sw4rm.common.ErrorCode rejection_code = 100;
  uint64 retry_after_ms = 101;
}
```

`rejection_code` MUST be set when `accepted=false`.

## 3. Envelope and Lineage Additions

To reconstruct cross-swarm traces without new trace entities, add one Envelope field:

```protobuf
message Envelope {
  // existing fields...
  string parent_correlation_id = 100;
}
```

Normative rules:

- `parent_correlation_id` MUST be set on first envelope crossing a swarm boundary.
- Child internal envelopes SHOULD keep their own `correlation_id` and MAY continue carrying `parent_correlation_id` for lineage.
- Lineage reconstruction MUST be possible using only `(correlation_id, parent_correlation_id, message_id, idempotency_token)`.

### 3.1 Multi-Hop Trace Reconstruction

For delegation chains deeper than 2 (i.e., swarm A → swarm B → swarm C), the full lineage can be reconstructed by walking the `parent_correlation_id` chain through the `envelope_log`:

1. Start with the leaf envelope's `correlation_id`.
2. Look up its `parent_correlation_id` in `envelope_log`.
3. Use the parent's `correlation_id` to find the next ancestor; repeat until `parent_correlation_id` is empty (the root).

Implementations SHOULD maintain an index on `(correlation_id, parent_correlation_id)` pairs in `envelope_log` to support efficient ancestor lookups. Without this index, reconstruction requires a full scan per hop and degrades at scale.

## 4. Backpressure and `OVERLOADED`

### 4.1 Error Code Extension

Add a first-class overload signal:

```protobuf
enum ErrorCode {
  // existing values 0-15, 99...
  OVERLOADED = 16;
}
```

> **Note:** Values 14 (`DUPLICATE_DETECTED`) and 15 (`ALREADY_IN_PROGRESS`) are allocated by Core. SW4-004 error codes begin at 16; see Appendix A for the full allocation registry.

### 4.2 Semantics

When a receiver cannot accept more delegated work due to concurrency, queue, or policy pressure, it MUST reject quickly using one of:

1. Handoff reject: `accepted=false`, `rejection_code=OVERLOADED`, optional `retry_after_ms`.
2. Message-plane NACK/ACK terminal rejection: `ack_stage=REJECTED`, `error_code=OVERLOADED`.

`OVERLOADED` MUST be treated as **backpressure**, not execution failure.

### 4.3 Caller Behavior on `OVERLOADED`

Callers MUST apply retry/reroute policy before escalating to failure:

1. Respect `retry_after_ms` when present.
2. Apply bounded exponential backoff with full jitter (recommended).
3. Add uniform random jitter of up to 20% of `retry_after_ms` to prevent thundering herd effects. For example, if `retry_after_ms=1000`, the actual wait MUST be in the range `[1000, 1200]`.
4. Stop retrying when budget envelope is exhausted.
5. Escalate as failure only after policy/budget exhaustion.

## 5. Cancellation Semantics

This section defines cascading cancellation for cross-swarm delegations, following a cooperative SIGTERM/SIGKILL model aligned with Core §7.2 (Cooperative Preemption) and §18.6 (Streaming Tool Cancellation).

### 5.1 CancelDelegation Message

```protobuf
message CancelDelegation {
  string correlation_id = 1;        // identifies the delegation to cancel
  string reason = 2;                // human-readable cancellation reason
  uint64 grace_period_ms = 3;       // time allowed for cleanup before forced termination
}

message CancelDelegationResponse {
  bool acknowledged = 1;
  string message = 2;
}
```

The `CancelDelegation` RPC is added to `HandoffService`:

```protobuf
service HandoffService {
  // existing RPCs...
  rpc CancelDelegation(CancelDelegation) returns (CancelDelegationResponse);
}
```

### 5.2 Gateway Cancellation Behavior

Upon receiving a `CancelDelegation` request, the gateway MUST:

1. **Acknowledge immediately**: return `CancelDelegationResponse{acknowledged=true}` to the caller. This does not mean cancellation is complete; it confirms receipt.
2. **Propagate SIGTERM**: set the cancellation flag on all active work items for the given `correlation_id` and propagate `CancelDelegation` to any child gateways the delegation was further delegated to.
3. **Enforce grace period**: start a grace period timer. If the delegated work does not reach a terminal state within `grace_period_ms`, the gateway MUST force-terminate (SIGKILL) the remaining work by failing all outstanding work items with `error_code=FORCED_PREEMPTION`.
4. **Report terminal status**: once all child work is terminated (cooperatively or forcefully), the gateway MUST report a terminal handoff status to the original caller.

### 5.3 Cascading Cancellation

At delegation depth > 1, cancellation propagates recursively: a gateway that receives `CancelDelegation` MUST forward it to all child gateways it delegated to, using the child delegation's `correlation_id`. Each child gateway follows the same acknowledge → propagate → enforce → report sequence.

### 5.4 Cooperative Preemption Integration

Agents check the cancellation flag at the same safe points where they check `deadline_epoch_ms` (§2.1 rule 6). When the cancellation flag is set:

- The agent MUST stop starting new model inference or tool invocations.
- Non-preemptible sections (e.g., in-flight atomic operations) are deferred until the next safe point, consistent with Core §7.2.
- Active streaming tool calls MUST receive a `Cancel` RPC per Core §18.6, bounded by the delegation's grace period.

### 5.5 Grace Period Defaults

| Trigger | Default Grace Period |
|---|---|
| Explicit `CancelDelegation` | As specified in `grace_period_ms` (minimum 5000ms) |
| Budget exhaustion (`token_budget_remaining = 0`) | 5000ms |
| Deadline expiry (`now_ms > deadline_epoch_ms`) | 5000ms |

If a caller sends `grace_period_ms = 0`, the receiver MUST treat it as the minimum (5000ms). This ensures at-exit handlers have a bounded window to complete.

### 5.6 At-Exit Handlers

Agents MAY register cleanup handlers (at-exit handlers) that execute during the grace period after cancellation. At-exit handlers:

- MUST complete within the remaining grace period; the gateway MUST force-terminate handlers that exceed it.
- MUST NOT start new model inference or tool invocations.
- SHOULD be idempotent, as cancellation may be signaled more than once during edge cases (e.g., cascading cancel arriving after deadline-triggered cancel).

### 5.7 Compatibility

Implementations that do not support `CancelDelegation` will not expose the RPC. Callers that receive an `UNIMPLEMENTED` gRPC status when calling `CancelDelegation` MUST fall back to deadline-based expiry: the delegation will terminate when `deadline_epoch_ms` is exceeded and the receiver's own deadline check fires. This fallback provides eventual termination but without the cooperative cleanup guarantees of explicit cancellation.

## 6. Data Model Constraints (Minimal-Entity Profile)

To minimize schema entropy while preserving extensibility, implementations SHOULD use three generic logical entities for inter-swarm runtime state:

1. `envelope_log` (immutable append-only envelope and ACK records)
2. `work_item` (mutable execution unit state, references envelope lineage)
3. `policy_snapshot` (immutable policy blobs/version references used at decision time)

Guidance:

- SDLC stages MUST be encoded as tags/metadata, not table families.
- Dashboards and analytics SHOULD use derived views/materializations, not new core entities.
- Implementations MAY physically map these entities differently, but conformance claims SHOULD document the logical mapping.

## 7. SDLC Composition Guidance

This extension does not mandate SDLC topology, but recommends the following default profile for bounded complexity:

- Requirements/Planning: Agent
- Build/Verify: Swarm (Gateway-exposed)
- Deploy: Agent (promote to swarm only when rollback/rollforward orchestration complexity requires it)
- Monitor/Observer: Agent (or lightweight swarm if multi-source triage is needed)

This profile keeps recursion where concurrency payoff is high while limiting cross-swarm traffic.

## 8. Observability Requirements

Implementations conforming to SW4-004 MUST emit metrics and traces sufficient to diagnose overload, nested delegation behavior, and cancellation.

### 8.1 Required Metrics

- `sw4rm_swarm_delegations_total{from_agent,to_agent,result}`
- `sw4rm_swarm_overloaded_total{to_agent}`
- `sw4rm_swarm_retry_total{from_agent,to_agent,reason}`
- `sw4rm_swarm_depth_current{agent_id}`
- `sw4rm_swarm_budget_exhausted_total{agent_id,budget_type}`
- `sw4rm_swarm_cancellations_total{agent_id,trigger}` — where `trigger` is one of `explicit`, `budget`, `deadline`

### 8.2 Required Span Attributes

- `sw4rm.correlation_id`
- `sw4rm.parent_correlation_id`
- `sw4rm.delegation_depth`
- `sw4rm.registration_type`

## 9. Implementation Requirements

### 9.1 MUST Requirements

Implementations claiming SW4-004 conformance MUST:

1. Support `SWARM_GATEWAY` registration type.
2. Enforce hierarchical gateway-only inter-swarm delegation.
3. Support `BudgetEnvelope` on cross-swarm handoff.
4. Enforce budget monotonicity and absolute deadline checks.
5. Support `OVERLOADED` (value 16) as a first-class rejection/error code.
6. Include `parent_correlation_id` on cross-swarm boundary envelopes.
7. Emit overload, delegation-depth, and cancellation observability signals.
8. Enforce `max_delegation_depth` with a default of `3`.
9. Independently validate delegation depth (MUST NOT trust caller-supplied `current_depth`).
10. Enforce `max_concurrent_delegations` for `SWARM_GATEWAY` registrations.
11. Check cancellation flag at the same checkpoints as deadline checks.
12. Add jitter of up to 20% to `retry_after_ms` on OVERLOADED retries.

### 9.2 SHOULD Requirements

Implementations SHOULD:

1. Support `retry_after_ms` hints on overload responses.
2. Keep persistence in the minimal-entity logical profile.
3. Keep deploy stage as an agent until orchestration pressure justifies swarm promotion.
4. Support `CancelDelegation` RPC with cascading propagation.
5. Index `(correlation_id, parent_correlation_id)` pairs for efficient trace reconstruction.

### 9.3 MAY Requirements

Implementations MAY:

1. Add adaptive spillover routing among equivalent gateway agents.
2. Add weighted overload admission controls per capability class.
3. Introduce richer saturation states in a future extension (for example SW4-005).
4. Register at-exit handlers for cleanup during cancellation grace periods.

### 9.4 SW4-004/SW4-005 Implementation Profile (Cross-SDK Required Behavior)

Implementations claiming SW4-004 conformance, and implementations that additionally enable SW4-005 spillover routing, MUST apply this interoperable behavior profile:

1. Redirect target normalization is mandatory for parity: gateways MUST emit `redirect_to_agent_id` using the canonical registry `agent_id` string with no leading or trailing ASCII whitespace, and callers MUST trim leading/trailing ASCII whitespace before policy checks, then resolve to a canonical registry `agent_id`; if canonical resolution fails, callers MUST terminate the attempt with validation failure and MUST NOT retry that hop.
2. Redirect loop detection: callers MUST track visited redirect targets by canonical `agent_id` per delegation attempt and MUST terminate the attempt when a canonical redirect target repeats.
3. Effective default redirect bound: callers MUST treat `SwarmDelegationPolicy.max_redirects` values of `0` or unset as an effective bound of `2`.
4. Deadline and wall-time monotonicity: callers MUST deduct elapsed wall-clock time from `BudgetEnvelope.wall_time_remaining_ms` on every redirect hop, and receivers/callers MUST NOT increase `deadline_epoch_ms` at any cross-swarm boundary.
5. Cancellation propagation and grace handling: gateways receiving cancellation MUST follow acknowledge -> cascade -> enforce behavior (§5.2), and each child delegation's grace window MUST be clamped to remaining parent grace time with a minimum effective floor of `5000ms`.
6. Overloaded fallback when spillover is disabled: when `allow_spillover_routing=false` (or delegation policy is absent), gateways MUST return SW4-004 `OVERLOADED` behavior and MUST NOT emit redirect signaling.

## 10. Conformance Test Outline

The following table defines normative test scenarios. An implementation claiming SW4-004 conformance MUST pass all scenarios marked **Required** and SHOULD pass those marked **Recommended**.

| ID | Scenario | Requirement Level | Validates |
|---|---|---|---|
| T-001 | Depth limit rejection | Required | §1.3 — Gateway rejects delegation when `current_depth >= max_delegation_depth` with `VALIDATION_ERROR` |
| T-002 | Independent depth validation | Required | §1.3 — Gateway correctly rejects when caller understates `current_depth` (independent verification) |
| T-003 | Budget monotonicity enforcement | Required | §2.1 — Callee rejects or corrects a budget envelope where child budget exceeds parent budget |
| T-004 | Deadline expiry fail-fast | Required | §2.1 — Agent stops new model/tool work when `now_ms > deadline_epoch_ms` |
| T-005 | Overload backpressure signal | Required | §4.1, §4.2 — Gateway returns `OVERLOADED` (not generic failure) when at capacity |
| T-006 | Retry jitter compliance | Required | §4.3 — Caller adds ≤20% uniform jitter to `retry_after_ms`; does not retry before jittered delay |
| T-007 | Cancellation cascade (depth=2) | Recommended | §5.3 — Cancel propagates from parent gateway to child gateway; both reach terminal state |
| T-008 | Cancellation grace period | Recommended | §5.5, §5.6 — At-exit handlers run within grace period; work stops after grace expiry |
| T-009 | Forced termination after grace | Recommended | §5.2 — Gateway force-terminates with `FORCED_PREEMPTION` after grace period expires |
| T-010 | Gateway-only addressing | Required | §1.2 — External caller cannot directly address child-swarm internal agents |
| T-011 | Parent correlation on boundary | Required | §3 — `parent_correlation_id` is set on first envelope crossing a swarm boundary |
| T-012 | Non-preemptible section during cancel | Recommended | §5.4 — Agent in non-preemptible section defers cancellation to next safe point per Core §7.2 |
| T-013 | Redirect loop rejection | Required | §9.4 — Caller terminates attempt when a redirect target repeats |
| T-014 | Effective default redirect bound | Required | §9.4 — `max_redirects` unset/`0` behaves as effective value `2` |
| T-015 | Redirect budget/deadline monotonicity | Required | §9.4 — `wall_time_remaining_ms` strictly decreases by elapsed routing time and `deadline_epoch_ms` never increases |
| T-016 | Cascading cancellation grace clamp | Required | §5.2, §9.4 — Child cancellation grace is clamped to parent remaining grace with `5000ms` minimum floor |
| T-017 | Spillover-disabled overload fallback | Required | §9.4 — Gateway returns `OVERLOADED` and does not emit redirect when spillover is disabled |
| T-018 | Canonical redirect target normalization | Required | §9.4 — Redirect targets resolve to canonical registry `agent_id` and invalid canonicalization is treated as terminal validation failure |

## 11. Compatibility

This extension is additive and backward-compatible:

- Existing clients that ignore additive fields continue to function.
- Implementations without SW4-004 retain current handoff behavior but do not have standardized inter-swarm composition guarantees.
- `OVERLOADED` SHOULD degrade to generic rejection handling in older clients.
- `CancelDelegation` degrades to deadline-based expiry in implementations that do not support it (see §5.7).

## 12. Migration Guidance

Recommended rollout order:

1. **Extract runtime ABCs + gateway interface together**
   Phase equivalent to decomposition Step 2.2; avoid separate moves.

2. **Wrap Build/Verify as first Gateway swarm**
   Keep external surface as existing handoff/task contracts with additive fields.

3. **Enable budget/depth enforcement + overloaded handling**
   Start conservative retry limits; tune from production telemetry.

4. **Add cancellation support**
   Deploy `CancelDelegation` RPC; existing deadline-based expiry continues as fallback.

5. **Promote additional SDLC stages only if concurrency economics justify it**
   Prefer agents by default.

## 13. Security Considerations

- Gateway-only topology reduces attack surface by hiding child internals.
- `OVERLOADED` responses MUST NOT leak sensitive capacity internals beyond bounded metadata (`retry_after_ms`, coarse reason).
- Deadline enforcement reduces zombie execution and token abuse in deep nesting.
- Implementations SHOULD apply ACLs so only authorized parents can delegate to a given gateway.
- Independent depth validation (§1.3) prevents compromised callers from bypassing nesting limits.
- Cancellation grace period minimum (5000ms) prevents denial-of-service via zero-grace forced termination.

## Appendix A. Field Number Allocation Registry

To prevent field number collisions across extensions sharing the same protobuf messages, this appendix defines a normative allocation registry. Extension authors MUST claim a range here before defining new fields.

### A.1 Per-Message Field Number Ranges

| Owner | Range (per message) | Notes |
|---|---|---|
| Core Spec | 1–16 | Current max across Envelope, HandoffRequest, etc. |
| SW4-002 (Timeout Profiles) | 50–59 | Pre-allocated; none used yet |
| SW4-003 (Observability) | 60–69 | Pre-allocated; none used yet |
| SW4-004 (Inter-Swarm Composition) | 100–109 | 100–101 used in AgentDescriptor, HandoffRequest, HandoffResponse, Envelope |
| SW4-005+ (Future) | 110+ | Must be claimed in a future extension document |

### A.2 ErrorCode Enum Allocation

| Owner | Values | Entries |
|---|---|---|
| Core Spec | 0–15, 99 | `ERROR_CODE_UNSPECIFIED` (0) through `ALREADY_IN_PROGRESS` (15), `INTERNAL_ERROR` (99) |
| SW4-004 | 16–19 | `OVERLOADED` (16); 17–19 reserved for future SW4-004 use |
| SW4-005+ | 20+ | Must be claimed in a future extension document |

## 14. References

- Core Spec §4: Architecture
- Core Spec §7.2: Cooperative Preemption
- Core Spec §11: Message Lifecycle and ACK semantics
- Core Spec §17.6: Agent Handoff Protocol
- Core Spec §18.6: Streaming Tool Cancellation
- SW4-002: Timeout Profiles Extension
- SW4-003: Observability Extension
- SW4-005: Spillover Routing Extension

---

*This extension is part of the SW4RM protocol extension series.*
