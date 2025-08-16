6. Telemetry and Metrics Milestone Context

6.1. Scope
This milestone integrates OpenTelemetry tracing and metrics across LLM calls, tool executions, scheduler decisions, and message bus operations. It provides a minimal Grafana dashboard definition for latency, error rates, token usage, and queue depth. It excludes log shipping beyond the existing tracing sink.

6.2. Objectives
The objective is to provide end-to-end visibility into performance and reliability, enabling rapid incident diagnosis and capacity planning. A secondary objective is to standardize semantic conventions for spans and metrics.

6.3. Deliverables
Deliverables include tracer initialization, span instrumentation in critical paths, counters and histograms for request counts, latencies, and token usage, exemplars linking metrics to representative traces, and a Grafana JSON import for a basic dashboard.

6.4. Architecture and Interfaces
Tracing initializes from configuration with exporters for stdout or OTLP. In the Bee/Hive implementation, initialization code resides under `bee/src/telemetry` and is invoked from `bee/src/main.rs` during process startup. Spans wrap LLM requests, tool invocations, scheduler enqueue/dequeue/preempt decisions, and bus publish/consume operations. Metrics register with a process-wide registry and expose Prometheus via an HTTP endpoint. Semantic attributes include provider name, model, hive, lane, task id, and error category.

6.5. Data Model
Spans and metrics use consistent attribute keys and units. Token usage is measured in integer tokens and cost in decimal cents. Latency histograms use milliseconds with sensible buckets.

6.6. Edge Cases and Failure Modes
Exporter failures must not crash the process. If the metrics endpoint fails to bind, the system logs a warning and continues. High-cardinality labels are avoided by hashing large identifiers. In Bee, OTLP exporter initialization failure results in fmt logging only; metrics listener bind failure disables `/metrics` without aborting startup.

6.7. Testing Strategy
Tests validate that spans are created and closed, attributes are set, and metrics counters change under simulated workloads. An integration test spins up the metrics endpoint and scrapes it to verify expected series and labels. Fault injection tests simulate exporter timeouts and confirm graceful degradation.

6.8. Non-Goals
This milestone does not implement distributed tracing across external systems beyond emitted spans.

6.9. Dependencies
Optional dependency on the message bus and LLM adapters to generate realistic spans and metrics during tests.

6.10. Migration and Rollout
Telemetry is enabled by default with safe exporters. Configuration allows disabling or switching exporters without code changes. For Bee, the following environment variables govern behavior: `BEE_OTEL_EXPORTER` (`none`, `stdout`, or `otlp`), `OTEL_EXPORTER_OTLP_ENDPOINT` (for OTLP gRPC), `BEE_OTEL_SAMPLING` (ratio sampler), and `BEE_METRICS_ADDR` (Prometheus listener address).

6.11. Operational Considerations
Dashboards should be versioned and included in release artifacts. Sampling rates are configurable to balance cost and visibility. The Bee dashboard JSON is versioned at `docs/dashboards/bee_telemetry.json` and expects Prometheus series such as `bee_requests_total`, `bee_errors_total`, `bee_request_duration_ms_bucket`, and `bee_task_duration_ms_bucket`.


6.12. Bee/Hive Implementation Details
Bee integrates a telemetry module comprising `config.rs`, `init.rs`, and `metrics.rs` under `bee/src/telemetry`. The process installs a `tracing_subscriber::fmt` layer unconditionally. When `BEE_OTEL_EXPORTER=otlp` is present, an OTLP tracer is installed using `opentelemetry_otlp` with a `ParentBased(TraceIdRatioBased)` sampler. There is no dedicated stdout exporter; `stdout` selection results in fmt logging only. The Prometheus exporter uses `metrics-exporter-prometheus` with the `http-listener` feature to expose `/metrics` on `BEE_METRICS_ADDR`.

6.13. Action Items (Next Steps)

- [ ] Implement `bee/src/telemetry/{config,init,metrics}.rs` and wire initialization in `bee/src/main.rs`.
- [ ] Support `BEE_OTEL_EXPORTER` (`none|stdout|otlp`), `OTEL_EXPORTER_OTLP_ENDPOINT`, `BEE_OTEL_SAMPLING`, and `BEE_METRICS_ADDR`.
- [ ] Add spans for LLM requests, tool executions, scheduler enqueue/dequeue/preempt, and bus publish/consume with standard attributes.
- [ ] Expose Prometheus `/metrics` endpoint; register counters/histograms; avoid high-cardinality labels by hashing large IDs.
- [ ] Provide `docs/dashboards/bee_telemetry.json` and a short operator guide to enable exporters and scrape metrics.
- [ ] Add tests: initialization without exporters, metrics endpoint bind failure handling, and basic counter/histogram emission.

6.14. Documentation Navigation Constraint

- Do not modify `mkdocs.yml` as part of this milestone. Navigation or site structure changes are handled separately; documentation updates should avoid touching `mkdocs.yml`.
