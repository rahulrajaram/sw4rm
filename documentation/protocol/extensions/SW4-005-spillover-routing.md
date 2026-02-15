# SW4-005: Spillover Routing

**Status:** Draft
**Version:** 0.2.1
**Date:** 2026-02-14
**Extends:** Core Spec §4 (Architecture), SW4-004 §2.2 (Delegation Policy), SW4-004 §4.3 (OVERLOADED Backpressure), SW4-004 §9.3 (Adaptive Spillover)

## Abstract

This extension defines normative spillover routing semantics for cross-swarm delegation when a target gateway is overloaded. SW4-005 standardizes peer discovery, redirect signaling, redirect-chain limits, health-aware target selection, and budget accounting across redirect hops. The extension is additive to SW4-004 and preserves opt-in behavior via `allow_spillover_routing`.

## 1. Scope

SW4-005 applies to delegation attempts sent through SW4-004 `HandoffService` where:

- the request includes `SwarmDelegationPolicy`
- `allow_spillover_routing=true`
- the receiver is registered as `SWARM_GATEWAY`

SW4-005 does not change SW4-004 cancellation semantics, budget schema, or gateway topology constraints.

## 2. Normative Language

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY in this document are to be interpreted as described in RFC 2119.

## 3. Protocol Additions

### 3.1 ErrorCode Addition

SW4-005 allocates error-code values 20-23 and defines:

```protobuf
enum ErrorCode {
  // existing values...
  REDIRECT = 20;
}
```

### 3.2 HandoffResponse Addition

SW4-005 allocates per-message fields 110-119 and defines:

```protobuf
message HandoffResponse {
  // existing fields...
  string redirect_to_agent_id = 110;
}
```

### 3.3 SwarmDelegationPolicy Addition

SW4-005 allocates policy fields 6-10 and defines:

```protobuf
message SwarmDelegationPolicy {
  // SW4-004 fields 1..5...
  uint32 max_redirects = 6;  // 0 => effective default 2
}
```

## 4. Peer Discovery and Equivalence

A gateway implementing SW4-005 MUST derive redirect candidates from registry entries. A peer is eligible only if:

1. `registration_type = SWARM_GATEWAY`
2. `capabilities` exactly match the source gateway capability set
3. `agent_id` differs from the source gateway `agent_id`

Additional rules:

1. A gateway MUST NOT redirect to itself.
2. A gateway MUST NOT redirect to non-gateway registrations.
3. Implementations MAY apply local allowlist or denylist filtering, but such filtering MUST only reduce the eligible set.
4. Implementations MUST NOT introduce a private peer outside the registry-eligible set for protocol-visible redirect decisions.

## 5. Redirect Signaling Semantics

When spillover is enabled and a gateway cannot accept work, the gateway MAY return a caller-visible redirect.

Normative requirements:

1. A gateway MUST emit redirect signaling only when `allow_spillover_routing=true`.
2. When `allow_spillover_routing=false` (or delegation policy is absent), a gateway MUST return SW4-004 `OVERLOADED` behavior and MUST NOT emit `REDIRECT`.
3. A redirect response MUST set `accepted=false`.
4. A redirect response MUST set `rejection_code=REDIRECT`.
5. A redirect response MUST set `redirect_to_agent_id` to an eligible peer `agent_id`.
6. A redirect response MUST NOT set `retry_after_ms`.
7. If no healthy eligible peer exists, the gateway MUST return SW4-004 `OVERLOADED` behavior instead of `REDIRECT`.
8. Protocol interoperability MUST NOT depend on transparent proxy forwarding between gateways.
9. A redirect response MUST emit `redirect_to_agent_id` in canonical registry `agent_id` form with no leading or trailing ASCII whitespace.

## 6. Redirect Chain Limits

Redirect following is bounded per delegation attempt:

1. If `max_redirects=0` or unset, callers MUST use an effective value of `2`.
2. Callers MUST stop following redirects after `effective_max_redirects` successful redirect hops.
3. Once the limit is reached, callers MUST treat the attempt as rejected and MUST NOT follow further redirects for that attempt.
4. Callers MUST track visited canonical `agent_id` values and MUST terminate early on loop detection.

## 7. Health-Aware Target Selection

Gateways MUST perform admission filtering before selecting a redirect target:

1. Exclude peers with stale heartbeat timestamps (older than local liveness threshold).
2. Exclude peers in non-serving states (`INITIALIZING`, `FAILED_STATE`, `SHUTTING_DOWN`).
3. Temporarily de-prioritize peers that recently returned `OVERLOADED` until `retry_after_ms` expires or local cooldown expires.
4. Select from the remaining healthy peers using round-robin.
5. If the healthy set is empty, return SW4-004 `OVERLOADED`.

Implementations MAY add weighting or latency-aware tie-breakers after health filtering, but MUST preserve fairness and MUST NOT bypass exclusion rules.

## 8. Budget Accounting Across Redirects

For a single delegation attempt with redirects:

1. Callers MUST deduct elapsed wall-clock time from `BudgetEnvelope.wall_time_remaining_ms` at each rejected redirect hop.
2. Callers MUST preserve `token_budget_remaining` across redirect hops unless model inference has already consumed tokens locally.
3. Callers MUST stop redirect-following when `wall_time_remaining_ms` reaches zero.
4. If both `wall_time_remaining_ms` and `deadline_epoch_ms` are present, callers MUST enforce the stricter bound at each hop.
5. Redirect overhead MUST be treated as routing overhead, not inference work.
6. `deadline_epoch_ms` MUST remain unchanged or become stricter across redirect hops; callers MUST reject any hop that attempts to extend deadline budget.

## 9. Caller Processing Model

For each delegation attempt where spillover is enabled:

1. Send handoff to initial gateway.
2. If accepted, complete normally.
3. If rejected with `REDIRECT`, validate target and policy limits.
4. Update budget envelope with elapsed wall time.
5. Retry to `redirect_to_agent_id`.
6. Repeat until accepted or terminal condition (limit reached, budget exhausted, deadline exceeded, or non-redirect rejection).

Callers MUST preserve correlation and idempotency metadata across redirect hops.

## 10. Observability Requirements

Implementations claiming SW4-005 conformance MUST emit:

- `sw4rm_swarm_redirects_total{from_gateway,to_gateway,result}`
- `sw4rm_swarm_redirect_latency_ms{from_gateway,to_gateway}`
- `sw4rm_swarm_redirect_limit_reached_total{from_gateway}`

Required span attributes:

- `sw4rm.redirect_count`
- `sw4rm.redirect_chain`
- `sw4rm.redirect_terminal_reason`

## 11. Conformance Test Outline

The following conformance scenarios define the minimum SW4-005 test surface:

| ID | Scenario | Expected Result |
|---|---|---|
| R-001 | Spillover disabled (`allow_spillover_routing=false`) | Gateway never emits `REDIRECT` |
| R-002 | Eligible peer exists and gateway overloaded | Rejection uses `REDIRECT` + `redirect_to_agent_id` |
| R-003 | No eligible healthy peers | Rejection uses `OVERLOADED`, not `REDIRECT` |
| R-004 | Redirect response shape | `accepted=false`, `rejection_code=REDIRECT`, no `retry_after_ms` |
| R-005 | Default redirect bound | `max_redirects=0` behaves as effective value 2 |
| R-006 | Explicit redirect bound | Caller stops after configured `max_redirects` |
| R-007 | Health filtering | Stale or non-serving peers are never selected |
| R-008 | Round-robin fairness | Sequential redirects rotate across healthy peers |
| R-009 | Wall-time budget deduction | `wall_time_remaining_ms` decreases across hops |
| R-010 | Deadline enforcement | Caller aborts redirects when stricter deadline bound is hit |
| R-011 | Metadata continuity | Correlation and idempotency metadata preserved across hops |
| R-012 | Backward compatibility | Legacy non-SW4-005 gateway behavior falls back to SW4-004 retries |
| R-013 | Redirect target canonicalization | Caller trims/normalizes redirect target to canonical registry `agent_id`; unresolved canonicalization is terminal validation failure |

## 12. Field Allocation Registry

Per SW4-004 Appendix A, SW4-005 claims:

| Context | Range | Allocations in this spec |
|---|---|---|
| Per-message fields | 110-119 | `HandoffResponse.redirect_to_agent_id = 110` |
| ErrorCode enum | 20-23 | `REDIRECT = 20` |
| SwarmDelegationPolicy fields | 6-10 | `max_redirects = 6` |

Future SW4-005 revisions MUST keep new allocations within these ranges.

## 13. Compatibility and Rollout

Compatibility rules:

1. SW4-005 is additive and does not modify SW4-004 wire compatibility.
2. Clients that do not implement SW4-005 will treat `REDIRECT` as a generic rejection and may fall back to existing retry logic.
3. Gateways that do not implement SW4-005 will continue returning SW4-004 `OVERLOADED` responses.
4. Mixed-version deployments SHOULD roll out caller support before enabling spillover in gateway policy defaults.

## 14. Implementation Requirements

### 14.1 MUST

1. Enforce opt-in via `allow_spillover_routing`.
2. Emit protocol-valid redirect responses.
3. Enforce redirect chain bounds with default effective value 2.
4. Deduct redirect wall-time overhead from `BudgetEnvelope`.
5. Select targets with health-aware filtering and round-robin.
6. Emit redirect observability metrics and span attributes.
7. Conform to the SW4-004/SW4-005 interoperable implementation profile in §15.

### 14.2 SHOULD

1. Detect and terminate redirect loops early.
2. Apply cooldown windows for recently overloaded peers.
3. Preserve idempotency token and lineage metadata unchanged across hops.

### 14.3 MAY

1. Use weighted round-robin after required health filtering.
2. Apply locality or latency preferences as tie-breakers.

## 15. SW4-004/SW4-005 Implementation Profile

Implementations claiming SW4-005 conformance MUST satisfy SW4-004 §9.4 and this section as one interoperable profile across SDKs:

1. Redirect target normalization is mandatory: gateways emit canonical registry `agent_id`; callers trim leading/trailing ASCII whitespace, resolve to canonical registry `agent_id`, and reject unresolved targets as terminal validation failure.
2. Redirect loop detection is mandatory: callers track visited canonical `agent_id` values per attempt and stop when a value repeats.
3. Default redirect bounds are mandatory: `max_redirects` of `0` or unset means effective value `2`.
4. Budget monotonicity is mandatory: `wall_time_remaining_ms` decreases by elapsed routing overhead at each hop, and `deadline_epoch_ms` never increases.
5. Cancellation cascade semantics from SW4-004 remain mandatory: acknowledge, cascade, and enforce grace handling with a `5000ms` minimum floor.
6. Spillover disable semantics are mandatory: if spillover is disabled, gateways return `OVERLOADED` and never emit `REDIRECT`.

## 16. References

- SW4-004 §2.2 Delegation Policy
- SW4-004 §4.3 Caller Behavior on `OVERLOADED`
- SW4-004 §5 Cancellation Semantics
- SW4-004 §9.4 SW4-004/SW4-005 Implementation Profile
- SW4-004 §9.3 Adaptive Spillover Guidance
- SW4-004 Appendix A Field Number Allocation Registry
- Core Spec §4 Architecture
