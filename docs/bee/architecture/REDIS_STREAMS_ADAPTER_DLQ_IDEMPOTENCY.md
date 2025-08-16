# 1. System Overview

## Implementation Status (2025-08-16)

- Code: bee specialization under `bee/src/bus/redis_streams` with CLI commands in `bee/src/main.rs`.
- Implemented:
  - Health (PING)
  - Publish with idempotency via Lua (atomic `SET NX` → `XADD` → `SET`) with TTL
  - Consume with processing idempotency (`SET NX PX` per-delivery key)
  - Reclaim timed-out entries via `XAUTOCLAIM` (configurable min idle)
  - DLQ routing after max attempts or handler error; `XACK` original after DLQ write
  - Minimal stats: `XLEN` depth and `XPENDING` pending count
- Pending:
  - Formal reason codes and envelope shaping for main/DLQ entries
  - Rich metrics (lag, latency) and admin ops (pending listings, DLQ replay)
- Key prefixes: primary `bus:<env>:<topic>`, DLQ `bus:<env>:<topic>:dlq`, publish-idem `bus:<env>:<topic>:idem:<key>`, processing-idem `bus:<env>:<topic>:proc:<group>:<id>`

## CLI Quickstart

- Health: `bee bus health --url redis://127.0.0.1/`
- Publish: `bee bus publish --topic demo --payload '{"hello":"world"}' --content-type application/json`
- Consume (managed): `bee bus consume --topic demo --group g1 --consumer c1 --block-ms 1000 --min-idle-ms 30000 --max-attempts 5`
- Stats: `bee bus stats --topic demo --group g1`

## Key Paths

- Adapter: `bee/src/bus/redis_streams/adapter.rs`
- Models: `bee/src/bus/redis_streams/models.rs`
- Health: `bee/src/bus/redis_streams/health.rs`
- Lua: `bee/src/bus/redis_streams/lua/publish_idem.lua`
- CLI wiring: `bee/src/main.rs`

This document specifies a Redis Streams–backed message bus adapter that provides at-least-once delivery with idempotent publish and consume semantics, per-topic dead-letter queues (DLQs), and backpressure metrics. The adapter encapsulates Redis-specific details behind a stable interface that exposes publish, subscribe, acknowledge, and negative-acknowledge operations. The implementation uses Redis Streams commands `XADD`, `XREADGROUP`, `XACK`, and `XAUTOCLAIM`, an idempotency store to deduplicate re-deliveries, and explicit DLQ routing after a configurable maximum delivery attempt count.

## 1.1. Goals

Guarantee at-least-once delivery and idempotent processing under re-delivery. Support per-environment topic scoping and expose metrics for stream depth, consumer lag, processing latency, and redelivery rates. Provide operational hooks for health checks and structured observability.

## 1.2. Non-Goals

No exactly-once delivery, cross-region replication, or transactional outbox. Not a replacement for Kafka/RabbitMQ.

# 2. Architecture

Publishers add envelopes to topic streams. Consumers read from consumer groups, acknowledge successfully processed messages, and route failures to DLQs when retry budgets are exhausted. A stats path queries Redis for stream and group state.

## 2.1. Components

- Bus interface surface: `publish`, `subscribe`, `ack`, `nack` (SDK-level)
- Redis adapter: connection manager, Lua publish-idem, managed consume loop
- Idempotency keys: publish-idem and processing-idem
- Stats: depth and pending; planned lag/latency
- Health checker: PING

## 2.2. Data Model

Current fields:
- Main stream: `ct` (content type), `payload` (string, usually JSON)
- DLQ: `orig`, `reason`, `group`, `consumer`, `deliveries`, `ct`, `payload`

Planned shaping: stable envelope headers (`ct`, `sv`, `cid`, `ccid`, `ts`, `idem`, `attempt`) and JSON payload; DLQ entries embed the envelope plus reason and context.

## 2.3. Keyspace Layout

- Primary stream: `bus:<env>:<topic>`
- DLQ stream: `bus:<env>:<topic>:dlq`
- Publish idempotency: `bus:<env>:<topic>:idem:<key>` value = stream id (TTL)
- Processing idempotency: `bus:<env>:<topic>:proc:<group>:<id>` value = "1" (TTL)

# 3. Publish Path

Admission uses a Lua script to atomically guard and publish.

## 3.1. Publish Idempotency Algorithm

`SET idem_key placeholder NX PX <ttl_ms>` → if exists, return stored id; else `XADD stream * ct <ct> payload <payload>` → `SET idem_key <id> PX <ttl_ms>` and return `<id>`.

## 3.2. Envelope Encoding

Current: `ct` + `payload` fields. Planned: stable headers + schema validation.

## 3.3. Error Handling

Client retries on transient errors; Lua ensures server-side atomicity between guard and publish.

# 4. Consume Path

Managed loop alternates between `XREADGROUP` for new entries and `XAUTOCLAIM` for stale pending entries.

## 4.1. Group Management

Ensure group via `XGROUP CREATE ... MKSTREAM` (ignore already-exists).

## 4.2. Fetch and Reclaim

`XREADGROUP GROUP <group> <consumer> COUNT <n> BLOCK <t> STREAMS <stream> >` and `XAUTOCLAIM <stream> <group> <consumer> <min-idle-ms> 0-0 COUNT <n>`.

## 4.3. Idempotent Processing

Reserve processing key: `SET proc_key 1 NX PX <ttl_ms>`. If key exists, `XACK` (already processed). On success, handle and `XACK` the original. Current policy keeps the key set for both success and DLQ to prevent duplicate handling after acknowledgement.

## 4.4. Retry and DLQ

Evaluate delivery count via `XPENDING` per-id lookup. If `deliveries >= max_attempts` or handler error, write DLQ entry and `XACK` original; else leave pending for future reclaim (backoff achieved via min idle).

## 4.5. DLQ Entry

Fields: `orig`, `reason` (`max_attempts` | `handler_error`), `group`, `consumer`, `deliveries`, `ct`, `payload`.

# 5. Metrics and Observability

Current: `depth` (`XLEN`) and `pending` (summary from `XPENDING`). Planned: group lag (`XINFO`), latency histograms, error rates, tracing spans.

# 6. Configuration

- `BEE_REDIS_URL`: Redis URL
- `BEE_BUS_ENV`: environment name used in stream keys
- `BEE_BUS_IDEM_TTL_MS`: TTL for publish idempotency (default 1h)
- `BEE_BUS_PROC_TTL_MS`: TTL for processing idempotency (default 6h)
- CLI flags (consume): `--min-idle-ms`, `--max-attempts`

