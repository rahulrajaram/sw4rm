1. Activity Buffer Architecture

1.1. Purpose
The Activity Buffer provides an append-only, queryable record of agent activity for observability, debugging, auditing, and deterministic replay. It persists structured events with strict schemas, assigns deterministic per-session sequence numbers, and supports bounded-history summarization. The implementation is local-first and uses SQLite with write-ahead logging (WAL) to achieve atomicity, durability, and good concurrent read performance.

1.2. Scope
This document describes the Activity Buffer data model, write and read paths, sequencing rules, retention and compaction, summarization architecture, command-line interface, concurrency characteristics, failure handling, configuration, testing, and operational guidance. The implementation lives in bee/, and integrates with the Reasoning service for optional remote summarization. Distributed log storage, cross-host replication, and vector indices are out of scope.

1.3. Non-Goals
The Activity Buffer is not a global event bus, does not perform cross-node consensus, and does not natively index content for similarity search. It does not replace upstream observability pipelines. It does not guarantee global ordering across sessions, only per-session determinism.

2. Data Model

2.1. Relational Schema
The Activity Buffer stores normalized records in SQLite with the following tables.

Sessions: sessions(id TEXT PRIMARY KEY, created_at TEXT NOT NULL, agent_id TEXT, topic TEXT, metadata TEXT)
Events: events(session_id TEXT NOT NULL, seq INTEGER NOT NULL, kind TEXT NOT NULL, at TEXT NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(session_id, seq), FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE)
Attachments: attachments(sha256 TEXT PRIMARY KEY, bytes BLOB, mime TEXT)
Summaries: summaries(session_id TEXT NOT NULL, upto_seq INTEGER NOT NULL, at TEXT NOT NULL, summary TEXT NOT NULL, tokens INTEGER, cost_cents REAL, UNIQUE(session_id, upto_seq), FOREIGN KEY(session_id) REFERENCES sessions(id) ON DELETE CASCADE)
Meta: meta(key TEXT PRIMARY KEY, value TEXT)

All timestamps use RFC3339 in UTC. The schema runs with WAL enabled and foreign keys enforced. Columns typed as JSON are stored as TEXT with UTF‑8 JSON; validation occurs before insert.

2.2. Event Kinds and Schemas
Each event has a kind that governs payload structure. Payloads are validated against JSON Schemas before persistence. The reference implementation includes schemas for prompt, assistant_output, tool_call, tool_result, operator, and system. The schema set is pluggable and may be extended per deployment. Validation is fail‑closed: invalid payloads are rejected.

2.3. Sequence Numbers
Sequence numbers are strictly increasing per session and assigned by the store inside a single transaction. The (session_id, seq) pair forms the events primary key. Clients cannot supply sequence numbers; this prevents race conditions and preserves replay determinism.

2.4. Attachments
Attachments are stored as content-addressed blobs keyed by SHA‑256 in the attachments table and a filesystem directory under the Bee home. Events may reference attachments by digest within their payload schema. Attachments are immutable. Retention rules do not delete attachments still referenced by retained events.

2.5. Summaries
Summaries capture rolling condensations of a session’s recent events. Each summary row records a session_id, the maximum sequence number covered (upto_seq), a summary string, token usage, and an optional cost estimate. Summaries never modify events. Retention logic treats upto_seq as a safety boundary for deletion.

3. Write Path

3.1. Append Operation
Appending an event performs the following steps atomically within a transaction: ensure the session row exists; validate the event kind and payload against its JSON Schema; compute next sequence number as COALESCE(MAX(seq), 0) + 1 for that session; insert the event row with the current UTC timestamp. If any step fails, the transaction rolls back and no partial state is committed.

3.2. Atomicity and Durability
SQLite runs with PRAGMA journal_mode=WAL and PRAGMA foreign_keys=ON. Each append uses a BEGIN IMMEDIATE transaction to reserve write access, executes validation and insertions, and commits. WAL guarantees durability across process restarts if the commit succeeds. In the presence of power loss during commit, SQLite guarantees transactional semantics.

3.3. Limits and Validation
The store enforces a maximum payload size and may enforce a maximum number of events per session. Oversized payloads and structurally invalid payloads are rejected with explicit errors. Event kinds outside the allowed set are rejected.

4. Read Path

4.1. Session Listing
Listing sessions performs a read-only query ordered by created_at descending and returns metadata. This operation does not require locks under WAL and can run concurrently with appends.

4.2. Event Listing
Listing events for a session returns the ordered sequence of events by ascending seq. Payloads are parsed as JSON from TEXT. The read path is tolerant of older rows that predate schema updates, provided the JSON is syntactically valid.

4.3. Replay Semantics
Replay constructs the deterministic transcript of a session by streaming events in ascending seq order. Attachments missing at replay time are rendered as placeholders, and replay proceeds without aborting. The Activity Buffer does not execute side effects; it emits the recorded data for external consumers to reconstruct behavior.

4.4. Summary Inspection
Summaries can be listed per session to observe coverage and cost accounting. Readers can use upto_seq to determine which events have been summarized.

5. Retention and Compaction

5.1. Safety Model
Retention never deletes unsummarized events unless explicitly configured to do so. For each session, the store computes a safe boundary as MAX(upto_seq) from summaries. Deletions are constrained to seq ≤ boundary to preserve the minimal context that summaries claim to cover.

5.2. Age-Based Deletion
If a maximum age is configured, the store deletes events older than the cutoff time but only up to the safe boundary for each session. This prevents removing recent context or violating summary coverage.

5.3. Size-Based Compaction
If a maximum on-disk size is configured and the database file exceeds the limit, the store iteratively deletes the oldest batches of events within the safe boundary until the size constraint is satisfied or no safe deletions remain. The implementation uses small batch deletes to avoid long‑running transactions. If no summaries exist for any session, size-based compaction refuses to delete events unless an override is provided.

5.4. Vacuum and Integrity Checks
Operators can run integrity checks using SQLite PRAGMA integrity_check. Vacuum can be executed during maintenance windows to reclaim free pages after compaction. The CLI exposes check and vacuum commands to standardize these procedures.

6. Summarization

6.1. Rolling Summarizer
The rolling summarizer computes condensed summaries over a sliding window of the most recent events not yet covered by an existing summary. It writes a new summaries row with upto_seq equal to the maximum sequence seen in the window. Summarization is idempotent per input window and does not mutate event rows.

6.2. Local Summarizer
The local summarizer implements a deterministic heuristic that concatenates salient textual fields from prompt and assistant_output events and inserts tool_result markers. It estimates token count as a function of character length. This mode has zero external dependencies and produces stable output for testing and incident analysis.

6.3. Remote Summarizer
The remote summarizer calls the Reasoning service over gRPC to perform model-backed summarization. The protocol defines a Summarize RPC that accepts a sequence of TextSegments with kind, content, seq, and at, plus a soft token budget and an operation mode. The response includes the summary, token usage, cost in USD cents, and the model identifier. The client applies timeouts and returns explicit errors on failure. The store persists the returned summary and accounting fields.

6.4. Windowing Strategy
The window selects the N most recent unsummarized events per session, where N is configurable. The summarizer computes a single summary covering up to the highest sequence number in that selection. Subsequent runs skip already covered ranges. This produces monotonic coverage growth without overlap.

7. Command-Line Interface

7.1. Overview
The Bee CLI exposes subcommands to initialize the store, inspect sessions and events, append test events, replay transcripts, summarize sessions, and run compaction. Commands operate on the local store under the Bee home directory and return explicit exit codes on failure. Interactive prompts are avoided in favor of explicit flags for reproducibility.

7.2. Semantics
Initialization creates the database and ensures default pragmas. Listing commands are read-only and never mutate state. Append validates data and writes a single event within a transaction. Replay prints the canonical transcript in order. Summarize computes a rolling summary using local or remote mode, with parameters for window size, token budget, and endpoint. Compaction enforces age and size limits without violating summary boundaries.

8. Concurrency and Determinism

8.1. Isolation
SQLite WAL allows concurrent readers during writes. The append path uses transactional sequencing to ensure that two concurrent appenders to the same session serialize and produce a single total order by seq. Readers always see a prefix of the event sequence and never observe torn writes.

8.2. Ordering Guarantees
Per-session ordering is strictly monotonic by seq. Cross-session ordering is not defined and is not required for replay. Summaries reference per-session upto_seq, which composes with the per-session ordering to define retention safety.

9. Failure Handling

9.1. Disk Full
If the file system is full, append fails with an explicit error, and the CLI surfaces mitigation guidance, including reducing retention thresholds or freeing space. Compaction attempts to reduce size within safety constraints but declines to delete unsummarized data by default.

9.2. Corruption
On suspected corruption, operators run the integrity check. If corruption is detected, the recommended protocol is to back up the database file, capture diagnostics, and restore from a known-good snapshot. The Activity Buffer does not attempt in-place repair beyond standard SQLite facilities.

9.3. Missing Attachments
Replay emits placeholders for missing attachment blobs and continues. The event stream remains intact, allowing downstream systems to handle absent artifacts explicitly.

9.4. Remote Summarizer Failures
If the Reasoning service is unavailable or times out, the CLI reports the failure and leaves the store unchanged. Operators can retry or fall back to local summarization. No partial summaries are written.

9.5. Validation Errors
Invalid event kinds or payloads are rejected at append time, and the transaction aborts. The CLI prints a structured error descriptor, including the specific JSON Schema violation messages in local mode.

10. Configuration

10.1. Paths
The default store location is ${BEE_HOME:-~/.config/bee}/activity/activity.sqlite with a sibling blobs directory for attachments. The path is configurable through environment variables and CLI flags.

10.2. Limits
Retention age, maximum database size, maximum payload size, and summarization window size are configurable. The remote summarizer accepts token budgets and mode flags. Reasoning endpoints are resolved from CLI flags or environment variables.

11. Security and Privacy

11.1. Access Model
The Activity Buffer is local to the Bee runtime and inherits operating system file permissions. Access control is enforced by the host OS. Multi-tenant scenarios require separate Bee homes and OS-level isolation.

11.2. Encryption at Rest
When available, SQLite page encryption can be enabled via PRAGMAs or by using an encrypted VFS. Alternatively, the Bee home directory can reside on an encrypted file system. The Activity Buffer does not store encryption keys.

11.3. Redaction
Operators should avoid appending sensitive material that violates organizational policy. If the remote summarizer is used, payload text is transmitted to the Reasoning endpoint; appropriate data handling agreements and transport security are required.

12. Testing Strategy

12.1. Unit Tests
Unit tests validate migrations, JSON Schema validation, sequence numbering, transactionality, and retention logic. Tests construct ephemeral databases and assert precise outcomes.

12.2. Property Tests
Property tests generate random payloads to verify that only schema-conforming inputs are accepted and that sequencing never regresses.

12.3. Concurrency Tests
Tests simulate multiple appenders writing to the same session and assert that sequence numbers remain strictly increasing without gaps or duplicates.

12.4. CLI Tests
CLI tests cover all subcommands, including summarize in both local and remote stub modes, and verify deterministic output for fixed inputs.

13. Operational Guidance

13.1. Monitoring
Operators should track append rates, summary coverage growth, compaction activity, replay latency, and remote summarizer token usage and cost. These metrics inform capacity planning and incident response.

13.2. Migrations
Schema version is tracked in the meta table. Migrations are forward-only and preserve data. The CLI provides a migrate command that runs pending migrations in a single transaction.

13.3. Backup and Restore
Backups can be taken by copying the SQLite database and blobs directory while the process is quiescent or by using SQLite online backups. Restores must preserve relative paths for attachment resolution.

13.4. Export and Import
The store supports exporting a session to JSON lines for archival or offline analysis and importing such logs into an empty or testing database. Exported logs include event payloads and attachment digests.

14. Extensibility

14.1. Pluggable Schemas
Deployments can augment or override event schemas through configuration files loaded at startup. The validator compiles schemas on demand and caches them for runtime use.

14.2. Pluggable Summarizers
Additional summarizers can be registered that implement a common interface. The CLI selects the implementation via flags, allowing side-by-side evaluation of strategies.

14.3. Future Work
Future enhancements may include incremental vector indices derived from summaries, multi-store backends, and integration with centralized observability systems. These do not modify the core append-only semantics or per-session determinism.

15. Phase 1 Implementation Details

15.1. Schema Versioning and Migrations
The SQLite database maintains a `meta(schema_version)` integer to track forward-only migrations. On open, the store executes a migration routine that creates the `meta` table if missing and initializes or updates `schema_version` to the current crate version’s schema. Migrations execute inside a single transaction and are idempotent. The command-line provides `bee activity migrate` to apply pending migrations and return a clear status for operational use.

15.2. Limits and Configuration
The append path enforces limits before inserting the new row inside the same transaction that assigns sequence numbers. The store rejects any event whose serialized JSON payload exceeds the configured maximum or whose session has reached an optional event cap, preventing partial state and preserving determinism. Configuration is via environment variables: `BEE_ACTIVITY_MAX_PAYLOAD` (bytes; default 262144), `BEE_ACTIVITY_MAX_EVENTS_PER_SESSION` (integer; optional), `BEE_ACTIVITY_MAX_BYTES` (bytes; optional, default for compaction), and `BEE_ACTIVITY_MAX_AGE_DAYS` (integer; optional, default for compaction). Explicit CLI flags override environment defaults.

15.3. Integrity and Maintenance Commands
The CLI exposes `bee activity check` to run `PRAGMA integrity_check` and print the result, and `bee activity vacuum` to reclaim free pages after deletions. These operations support incident triage and routine maintenance. `check` is read-only; `vacuum` does not modify logical rows or sequencing.

15.4. Inspection Enhancements
The CLI extends observability with `bee activity summaries --session <id>` to list summary coverage (upto_seq, timestamp, token usage, and cost) and `bee activity show --session <id> --seq <n>` to pretty-print individual events. These commands reduce the need for ad-hoc SQL during incident response.

15.5. Safety Guarantees
All new enforcement runs before insertion within the same transaction, so rejected writes do not consume sequence numbers. Compaction continues to respect per-session safety boundaries derived from `summaries.upto_seq` and avoids deleting unsummarized ranges unless explicitly overridden by a future policy. Maintenance commands do not alter event content or ordering.

15.6. Testing Additions
Unit tests cover schema version initialization and idempotent migration; payload size limit enforcement at boundaries; optional per-session caps with explicit error messages; integrity check surfacing for corrupted fixtures; and CLI output for `summaries` and `show` on ephemeral databases. Existing concurrency tests for appenders remain valid and enforce serializable ordering.
