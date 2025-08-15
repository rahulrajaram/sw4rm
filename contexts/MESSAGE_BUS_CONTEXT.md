4. Redis Streams Adapter Milestone Context

4.1. Scope
This milestone implements a production-ready Redis Streams adapter for the message bus layer with idempotent publish and consume semantics, per-topic dead-letter queues, and minimal backpressure metrics. It does not include RabbitMQ or Kafka adapters, which will follow later.

4.2. Objectives
The objective is to standardize message publication and consumption via a well-defined interface with delivery guarantees suitable for internal orchestration events. A secondary objective is to isolate Redis-specific concerns behind an adapter to support future pluggability.

4.3. Deliverables
Deliverables include a `Bus` trait, a Redis Streams adapter implementing `publish`, `subscribe`, `ack`, and `nack` with dead-lettering; idempotency keys to deduplicate re-deliveries; and metrics for queue depth, lag, and processing latency. Configuration supports connection URIs, TLS options, and authentication.

4.4. Architecture and Interfaces
The adapter uses XADD with explicit IDs for idempotency and XREADGROUP for consumer groups. Acknowledgements use XACK; negative acknowledgements send messages to a DLQ stream with reason codes. The adapter enforces a maximum delivery attempt count before dead-lettering. Messages carry typed envelopes with headers and a JSON payload validated against registered schemas. Consumers expose a cooperative cancellation token for clean shutdown.

4.5. Data Model
Messages include an `id`, `topic`, `headers` (content type, schema version, correlation id), and `payload`. DLQ entries include the original message, attempt count, and reason. Topics follow a hive-scoped naming convention to isolate environments.

4.6. Edge Cases and Failure Modes
The adapter must detect duplicate deliveries and suppress reprocessing by consulting the idempotency store. Network partitions trigger exponential backoff and circuit breaking. Oversized payloads are rejected with actionable errors. Schema version mismatches route to DLQ with a specific reason code.

4.7. Testing Strategy
Integration tests run against an ephemeral Redis container or a mock, validating publish/consume/ack/nack flows, idempotency under re-delivery, DLQ routing, and backpressure metrics. Property tests fuzz headers and payload sizes. Fault injection tests simulate timeouts and network errors. Serialization tests ensure consistent envelope encoding and decoding.

4.8. Non-Goals
This milestone does not commit to exactly-once processing, nor does it implement cross-region replication or transactional outboxes.

4.9. Dependencies
No hard dependencies beyond configuration and logging. Optional: OpenTelemetry for spans around bus operations.

4.10. Migration and Rollout
The bus adapter is introduced behind a feature flag. Existing direct in-process channels continue to function until consumers migrate to the bus interface.

4.11. Operational Considerations
Metrics expose stream lengths, consumer lag, and DLQ rates. Alerting thresholds are configurable. Health checks validate connectivity and basic XADD/XREAD operations at startup.


4.12. Action Items (Next Steps)

- [ ] Implement idempotent publish via Lua (SET NX → XADD → SET; TTL configurable); store stream ID in idem key.
- [ ] Implement processing idempotency with `SET NX` proc keys (PX TTL); `XACK` on success; delete proc key on failure.
- [ ] Add `XAUTOCLAIM` reclaim path with backoff using min-idle windows; ensure idempotent group creation.
- [ ] Implement DLQ routing with reason codes and context; acknowledge original after DLQ write.
- [ ] Validate envelopes against per-topic JSON Schemas; finalize header fields (`ct`, `sv`, `cid`, `ccid`, `ts`, `idem`, `attempt`).
- [ ] Expose minimal metrics (depth via `XLEN`, lag/pending via `XINFO`/`XPENDING`) and health commands in CLI.
- [ ] Add integration tests with ephemeral Redis or mock: publish/consume/ack/nack, idempotency, DLQ, and fault injection.
- [ ] Document configuration (`BEE_REDIS_URL`, `BEE_BUS_ENV`) and operational runbooks (lag diagnosis, DLQ replay).
