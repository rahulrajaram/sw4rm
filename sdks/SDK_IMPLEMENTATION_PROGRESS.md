# SW4RM SDK Implementation Progress (SW4-004/SW4-005)

This document tracks cross-SDK parity for the inter-swarm extensions:

- SW4-004: Inter-Swarm Composition
- SW4-005: Spillover Routing

Status values:

- `DONE`: Implemented and covered by tests in that SDK.
- `PARTIAL`: Implemented only for part of the extension surface.
- `PENDING`: Not implemented yet.

## Cross-SDK Capability Matrix

| Capability | Python | JS/TS | Rust | Common Lisp | Notes |
|---|---|---|---|---|---|
| SW4-004/SW4-005 handoff wire fields (`budget`, `delegation_policy`, `rejection_code`, `retry_after_ms`, `redirect_to_agent_id`) | DONE | DONE | DONE | DONE | All SDKs expose these fields on handoff request/response surfaces. |
| SW4-004 deadline validation + delegation policy normalization | DONE | DONE | DONE | DONE | Enforced in each SDK handoff client path. |
| SW4-005 caller redirect helper (`REDIRECT` follow, `OVERLOADED` retry, loop protection, redirect bounds, wall-time deduction) | DONE | DONE | DONE | DONE | Implemented in Python/JS/Rust/Common Lisp delegation helpers; JS/Rust/Common Lisp parity includes post-attempt `ACK_TIMEOUT` fail-fast and trimmed redirect-target validation ordering before redirect-bound fallback. |
| SW4-005 gateway redirect emitter + health-aware peer selection | DONE | DONE | DONE | DONE | Implemented in Python/JS/Rust/Common Lisp gateway redirect-emitter helpers with health-aware peer filtering and spillover fallback semantics. |
| SW4-004 cancellation helper behavior (cascade + grace-period handling) | DONE | DONE | DONE | DONE | Python/JS/Rust/CL now provide local cancellation helper APIs with cascade + grace-expiry semantics and forced-preemption signaling. |
| SW4-004 conformance suite (T-001..T-012) | DONE | DONE | DONE | DONE | Full suite coverage is exercised in Python/JS/Rust/Common Lisp test adapters and parity suites. |
| SW4-005 conformance suite (R-001..R-012) | DONE | DONE | DONE | DONE | Full suite coverage is exercised in Python/JS/Rust/Common Lisp test adapters and parity suites. |
| Targeted SW4-004/SW4-005 parity tests | DONE | DONE | DONE | DONE | JS/Rust/CL include targeted parity tests for implemented surfaces. |
| Shared SW4-005 gateway/delegation conformance vectors | DONE | DONE | DONE | DONE | `tests/conformance_vectors/sw4_005_delegation_vectors.json` (`v2`) is consumed by SDK-specific adapters in Python/JS/Rust/Common Lisp tests. |
| Shared SW4-004 cancellation conformance vectors | DONE | DONE | DONE | DONE | `tests/conformance_vectors/sw4_004_cancellation_vectors.json` is consumed by SDK-specific adapters in Python/JS/Rust/Common Lisp tests. |

## Evidence (Code + Tests)

### Python
- Handoff/gateway surfaces: `sdks/py_sdk/sw4rm/gateway.py`
- Redirect helper: `sdks/py_sdk/sw4rm/delegation.py`
- SW4-004 conformance tests: `sdks/py_sdk/tests/test_sw4_004_conformance.py`
- SW4-005 conformance tests: `sdks/py_sdk/tests/test_sw4_005_conformance.py`
- Shared vector adapter: `sdks/py_sdk/tests/test_cross_sdk_conformance_vectors.py`

### JS/TS
- Handoff wire surface: `sdks/js_sdk/src/clients/handoff.ts`
- Redirect helper: `sdks/js_sdk/src/runtime/delegation.ts`
- Gateway redirect emitter helper: `sdks/js_sdk/src/runtime/gateway.ts`
- Cancellation helper: `sdks/js_sdk/src/runtime/cancellation.ts`
- SW4-004/SW4-005 parity tests: `sdks/js_sdk/test/handoff.test.ts`, `sdks/js_sdk/test/crossSdk.test.ts` (includes redirect-target validation ordering and post-attempt budget-exhaustion fail-fast checks)
- Gateway redirect-emitter parity tests: `sdks/js_sdk/test/gateway.test.ts`
- Cancellation parity tests: `sdks/js_sdk/test/cancellation.test.ts` (cascade propagation, grace boundary expiry, forced-preemption signaling, metadata normalization)
- Full SW4-004/SW4-005 conformance coverage (T-001..T-012, R-001..R-012) across JS parity suites: `sdks/js_sdk/test/handoff.test.ts`, `sdks/js_sdk/test/crossSdk.test.ts`, `sdks/js_sdk/test/gateway.test.ts`, `sdks/js_sdk/test/cancellation.test.ts`
- Shared vector adapter: `sdks/js_sdk/test/conformanceVectors.test.ts`

### Rust
- Handoff wire surface: `sdks/rust_sdk/src/clients/handoff.rs`
- Redirect helper: `sdks/rust_sdk/src/clients/delegation.rs`
- Gateway redirect emitter helper: `sdks/rust_sdk/src/clients/gateway.rs`
- Cancellation helper: `sdks/rust_sdk/src/clients/cancellation.rs`
- SW4-004/SW4-005 parity tests: `sdks/rust_sdk/tests/cross_sdk_tests.rs`
- Redirect helper tests (including redirect-target validation ordering and post-attempt budget fast-fail): `sdks/rust_sdk/tests/integration_tests.rs`
- Gateway redirect-emitter parity tests: `sdks/rust_sdk/tests/gateway_tests.rs`
- Cancellation parity tests: `sdks/rust_sdk/tests/cancellation_tests.rs` (cascade propagation, grace boundary expiry, forced-preemption signaling, metadata normalization)
- Full SW4-004/SW4-005 conformance coverage (T-001..T-012, R-001..R-012) across Rust parity suites: `sdks/rust_sdk/tests/cross_sdk_tests.rs`, `sdks/rust_sdk/tests/integration_tests.rs`, `sdks/rust_sdk/tests/gateway_tests.rs`, `sdks/rust_sdk/tests/cancellation_tests.rs`
- Shared vector adapters:
  - `sdks/rust_sdk/tests/integration_tests.rs` (`delegation_tests::test_delegate_to_swarm_shared_conformance_vectors`)
  - `sdks/rust_sdk/tests/cancellation_tests.rs` (`shared_cancellation_conformance_vectors`)

### Common Lisp
- Handoff wire + caller redirect helper + cancellation helper surface: `sdks/cl_sdk/src/clients/handoff.lisp`
- Gateway redirect emitter helper: `sdks/cl_sdk/src/clients/gateway.lisp`
- SW4-004/SW4-005 parity tests (including redirect/retry ordering, gateway peer health/redirect emission parity, budget exhaustion fail-fast, and cancellation metadata/cascade checks): `sdks/cl_sdk/test/suite.lisp`
- Full SW4-004/SW4-005 conformance coverage (T-001..T-012, R-001..R-012): `sdks/cl_sdk/test/suite.lisp`
- Shared vector adapters:
  - `sdks/cl_sdk/test/suite.lisp` (`handoff-delegate-to-swarm-shared-conformance-vectors`)
  - `sdks/cl_sdk/test/suite.lisp` (`handoff-cancellation-shared-conformance-vectors`)

## Current Gaps

- No remaining SW4-004/SW4-005 conformance-suite parity gaps across Python/JS/Rust/Common Lisp.

## Recent CL Transport Closure Evidence

- `I61` now implements previously `UNIMPLEMENTED` Common Lisp SDK method surfaces with matching gRPC transport calls and codec tests:
  - Scheduler: `cancel-task`, `get-task-status` (client + codec + tests).
  - Negotiation: `get-session` (client + codec + tests).
  - HITL: `respond`, `get-pending`, `get-decision-status` (client + codec + tests).
  - Logging: `query-logs` (client + codec + tests).
  - Connector: `list-providers` (client + codec + tests).
  - Activity: `deregister-activity`, `get-artifact` (client + codec + tests).
  - Tool: `list-tools` (client + codec + tests).

Evidence files:
- `sdks/cl_sdk/src/clients/scheduler.lisp`
- `sdks/cl_sdk/src/clients/negotiation.lisp`
- `sdks/cl_sdk/src/clients/hitl.lisp`
- `sdks/cl_sdk/src/clients/logging.lisp`
- `sdks/cl_sdk/src/clients/connector.lisp`
- `sdks/cl_sdk/src/clients/activity.lisp`
- `sdks/cl_sdk/src/clients/tool.lisp`
- `sdks/cl_sdk/src/transport/protobuf-codec.lisp`
- `sdks/cl_sdk/test/run-codec-tests.lisp`

## Phase 6 Closure Summary (I49)

- Phase 6 (`I39`-`I49`) is closed with full tranche-chain evidence recorded under `artifacts/verification/`.
- Cross-SDK parity for all tracked SW4-004/SW4-005 helper surfaces is complete after `I50` closed Common Lisp SW4-005 gateway redirect-emitter + health-aware peer selection.
- Full-matrix verification was completed in `I48` and carried forward in `I49` closure documentation.

## Phase 7 Seed Targets

- `I50`: Common Lisp SW4-005 gateway redirect-emitter parity closure (DONE).
- `I51`: Full SW4-004/SW4-005 conformance suite expansion for JS/TS, Rust, and Common Lisp (DONE).
- `I52`: Production transport + multi-process inter-swarm integration testbed bootstrap (DONE).

## I52 Bootstrap Artifacts

- Manifest-driven transport/testbed scaffold: `tests/inter_swarm_testbed/bootstrap_manifest.json`
- Multi-process dual-swarm compose template: `tests/inter_swarm_testbed/docker-compose.multi-swarm.yml`
- Bootstrap validation coverage: `sdks/py_sdk/tests/test_inter_swarm_testbed_bootstrap.py`
- Runbook: `documentation/production/inter-swarm-transport-testbed.md`

## Phase 9 Transport Continuation

- `I62`: CL deferred codec closure for policy/workflow deep decode completed in `sdks/cl_sdk/src/transport/protobuf-codec.lisp` (including parser-corrected deep codec forms) and client coverage in `sdks/cl_sdk/src/clients/scheduler-policy.lisp`.
- `I63`: Cross-SDK/spec drift audit and parity fixes completed, including CL transport placeholder-channel error normalization, CL endpoint/config parity updates, and refreshed parity audit evidence.
- `I64`: Full matrix verification + dispatch closure completed with two consecutive clean passes over `py-test`, `conformance`, `conformance-005`, `proto-check`, `docs-lint`, `docs-build`, `test-js`, `test-rust`, and `test-lisp`.

- Evidence files for `I62` verification:
  - `sdks/cl_sdk/src/transport/protobuf-codec.lisp`
  - `sdks/cl_sdk/src/clients/scheduler-policy.lisp`
  - `sdks/cl_sdk/test/run-codec-tests.lisp`
  - `.yarli/evidence/i62-verify-b-codec-load-20260222T010730Z.log`

- Evidence files for `I63` verification:
  - `tests/test_reports/sdk_parity_audit.md`
  - `sdks/cl_sdk/src/transport/grpc-transport.lisp`
  - `sdks/cl_sdk/src/config.lisp`

- Evidence files for `I64` verification:
  - `artifacts/verification/i64-verify-a-full-matrix-20260222T011542Z.log`
  - `artifacts/verification/i64-verify-b-full-matrix-20260222T011649Z.log`
 

---

Last updated: 2026-02-22 (I64)
