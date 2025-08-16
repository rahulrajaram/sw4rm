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

Current branch status: spans and metrics are implemented for key Bee operations. Specifically:

- Router: `router.ping` span + request/error/duration metrics; incoming events from `stream_incoming` are counted.
- Scheduler: `scheduler.submit`, `scheduler.preempt`, `scheduler.shutdown`, `scheduler.activity`, and `scheduler.purge` spans + request/error/duration metrics.
- Bus (Redis Streams): `bus.publish` span + request/error/duration metrics; `PING` health call emits request/error/duration metrics.

Further coverage can be added to additional SDK calls and runtime paths as needed. Conventions for any new spans should follow the guidance below:

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

The following metric taxonomy is defined for Bee. The series listed here are already emitted by the current implementation and align with the provided Grafana dashboard.

## 4.1. Counters

Counters track event rates and error occurrences and must be strictly monotonic.

- `bee_requests_total{component,operation}`: increments for each operation start/completion (e.g., `component="scheduler"`, `operation="submit"`).
- `bee_errors_total{error_category}`: increments on failures with a coarse `error_category` label (e.g., `scheduler_submit`, `router_ping`, `redis_publish`).

## 4.2. Histograms

Latency histograms use milliseconds as the unit. The current implementation records:

- `bee_request_duration_ms{component,operation}`
- `bee_task_duration_ms`

## 4.3. Gauges

Gauges represent instantaneous values such as scheduler queue depth or active tasks.

- `bee_scheduler_queue_depth{hive,lane}`
- `bee_tasks_active{hive,lane}`

## 4.4. High‑Cardinality Management

Labels that may assume a large number of unique values (for example, `task_id`, `correlation_id`) must not be attached directly. Where business correlation is unavoidable, attach a fixed‑length hash (for example, SHA‑256 truncated) and present the original values in logs or payloads referenced by trace links.

# 5. Failure Modes and Degradation

Exporter initialization errors do not abort process startup. If OTLP exporter construction fails due to a misconfigured or unreachable endpoint, Bee logs a single warning and proceeds without an OTLP layer. If the Prometheus listener fails to bind to `BEE_METRICS_ADDR`, Bee logs a warning and continues without a metrics endpoint. Telemetry components must not panic on transient exporter failures.

# 6. Security and Performance Considerations

The metrics listener binds to loopback by default to avoid inadvertent exposure. Operators must set `BEE_METRICS_ADDR` explicitly when remote scrapers are required and ensure appropriate network policy. Sampling is enforced at the SDK tracer using a ratio sampler; lowering the ratio reduces exporter and backend load at the cost of observability for low‑frequency events. All metrics operations occur in‑process and are non‑blocking. The OTLP exporter uses a batch runtime to minimize impact on request latency.

# 7. Operational Procedures

To enable OTLP tracing during development, set `BEE_OTEL_EXPORTER=otlp` and `OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317` before launching Bee. To expose metrics, set `BEE_METRICS_ADDR=127.0.0.1:9464` or another binding as appropriate. Verify the metrics endpoint locally with `curl http://127.0.0.1:9464/metrics` and confirm that the endpoint responds with Prometheus exposition text.

Prometheus can scrape Bee using a static job definition. A minimal scrape configuration:

scrape_configs:
  - job_name: "bee"
    static_configs:
      - targets: ["127.0.0.1:9464"]

Grafana dashboards should query the exported series to visualize request rate, p50/p95/p99 latencies, error rate by category, and active task gauges. A ready-to-import dashboard is versioned at `docs/dashboards/bee_telemetry.json` (select your Prometheus datasource when importing).

# 8. Future Work

- Registry and Negotiation client coverage (spans + metrics).
- LLM tool/adapter instrumentation including token usage and cost counters.
- gRPC interceptors for W3C TraceContext propagation across services.
- Metrics exemplars with active `trace_id` for trace-linked analysis.
