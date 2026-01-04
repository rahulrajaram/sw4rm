# SW4RM SDK Implementation Progress (Parity + Tests)

## Assertion
SDK parity across Rust, Python, and JS/TS is complete. **All three SDKs expose HandoffClient, WorkflowClient, and NegotiationRoomClient from their main clients packages.** These three services now have both in-memory implementations AND gRPC server implementations for distributed deployments.

## Current Version: v0.6.0

## Recent Changes (v0.6.0)

### Completed

#### 1. gRPC Servers for Coordination Services
Implemented full gRPC server implementations for Handoff, Workflow, and NegotiationRoom services in all 3 SDKs:

| SDK | Location | Run Command |
|-----|----------|-------------|
| Python | `sdks/py_sdk/reference-services/coordination/` | `python -m coordination.server --port 50060` |
| Rust | `sdks/rust_sdk/reference-services/src/coordination/` | `cargo run --bin coordination-service -- --port 50060` |
| TypeScript | `sdks/js_sdk/reference-services/src/coordination/` | `npm run start:coordination` |

**Features:**
- Thread-safe state management (RLock in Python, DashMap in Rust, Map in TypeScript)
- Complete proto compliance for all RPC methods
- Request validation (required fields, score ranges 0-10, confidence 0-1)
- DAG cycle detection for workflows
- Unified server (all 3 services on one port)
- Graceful shutdown (SIGINT/SIGTERM handlers)

#### 2. NegotiationRoomClient Concurrency Fix
Added pluggable store abstraction to fix instance-local state issue:

```python
# Python - Default (shared in-process state)
client = NegotiationRoomClient()

# Explicit shared store (multi-instance in same process)
store = InMemoryNegotiationRoomStore()
producer = NegotiationRoomClient(store=store)
critic = NegotiationRoomClient(store=store)

# File-based persistence (multi-process) - requires colony
from colony.stores.python import JSONFileNegotiationRoomStore
store = JSONFileNegotiationRoomStore("/var/lib/sw4rm/negotiation")
client = NegotiationRoomClient(store=store)
```

**Core store (in all 3 SDKs):**
- `InMemoryNegotiationRoomStore` - Default, shared within process

**Colony stores (see `colony/stores/`):**
- `JSONFileNegotiationRoomStore` - File-based persistence for multi-process

**Test results:** 36 tests pass (6 new shared state tests)

#### 3. CI Proto Validation
Created GitHub Actions workflow (`.github/workflows/proto-check.yml`) to detect proto drift:

- Regenerates protos for Python + JS SDKs
- Detects modified or missing generated files
- Rust excluded (compiles at build time via `build.rs`)
- Actionable `::error::` annotations

### Files Changed (v0.7.0)

**Python SDK:**
- `sdks/py_sdk/reference-services/coordination/` - New directory with server implementations
- `sdks/py_sdk/sw4rm/clients/negotiation_room.py` - Added store abstraction
- `sdks/py_sdk/sw4rm/clients/negotiation_room_store.py` - New store implementations
- `sdks/py_sdk/sw4rm/clients/__init__.py` - Export store types

**Rust SDK:**
- `sdks/rust_sdk/reference-services/src/coordination/` - New module with server implementations
- `sdks/rust_sdk/reference-services/src/bin/coordination_service.rs` - Server binary
- `sdks/rust_sdk/src/clients/negotiation_room.rs` - Added store trait
- `sdks/rust_sdk/src/clients/negotiation_room_store.rs` - Store implementations

**JS/TS SDK:**
- `sdks/js_sdk/reference-services/src/coordination/` - New directory with server implementations
- `sdks/js_sdk/src/clients/negotiationRoom.ts` - Added store abstraction
- `sdks/js_sdk/src/clients/negotiationRoomStore.ts` - Store implementations

**CI:**
- `.github/workflows/proto-check.yml` - New workflow for proto validation

---

## Parity Matrix (Service Clients)

Legend: grpc = gRPC client; server = gRPC server available in reference-services

Service                | Rust        | JS/TS       | Python      | Server Available
-----------------------|-------------|-------------|-------------|------------------
ActivityService        | grpc        | grpc        | grpc        | Yes
ConnectorService       | grpc        | grpc        | grpc        | Yes
HandoffService         | grpc        | grpc        | grpc        | Yes (v0.7.0)
HitlService            | grpc        | grpc        | grpc        | Yes
LoggingService         | grpc        | grpc        | grpc        | Yes
NegotiationService     | grpc        | grpc        | grpc        | Yes
NegotiationRoomService | grpc        | grpc        | grpc        | Yes (v0.7.0)
ReasoningProxy         | grpc        | grpc        | grpc        | Yes
RegistryService        | grpc        | grpc        | grpc        | Yes
RouterService          | grpc        | grpc        | grpc        | Yes
SchedulerService       | grpc        | grpc        | grpc        | Yes
SchedulerPolicyService | grpc        | grpc        | grpc        | Yes
ToolService            | grpc        | grpc        | grpc        | Yes
WorkflowService        | grpc        | grpc        | grpc        | Yes (v0.7.0)
WorktreeService        | grpc        | grpc        | grpc        | Yes

**All 15 services now have full gRPC client implementations across all 3 SDKs.**

---

## Core Protocol TODOs

All core protocol items are complete. See Completed Items section below.

---

## Colony Items (Moved)

The following items have been moved to `COLONY_SPEC_PROGRESS.md`:

- **JSONFileNegotiationRoomStore** - Moved from core SDKs to `colony/stores/` (✓ complete)
- Cross-language integration tests
- Redis/Database store implementation
- Dockerization
- Harden file store implementations
- Runnable examples in CI
- Release cadence planning
- Production packaging

See [COLONY_SPEC_PROGRESS.md](./COLONY_SPEC_PROGRESS.md) for ecosystem extras, plugins, and deployment tooling.

---

## Completed Items (v0.6.0)

- [x] Python HandoffClient moved to `sw4rm.clients`
- [x] Python WorkflowClient added to `sw4rm.clients`
- [x] Python Makefile fixed for all 15 proto files
- [x] gRPC servers for Handoff, Workflow, NegotiationRoom (all 3 SDKs)
- [x] Pluggable store abstraction for NegotiationRoomClient (all 3 SDKs)
- [x] CI validation for proto generation
- [x] 36 tests passing including 6 new shared state tests
- [x] Error code normalization - `docs/ERROR_CODES.md` created with cross-SDK mapping
- [x] Operational contracts documentation - `docs/OPERATIONAL_CONTRACTS.md` (~800 lines)
- [x] JS/TS coordination tests - 86 tests (24 handoff, 32 workflow, 30 negotiation room)
- [x] JSONFileNegotiationRoomStore moved to colony (all 3 SDKs)
- [x] SDK READMEs updated with operational contracts references

---

## Resolved Risks

- ~~Python SDK can lose handoff/negotiation_room/workflow proto stubs when `make protos` is run.~~ **FIXED**: Makefile now includes all 15 proto files.
- ~~Python SDK surface differs from Rust/JS for handoff/workflow.~~ **FIXED**: HandoffClient and WorkflowClient now exported from `sw4rm.clients`.
- ~~NegotiationRoomClient state isolation breaks multi-instance deployments.~~ **FIXED**: Pluggable store abstraction allows shared state.
- ~~No gRPC servers for coordination services.~~ **FIXED**: Full server implementations in all 3 SDKs.
- ~~No CI validation for proto generation.~~ **FIXED**: GitHub Actions workflow added.
- ~~Cross-SDK Behavior Drift.~~ **FIXED**: Operational contracts documented in `docs/OPERATIONAL_CONTRACTS.md`.
- ~~Error Semantics Inconsistency.~~ **FIXED**: Error codes documented in `docs/ERROR_CODES.md`.
- ~~JS Test Coverage Gap.~~ **FIXED**: 86 tests added for coordination services.

## Active Risks

*All core protocol risks resolved. Infrastructure risks (horizontal scaling, file store race conditions) tracked in [COLONY_SPEC_PROGRESS.md](./COLONY_SPEC_PROGRESS.md).*

---

## Evidence Links

- Proto definitions: `protos/*.proto` (15 service protos + 2 message-only)
- Python clients: `sdks/py_sdk/sw4rm/clients/`
- Rust clients: `sdks/rust_sdk/src/clients/`
- JS/TS clients: `sdks/js_sdk/src/clients/`
- Python servers: `sdks/py_sdk/reference-services/coordination/`
- Rust servers: `sdks/rust_sdk/reference-services/src/coordination/`
- JS servers: `sdks/js_sdk/reference-services/src/coordination/`
- Colony stores: `sdks/colony/stores/{python,rust,typescript}/`
- CI workflow: `.github/workflows/proto-check.yml`
- Error codes: `sdks/docs/ERROR_CODES.md`
- Operational contracts: `sdks/docs/OPERATIONAL_CONTRACTS.md`
- Python tests: `sdks/py_sdk/tests/test_handoff.py`, `test_negotiation_room.py`, `test_workflow_engine.py`
- Rust tests: inline in `handoff.rs` (8 tests), `workflow.rs` (12 tests), `negotiation_room.rs`
- JS tests: `sdks/js_sdk/test/handoff.test.ts`, `workflow.test.ts`, `negotiationRoom.test.ts` (86 tests)

---

*Last updated: 2026-01-10 | Version: 0.6.0*
