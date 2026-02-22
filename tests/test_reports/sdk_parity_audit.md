# SW4RM Cross-SDK Parity Audit

**Audit Date**: 2026-02-22  
**SDKs Audited**: Python (`sdks/py_sdk/`), JavaScript/TypeScript (`sdks/js_sdk/`), Rust (`sdks/rust_sdk/`), Common Lisp (`sdks/cl_sdk/`)

## Executive Summary

Current parity pass found **0 critical** and **0 high-priority** unresolved discrepancies for the audited SW4RM SDK surfaces.

A previously latent Common Lisp transport mismatch discovered during this audit was fixed:
- Placeholder string channels now fail with structured `rpc-error` (`UNIMPLEMENTED`) instead of `NO-APPLICABLE-METHOD` when gRPC transport is unavailable.

## Resolved Critical/High Items (Current State)

| Item | Status | Evidence |
|---|---|---|
| Python state transition validation missing | RESOLVED | `sdks/py_sdk/sw4rm/state_transitions.py`, Python test suite pass |
| Rust ActivityBuffer pruning instead of rejecting full buffer | RESOLVED | `sdks/rust_sdk/src/activity_buffer.rs`, `make test-rust` pass |
| JS idempotency token format drift | RESOLVED | `sdks/js_sdk/src/internal/idempotency.ts` now emits `{producer}:{op}:{hash16}` |
| Endpoint scheme mismatch (`host:port` vs `http://host:port`) | RESOLVED | `sdks/cl_sdk/src/config.lisp` updated defaults + `sdks/cl_sdk/src/transport/grpc-transport.lisp` target normalization |
| Python AgentConfig field parity gaps | RESOLVED | `sdks/py_sdk/sw4rm/config.py` includes version/capabilities/heartbeat/communication/modalities/public_key/metadata |
| Python timeout unit mismatch | RESOLVED | `timeout_ms` is canonical in `sdks/py_sdk/sw4rm/config.py` |

## Medium / Follow-up Items

These are not blocking for I63 closure but remain candidates for future spec-led harmonization:
- Activity buffer model convergence (task-tracking vs envelope-tracking semantics).
- Optional global configuration singleton parity pattern for Rust/Common Lisp.

## Verification Snapshot (2026-02-22)

- `cd sdks/py_sdk && python -m pytest tests/ -x -q` → **732 passed**
- `python -m pytest sdks/py_sdk/tests/test_sw4_004_conformance.py -v` → **43 passed**
- `python -m pytest sdks/py_sdk/tests/test_sw4_005_conformance.py -v` → **15 passed**
- `make test-js` → **30 files / 410 tests passed**
- `make test-rust` → **all unit/integration/doc tests passed**
- `make test-lisp` → **333 checks passed**
- `sbcl --load sdks/cl_sdk/test/run-codec-tests.lisp --quit` → **87/87 passed**
- `python scripts/check_docs_style.py` → **OK**
- `make docs-build` → **OK**
- `make smoke` (`proto-check`) → **OK**

## Conclusion

Cross-SDK/spec drift in the previously critical/high categories has been reconciled in the current workspace state. Remaining items are non-blocking and primarily governance/spec-harmonization choices.
