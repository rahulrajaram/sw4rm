# 1. Telemetry Architecture for Bee/Hive

The Bee binary integrates tracing and metrics to provide end‑to‑end observability for agent execution, RPC interactions, and scheduler coordination. Telemetry initialization lives in `bee/src/telemetry` and is invoked from `bee/src/main.rs` at process start. Metrics are exported over an embedded Prometheus endpoint, and traces can be exported via OTLP using OpenTelemetry.

## 1.1. Objectives

This design provides reliable, low‑overhead visibility into latency, error rates, and execution flow so that engineers can diagnose incidents and plan capacity. The telemetry subsystem must never prevent Bee from starting or continuing operation. All exporters are optional and default to safe local settings.

## 1.2. Scope

The scope includes process‑local tracing initialization, configurable trace exporting over OTLP, a Prometheus metrics listener, and conventions for spans and metrics emitted by Bee and hive‑specific components. Distributed trace propagation across external systems is explicitly out of scope for this iteration.

# 2. Initialization and Configuration

Telemetry initialization is performed by `telemetry::init_tracing_and_otel` which installs a `tracing` subscriber and, when configured, an OpenTelemetry tracer. Immediately after initialization the process attempts to start a Prometheus HTTP listener using `telemetry::start_metrics_endpoint`. Both steps are designed to degrade gracefully: failures are logged and execution proceeds.

Configuration is sourced from environment variables at process start. The following settings control behavior:

- `BEE_OTEL_EXPORTER`: selects the tracing exporter. Accepted values are `none` (disable OTEL), `stdout` (use only fmt logging), and `otlp` (enable OTLP exporter). Default is `stdout` semantics (fmt logging only).
- `OTEL_EXPORTER_OTLP_ENDPOINT`: specifies the OTLP gRPC endpoint (for example, `http://localhost:4317`). Used only when `BEE_OTEL_EXPORTER=otlp`.
- `BEE_OTEL_SAMPLING`: sets probabilistic sampling using a ratio in the inclusive range `[0.0,1.0]`. The value may be provided as `ratio:<float>` or a bare float (for example, `ratio:0.2` or `0.2`). Defaults to `1.0` (always on) for OTLP.
- `BEE_METRICS_ADDR`: sets the Prometheus listener socket address (for example, `127.0.0.1:9464`). Default is `127.0.0.1:9464`.

Environment values are read once during initialization; dynamic reconfiguration is not supported in this iteration.

# 3. Tracing

When `BEE_OTEL_EXPORTER=otlp` is set, Bee installs an OTLP tracer via `opentelemetry_otlp` using Tonic gRPC and a Tokio runtime. The tracer is configured with a `ParentBased(TraceIdRatioBased)` sampler using the configured ratio. The `service.name` resource attribute is set to `bee` to allow consistent service‑level segregation in backends.

The process always installs a `tracing_subscriber::fmt` layer for human‑readable logs. When OTLP is enabled, a `tracing_opentelemetry` layer is added to bridge `tracing` spans and events to the OTLP exporter. If exporter initialization fails, Bee logs a warning and continues with fmt logging only.

At this stage, tracing spans are emitted by code paths that already use the `tracing` crate. Additional span coverage for SW4RM SDK client calls and scheduler interactions is not yet implemented in this branch and will be added in subsequent commits. This document establishes the conventions those spans must follow:

## 3.1. Span Conventions

Spans should be named using the pattern `<component>.<operation>` (for example, `router.send`, `scheduler.submit`, `runtime.run`). Standard attributes should be applied consistently:

- `sw4rm.provider`: LLM or service provider name when applicable.
- `sw4rm.model`: model identifier or selection.
- `sw4rm.hive`: hive name bound to the Bee process.
- `sw4rm.lane`: lane identifier when routing decisions apply.
- `sw4rm.task_id`: logical task identifier when known.
- `sw4rm.error_category`: coarse error class for aggregation (for example, `timeout`, `invalid_argument`, `unavailable`).

Identifiers that can explode cardinality must be reduced using deterministic hashing before attaching as attributes.

## 3.2. Context Propagation

W3C TraceContext propagation for outgoing and incoming gRPC calls will use Tonic interceptors in the SDK. That interceptor is not present in this branch; cross‑process linkage is therefore absent. In‑process spans maintain correct nesting and timing relationships.

## 3.3. Implementation Files

Tracing initialization is implemented in `bee/src/telemetry/init.rs`. Configuration parsing is in `bee/src/telemetry/config.rs`. The Bee process wires initialization in `bee/src/main.rs` via `telemetry::init_tracing_and_otel`.

# 4. Metrics

Bee exposes Prometheus metrics via `metrics-exporter-prometheus` using an embedded HTTP listener bound to `BEE_METRICS_ADDR`. The exporter exposes a single path `/metrics` providing text exposition format. Listener startup failures are non‑fatal and generate a warning with the bind error.

The following metric taxonomy is defined for Bee. Not all series are emitted yet; instrumentation will be rolled out across critical paths in the SDK and runtime using the `metrics` crate.

## 4.1. Counters

Counters track event rates and error occurrences and must be strictly monotonic. Representative names include `bee_requests_total` (labeled by `component`, `operation`, `hive`, `lane`), and `bee_errors_total` (labeled by `component`, `operation`, `error_category`).

## 4.2. Histograms

Latency histograms use milliseconds as the unit, with buckets tuned for tail observability (for example, `[1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000]`). Representative names include `bee_request_duration_ms` and `bee_task_duration_ms`, labeled by `component`, `operation`, and task contextual labels where cardinality is controlled.

## 4.3. Gauges

Gauges represent instantaneous values such as scheduler queue depth or active tasks. Representative names include `bee_scheduler_queue_depth` and `bee_tasks_active`.

## 4.4. High‑Cardinality Management

Labels that may assume a large number of unique values (for example, `task_id`, `correlation_id`) must not be attached directly. Where business correlation is unavoidable, attach a fixed‑length hash (for example, SHA‑256 truncated) and present the original values in logs or payloads referenced by trace links.

# 5. Failure Modes and Degradation

Exporter initialization errors do not abort process startup. If OTLP exporter construction fails due to a misconfigured or unreachable endpoint, Bee logs a single warning and proceeds without an OTLP layer. If the Prometheus listener fails to bind to `BEE_METRICS_ADDR`, Bee logs a warning and continues without a metrics endpoint. Telemetry components must not panic on transient exporter failures.

# 6. Security and Performance Considerations

The metrics listener binds to loopback by default to avoid inadvertent exposure. Operators must set `BEE_METRICS_ADDR` explicitly when remote scrapers are required and ensure appropriate network policy. Sampling is enforced at the SDK tracer using a ratio sampler; lowering the ratio reduces exporter and backend load at the cost of observability for low‑frequency events. All metrics operations occur in‑process and are non‑blocking. The OTLP exporter uses a batch runtime to minimize impact on request latency.

# 7. Operational Procedures

To enable OTLP tracing during development, set `BEE_OTEL_EXPORTER=otlp` and `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317` before launching Bee. To expose metrics, set `BEE_METRICS_ADDR=127.0.0.1:9464` or another binding as appropriate. Verify the metrics endpoint locally with `curl http://127.0.0.1:9464/metrics` and confirm that the endpoint responds with Prometheus exposition text.

Prometheus can scrape Bee using a static job definition. A minimal scrape configuration resembles the following:

`job_name: bee` with `static_configs: targets: ['127.0.0.1:9464']`.

Grafana dashboards should query the exported series to visualize request rate, p50/p95/p99 latencies, error rate by category, and active task gauges. Dashboard JSON should be versioned under the repository so that releases provide a reproducible visualization baseline.

# 8. Future Work

The following enhancements are prioritized for subsequent milestones: add spans and metrics around SW4RM SDK clients (router, registry, scheduler, negotiation) with standardized attributes; introduce gRPC metadata interceptors to propagate W3C TraceContext across service boundaries; attach exemplars to latency histograms and error counters using the active span `trace_id` to enable trace‑linked metric analysis; and provide a Grafana dashboard JSON with curated panels for latency, error rate, token usage, scheduler queue depth, and active tasks.
