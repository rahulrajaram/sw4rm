# SW4RM SDK Implementation Progress (Parity + Tests)

## Executive Summary

All three SDKs (Rust, Python, JavaScript/TypeScript) implement the full client surface for core services and the additive policy/artifact services. Test suites are green across the board.

Status (2025-08-31)
- Rust SDK: ✅ Complete client surface; cargo test passing
- Python SDK: ✅ Complete client surface; pytest suite passing
- JavaScript SDK: ✅ Complete client surface; vitest suite passing

Recent updates
- Added shared protos: `policy.proto`, `scheduler_policy.proto`, `activity.proto`
- New clients: SchedulerPolicy + Activity across all SDKs
- Negotiation helpers (parse events, base64 payload/result) across all SDKs
- Expanded Python tests; fixed JS ACK helper semantics; ensured codegen/build scripts include new protos
- CONTROL parity: Added CONTROL content-types and helpers in Rust/JS SDKs (`scheduler.command+json;v=1`, `agent.report+json;v=1`) with path normalization utilities and strict JSON encoding.

---

## Service Client Matrix (All SDKs)

| Service | Python | Rust | JavaScript |
|---------|--------|------|------------|
| Registry | ✅ | ✅ | ✅ |
| Router | ✅ | ✅ | ✅ |
| Scheduler | ✅ | ✅ | ✅ |
| HITL | ✅ | ✅ | ✅ |
| Worktree | ✅ | ✅ | ✅ |
| Tool | ✅ | ✅ | ✅ |
| Connector | ✅ | ✅ | ✅ |
| Negotiation | ✅ | ✅ | ✅ |
| Reasoning | ✅ | ✅ | ✅ |
| Logging | ✅ | ✅ | ✅ |
| SchedulerPolicy (additive) | ✅ | ✅ | ✅ |
| Activity (additive) | ✅ | ✅ | ✅ |

All clients are present and typed in each SDK.

## 0.3.0 SDK Update Checklist (Spec + proto rename)

This release (0.3.0) renames negotiation policy to `NegotiationPolicy` across the spec and canonical protos (`protos/policy.proto`, `protos/scheduler_policy.proto`). Wire fields are unchanged; only message/RPC names changed. SDKs must regenerate stubs and update imports.

Proto changes applied
- `policy.proto`: `message NegotiationPolicy` (was `WagglePolicy`)
- `scheduler_policy.proto` RPC/messages:
  - `SetNegotiationPolicyRequest/Response` (was `SetWagglePolicy*`)
  - `GetNegotiationPolicyRequest/Response` (was `GetWagglePolicy*`)
  - `EffectivePolicy.policy`: type `NegotiationPolicy` (was `WagglePolicy`)
  - `PolicyProfile.policy`: type `NegotiationPolicy` (was `WagglePolicy`)

Python SDK steps
- Regenerate stubs (`grpc_tools.protoc`) and update imports:
  - `from sw4rm.policy_pb2 import NegotiationPolicy`
  - `from sw4rm.scheduler_policy_pb2 import SetNegotiationPolicyRequest` and corresponding Get* types
- Update references to field types in `EffectivePolicy` and `PolicyProfile`.
- Update negotiation helpers: event schema remains `policy: {...}`; only the documented type name changes.
- Run tests: negotiation policy client, evaluation submit, effective policy fetch.

JS/TS SDK steps
- Rebuild protos (`npm run build:proto`) and update imports/types accordingly.
- Update unit tests covering policy clients and negotiation helpers.

Rust SDK steps
- Rebuild (`cargo build`), update module paths if generated names change.
- Update references to policy types and RPCs in clients; run tests.

Other clarifications in 0.3.0 (no code change required)
- Sections 10/11/13/15/18 expanded for operational clarity (activity buffer purpose, message fields, buffer NACK example and metrics, HITL expectations, MCP/tool calling). These do not change wire contracts.
- §5.1 clarifies canonical `.proto` source, SDK packaging expectations, and artifact reference.

---

## Protobuf Parity

Shared protos under `protos/` are authoritative and consumed by all SDKs:
- Core: common, registry, router, scheduler, hitl, worktree, tool, connector, negotiation, reasoning, logging
- Additive (NEW): policy, scheduler_policy, activity

Generation/Build
- Rust: `sdks/rust_sdk/build.rs` compiles all protos automatically
- JS: `sdks/js_sdk` npm scripts `build:proto` (grpc-tools + ts plugin)
- Python: `sdks/py_sdk/Makefile protos` (grpcio-tools) or direct `grpc_tools.protoc`

---

## Tests and How to Run

Rust
- `cargo test --manifest-path sdks/rust_sdk/Cargo.toml`

Python
- Generate stubs: `make -C sdks/py_sdk protos`
- Run: `PYTHONPATH=. venv/bin/python -m pytest -q sdks/py_sdk/tests`
- Coverage highlights: envelope + idempotency; activity buffer + persistence round-trip; error mapping + acks; config env; interceptors; pb2 import smoke; negotiation event helpers

JavaScript/TypeScript
- `cd sdks/js_sdk && npm install && npm run build:proto && ./node_modules/.bin/vitest run`
- Unit tests validate: envelope builder/idempotency; ACK lifecycle + send/timeout semantics; persistence adapter; resilient streams; smoke/integration of runtime helpers

Results (current)
- Rust: all tests passing
- Python: all tests passing (warnings only)
- JavaScript: all tests passing

---

## Notable Implementation Notes

- Transport-agnostic envelopes maintained; SDKs preserve raw payload bytes and ignore unknown fields
- Policy and artifacts APIs are additive; older deployments continue to work
- Negotiation room semantics enforced (`correlation_id = negotiation_id`)

---

## Quick Reference: Codegen Commands

Python (from repo root)
```
make -C sdks/py_sdk protos
```

JavaScript (from `sdks/js_sdk`)
```
npm run build:proto
```

Rust
```
cargo build --manifest-path sdks/rust_sdk/Cargo.toml
```

---

This progress file is kept in lockstep with SDK/spec changes. When updating protos or clients, update the matrix and commands here in the same commit.
