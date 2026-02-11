# SW4RM SDK — Implementation Plan

Prioritized remediation of all spec-compliance and cross-SDK parity issues found during the spec-lead / sdk-engineer audit. Each item references the relevant spec section and affected SDK(s).

---

## P0 — Spec Violations (MUST-level)

These violate normative MUST requirements and block any conformance claim.

### 1. Add `timeout` field to `HandoffRequest` in all 4 SDKs
- **Spec ref:** Section 17.6 — HandoffRequest MUST include `timeout`
- **SDKs:** Python, JS/TS, Rust, CL
- **Work:** Add optional `timeout: Duration` field to HandoffRequest type/struct; plumb through to client send path; add validation (reject ≤ 0).

### 2. Implement `ResumeWorkflow` operation in all 4 SDKs
- **Spec ref:** Section 17.7 — Workflow service MUST support ResumeWorkflow
- **SDKs:** Python, JS/TS, Rust, CL
- **Work:** Add `resume_workflow(workflow_id, from_step?)` to WorkflowClient; wire to proto RPC; add in-memory implementation; add tests.

---

## P1 — Core Protocol Gaps (HIGH parity impact)

Critical for SDK usability and interop testing.

### 3. CL SDK: Add ACK lifecycle manager
- **SDKs:** CL (`sdks/cl_sdk/`)
- **Issue:** CL SDK has no acknowledgement tracking. Python, JS, Rust all have `AckManager` / `AckTracker`.
- **Work:** Implement `ack-manager` package in CL; track pending ACKs, timeouts, retry scheduling; integrate with envelope send path.

### 4. CL SDK: Write test suite
- **SDKs:** CL (`sdks/cl_sdk/test/`)
- **Issue:** Test directory exists but is empty. Zero test coverage.
- **Work:** Add FiveAM-based test suite covering: envelope codec, ACK lifecycle (after #3), activity buffer, constants parity. Minimum: 1 test file per source module.

### 5. Fix Python AgentState numbering (0-based vs 1-based)
- **SDKs:** Python (`sdks/py_sdk/sw4rm/runtime/agent.py` vs `sw4rm/constants.py`)
- **Issue:** `runtime/agent.py` defines AgentState enum 0–11; `constants.py` defines the same states 1–12. Wire-format mismatch risk.
- **Work:** Reconcile to single canonical source (1-based per proto). Remove duplicate. Add assertion test.

### 6. Add control message types to Python + CL
- **SDKs:** Python, CL
- **Types:** `SchedulerCommandV1`, `AgentReportV1`
- **Issue:** JS/TS and Rust define these; Python and CL do not.
- **Work:** Add dataclass / defstruct definitions; register in envelope codec dispatch table; add round-trip serialization tests.

---

## P2 — Error Type Parity (MEDIUM)

Missing error types cause silent failures or untyped exceptions in downstream consumers.

### 7. JS/TS: Add PreemptionError, WorktreeError, PolicyViolationError
- **SDKs:** JS/TS (`sdks/js_sdk/src/`)
- **Work:** Add error classes extending `Sw4rmError`; export from `index.ts`.

### 8. Rust: Add Preemption error variant
- **SDKs:** Rust (`sdks/rust_sdk/src/error.rs`)
- **Work:** Add `Preemption { agent_id, reason }` variant to `Sw4rmError` enum.

### 9. Rust: Rename `FAILED_STATE` → `FAILED`
- **SDKs:** Rust (`sdks/rust_sdk/src/constants.rs`)
- **Issue:** Other SDKs use `FAILED`; Rust uses `FAILED_STATE`. Wire-format string mismatch.
- **Work:** Rename constant; update all internal references; run `cargo test`.

---

## P3 — Feature Parity (MEDIUM)

Non-blocking but needed for cross-SDK behavioral consistency.

### 10. Standardize HLC timestamp stub format
- **SDKs:** All
- **Issue:** Each SDK has a different placeholder format for hybrid logical clock stubs.
- **Work:** Define canonical format in constants (e.g., `HLC:<wall>:<logical>:<node>`); align all SDKs.

### 11. Add TTL enforcement for BOUND_NON_HOME
- **SDKs:** Python, Rust, CL (JS already has it)
- **Work:** In state machine transition to `BOUND_NON_HOME`, start TTL timer; on expiry, transition to `UNBOUND` or `FAILED`. Port logic from JS SDK `runtime/` module.

### 12. Rust: Change default TriggerType from Event → Dependency
- **SDKs:** Rust
- **Issue:** Spec default is `Dependency`; Rust defaults to `Event`.
- **Work:** Change `Default` impl for `TriggerType`; update tests.

### 13. Python: Fix default buffer size to match spec
- **SDKs:** Python
- **Issue:** Default activity buffer size doesn't match spec Section 10 recommendation.
- **Work:** Update default in `activity_buffer.py`; add comment citing spec section.

---

## P4 — Spec Clarifications Needed

These require spec-lead decisions before implementation.

### 14. Define canonicalization algorithm for idempotency tokens
- **Spec ref:** Section 12 mentions idempotency but doesn't specify token canonicalization.
- **Action:** spec-lead drafts normative text; then implement in all SDKs.

### 15. Clarify Activity Buffer (Section 10) vs inbound message buffer (Section 13)
- **Issue:** Ambiguous whether these are the same buffer or two distinct buffers.
- **Action:** spec-lead adds clarifying note; adjust SDK implementations if needed.

### 16. Resolve `activity_buffer_full` vs `buffer_full` naming
- **Issue:** Spec text uses both names for what appears to be the same error.
- **Action:** spec-lead picks one canonical name; update spec + all SDKs.

---

## P5 — Triage Complete

### 17. Python-only module porting strategy

**Triage result:** 11 Python-only modules identified, split into protocol-level (must port) and convenience (stay Python-only).

#### Protocol-level — Port to other SDKs (new work items)

| Module | Priority | Rationale |
|--------|----------|-----------|
| `content_types.py` | P1 | Wire-format semantic constants (INTENT_QUERY, SCHEDULER_COMMAND, etc.) needed for cross-SDK message understanding |
| `metrics.py` | P1 | Spec §13 standardized metrics (INBOUND_QUEUE_DEPTH, etc.) needed for observability parity |
| `negotiation_types.py` | P1 | Wire-format dataclasses for Negotiation Room pattern (votes, scores, decisions) |
| `policy_types.py` | P1 | ScoringConfig and policy structures for SchedulerPolicyService |
| `shared_context.py` | P2 | Versioned shared context with optimistic concurrency — core coordination feature |
| `negotiation_coordinator.py` | P2 | Decision logic for critic votes / Negotiation Room (auto-approve, revise, escalate) |
| `workflow/` (engine, builder) | P3 | Full DAG engine — other SDKs only have gRPC client stubs |

#### Convenience — Stay Python-only

| Module | Rationale |
|--------|-----------|
| `feature_flags.py` | Dev tooling, not wire protocol |
| `buffer_strategy.py` | Pluggable eviction strategies — language-specific abstraction |
| `llm/` (client, factory, claude_sdk) | LLM integration differs per language ecosystem |
| `colony/` (spawner) | Agent spawning uses Python threading; Rust/JS have different concurrency models |
| `cli.py` | Python-specific development CLI tool |

---

## Tracking

| ID | Priority | Status | Owner |
|----|----------|--------|-------|
| 1  | P0       | DONE   | claude |
| 2  | P0       | DONE   | claude |
| 3  | P1       | DONE   | claude |
| 4  | P1       | DONE   | claude |
| 5  | P1       | DONE   | claude |
| 6  | P1       | DONE   | claude |
| 7  | P2       | DONE   | claude |
| 8  | P2       | DONE   | claude |
| 9  | P2       | DONE   | claude |
| 10 | P3       | DONE   | claude |
| 11 | P3       | DONE   | claude |
| 12 | P3       | DONE   | claude |
| 13 | P3       | DONE   | claude |
| 14 | P4       | DONE   | claude | Written up in SPEC_QUESTIONS.md |
| 15 | P4       | DONE   | claude | Written up in SPEC_QUESTIONS.md |
| 16 | P4       | DONE   | claude | Written up in SPEC_QUESTIONS.md — already resolved (BUFFER_FULL is canonical) |
| 17 | P5       | DONE   | claude | Triaged: 7 protocol-level (port), 5 convenience (keep Python-only) |
