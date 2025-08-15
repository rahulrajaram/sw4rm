# MASTER_CONTEXT — Status and Next Actions

This document consolidates milestone contexts into a single, actionable view: where the project stands and what to do next. It’s derived from the files in `contexts/` and serves as the living checklist for near‑term delivery.

Updated: 2025-08-15

## Project Positioning (Where We Are)

- LLM Platform: Milestone scope/spec defined (uniform trait, streaming, tool calls, adapters for Anthropic/OpenAI, caching, rate limiting). Implementation status in code not enumerated here; assumes partial progress pending fixtures, robust error taxonomy, and CLI smoke tests.
- Secrets: Broadly implemented across SDKs + Bee CLI with file/keyring backends and precedence resolver. Remaining work includes richer error codes, audit logs, telemetry counters, import from `.env`, provider helpers, and targeted tests.
- Scheduler: Lanes/preemption milestone designed. Bee CLI already exposes non‑interactive scheduler subcommands. Interactive shell verbs planned; core lane queues, preemption/resume, and aging logic not yet complete.
- Activity Buffer: Detailed design for SQLite‑backed append‑only event store, rolling summarizer, and CLI. Implementation appears pending, including migrations, limits enforcement, integrity/maintenance commands, and tests.
- Message Bus (Redis Streams): Basic capabilities exist (health, publish, simple consumer). P0 items outstanding: publish/processing idempotency (Lua + keys), `XAUTOCLAIM` path, DLQ routing, minimal metrics.
- Telemetry: Integration plan defined (OpenTelemetry tracing + Prometheus metrics, dashboard JSON). Implementation hooks across LLM, tools, scheduler, and bus appear pending.
- Shell/TUI: MVP features largely shipped (history, status line basics, scheduler slash commands, `/events` parity, incremental search). Remaining: cost estimates, autocomplete/help, keybindings config, stronger preemption UX, tests, and observability metrics.
- Packaging & Examples: CI packaging strategy and examples described; workflows, checksums, and install docs need verification and wiring if not already present.

## Next Actions (Prioritized, Cross‑Component)

1) Redis Streams Adapter (P0 readiness)
- [ ] Implement publish idempotency via Lua (SET NX → XADD → SET; TTL configurable).
- [ ] Add processing idempotency (SET NX proc_key PX TTL); `XACK` on success; delete on failure.
- [ ] Add `XAUTOCLAIM` reclaim path with simple backoff using min‑idle windows.
- [ ] Implement DLQ routing with reason/context; `XACK` original on DLQ write.
- [ ] Smoke health: startup connectivity, minimal XADD/XREAD test; expose minimal metrics (depth via `XLEN`, lag/pending via `XINFO`/`XPENDING`).
- [ ] Implement `bee/src/bus/redis_streams/lua/publish_idem.lua` and wire to adapter.
- [ ] Finalize envelope field names (`ct`, `sv`, `cid`, `ccid`, `ts`, `idem`, `attempt`) and per‑topic JSON Schemas; validate on publish.

2) Secrets Hardening
- [ ] Expand and unify error codes with precise remediation text.
- [ ] Add audit logging (no values) + telemetry counters for set/get/list and env overrides.
- [ ] Implement `bee secret import --from .env --scope <hive>` with dry‑run/confirm.
- [ ] Provide helpers for `provider.*.api_key` lookup by scope in SDKs and wire into LLM adapters.
- [ ] Add targeted tests: precedence, backend selection, file perms, env override warnings.

3) Scheduler Lanes + Preemption
- [ ] Define lane config and defaults; validate load from config with feature flag.
- [ ] Implement per‑lane run queues and persistent task state machine.
- [ ] Enforce preemption policy with deterministic tie‑breakers and serialized control loop.
- [ ] Worker checkpoint handshake with deadlines; idempotent preempt‑by‑id/above‑priority.
- [ ] Resume‑from‑checkpoint flow with idempotency and fallbacks when missing.
- [ ] Add within‑lane aging to prevent starvation.
- [ ] Shell/TUI verbs: wire `/submit`, `/preempt`, `/bind`, `/switch` with contextual help and autocomplete.
- [ ] Unit/integration tests for ordering, aging, state transitions, and preempt/resume correctness.

4) Activity Buffer (Phase 1)
- [ ] Implement SQLite store with schema (`sessions`, `events`, `attachments`, `summaries`) and transactional append with store‑assigned monotonic seq.
- [ ] Add forward‑only migrations with `bee activity migrate` and idempotence.
- [ ] Enforce limits from env (payload size, optional per‑session cap; bytes/age for compaction).
- [ ] Integrity/maintenance: `bee activity check` (PRAGMA integrity_check) and `bee activity vacuum`; enable WAL + foreign_keys pragmas by default.
- [ ] CLI UX: `sessions`, `events`, `show`, `replay`, `summaries` with stable, pretty output.
- [ ] Rolling summarizer job using model provider abstraction; optionally support remote Reasoning gRPC summarizer; record cost/tokens in `summaries`.
- [ ] Tests: schema/migration, limit enforcement, concurrency, deterministic replay, summarizer stubbing, CLI outputs.

5) Telemetry Integration
- [ ] Implement Bee telemetry module (`bee/src/telemetry/{config,init,metrics}.rs`).
- [ ] Add tracing spans for LLM calls, tool execs, scheduler decisions, and bus pub/consume.
- [ ] Expose Prometheus metrics endpoint (`/metrics` on `BEE_METRICS_ADDR`); register counters/histograms; avoid high cardinality and hash large IDs.
- [ ] Add dashboard JSON at `docs/dashboards/bee_telemetry.json`; document exporters/env.
- [ ] Fault tests for exporter/endpoint failures and graceful degradation.

6) Shell/TUI Enhancements
- [ ] Status line cost estimates from recent token usage; graceful fallback without telemetry.
- [ ] Contextual help and autocomplete for slash commands; inline usage hints on errors.
- [ ] Keybindings + dotfile config; documented defaults and overrides.
- [ ] Robust preemption UX: checkpoint progress, resume hints, warnings for risky mass‑preempt.
- [ ] Tests: history read/write/rotation, keybinding map, status line snapshots, slash commands.
- [ ] Observability: emit metrics for command outcomes, lane depths, and preemption rates.

7) LLM Platform Completeness
- [ ] Finalize adapters (Anthropic/OpenAI) to common trait with strict schemas and normalized errors.
- [ ] Add provider‑recorded fixtures; streaming assembly parity tests; tool‑call round‑trip validation.
- [ ] Rate limiting + idempotency keys; optional exact‑match cache; CLI smoke tests for both providers.
- [ ] Secrets integration: resolve API keys via scoped resolver with clear override warnings.

## Doc‑Backed Implementation Hooks

- Redis Streams: adapter at `bee/src/bus/redis_streams/{adapter.rs,models.rs,health.rs}`, Lua script at `bee/src/bus/redis_streams/lua/publish_idem.lua`, CLI wiring in `bee/src/main.rs` (`bee bus health|publish|consume`).
- Activity Buffer: store and CLI in `bee/` with WAL and `BEGIN IMMEDIATE` on append; attachment CAS under Bee home.
- Telemetry: init/config/metrics under `bee/src/telemetry`, OTLP gated by `BEE_OTEL_EXPORTER=otlp`, Prometheus at `BEE_METRICS_ADDR`.

8) Packaging and Examples
- [ ] Wire CI workflows for cross‑platform builds, checksums, and artifact upload.
- [ ] Provide minimal install script and verify `bee --version` in CI.
- [ ] Validate and pin the two examples with `make` targets and CI assertions against outputs.
- [ ] Document troubleshooting for codesigning (macOS) and SmartScreen (Windows).

## Cross‑Cutting Notes

- Documentation: Follow constraints (e.g., place Secrets docs under `docs/bee/architecture/` without modifying `mkdocs.yml`).
- Feature Flags: Introduce new modules behind flags; preserve forward‑only migrations and schema stability.
- Security/Permissions: Enforce strict file perms for secrets/history; avoid leaking secrets in logs/telemetry.
- Operator UX: Favor precise, actionable error messages and consistent CLI/shell ergonomics across features.
