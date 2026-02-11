# SW4RM Cross-SDK Parity Audit

**Audit Date**: 2026-02-11
**SDKs Audited**: Python (`sdks/py_sdk/`), JavaScript/TypeScript (`sdks/js_sdk/`), Rust (`sdks/rust_sdk/`), Common Lisp (`sdks/cl_sdk/`)

## Executive Summary

Found **3 critical issues**, **4 high-priority issues**, and **7 medium-priority discrepancies** across the four SDK implementations.

---

## 1. Discrepancy Priority Summary

### CRITICAL (Must Fix)

| # | Issue | SDKs Affected |
|---|-------|--------------|
| C1 | Python SDK has NO state transition validation | Python |
| C2 | Rust ActivityBuffer silently prunes instead of rejecting (violates spec 10.1) | Rust |
| C3 | JS idempotency token format incompatible with other SDKs | JS |

### HIGH (Should Fix)

| # | Issue | SDKs Affected |
|---|-------|--------------|
| H1 | Default endpoint format inconsistent (scheme vs no scheme) | Python, CL |
| H2 | Python AgentConfig missing many fields vs JS/Rust | Python |
| H3 | Two different ActivityBuffer models split across SDKs | All |
| H4 | Python timeout in seconds, all others in milliseconds | Python |

### MEDIUM (Should Address)

| # | Issue | SDKs Affected |
|---|-------|--------------|
| M1 | JS EnvelopeBuilt has `timestamp` field not in other SDKs | JS |
| M2 | HLC timestamp format differs (CL uses richer format) | CL |
| M3 | Only Python has idempotency dedup in activity buffer | JS, Rust, CL |
| M4 | Rust has no state machine class (only validation fns) | Rust |
| M5 | StateTransitionError error code differs (INTERNAL vs VALIDATION) | JS vs Python/CL |
| M6 | CL version default "0.6.0" vs JS/Rust "0.1.0" | CL, JS, Rust |
| M7 | Rust and CL missing SW4RMConfig global singleton | Rust, CL |

---

## 2. Envelope Structure Parity

All SDKs implement the 16-field envelope matching `common.proto`. SDK extension fields (`effective_policy_id`, `audit_proof`, `audit_policy_id`) are present in all four SDKs.

**Discrepancy**: `timestamp` field (proto field 14) is only in JS/TS. Python, Rust, CL omit it.

**Content-type defaulting**:
- Python/CL: Always `"application/json"`
- JS: `"application/octet-stream"` for binary payloads
- Rust: `with_payload()` overrides to `"application/octet-stream"`

---

## 3. Error Types / Exception Hierarchy

| Error Type | Python | JS | Rust | CL |
|-----------|--------|-----|------|-----|
| Base error | `SW4RMError` | `Sw4rmError` | `Error` (enum) | `sw4rm-error` |
| Validation | `ValidationError` | `ValidationError` | `Error::Validation` | `validation-error` |
| State Transition | `StateTransitionError` | `StateTransitionError` | `StateTransitionError` | `state-transition-error` |
| Timeout | `TimeoutError` | `TimeoutError` | `Error::Timeout` | `timeout-error` |
| Buffer Full | `BufferFullError` | `BufferFullError` | **(missing)** | `buffer-full-error` |
| Negotiation | `NegotiationError` | `NegotiationError` | **(missing)** | `negotiation-error` |
| Worktree | `WorktreeError` | **(missing)** | **(missing)** | `worktree-error` |
| Preemption | `PreemptionError` | **(missing)** | (via runtime) | **(missing)** |
| Policy Violation | `PolicyViolationError` | `PermissionError` | **(missing)** | **(missing)** |
| Duplicate Detected | **(missing)** | `DuplicateDetectedError` | **(missing)** | `duplicate-detected-error` |

**StateTransitionError default code**: Python=INTERNAL_ERROR(99), JS=VALIDATION_ERROR(6) -- must agree.

---

## 4. Configuration Parity

### Default Endpoint Format

| SDK | Format | Example |
|-----|--------|---------|
| Python | `host:port` (no scheme) | `localhost:50051` |
| JS | `http://host:port` | `http://localhost:50051` |
| Rust | `http://host:port` | `http://localhost:50051` |
| CL | `host:port` (no scheme) | `localhost:50051` |

### AgentConfig Fields

| Field | Python | JS | Rust | CL |
|-------|--------|-----|------|-----|
| version | N | Y | Y | Y |
| capabilities | N | Y | Y | Y |
| timeout unit | seconds | ms | ms | ms |
| heartbeat_interval | N | N | Y | Y |
| communication_class | N | Y | Y | N |
| modalities_supported | N | Y | Y | N |
| public_key | N | Y | Y | N |
| metadata | N | Y | Y | N |

### SW4RMConfig Global Singleton

| SDK | Has global config? |
|-----|-------------------|
| Python | Y |
| JS | Y |
| Rust | **N** |
| CL | **N** |

---

## 5. Activity Buffer Parity

**Two fundamentally different designs exist:**

1. **Envelope-tracking** (Python, Rust): Tracks message envelopes with ACK progression, direction, dedup
2. **Task-tracking** (JS, CL): Tracks high-level tasks with repo/worktree/branch metadata, 200-word descriptions

**Buffer capacity behavior**:
- Python: Raises `BufferFullError` (spec-compliant)
- CL: Signals `buffer-full-error` (spec-compliant)
- **Rust: Silently prunes (VIOLATES spec 10.1)**
- JS: No explicit rejection

**Idempotency dedup in buffer**: Only Python implements this.

---

## 6. State Machine Parity

### Transition Matrix: All SDKs match. **PASS.**

### State Machine Features

| Feature | Python | JS | Rust | CL |
|---------|--------|-----|------|-----|
| `is_valid_transition()` | **N** | Y | Y | Y |
| `valid_transitions()` | **N** | Y | Y | Y |
| State machine class | **N** | Y | N | Y |
| Lifecycle hooks | **N** | Y (10 types) | N | Y |
| State history | **N** | Y | N | Y |

**Python has NO state transition validation at all** -- critical gap.

---

## 7. Idempotency Token Format

| SDK | Format | Hash Length |
|-----|--------|------------|
| Python | `{producer_id}:{op}:{hash16}` | 16 hex chars |
| Rust | `{producer_id}:{op}:{hash16}` | 16 hex chars |
| CL | `{producer_id}:{op}:{hash16}` | 16 hex chars |
| **JS** | **`v1:{full_sha256}`** | **64 hex chars** |

**JS tokens will NOT match Python/Rust/CL tokens for the same operation.** This breaks cross-SDK deduplication.

---

## 8. Feature Coverage Matrix

### Core Modules

| Module | Python | JS | Rust | CL |
|--------|--------|-----|------|-----|
| Constants | Y | Y | Y | Y |
| Envelope builder | Y | Y | Y | Y |
| Error types | Y (9) | Y (8) | Y (limited) | Y (8) |
| AgentConfig | Y (basic) | Y (full) | Y (full) | Y (mid) |
| SW4RMConfig global | Y | Y | N | N |
| Activity buffer (envelope) | Y | N | Y | N |
| Activity buffer (task) | N | Y | N | Y |
| Persistent buffer | Y | Y | Y | N |
| State machine | N | Y (full) | Y (fns) | Y (full) |
| Idempotency helpers | Y | Y (diff format) | Y | Y |

### gRPC Service Clients

All 16 service clients present in all 4 SDKs. **PARITY: PASS.**

---

## 9. Per-SDK Action Items

### Python SDK
1. **[CRITICAL]** Add state transition validation module
2. **[HIGH]** Extend AgentConfig with missing fields
3. **[HIGH]** Update default endpoints to `http://` scheme
4. **[HIGH]** Change timeout from seconds to milliseconds

### JavaScript/TypeScript SDK
1. **[CRITICAL]** Rewrite idempotency token format to match `{producer_id}:{op}:{hash16}`
2. **[MEDIUM]** Change StateTransitionError default to INTERNAL_ERROR
3. **[MEDIUM]** Add `timestamp` to other SDKs or remove from JS

### Rust SDK
1. **[CRITICAL]** Change ActivityBuffer to return BufferFull error instead of silently pruning
2. **[MEDIUM]** Add AgentStateMachine struct with hooks and history
3. **[MEDIUM]** Add SW4RMConfig global config pattern
4. **[LOW]** Add dedicated error variants

### Common Lisp SDK
1. **[HIGH]** Update default endpoints to `http://` scheme
2. **[MEDIUM]** Align HLC timestamp format with Python/JS
3. **[MEDIUM]** Change default version from "0.6.0" to "0.1.0"
4. **[MEDIUM]** Add SW4RMConfig global config pattern

---

## 10. Clarifications Needed from Spec Lead

1. Should default endpoints include `http://` scheme or use bare `host:port`?
2. Should all SDKs implement both task-tracking (spec 10) AND envelope-tracking activity buffers?
3. What is the canonical HLC timestamp stub format for pre-HLC implementations?
4. Should StateTransitionError map to INTERNAL_ERROR or VALIDATION_ERROR?
