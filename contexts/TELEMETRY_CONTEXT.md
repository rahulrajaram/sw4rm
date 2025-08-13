6. Telemetry and Metrics Milestone Context

6.1. Scope
This milestone integrates OpenTelemetry tracing and metrics across LLM calls, tool executions, scheduler decisions, and message bus operations. It provides a minimal Grafana dashboard definition for latency, error rates, token usage, and queue depth. It excludes log shipping beyond the existing tracing sink.

6.2. Objectives
The objective is to provide end-to-end visibility into performance and reliability, enabling rapid incident diagnosis and capacity planning. A secondary objective is to standardize semantic conventions for spans and metrics.

6.3. Deliverables
Deliverables include tracer initialization, span instrumentation in critical paths, counters and histograms for request counts, latencies, and token usage, exemplars linking metrics to representative traces, and a Grafana JSON import for a basic dashboard.

6.4. Architecture and Interfaces
Tracing initializes from configuration with exporters for stdout or OTLP. Spans wrap LLM requests, tool invocations, scheduler enqueue/dequeue/preempt decisions, and bus publish/consume operations. Metrics register with a process-wide registry and expose Prometheus via an HTTP endpoint. Semantic attributes include provider name, model, hive, lane, task id, and error category.

6.5. Data Model
Spans and metrics use consistent attribute keys and units. Token usage is measured in integer tokens and cost in decimal cents. Latency histograms use milliseconds with sensible buckets.

6.6. Edge Cases and Failure Modes
Exporter failures must not crash the process. If the metrics endpoint fails to bind, the system logs a warning and continues. High-cardinality labels are avoided by hashing large identifiers.

6.7. Testing Strategy
Tests validate that spans are created and closed, attributes are set, and metrics counters change under simulated workloads. An integration test spins up the metrics endpoint and scrapes it to verify expected series and labels. Fault injection tests simulate exporter timeouts and confirm graceful degradation.

6.8. Non-Goals
This milestone does not implement distributed tracing across external systems beyond emitted spans.

6.9. Dependencies
Optional dependency on the message bus and LLM adapters to generate realistic spans and metrics during tests.

6.10. Migration and Rollout
Telemetry is enabled by default with safe exporters. Configuration allows disabling or switching exporters without code changes.

6.11. Operational Considerations
Dashboards should be versioned and included in release artifacts. Sampling rates are configurable to balance cost and visibility.

