# SW4RM Protocol Spec Compliance Audit

**Audit Date**: 2026-02-11
**Spec Version**: 0.6.0 (2026-01-10)
**Proto Reference**: `protos/common.proto` (canonical)
**SDKs Audited**: Python, JavaScript/TypeScript, Rust, Common Lisp

## Executive Summary

All four SDKs demonstrate strong alignment with the core protocol specification. The enum constants (MessageType, AckStage, ErrorCode, AgentState, CommunicationClass, DebateIntensity, HitlReasonType, EnvelopeState, WorktreeState) are **correctly mirrored** across all four SDKs and match `common.proto` exactly. Envelope construction, Three-ID model, and state machine implementations are generally consistent.

---

## 1. Envelope Structure and Fields

### 1.1 SDK Envelope Field Compliance Matrix

| Field | Proto | Python | JS/TS | Rust | CL |
|-------|-------|--------|-------|------|-----|
| `message_id` | string (1) | OK | OK | OK | OK |
| `idempotency_token` | string (2) | OK | OK | OK | OK |
| `producer_id` | string (3) | OK | OK | OK | OK |
| `correlation_id` | string (4) | OK | OK | OK | OK |
| `sequence_number` | uint64 (5) | OK | OK | OK | OK |
| `retry_count` | uint32 (6) | OK | OK | OK | OK |
| `message_type` | MessageType (7) | OK | OK | OK | OK |
| `content_type` | string (8) | OK | OK | OK | OK |
| `content_length` | uint64 (9) | OK | OK | OK | OK |
| `repo_id` | string (10) | OK | OK | OK | OK |
| `worktree_id` | string (11) | OK | OK | OK | OK |
| `hlc_timestamp` | string (12) | OK | OK | OK | OK |
| `ttl_ms` | uint64 (13) | OK | OK | OK | OK |
| `timestamp` | Timestamp (14) | **MISSING** | OK | **MISSING** | **MISSING** |
| `payload` | bytes (15) | OK | OK | OK | OK |
| `state` | EnvelopeState (16) | OK | OK | OK | OK |

### 1.2 Discrepancies

**D-ENV-1: `timestamp` field missing from Python, Rust, and CL envelope builders** (Severity: MEDIUM)

**D-ENV-3: Content-type defaulting divergence** (Severity: LOW)
- Python/CL: Always default to `"application/json"`
- JS/TS: Switches to `"application/octet-stream"` when binary payload provided
- Rust: `with_payload()` overrides to `"application/octet-stream"`

---

## 2. Constants and Enum Values

All enum values (MessageType 0-11, AckStage 0-6, ErrorCode 0-15+99, CommunicationClass 0-3, DebateIntensity 0-5, HitlReasonType 0-8, EnvelopeState 0-7, WorktreeState 0-5): **All four SDKs match `common.proto` exactly. PASS.**

**D-CONST-2: Python uses `FAILED = 10` while proto uses `FAILED_STATE = 10`** (Severity: MEDIUM)

---

## 3. Error Handling

**D-ERR-1: Inconsistent exception coverage across SDKs** (Severity: MEDIUM)
- Python: Most complete (8 specific exception types)
- JS/TS: Good set including `DuplicateDetectedError`
- Rust: Flat enum lacking specific variants for buffer_full, negotiation, preemption
- CL: Condition system with fewer specialized conditions

**D-ERR-2: Python lacks explicit gRPC-to-ErrorCode mapping** (Severity: LOW)

---

## 4. Agent State Machine

All four SDKs implement the spec section 8 transition matrix correctly.

**D-SM-1: Python SDK lacks explicit state transition validation module** (Severity: MEDIUM)

---

## 5. Worktree State Machine

**D-WT-1: Rust worktree state lacks spec-required 5-state machine** (Severity: HIGH)
Missing SWITCH_PENDING, BIND_FAILED states, transition validation, and TTL auto-revert.

**D-WT-2: Python worktree state lacks spec-required 5-state machine** (Severity: HIGH)
Simple BOUND/UNBOUND toggle only.

JS/TS and CL both have full implementations with transition validation and TTL support.

---

## 6. Activity Buffer

**D-AB-1: Python activity buffer schema deviates from spec** (Severity: MEDIUM)
Spec mandates `<task_id, repo_id, worktree_id, branch, timestamp, description>`. Python tracks per-envelope data.

**D-AB-2: Python buffer default 1,000 vs spec-recommended 10,000** (Severity: LOW)

---

## 7. Messaging Model

Three-ID model correctly implemented in all four SDKs. **PASS.**

**D-MSG-1: Rust deterministic hash does not sort JSON keys** (Severity: LOW)

**D-MSG-2: Missing default ACK timeout constant (10s)** in Python, JS/TS, Rust (Severity: MEDIUM)

**D-MSG-3: Missing deduplication window constant (3600s)** in JS/TS and Rust (Severity: LOW)

---

## 8. Protocol Services

All four SDKs provide clients for all 16 service categories. **PASS**.

**D-SVC-1: JS/TS BaseClient does not load handoff, workflow, negotiation_room protos** (Severity: MEDIUM)

---

## 9. Summary of Required Actions

### HIGH Priority
1. **D-WT-1/D-WT-2**: Rust and Python SDKs MUST implement the full 5-state worktree binding state machine per spec section 16.

### MEDIUM Priority
2. **D-ENV-1**: Python, Rust, CL SDKs SHOULD add `timestamp` field to envelope builders.
3. **D-SM-1**: Python SDK SHOULD add a standalone state transition validation module.
4. **D-MSG-2**: Python, JS/TS, Rust SDKs SHOULD define `DEFAULT_ACK_TIMEOUT_MS = 10000`.
5. **D-SVC-1**: JS/TS `BaseClient` SHOULD load all proto files.
6. **D-AB-1**: Python activity buffer SHOULD support spec-mandated task-level schema.
7. **D-MSG-1**: Rust `compute_deterministic_hash` SHOULD use sorted-key JSON.

### LOW Priority
8. **D-AB-2**: Python buffer default should be 10,000 per spec recommendation.
9. **D-MSG-3**: JS/TS and Rust should define deduplication window constant.
10. **D-CONST-3**: Fix Python envelope.py docstring to use normative state names.
11. **D-ERR-1**: Harmonize exception hierarchy across SDKs.

### INFORMATIONAL
12. **D-CL-1**: Clarify CL SDK maintenance status (files staged for deletion in git).
13. **D-ENV-2**: SDK extension fields are documented and acceptable.
14. **D-CONST-2**: FAILED vs FAILED_STATE naming is acceptable (values match).
