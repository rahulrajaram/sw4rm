# SW4-003: Observability Extension

**Status:** Draft
**Version:** 0.1.0
**Date:** 2026-01-10
**Extends:** Core Spec §4 (Architecture - Observability Sink)

## Abstract

This extension defines standard observability interfaces for SW4RM implementations, including OpenTelemetry integration, Prometheus metrics, and health check endpoints. Implementations conforming to this extension provide production-grade monitoring capabilities.

## Motivation

The core specification mentions an "Observability Sink" but does not define:

- Standard metric names and labels
- Tracing span conventions
- Health check interfaces
- Log correlation requirements

Without standardization, operators cannot build unified dashboards or alerts across SW4RM deployments.

## 1. Metrics

### 1.1. Metric Naming Convention

All SW4RM metrics MUST use the prefix `sw4rm_` and follow Prometheus naming conventions:

- Snake_case names
- Unit suffix where applicable (`_total`, `_seconds`, `_bytes`)
- Labels for dimensions (service, method, status, agent_id)

### 1.2. Required Metrics

Implementations MUST expose these metrics:

#### RPC Metrics

```
sw4rm_rpc_requests_total{service, method, status}
  Counter: Total RPC requests by service, method, and gRPC status

sw4rm_rpc_duration_seconds{service, method}
  Histogram: RPC latency distribution
  Buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30]

sw4rm_rpc_in_flight{service}
  Gauge: Currently executing RPCs per service
```

#### Agent Metrics

```
sw4rm_agents_registered_total
  Gauge: Number of currently registered agents

sw4rm_agent_state{agent_id, state}
  Gauge: Agent state (1 = current state, 0 = other states)

sw4rm_agent_heartbeat_age_seconds{agent_id}
  Gauge: Seconds since last heartbeat
```

#### Scheduler Metrics

```
sw4rm_tasks_queued_total{priority}
  Gauge: Tasks currently queued by priority

sw4rm_tasks_completed_total{status}
  Counter: Completed tasks by status (success, failed, preempted)

sw4rm_preemption_total{type}
  Counter: Preemptions by type (cooperative, forced)
```

#### Negotiation Metrics

```
sw4rm_negotiations_active_total
  Gauge: Currently active negotiation rooms

sw4rm_negotiation_decisions_total{outcome}
  Counter: Decisions by outcome (approved, revision_requested, escalated)

sw4rm_negotiation_quorum_failures_total
  Counter: Negotiations that failed to reach quorum (see SW4-001)

sw4rm_negotiation_vote_latency_seconds
  Histogram: Time from proposal to final vote
```

#### Handoff Metrics

```
sw4rm_handoffs_total{status}
  Counter: Handoffs by status (accepted, rejected, timeout)

sw4rm_handoff_duration_seconds
  Histogram: Time from request to completion
```

### 1.3. Metric Labels

Standard labels that SHOULD be applied consistently:

| Label | Description | Example Values |
|-------|-------------|----------------|
| `service` | gRPC service name | `RegistryService`, `SchedulerService` |
| `method` | RPC method name | `RegisterAgent`, `SubmitTask` |
| `status` | gRPC status code | `OK`, `DEADLINE_EXCEEDED`, `INTERNAL` |
| `agent_id` | Agent identifier | `agent-001` |
| `priority` | Task priority | `-19`, `0`, `20` |
| `outcome` | Decision outcome | `approved`, `rejected` |

## 2. Distributed Tracing

### 2.1. OpenTelemetry Integration

Implementations SHOULD support OpenTelemetry tracing with:

- Automatic span creation for all RPCs
- Context propagation via gRPC metadata
- Correlation with `correlation_id` from messages

### 2.2. Span Naming Convention

```
sw4rm.{service}.{method}
```

Examples:

- `sw4rm.registry.register_agent`
- `sw4rm.scheduler.submit_task`
- `sw4rm.negotiation_room.submit_proposal`

### 2.3. Required Span Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `sw4rm.correlation_id` | string | Message correlation ID |
| `sw4rm.agent_id` | string | Requesting agent ID |
| `sw4rm.task_id` | string | Task ID (if applicable) |
| `sw4rm.negotiation_room_id` | string | Room ID (if applicable) |
| `sw4rm.artifact_id` | string | Artifact ID (if applicable) |

### 2.4. Span Events

Implementations SHOULD add span events for significant state changes:

```
span.add_event("quorum_evaluated", {
    "votes_received": 3,
    "votes_expected": 5,
    "quorum_met": true
})

span.add_event("decision_rendered", {
    "outcome": "approved",
    "aggregated_score": 8.5
})
```

## 3. Health Checks

### 3.1. Health Check Endpoint

Implementations MUST expose a health check endpoint:

**gRPC**: `grpc.health.v1.Health/Check` (standard gRPC health protocol)

**HTTP** (optional): `GET /health` returning:

```json
{
  "status": "healthy|degraded|unhealthy",
  "version": "0.6.0",
  "uptime_seconds": 3600,
  "checks": {
    "registry_connection": "healthy",
    "scheduler_connection": "healthy",
    "database_connection": "healthy"
  }
}
```

### 3.2. Readiness vs Liveness

Implementations SHOULD distinguish:

- **Liveness** (`/health/live`): Process is running
- **Readiness** (`/health/ready`): Process can accept traffic

### 3.3. Component Health Checks

Each SW4RM component SHOULD check:

| Component | Health Checks |
|-----------|---------------|
| Registry | Database connectivity, schema version |
| Scheduler | Registry connectivity, queue health |
| Agent | Registry registration, heartbeat success |
| NegotiationRoom | Store connectivity, pending decisions |

## 4. Structured Logging

### 4.1. Log Format

Implementations SHOULD use structured logging (JSON) with:

```json
{
  "timestamp": "2026-01-10T12:00:00.000Z",
  "level": "info",
  "message": "Task completed",
  "service": "scheduler",
  "correlation_id": "abc-123",
  "trace_id": "def-456",
  "span_id": "ghi-789",
  "agent_id": "agent-001",
  "task_id": "task-100",
  "duration_ms": 1500
}
```

### 4.2. Required Log Fields

| Field | Description |
|-------|-------------|
| `timestamp` | ISO 8601 timestamp |
| `level` | Log level (debug, info, warn, error) |
| `message` | Human-readable message |
| `service` | Service name |
| `correlation_id` | Message correlation ID |

### 4.3. Log Correlation

Logs MUST include `correlation_id` when available to enable:

- Tracing request flow across services
- Correlating logs with distributed traces
- Debugging multi-agent interactions

## 5. Alerting Recommendations

### 5.1. Critical Alerts

Implementations SHOULD alert on:

| Condition | Severity | Description |
|-----------|----------|-------------|
| `sw4rm_agents_registered_total == 0` | Critical | No agents registered |
| `sw4rm_agent_heartbeat_age_seconds > 60` | Warning | Agent may be unhealthy |
| `sw4rm_rpc_requests_total{status="INTERNAL"} increase > 10/min` | Critical | Internal errors spike |
| `sw4rm_negotiation_quorum_failures_total increase > 5/hour` | Warning | Quorum problems |

### 5.2. SLI/SLO Recommendations

| SLI | Recommended SLO |
|-----|-----------------|
| RPC success rate | 99.9% |
| RPC p99 latency | < 1s (varies by operation) |
| Heartbeat freshness | < 30s |
| Negotiation quorum success | > 95% |

## 6. Implementation Requirements

### 6.1. MUST Requirements

Implementations MUST:

1. Expose gRPC health check endpoint
2. Include `correlation_id` in all logs
3. Expose basic RPC metrics (requests, duration)

### 6.2. SHOULD Requirements

Implementations SHOULD:

1. Support OpenTelemetry tracing export
2. Expose Prometheus-compatible metrics endpoint
3. Use structured JSON logging
4. Expose all metrics defined in §1.2

### 6.3. MAY Requirements

Implementations MAY:

1. Provide Grafana dashboard templates
2. Include alerting rule templates
3. Support custom metric labels

## 7. Compatibility

This extension is additive. Implementations not conforming to SW4-003:

- Will have limited observability
- Cannot participate in unified monitoring
- SHOULD document available observability interfaces

## 8. References

- Core Spec §4: Architecture (Observability Sink)
- OpenTelemetry Specification: https://opentelemetry.io/docs/specs/
- Prometheus Naming Conventions: https://prometheus.io/docs/practices/naming/
- gRPC Health Checking Protocol: https://github.com/grpc/grpc/blob/master/doc/health-checking.md

---

*This extension is part of the SW4RM protocol extension series.*
