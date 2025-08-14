# 1. System Overview

## Implementation Status

- Code: bee specialization under `bee/src/bus/redis_streams` with CLI commands in `bee/src/main.rs`.
- Current: health (PING), basic publish (XADD), and basic consume (XREADGROUP) demo.
- Pending: idempotent publish (Lua), processing idempotency, XAUTOCLAIM reclaim + backoff, DLQ routing, metrics.
- Prefixes: `bus:<env>:<topic>` and DLQ `bus:<env>:<topic>:dlq`.

## CLI Quickstart

- Health: `bee bus health --url redis://127.0.0.1/`
- Publish: `bee bus publish --topic demo --payload '{"hello":"world"}' --content-type application/json`
- Consume: `bee bus consume --topic demo --group g1 --consumer c1`

## Key Paths

- Adapter: `bee/src/bus/redis_streams/adapter.rs`
- Models: `bee/src/bus/redis_streams/models.rs`
- Health: `bee/src/bus/redis_streams/health.rs`
- Lua: `bee/src/bus/redis_streams/lua/publish_idem.lua`
- CLI wiring: `bee/src/main.rs`


This document specifies a Redis Streams–backed message bus adapter that provides at-least-once delivery with idempotent publish and consume semantics, per-topic dead-letter queues (DLQs), and backpressure metrics. The adapter encapsulates Redis-specific details behind a stable interface that exposes publish, subscribe, acknowledge, and negative-acknowledge operations. The implementation uses Redis Streams commands `XADD`, `XREADGROUP`, `XACK`, and `XAUTOCLAIM` (or `XCLAIM` where required), an idempotency store to deduplicate re-deliveries, and explicit DLQ routing after a configurable maximum delivery attempt count. Consumers operate in groups with cooperative cancellation for graceful shutdown.

## 1.1. Goals

The adapter guarantees at-least-once delivery and idempotent processing under re-delivery. It supports topic scoping per environment and reports metrics for stream depth, consumer lag, processing latency, and redelivery rates. It provides operational hooks for health checks and structured observability.

## 1.2. Non-Goals

The adapter does not implement exactly-once delivery, cross-region replication, or transactional outbox patterns. It does not attempt to replace external brokers such as RabbitMQ or Kafka.

# 2. Architecture

The system consists of a Bus interface, a Redis Streams adapter, an idempotency store, and monitoring instrumentation. Publishers add typed envelopes to topic streams. Consumers read from consumer groups, acknowledge successfully processed messages, and route failures to DLQs when retry budgets are exhausted. A metrics reporter queries Redis for stream and group state and records timing derived from envelope metadata.

## 2.1. Components

The Bus interface defines methods `publish`, `subscribe`, `ack`, and `nack`. The Redis adapter implements these methods using a connection pool with optional TLS and authentication. The idempotency store relies on Redis keys to record publication and processing decisions. A metrics module periodically samples Redis via `XLEN`, `XINFO`, and `XPENDING` to compute depth, lag, and retry rates. A health checker validates connectivity and minimal stream operations at startup.

## 2.2. Data Model

Messages carry a typed envelope encoded as JSON. Each envelope contains an immutable identifier `id`, a `topic`, headers, and a JSON `payload`. Headers include a content type, a schema version, a correlation identifier, a causation identifier, a created-at timestamp, an idempotency key, and an attempt count used for observability. DLQ entries embed the original envelope, the group and consumer context, a reason code, and a timestamp.

## 2.3. Keyspace Layout

Each topic maps to a Redis stream `bus:<env>:<topic>`. Each topic has a corresponding DLQ stream `bus:<env>:<topic>:dlq`. Idempotent publish uses keys `bus:idem:pub:<env>:<topic>:<key>` whose values store the resulting stream IDs. Idempotent consume uses keys `bus:idem:proc:<env>:<topic>:<msg-id>` to record completed processing. Optional per-message attempt counters use keys `bus:attempts:<env>:<topic>:<msg-id>` if delivery counts from Redis are not sufficient for a given policy.

# 3. Publish Path

Publishing accepts a topic, an envelope, and options. The adapter performs idempotency admission before writing to the stream. The admission uses an atomic guard to ensure that duplicate publish requests with the same idempotency key do not produce duplicate stream entries. After admission succeeds, the adapter writes the envelope with `XADD` and persists the assigned stream ID in the idempotency record.

## 3.1. Publish Idempotency Algorithm

The adapter executes a Lua script to atomically establish idempotency and publish. First, it attempts `SET idem_key placeholder NX PX <ttl_ms>`. If this operation fails, it returns the stored stream ID from `idem_key` to indicate a duplicate publish and completes without adding a new entry. If it succeeds, the script issues `XADD stream * <fields>` to write the envelope fields and then `SET idem_key stream_id PX <ttl_ms>` to record the definitive stream ID. The script returns the stream ID to the caller. This approach achieves idempotent publication even under client retry. The TTL bounds the idempotency window and should exceed the maximum expected latency between publish and observation.

## 3.2. Envelope Encoding

The envelope is encoded as a flat field map compatible with Redis Streams. The payload is stored as a JSON string under a `payload` field. Headers are stored as separate fields with stable names such as `ct`, `sv`, `cid`, `ccid`, `ts`, `idem`, and `attempt`. The adapter validates the payload against the registered schema for the topic before admission.

## 3.3. Error Handling

If the Lua script fails due to a network error, the client retries with exponential backoff using a bounded number of attempts. If `XADD` fails after the idempotency placeholder is set and before the second `SET`, the script guarantees atomicity because both operations execute on the server within a single script. When the server is unavailable, the adapter trips a circuit breaker after consecutive failures and backs off before reattempting.

# 4. Consume Path

Consumers join a consumer group per topic and read new messages with `XREADGROUP`. Each consumer uses a distinct consumer name to enable work-stealing and failure detection. The adapter processes deliveries idempotently and acknowledges successful processing with `XACK`. Failures result in either a retry decision or immediate DLQ routing depending on the reason and configured policy.

## 4.1. Group Management

On subscription, the adapter ensures the consumer group exists by issuing `XGROUP CREATE stream group $ MKSTREAM` and ignoring the “already exists” error when present. The adapter registers a consumer name implicitly on the first `XREADGROUP`. Consumers use `BLOCK` to wait for messages and `COUNT` to bound batch sizes.

## 4.2. Fetch and Reclaim

The adapter alternates between reading new entries and reclaiming timed-out pending entries. It issues `XREADGROUP GROUP <group> <consumer> COUNT <n> BLOCK <t> STREAMS <stream> >` to fetch new messages. It then uses `XAUTOCLAIM <stream> <group> <consumer> <min-idle-ms> <start-id> COUNT <n>` to atomically claim and fetch stale pending messages that have exceeded the configured idle threshold. This mechanism prevents message starvation and ensures forward progress when consumers crash.

## 4.3. Idempotent Processing

Before invoking user code, the adapter performs a processing idempotency check. It attempts `SET proc_key 1 NX PX <ttl_ms>`. If the key already exists, the adapter interprets the message as already processed and acknowledges it immediately with `XACK`. If `SET ... NX` succeeds, the adapter invokes the user handler with the envelope and a cancellation token. Upon successful completion, `XACK` removes the entry from the pending list. If the handler fails, the adapter deletes `proc_key` to allow future reprocessing unless a policy dictates otherwise for non-recoverable errors.

## 4.4. Acknowledge and Negative Acknowledge Semantics

Acknowledgement marks completion of processing for one or more message IDs via `XACK`. Negative acknowledgement represents a processing failure. The adapter evaluates the retry policy, which considers the Redis-reported delivery count and error classification. If the delivery count is below the configured maximum, the adapter leaves the entry pending and relies on idle-time reclamation to trigger redelivery after a backoff delay. If the count meets or exceeds the limit, the adapter routes the message to the DLQ and acknowledges the original entry to remove it from the group pending list.

## 4.5. Delivery Count and Backoff

Redis exposes per-entry delivery counts through `XPENDING stream group start end count` and implicitly via `XAUTOCLAIM` replies. The adapter uses these counts to implement a bounded retry policy. Backoff is implemented by delaying `XAUTOCLAIM` reclamation for entries whose idle time is lower than a computed backoff interval based on the attempt number, for example using exponential backoff with a configured maximum idle.

## 4.6. DLQ Routing

DLQ routing writes a DLQ entry containing the original envelope, the original stream and ID, the group name, the delivery count, a reason code, and the most recent error message. The adapter writes this entry to `bus:<env>:<topic>:dlq` using `XADD`. After writing to the DLQ, the adapter acknowledges the original entry with `XACK`. DLQ entries are immutable and retained per configured retention limits, which may differ from primary stream retention.

## 4.7. Cooperative Cancellation

The subscription loop accepts a cancellation token. The adapter checks the token before each blocking read and before invoking the user handler. On cancellation, the adapter stops issuing new reads, completes in-flight handlers, and flushes pending acknowledgements before returning control to the caller.

# 5. Metrics and Observability

The adapter emits metrics for stream depth, consumer group lag, pending counts, redelivery rates, and processing latency. Depth derives from `XLEN`. Group lag is computed as the difference between the stream’s last-generated ID and the group’s last-delivered ID obtained from `XINFO STREAM` and `XINFO GROUPS`. Pending count derives from `XINFO GROUPS` and `XPENDING`. Processing latency is measured as the difference between the current time and the envelope timestamp at the point of acknowledgement. The adapter records handler execution durations and error rates, and it annotates operations with tracing spans when OpenTelemetry is enabled.

# 6. Configuration

Configuration includes the Redis URI, optional TLS parameters, authentication credentials, timeouts, pool size, and circuit breaker thresholds. Bus-level options include environment scope prefixing, per-topic retention and DLQ retention, maximum delivery attempts, minimum idle time for reclamation, read batch size, block timeout, idempotency TTLs for publish and process, and schema registry bindings per topic. Each option has a deterministic default and can be overridden per subscription.

# 7. Failure Handling and Recovery
# 7. Failure Handling and Recovery

Network partitions and broker outages cause read and write operations to fail. The adapter applies exponential backoff and trips a circuit breaker after a configured number of consecutive failures, short-circuiting further attempts for a cooldown interval. Upon recovery, it re-establishes the connection pool and resumes consumer group participation without losing pending work. If a producer crash occurs after the idempotency placeholder is established but before the publish completes, server-side scripting guarantees atomicity: either both idempotency and stream write happen or neither does. If a consumer crashes while holding pending messages, those entries become reclaimable after the minimum idle time and another consumer claims them using `XAUTOCLAIM`, ensuring forward progress without manual intervention.

# 8. Concurrency and Performance

The adapter uses a bounded connection pool sized to the product of the number of active topics and the degree of parallelism per topic. Publish operations batch field encoding and use pipelining when supported by the client library to amortize round-trip latency. Consume operations read in bounded batches, and the adapter coalesces acknowledgements and DLQ writes to reduce network calls. `XAUTOCLAIM` avoids the coordination overhead of `XPENDING` plus `XCLAIM` by atomically advancing the start cursor while returning claimed entries. Payload sizes are validated before publish, and oversized messages are rejected deterministically. Stream retention uses `MAXLEN` trimming policies tuned to bound memory growth without violating at-least-once delivery semantics.

# 9. Security

Connections support TLS with server certificate validation and optional client authentication. Authentication uses Redis ACLs or password authentication with least-privilege roles that restrict access to bus and DLQ keyspaces. Idempotency and processing keys store only opaque identifiers and timestamps; no payload material is persisted outside streams and DLQs. Logs and traces redact sensitive header fields and payloads according to a configurable allowlist. Credentials are loaded from the platform secrets manager and never written to disk.

# 10. Testing Strategy

Integration tests provision an ephemeral Redis instance and validate publish–consume–ack workflows for success, transient failure, and permanent failure cases. Idempotent publish is verified by issuing duplicate requests with the same idempotency key and asserting a single stream entry and a stable returned ID. Idempotent processing is validated by forcing re-delivery and asserting single side effects in the handler. DLQ routing is exercised by failing a handler repeatedly until the delivery count reaches the configured limit and asserting the presence and content of the DLQ entry. Fault injection simulates timeouts and connection resets to validate backoff and circuit breaker behavior. Serialization tests assert envelope field name and type stability across versions.

# 11. Migration and Rollout

The adapter is introduced behind a feature flag. Services initially run with in-process channels enabled and the Redis-backed bus disabled. During rollout, producers enable publishing to Redis while retaining legacy paths as a fallback. Consumers deploy with the feature flag disabled and are enabled per topic after verifying metrics and health checks. Rollback disables the feature flag and drains consumers to a quiescent state before resuming legacy transports.

# 12. Interface Specification

The interface is language-neutral. The `publish(topic, envelope, options) -> StreamId` operation publishes an envelope idempotently and returns the assigned stream identifier after schema validation. The `subscribe(topic, group, handler, options) -> Subscription` operation starts a consumer loop in the specified group; the handler receives the decoded envelope and a cancellation token and returns success or error. The `ack(topic, group, ids)` operation acknowledges one or more processed message identifiers within the group. The `nack(topic, group, id, reason)` operation applies the retry policy to a failed message; on exhaustion, it routes the message to the DLQ and acknowledges the original entry. Options include batch size, block timeout, minimum idle time, maximum delivery attempts, idempotency TTLs, and schema bindings.

# 13. Operational Procedures

Operational readiness requires initial stream and group creation, verification of health checks, and calibration of retention and idle thresholds. On-call runbooks include diagnosing lag using `XINFO GROUPS`, inspecting pending entries with `XPENDING` for stalled consumers, and auditing DLQ entries to classify failure modes. Capacity planning monitors stream memory growth and adjusts retention and payload size limits. Backups and recovery rely on Redis persistence (AOF or RDB) configured to meet recovery point objectives.

# 14. Rationale for Key Decisions

Idempotent publish uses a Lua script to provide strong atomicity without external coordination. Idempotent processing relies on a short-lived processing key to avoid rework while allowing retries after failure. `XAUTOCLAIM` is preferred over `XCLAIM` because it claims and returns entries while advancing the start cursor, reducing coordination overhead. DLQs are modeled as separate streams to preserve ordering and retention policies independent of the primary topic. Metrics derive from Redis-native introspection to avoid per-message side channels and minimize overhead while providing actionable visibility.

# 15. Interoperability With Kafka and RabbitMQ

The adapter can work with Kafka and RabbitMQ through polymorphic backends and bridging connectors. Polymorphic backends allow services to target a common Bus interface while selecting a concrete transport at deployment time; bridging connectors mirror topics across systems to support heterogeneous deployments while preserving at-least-once semantics.

## 15.1. Polymorphic Backends

A stable Bus interface permits multiple adapters that implement identical methods for publish, subscribe, acknowledge, and negative-acknowledge. Runtime configuration selects the adapter globally, per environment, or per topic. Application services (bees) invoke the Bus interface without awareness of the underlying broker, while the control plane (hive) manages adapter selection, topic provisioning, and schema bindings. This mode is appropriate when a domain can be homed on one broker at a time and different environments or topics prefer different transports.

## 15.2. Bridging Connectors

Bridging connectors are stateless workers that consume from a source broker and publish to a sink broker. A Redis→Kafka bridge joins a Redis consumer group, reads stream entries, and produces records to a Kafka topic. A Kafka→Redis bridge consumes from a Kafka consumer group and publishes to a Redis stream. RabbitMQ bridges analogously consume from queues bound to exchanges and republish to Redis streams or, in the opposite direction, consume streams and publish to exchanges. Bridges implement at-least-once replication, deduplication, loop prevention, and backpressure translation.

Deduplication relies on idempotency metadata propagated in headers, such as a deterministic idempotency key, the source system identifier, and the source position (Redis stream ID, Kafka topic/partition/offset, or RabbitMQ delivery tag). The sink records a short-lived "seen" key per message to suppress replays. Loop prevention marks messages with a source-system header and suppresses republishing messages that originated from the destination system, preventing cycles in bi-directional configurations. Backpressure is translated from sink to source using native flow control: Kafka uses controlled poll cadence and limits on in-flight records, RabbitMQ uses prefetch limits, and Redis uses block time and batch size.

## 15.3. Semantic Mappings and Caveats

Ordering is preserved only within mapped units. Kafka guarantees ordering per partition, RabbitMQ per queue, and Redis Streams per stream with possible reordering during stale entry reclamation. Bridges must choose a stable partitioning key (for example, a message key or correlation identifier) to map a Redis stream entry to a Kafka partition deterministically, and they must route RabbitMQ queue messages consistently into a stream. Acknowledgement semantics align by committing Kafka offsets or acknowledging RabbitMQ deliveries only after the sink write completes and by issuing `XACK` for Redis only after the sink write has succeeded, thereby preserving at-least-once end-to-end.

Dead-lettering is translated between systems. Kafka DLQs are modeled as dead-letter topics, RabbitMQ uses dead-letter exchanges and queues, and Redis uses per-topic DLQ streams. Bridges copy the original envelope, attempt counts, and reason codes into the sink’s DLQ mechanism. Delivery attempt visibility differs by broker: Redis exposes delivery counts via pending metadata, Kafka does not expose a delivery count, and RabbitMQ exposes a redelivered flag rather than a counter. Bridges therefore maintain attempt counts in headers to provide a consistent basis for retry policy decisions.

Idempotent publication differs across systems. Redis enforces idempotent publish via a Lua-guarded idempotency key and returns the assigned stream ID. Kafka provides idempotent producers within a producer session and partition but does not yield cross-system guarantees, and RabbitMQ requires application-level idempotency keys or broker plugins. Bridges rely on application-level idempotency keys propagated in headers to unify semantics across brokers.

# 16. Adapter Interaction Model

The adapter functions as a client-side library that services link into and as a set of operational processes managed by the platform. Bees interact with the adapter for all publish and consume operations. The hive configures, observes, and automates the adapter and any bridges. Platform operators provision and maintain the underlying brokers and execute operational procedures such as DLQ replay.

## 16.1. Bees (Application Services)

Bees invoke the Bus interface to publish domain events and subscribe to topics. They supply schema-validated payloads, receive cancellation tokens for cooperative shutdown, and depend on the adapter to enforce idempotency, retries, and DLQ routing. Bees do not interact directly with Redis, Kafka, or RabbitMQ; they are insulated from transport concerns by the adapter.

## 16.2. Hive (Control Plane and Orchestration)

The hive defines topic namespaces, retention policies, consumer group names, and schema bindings. It provisions adapter configuration, including connection parameters, retry and backoff policies, and feature flags. It operates health checks, inspects lag and DLQ rates, coordinates rollouts and rollbacks, and may publish orchestration events while avoiding high-volume production or consumption of application topics.

## 16.3. Bridges and Integrations

When heterogeneous brokers must interoperate, dedicated bridge processes consume from one system and publish into another using either the adapter or native client libraries. The hive deploys and configures these bridges, sets loop-prevention and deduplication policies, and monitors replication lag and DLQ handoffs. External systems integrate via Kafka or RabbitMQ protocols while internal services continue to use the Bus interface backed by Redis, decoupling internal SDKs from external broker choices.

## 16.4. Platform Operations

Operators provision the brokers, configure authentication and TLS, set persistence modes (AOF or RDB for Redis, ISR and replication for Kafka, and mirroring and DLX for RabbitMQ), and tune resource limits. They respond to alerts on lag, DLQ rates, and error budgets and execute DLQ replay workflows using the adapter’s administrative utilities.

## 16.5. Summary

Bees use the adapter directly for publish and consume. The hive governs configuration, orchestration, and observability. Bridges enable working with Kafka and RabbitMQ as alternative backends or as replicated peers. The design preserves at-least-once semantics across brokers while acknowledging unavoidable differences in ordering, acknowledgement, and idempotency models.
