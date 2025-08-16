# Redis Streams Adapter — DLQ + Idempotency

This document tracks the worktree’s purpose, key links, and the prioritized delivery checklist for the Redis Streams adapter with DLQ and idempotent publish/consume semantics.

## Overview

- Objective: at-least-once delivery with idempotent publish and processing, per-topic DLQs, and operational metrics.
- Scope: language-agnostic Bus interface (`publish`, `subscribe`, `ack`, `nack`) backed by Redis Streams.
- Outputs: adapter implementation, Lua scripts for idempotency, config surface, metrics, and runbooks.
- Status: use the checklist below to track P0→P3 items.

## Associated Docs

- Architecture: [docs/bee/architecture/REDIS_STREAMS_ADAPTER_DLQ_IDEMPOTENCY.md](../docs/bee/architecture/REDIS_STREAMS_ADAPTER_DLQ_IDEMPOTENCY.md)
- Worktree guide: [WORKTREE_README.md](../WORKTREE_README.md)

---

## Implementation Snapshot

- Updated: 2025-08-16
- Code location (bee specialization):
  - `bee/src/bus/redis_streams/` (models, adapter, health, Lua)
  - `bee/src/main.rs` (CLI `bee bus health|publish|consume|stats`)
- Current capabilities:
  - Health check via Redis PING.
  - Publish with optional idempotency via Lua script: `SET NX` placeholder → `XADD` → `SET` final id with TTL; key prefix `bus:<env>:<topic>:idem:<key>`.
  - Consumer with processing idempotency: `SET NX PX` per delivery key `bus:<env>:<topic>:proc:<group>:<id>`; `XACK` on success; duplicates auto-ack.
  - Reclaim stale deliveries via `XAUTOCLAIM` with configurable `min_idle_ms`; simple retry/backoff using min-idle window and delivery counts.
  - DLQ routing to `bus:<env>:<topic>:dlq` with fields `{orig, reason, group, consumer, deliveries, ct, payload}`; original is `XACK`ed after DLQ write.
  - Minimal stats CLI: `bee bus stats` prints `depth` (`XLEN`) and `pending` (`XPENDING` count).
- Not yet implemented:
  - Formal reason codes and envelope shaping for DLQ and main stream entries.
  - Rich metrics/tracing surface and admin ops (pending listing, DLQ replay tools).

### Immediate Next Steps

- [ ] Add formal reason codes and envelope shaping for both main stream and DLQ entries.
- [ ] Expose richer metrics: depth, lag, pending, lat/error; tracing spans.
- [ ] Add CLI convenience: `bee bus publish --idem <key>` and admin ops (pending browse, DLQ replay).

## Configuration

- `BEE_REDIS_URL`: Redis connection string (default `redis://127.0.0.1/`).
- `BEE_BUS_ENV`: Environment scope in key prefix (default `dev`).
- Stream key prefix: `bus:<env>:<topic>`; DLQ: `bus:<env>:<topic>:dlq`.

## Next Milestones

- P0: Add Lua publish idempotency (SET NX → XADD → SET; TTLs).
- P0: Add processing idempotency SET NX with TTL; `XACK` on success.
- P0: Add `XAUTOCLAIM` path + simple backoff using min-idle windows.
- P0: DLQ routing with reason/context and original `XACK`.
- P1: Metrics hooks (depth, lag, pending, lat/error); config surface.

## Open Questions / Decisions

- Should Envelope/Headers live in SDK for reuse across tools? (Leaning yes for schema stability.)
- Spec updates to formalize idempotency semantics and DLQ payload shape.

---

## Prioritized Checklist

- [ ] P0: Define language-agnostic Bus interface (`publish`, `subscribe`, `ack`, `nack`) and envelope schema.
- [x] P0: Implement publish with Lua idempotency (SET NX placeholder + XADD + SET; configurable TTLs).
- [ ] P0: Enforce schema validation and payload size limits with deterministic errors.
- [x] P0: Ensure idempotent group creation (XGROUP CREATE MKSTREAM) and consumer naming.
- [x] P0: Implement subscribe loop (XREADGROUP for new; XAUTOCLAIM for stale; basic loop).
- [x] P0: Implement processing idempotency (SET NX proc_key PX TTL); XACK on success; duplicate deliveries auto-ack.
- [x] P0: Implement retry/backoff policy using delivery counts and minimum idle windows (basic).
- [x] P0: Implement DLQ routing (per-topic stream) with context; XACK original after DLQ write.
- [x] P0: Add startup health checks (connectivity via PING).
- [ ] P0: Add formal reason codes and envelope shaping for main stream and DLQ entries.

- [ ] P1: Instrument metrics (depth, lag, pending, handler lat/error; tracing spans).
- [ ] P1: Expose configuration surface (URI, TLS, auth, pool, timeouts, feature flags, retention, backoff, max attempts).
- [ ] P1: Add exponential backoff and circuit breaker for producer/consumer operations with bounded retries.
- [ ] P1: Batch acknowledgements and DLQ writes; tune XREADGROUP COUNT and BLOCK.

- [ ] P2: Integration tests against ephemeral Redis (pub/consume/ack/nack; pub+proc idempotency; DLQ routing; faults).
- [ ] P2: Serialization and schema-compatibility tests (envelope field stability; schema registry bindings).
- [ ] P2: Author operational runbooks (lag diagnosis, pending inspection, DLQ replay workflow, retention tuning).

- [ ] P3: Draft bridge designs (Redis→Kafka, Kafka→Redis, RabbitMQ↔Redis): dedupe keys, loop prevention, DLQ mapping.
- [ ] P3: Build admin utilities for DLQ browsing and replay with guardrails.
- [ ] P3: Produce migration plan doc (feature-flag rollout, alerts, rollback procedures).
