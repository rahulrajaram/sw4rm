# Documentation Remediation Report

**Date:** 2026-02-11
**Scope:** SW4RM Agentic Protocol documentation site (52 files)
**Phases:** Editorial pass + spec compliance + low-priority remediation

## Final Audit Results

| Metric | Before | After | Status |
|--------|--------|-------|--------|
| Broken links | 0 | 0 | PASS |
| Total links verified | 160 | 190+ | +30 new cross-references |
| Orphaned pages | 7 | 2 | PASS (remaining 2 are non-content) |
| High-similarity duplicates | 1 (83%) | 0 | PASS |
| Stale files (>90 days) | 3 | 0 | PASS |
| Weasel words | 7 | 4 | IMPROVED |
| Informal contractions | 2 | 0 | PASS |
| Deprecated terminology | 4 instances | 0 | PASS |
| MkDocs strict build | Not verified | 0 errors | PASS |
| SDK extension docs | 0 of 14 | 14 of 14 | PASS |
| CL SDK examples | 0 | 3 | PASS |
| ACK timeout discrepancy | Reported | False alarm (all SDKs use 10s) | RESOLVED |

## Phase 1: Editorial & Structural Fixes

### 1. mkdocs.yml
- Added `quickstart/persistence.md` to nav
- Added `protocol/advanced-patterns.md` to nav
- Added `protocol/spec_extensions.md` to nav
- Added `clients/sdk-extensions.md` to nav
- Updated copyright from "2025" to "2025-2026"

### 2. protocol/index.md
- Bumped version from v0.5.0 to v0.6.0
- Updated "Last Updated" date to 2026-02-11
- Added v0.6.0 changelog entry
- Added HEARTBEAT (3) and NOTIFICATION (4) to message type table
- Sorted message types by numeric value
- Added 5 missing services to SOA topology diagram (NegotiationRoom, Activity, SchedulerPolicy, Handoff, Workflow)
- Added cross-references to content-types.md, handoff-serialization.md, deprecations.md

### 3. index.md / overview.md De-duplication
- Rewrote index.md from ~1045 lines to ~243 lines (landing page focus)
- Removed all duplicate sections (1.4-1.8) that exist in overview.md
- Added cross-reference to overview.md for detailed content

### 4. architecture/state-machines.md
- Added 5 missing state transitions per spec section 8:
  - INITIALIZING -> FAILED (init_timeout)
  - WAITING_RESOURCES -> FAILED (resource_timeout)
  - SUSPENDED -> FAILED (suspend_timeout)
  - COMPLETED -> RUNNABLE (ready for next task)
  - RECOVERING -> SHUTTING_DOWN (recovery_abort)
- Updated State Reference Table

### 5. architecture/index.md
- Added same 5 missing state transitions to overview diagram

### 6. clients/scheduler-policy.md
- Replaced deprecated `setWagglePolicy` -> `setNegotiationPolicy`
- Replaced deprecated `getWagglePolicy` -> `getNegotiationPolicy`
- Updated deprecation note and JS/TS code example

### 7. protocol/advanced-patterns.md
- Updated version header from v0.5.0 to v0.6.0

### 8. Language Fixes
- quickstart/first-agent.md: Replaced "We'll create" -> "This guide creates"
- quickstart/first-agent.md: Replaced "we'll add" -> "The next section adds"
- protocol/extensions/SW4-002-timeout-profiles.md: Removed "generally" weasel word
- protocol/content-types.md: Replaced "usually json" -> "e.g., json, protobuf"

### 9. Orphan Remediation
- Added cross-references from protocol/index.md to: content-types.md, handoff-serialization.md, deprecations.md
- Added cross-reference from examples/index.md to use-cases.md
- Reduced orphans from 7 to 2 (README.md excluded by config, favicon-config.md is dev asset)

## Phase 2: Spec Compliance Content Additions

### 10. protocol/messages.md — Three-ID Model Section (§11.3)
- Added complete Three-ID Model documentation: message_id, correlation_id, idempotency_token
- Includes identifier comparison table, semantics, format specification, and relationship example

### 11. protocol/services.md — 6 Missing Services
- Added SchedulerPolicyService (7 RPCs, policy management)
- Added NegotiationRoomService (5 RPCs, artifact approval workflows)
- Added HandoffService (5 RPCs, agent delegation)
- Added WorkflowService (4 RPCs, DAG orchestration)
- Added ActivityService (2 RPCs, artifact storage)
- All include proto message definitions and cross-references to client docs

### 12. protocol/advanced-patterns.md — §17.1-17.4 + v0.6.0 Additions
- Added §3.11.0.1 Negotiation Event Fanout (7 event kinds with schemas)
- Added §3.11.0.2 Negotiation Policy and Effective Policy (field table, clamping)
- Added §3.11.0.3 Validation, Diff, and Scoring (DeltaSummary, blended scoring)
- Added §3.11.0.4 Reports and Artifacts (EvaluationReport, DecisionReport, contracts)
- Added Policy-Based Auto-Approval section (v0.6.0) with threshold table and rules
- Added DAG Validation and Cycle Detection section (v0.6.0) with algorithm requirements

### 13. clients/error-handling.md — Dead Letter Queue (§21.1)
- Added DLQ entry contents table (6 diagnostic fields)
- Added DLQ operations (requeue, export, filter)
- Added DLQ retention policies (time-based, count-based)
- Includes Python example code

### 14. clients/hitl.md — HITL Absence Behavior (§15.3, §15.4)
- Added §6.12.5 HITL Absence Policy (deny-by-default, threshold-based)
- Added §6.12.6 HITL Unavailability During Negotiation Timeout (3 fallback policies table, detection, audit trail)

### 15. clients/handoff.md — Return Type Clarification
- Added note explaining SDK wrapping of proto Empty -> HandoffResponse

### 16. quickstart/installation.md — Multi-SDK Installation
- Added "Quick Install by Language" tabbed section covering Python, Rust, JS/TS, and Common Lisp
- Includes package names, version numbers, and dependency requirements

### 17. 8 Client Docs — GitHub Example Links
Added "Working Examples" sections with GitHub links to:
- router.md (Python, Rust, TypeScript echo agents)
- handoff.md (Python, Rust, TypeScript handoff examples)
- hitl.md (Python, TypeScript HITL escalation)
- negotiation.md (Python negotiation debate)
- negotiation-room.md (Rust, TypeScript negotiation room)
- workflow.md (Python, Rust, TypeScript workflow orchestration)
- tool.md (Python tool streaming)
- activity.md (Rust activity demo)

## Phase 3: Low-Priority Remediation

### 18. protocol/acks.md — Refresh (183 days stale)
- Added v0.6.0 version header and "Last updated" date
- Expanded Late ACK Reconciliation section with full spec §11.1 rules (4 reconciliation scenarios)
- Added Exactly-Once Processing idempotency handling per §11.2 (token-to-state mapping)
- Updated example timestamps from 2024 to 2026
- Added "See Also" cross-references to Three-ID Model, DLQ, and Protocol Index

### 19. clients/sdk-extensions.md — 14 SDK Extensions Documented (NEW FILE)
- Secret Management (Python, Rust, JS/TS): backends, types, resolver, factory
- Negotiation Room Store (Python, Rust, JS/TS): store interface, implementations
- Negotiation Coordinator (Python): policy application, auto-approval, escalation
- Shared Context Manager (Python): cross-reference to existing client doc
- Feature Flags (Python): built-in flags, resolution order, environment overrides
- Content Types (Python): vendor MIME types, ContentTypeRegistry
- Preemption Manager (Rust): cooperative preemption, RAII guard
- CONTROL Message Content Types (JS/TS): scheduler commands, agent reports
- Colony / Agent Spawning (Python): spawn modes, lifecycle, ThreadSpawner
- LLM Integration (Python): ClaudeSDKClient, MockLLMClient, factory
- Envelope-Level Message Tracking (Python, Rust): extended ActivityRecord fields
- Extended Envelope Fields (Python, Rust, JS/TS): effective_policy_id, audit_proof, audit_policy_id
- Voting / Aggregation Analytics (Python, Rust, JS/TS): entropy, consensus, polarization
- Persistence Backends (Python): JSONFilePersistence, SQLitePersistence

### 20. Common Lisp SDK Examples (3 new files)
- `sdks/cl_sdk/examples/echo-agent.lisp`: Agent config, envelope construction, state transitions, retry pattern
- `sdks/cl_sdk/examples/negotiation-voting.lisp`: Event emitter, voting strategies, aggregation
- `sdks/cl_sdk/examples/secret-management.lisp`: File backend, env backend, resolver fallback chain

### 21. ACK Timeout Discrepancy — Resolved
- Investigation confirmed all SDKs use 10s default (matching spec §20):
  - Python: `ack_timeout_seconds or 10` in `ack_integration.py`
  - Rust: `DEFAULT_ACK_TIMEOUT_MS: u64 = 10000` in `constants.rs`
  - JS/TS: `DEFAULT_ACK_TIMEOUT_MS = 10000` in `constants/index.ts`
- The previously reported "30s" was `heartbeat_interval_ms`, not ACK timeout

### 22. MkDocs Strict Build — Verified
- Installed mkdocs, mkdocs-material, mkdocs-kroki-plugin
- `mkdocs build --strict` passes with 0 errors
- Fixed anchor mismatch in acks.md link to messages.md Three-ID Model section
- 5 INFO-level notices for pages intentionally excluded from nav (spec.md, favicon-config.md, 3 extension detail pages)

## Files Modified (26 total)

| File | Changes |
|------|---------|
| `mkdocs.yml` | Nav additions (4), copyright |
| `documentation/index.md` | De-duplicated landing page |
| `documentation/protocol/index.md` | v0.6.0, message types, services, cross-refs |
| `documentation/protocol/messages.md` | Three-ID Model section |
| `documentation/protocol/services.md` | 6 missing service definitions |
| `documentation/protocol/advanced-patterns.md` | §17.1-17.4, auto-approval, DAG validation |
| `documentation/protocol/acks.md` | v0.6.0 refresh, §11.1 reconciliation, §11.2 idempotency |
| `documentation/protocol/content-types.md` | Weasel word fix |
| `documentation/protocol/extensions/SW4-002-timeout-profiles.md` | Weasel word fix |
| `documentation/architecture/state-machines.md` | 5 missing state transitions |
| `documentation/architecture/index.md` | 5 missing state transitions |
| `documentation/clients/scheduler-policy.md` | Deprecated Waggle terminology |
| `documentation/clients/error-handling.md` | DLQ documentation |
| `documentation/clients/hitl.md` | HITL absence behavior, GitHub links |
| `documentation/clients/handoff.md` | Return type note, GitHub links |
| `documentation/clients/router.md` | GitHub example links |
| `documentation/clients/negotiation.md` | GitHub example links |
| `documentation/clients/negotiation-room.md` | GitHub example links |
| `documentation/clients/workflow.md` | GitHub example links |
| `documentation/clients/tool.md` | GitHub example links |
| `documentation/clients/activity.md` | GitHub example links |
| `documentation/clients/sdk-extensions.md` | **NEW** — 14 SDK extension docs |
| `documentation/quickstart/installation.md` | Multi-SDK install section |
| `documentation/quickstart/first-agent.md` | Informal language fixes |
| `documentation/examples/index.md` | Use-cases cross-reference |
| `sdks/cl_sdk/examples/` | **NEW** — 3 Common Lisp example files |

## Noted Issues (Non-blocking)

1. **CL SDK package inconsistency**: `src/package.lisp` defines package `#:sw4rm`, but 10 source files use `(in-package :sw4rm-sdk)`. Voting, negotiation-events, and secrets symbols are not exported. Recommend adding `:nicknames (:sw4rm-sdk)` to the defpackage or fixing the in-package declarations.
2. **5 pages not in nav**: `spec.md`, `favicon-config.md`, and 3 extension detail pages (linked from `protocol/extensions/index.md`). These are intentionally excluded.

## Verification Commands

```bash
# Rebuild yore index and run full check suite
yore build documentation --output .yore --types md
yore check --links --stale --ci --index .yore
yore orphans --index .yore --json
yore dupes --index .yore --json

# MkDocs strict build (verified passing)
mkdocs build --strict
```
