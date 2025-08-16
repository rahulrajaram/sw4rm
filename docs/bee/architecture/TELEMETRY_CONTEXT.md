# Telemetry and Metrics Milestone Context (Bee)

This file mirrors and tracks the working context for the Bee telemetry milestone. Keep this document up to date alongside code changes; it is the source of truth for scope, objectives, deliverables, and operational guidance. It is derived from the repo-level `contexts/TELEMETRY_CONTEXT.md` and tailored to Bee.

## 6.1. Scope
Integrates OpenTelemetry tracing and Prometheus metrics across LLM calls (future), tool executions (future), scheduler decisions, router operations, and message bus (Redis Streams) interactions. Provides a minimal Grafana dashboard for latency, error rates, and operational gauges. Log shipping is out of scope beyond existing tracing sinks.

## 6.2. Objectives
Provide end-to-end visibility into performance and reliability, enabling rapid incident diagnosis and capacity planning. Standardize semantic conventions for spans and metrics.

## 6.3. Deliverables
- Tracer initialization with graceful fallback.
- Span instrumentation in critical paths.
- Counters and histograms for request counts, latencies, and selected gauges.
- Grafana JSON import for a basic dashboard.

## 6.4. Architecture and Interfaces
- Tracing initializes from configuration with exporters for fmt or OTLP.
- Initialization code resides under `bee/src/telemetry` and is invoked from `bee/src/main.rs`.
- Spans cover scheduler operations, router ping, and bus publish; router incoming events are counted. Future: LLM requests, tool invocations.
- Metrics register process-wide and expose Prometheus via HTTP.
- Semantic attributes include provider, model, hive, lane, task id, and error category (hashed if needed).

## 6.5. Data Model
- Consistent attribute keys and units.
- Token usage in integer tokens and cost in decimal cents (future).
- Latency histograms in milliseconds.

## 6.6. Edge Cases and Failure Modes
- Exporter failures must not crash the process.
- Metrics endpoint bind failure logs a warning; `/metrics` may be disabled.
- Avoid high-cardinality labels by hashing large identifiers.

## 6.7. Testing Strategy
- Validate that spans create/close and attributes are set.
- Metrics counters/histograms change under simulated workloads.
- Integration test for metrics endpoint bind behavior.
- Fault injection for exporter timeouts (future).

## 6.8. Non-Goals
Distributed tracing across external systems beyond emitted spans (for now).

## 6.9. Dependencies
Optional dependency on message bus and LLM adapters for realistic spans/metrics in tests.

## 6.10. Migration and Rollout
Telemetry enabled by default with safe exporters. Configuration allows disabling/switching exporters without code changes.

Environment variables:
- `BEE_OTEL_EXPORTER` (`none|stdout|otlp`)
- `OTEL_EXPORTER_OTLP_ENDPOINT` (for OTLP gRPC)
- `BEE_OTEL_SAMPLING` (ratio sampler)
- `BEE_METRICS_ADDR` (Prometheus listener address)

## 6.11. Operational Considerations
- Dashboards are versioned under `docs/dashboards/bee_telemetry.json`.
- Sampling rates are configurable to balance cost vs. visibility.
- Expected Prometheus series: `bee_requests_total`, `bee_errors_total`, `bee_request_duration_ms_bucket`, `bee_task_duration_ms_bucket`, `bee_scheduler_queue_depth`, `bee_tasks_active`.

## 6.12. Bee Implementation Details
- Telemetry module: `bee/src/telemetry/{config,init,metrics}.rs`.
- `tracing_subscriber::fmt` installed unconditionally.
- When `BEE_OTEL_EXPORTER=otlp`, install OTLP tracer via `opentelemetry-otlp` with `ParentBased(TraceIdRatioBased)` sampler.
- Prometheus exporter uses `metrics-exporter-prometheus` with `http-listener` to expose `/metrics` on `BEE_METRICS_ADDR`.
- Implemented spans/metrics:
  - Scheduler: submit, preempt, shutdown, activity, purge.
  - Router: ping span + metrics; incoming stream counts.
  - Bus (Redis Streams): publish span + metrics; ping metrics.

## 6.13. Action Items (Next Steps)
- Extend spans/metrics to registry and negotiation clients.
- Add LLM/tool instrumentation including token usage and cost metrics.
- Attach exemplars to metrics using active `trace_id`.
- Optional: dynamic label handling with safe hashing for hive/lane/task.

