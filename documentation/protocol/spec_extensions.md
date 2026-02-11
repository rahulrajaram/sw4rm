# SW4RM SDK Extensions

Version: 0.5.0 (2026-02-10)

This document catalogs SDK-implemented features that extend beyond the normative
requirements of `spec.md`. These extensions are NOT part of the core protocol
specification. Implementers MAY support them for improved developer experience,
but conformant SDKs are NOT REQUIRED to include any of these features.

## 1. Secret Management (`secrets/` module)

**SDKs**: Python, JS/TS, Rust

Provides pluggable secret storage backends for managing API keys, tokens, and
credentials used by agents. Not specified in the protocol since it is a
local-only concern.

**Backends**:

- `FileBackend` - JSON file-based secret storage (all 3 SDKs)
- `KeyringBackend` - OS keyring integration (Python via `keyring`, Rust via `keyring`, JS via `keytar`)
- `SecretResolver` - Resolves secrets from configured backends with fallback chain

## 2. Negotiation Room Store

**SDKs**: Python, JS/TS, Rust

Local persistent storage for negotiation room state. The spec defines the
negotiation protocol but does not prescribe local state management.

**Implementations**:

- `InMemoryNegotiationRoomStore` - Ephemeral in-process store
- `JSONFileNegotiationRoomStore` - JSON file-backed persistence (also available in `colony/stores/`)

## 3. Negotiation Coordinator (Python only)

**SDK**: Python

Policy-based decision coordination for multi-agent negotiation. Provides
automated scoring, threshold-based auto-approval, and coordinator-role
orchestration. Built on top of the spec's Negotiation Room pattern (spec s17.5)
but adds opinionated coordination logic.

## 4. Shared Context Manager (Python only)

**SDK**: Python

Optimistic-locking shared context store for concurrent agent access. Provides
`get`/`put` with version tracking and conflict detection. Not part of the
protocol; agents communicate shared state via messages per spec.

## 5. Feature Flags (Python only)

**SDK**: Python

Runtime feature flag system for SDK behavior toggles. Allows enabling/disabling
experimental features and SDK behavior variants without code changes.

## 6. Content Types (Python only)

**SDK**: Python

Vendor-specific MIME type constants (e.g., `application/vnd.sw4rm.*`). The spec
requires `application/json` and `application/protobuf` support; these
vendor types are extensions for custom payload formats.

## 7. Preemption Manager (Rust only)

**SDK**: Rust

Cooperative agent preemption with cancellation tokens and safe-point checking.
The spec defines preemption semantics (RUNNING -> SUSPENDED) but does not
prescribe the cooperative implementation pattern. The Rust SDK provides
`PreemptionManager` with `check_preemption()` at safe points.

## 8. CONTROL Message Content Types (JS only)

**SDK**: JS/TS

Custom content-type constants for CONTROL messages:

- `scheduler.command` - Scheduler control commands
- `agent.report` - Agent status/progress reports

The spec defines the CONTROL MessageType but does not enumerate content-type
subtypes for it.

## 9. Colony / Agent Spawning (Python only)

**SDK**: Python

Agent thread spawning infrastructure (`colony/` module). Provides `Spawner`
base class and thread-based agent lifecycle management. This is an
application-level concern not specified in the protocol.

## 10. LLM Integration (Python only)

**SDK**: Python

Claude SDK adapter (`llm/` module) for integrating language model inference
into agent decision-making. Protocol-agnostic; the spec does not prescribe
inference engine integration.

## 11. Envelope-Level Message Tracking (Python extension)

**SDK**: Python

The Python `ActivityBuffer` tracks individual envelopes (message_id, direction,
ACK progression) in addition to the spec-mandated task-level entries. This
provides finer-grained observability for message lifecycle debugging.

The spec-compliant `ActivityBuffer` schema (spec s10) requires:
`<task_id, repo_id, worktree_id, branch, timestamp, description>`

The Python SDK's envelope tracking extends this with per-message tracking
including `message_id`, `direction`, `ack_stage`, `error_code`, and
`idempotency_token` indexing for deduplication support.

## 12. Extended Envelope Fields

**SDK**: Python (implemented), JS/TS and Rust (added for parity)

The following envelope fields extend the proto-defined `Envelope` message:

- `effective_policy_id` (string) - ID of the effective policy governing the
  operation. Attached when initiating negotiations or submitting tasks for
  execution where policy context is needed.

- `audit_proof` (bytes) - Cryptographic proof for audit trail. Supports
  pluggable proof types (simple hash, ZK-proof, signatures).

- `audit_policy_id` (string) - ID of the audit policy governing this envelope.

These fields are set by SDK envelope builders but are not yet defined in
`common.proto` Envelope message. They are carried as SDK-level metadata until
the proto is updated.

## 13. Voting / Aggregation Analytics

**SDKs**: Python, JS/TS, Rust

The `VotingAggregator` provides analytics and tracking on top of the four
aggregation strategies (MajorityVote, SimpleAverage, BordaCount,
ConfidenceWeighted). The spec defines aggregation strategies for the
Negotiation Room pattern but the analytics layer (history tracking,
statistics) is an SDK extension.

## 14. Persistence Backends

**SDKs**: Python, JS/TS, Rust

JSON file-based persistence for activity buffer, worktree bindings, and
configuration. The spec does not prescribe persistence mechanisms; these
are provided for developer convenience.

---

*This document is maintained alongside spec.md. When features graduate from
extension to normative, they should be moved into spec.md and removed from
this document.*
