2. Activity Buffer Milestone Context

2.1. Scope
This milestone establishes the activity buffer as an append-only event store for agent activities, including prompts, tool calls, tool results, assistant outputs, operator interventions, and system events. It implements a SQLite-backed storage engine with strict schemas, retention policies, deterministic ordering, and read APIs to list and replay sessions. It includes a rolling summarizer that generates condensed digests using the model provider abstraction. It excludes distributed storage engines and full-text search indices, which are deferred.

2.2. Objectives
The goal is to provide a reliable, queryable record of agent activity for debugging, auditing, and retrieval-augmented reasoning. A secondary goal is to support deterministic replay of sessions for testing and incident analysis. A tertiary goal is to expose a minimal CLI to list sessions, show details, and replay interactions to stdout.

2.3. Deliverables
The deliverables include a SQLite schema with tables for sessions, events, attachments, and summaries; a library API to append validated events with monotonic sequence numbers; retention enforcement with size and age thresholds; a summarization job that produces rolling summaries per session; and CLI commands to list sessions, inspect events, and replay. It also includes encryption-at-rest options via SQLite PRAGMAs when supported by the environment.

2.4. Architecture and Interfaces
The activity buffer presents an `ActivityStore` trait with `append_event`, `list_sessions`, `list_events(session_id)`, `get_session`, `replay(session_id)`, and `summarize(session_id)` functions. Events are immutable and carry a strictly increasing sequence within a session, assigned by the store to prevent client-side race conditions. Attachments reference blobs stored in a content-addressable directory under the Bee home. The summarizer consumes a bounded window of recent events and writes a new summary record referencing the covered range. All write operations occur in transactions to guarantee atomicity.

2.5. Data Model
The schema defines `sessions(id TEXT PRIMARY KEY, created_at TIMESTAMP, agent_id TEXT, topic TEXT, metadata JSON)`; `events(session_id TEXT, seq INTEGER, kind TEXT, at TIMESTAMP, payload JSON, PRIMARY KEY(session_id, seq))`; `attachments(sha256 TEXT PRIMARY KEY, bytes BLOB, mime TEXT)`; and `summaries(session_id TEXT, upto_seq INTEGER, at TIMESTAMP, summary TEXT, tokens INTEGER, cost_cents REAL, UNIQUE(session_id, upto_seq))`. All timestamps use UTC. Event kinds are enumerated and validated. Payloads follow JSON Schemas per kind and must validate before persistence.

2.6. Edge Cases and Failure Modes
The system must reject out-of-order or duplicate sequence numbers, large payloads exceeding configured limits, and invalid payload schemas. Retention deletes old events only after confirming no summary or external reference requires them. Disk-full conditions produce backpressure errors with actionable messages. Corruption detection leverages SQLite PRAGMA integrity checks during startup tests. Replay tolerates missing attachments by emitting placeholders and continuing.

2.7. Testing Strategy
Unit tests validate schema migrations, JSON Schema validation, sequence numbering, transactional integrity, and retention behavior. Property tests fuzz event payloads against schemas. Replay tests reconstruct expected transcripts deterministically from recorded events. Summarization tests stub the model provider and assert stable summaries for fixed inputs and parameters. CLI tests create an ephemeral database, append events, and validate list/show/replay outputs. Concurrency tests simulate appenders from multiple threads and assert serializable outcomes.

2.8. Non-Goals
This milestone does not implement distributed consensus, cross-host replication, or external message bus ingestion. It also does not implement vector search indices beyond storing summaries.

2.9. Dependencies
This milestone depends on the model provider trait for summarization. It otherwise operates locally and does not require the scheduler or router.

2.10. Migration and Rollout
The schema version is tracked in a meta table. Migrations are forward-only and must preserve data. The initial version creates the core tables and indices. Rolling out enables the store by default in the Bee home directory with an opt-out flag.

2.11. Operational Considerations
The store enforces size and age limits via a periodic compaction task. Telemetry records append rates, replay latencies, and summarization costs. Configuration accepts paths, limits, and summarizer parameters from environment variables.

2.12. Phase 1 Implementation Details
This phase introduces production-hardening features in the Bee-local implementation without altering the SDK surface beyond what is already specified for summarization. All capabilities are additive, forward-only, and gated by explicit CLI commands and environment variables.

2.12.1. Schema Versioning and Migrations
The database maintains a `meta(schema_version)` integer. On open, the store executes a forward-only migration routine that creates the `meta` table if missing and initializes or updates `schema_version` to the current value. Migrations MUST run in a single transaction and MUST be idempotent. A new CLI command, `bee activity migrate`, opens the store and applies any pending migrations, printing an explicit status.

2.12.2. Limits and Configuration Enforcement
The append path enforces a maximum payload size and, optionally, a per-session event cap before writing a new row, rejecting non-conforming writes with actionable errors. The following environment variables are recognized:
- `BEE_ACTIVITY_MAX_PAYLOAD` (bytes; default 262144): maximum serialized JSON payload length per event.
- `BEE_ACTIVITY_MAX_EVENTS_PER_SESSION` (integer; optional): hard ceiling on the number of events per session.
- `BEE_ACTIVITY_MAX_BYTES` (bytes; optional): default maximum database file size for compaction commands.
- `BEE_ACTIVITY_MAX_AGE_DAYS` (integer; optional): default age threshold for compaction commands.
Compaction commands accept explicit flags which override environment defaults.

2.12.3. Integrity and Maintenance Commands
The CLI exposes `bee activity check` to run `PRAGMA integrity_check` and print the result, and `bee activity vacuum` to perform a VACUUM to reclaim free pages, intended for maintenance windows following deletions. These commands MUST be read-only apart from the VACUUM operation and MUST return non-zero exit codes on failure.

2.12.4. Inspection and UX Enhancements
The CLI adds `bee activity summaries --session <id>` to list summary coverage with `upto_seq`, timestamp, token usage, and cost accounting, enabling quick verification of summarization progress. The CLI adds `bee activity show --session <id> --seq <n>` to retrieve and pretty-print a single event for targeted inspection during incident response or test triage. Existing commands (`init`, `sessions`, `events`, `replay`, `append`, `compact`, `summarize`) remain unchanged in semantics.

2.12.5. Determinism and Safety Guarantees
All new enforcement occurs before event insertion, inside the same transaction that assigns sequence numbers, so rejected writes leave no partial state and do not consume a sequence number. `compact` continues to respect the per-session safety boundary derived from `summaries.upto_seq`, and will not delete beyond coverage unless the operator supplies an override in a future phase. `check` and `vacuum` MUST NOT mutate event content or sequence ordering.

2.12.6. Testing Additions
Unit tests SHALL cover: (a) schema version initialization and idempotent migration, (b) payload size enforcement with boundary conditions, (c) optional per-session caps with clear error messages, (d) integrity check happy-path and failure surfacing (using a corrupted fixture), and (e) CLI output for `summaries` and `show` on an ephemeral database. Concurrency tests for appenders remain as defined in §2.7 and MUST pass with the added limit checks.
