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

- Updated: 2025-08-15
- Code location (bee specialization):
  - `bee/src/bus/redis_streams/` (models, adapter, health, Lua placeholder)
  - `bee/src/main.rs` (CLI `bee bus health|publish|consume`)
- Current capabilities:
  - Health check via Redis PING.
  - Publish via `XADD` to `bus:<env>:<topic>` (basic; no idempotency yet).
  - Basic consumer demo: ensure group (`XGROUP CREATE MKSTREAM`) + `XREADGROUP` loop.
- Not yet implemented:
  - Publish idempotency (Lua script) and processing idempotency keys.
  - `XAUTOCLAIM` reclaim, retry/backoff, and DLQ routing.
  - Metrics surface and admin ops (pending, dlq replay).

### Immediate Next Steps

- [ ] Implement `bee/src/bus/redis_streams/lua/publish_idem.lua` and wire to publish path (SET NX → XADD → SET; TTL).
- [ ] Add processing idempotency keys (SET NX PX TTL) and acknowledge on success; delete key on failure.
- [ ] Implement `XAUTOCLAIM` reclaim loop with min-idle backoff and group/consumer naming conventions.
- [ ] Implement DLQ routing with reason codes and context; `XACK` original after DLQ write.
- [ ] Expose minimal metrics: depth (`XLEN`), lag/pending (`XINFO`/`XPENDING`); add health CLI smoke tests.

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
- [ ] P0: Implement publish with Lua idempotency (SET NX placeholder + XADD + SET; configurable TTLs).
- [ ] P0: Enforce schema validation and payload size limits with deterministic errors.
- [ ] P0: Ensure idempotent group creation (XGROUP CREATE MKSTREAM) and consumer naming.
- [ ] P0: Implement subscribe loop (XREADGROUP for new; XAUTOCLAIM for stale; cancellation token).
- [ ] P0: Implement processing idempotency (SET NX proc_key PX TTL); XACK on success; delete proc_key on failure.
- [ ] P0: Implement retry/backoff policy using delivery counts (XPENDING/XAUTOCLAIM) and minimum idle windows.
- [ ] P0: Implement DLQ routing (per-topic stream) with envelope, attempt count, reason, group context; XACK original.
- [ ] P0: Add startup health checks (connectivity; minimal XADD/XREAD smoke test).

- [ ] P1: Instrument metrics (XLEN depth, XINFO/lag, XPENDING/pending, handler latency/error rate; tracing spans).
- [ ] P1: Expose configuration surface (URI, TLS, auth, pool, timeouts, feature flags, retention, backoff, max attempts).
- [ ] P1: Add exponential backoff and circuit breaker for producer/consumer operations with bounded retries.
- [ ] P1: Batch acknowledgements and DLQ writes; tune XREADGROUP COUNT and BLOCK.

- [ ] P2: Integration tests against ephemeral Redis (pub/consume/ack/nack; pub+proc idempotency; DLQ routing; faults).
- [ ] P2: Serialization and schema-compatibility tests (envelope field stability; schema registry bindings).
- [ ] P2: Author operational runbooks (lag diagnosis, pending inspection, DLQ replay workflow, retention tuning).

- [ ] P3: Draft bridge designs (Redis→Kafka, Kafka→Redis, RabbitMQ↔Redis): dedupe keys, loop prevention, DLQ mapping.
- [ ] P3: Build admin utilities for DLQ browsing and replay with guardrails.
- [ ] P3: Produce migration plan doc (feature-flag rollout, alerts, rollback procedures).
