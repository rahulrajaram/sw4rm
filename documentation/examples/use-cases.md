# 4. Use Cases

Representative enterprise scenarios that demonstrate how to apply the SW4RM SDK to real problems. Each use case links to deeper architectural context and concrete patterns.

Related resources: [Examples overview](./index.md) · [Deployment Patterns](./deployment.md)

## 4.1 DevOps Automation and Infrastructure Orchestration

Automate multi-stage deployments with durable state, approvals, and auditability. Agents coordinate pipeline execution, request approvals, and perform Git- and Kubernetes-backed rollouts while preserving at-least-once semantics and full traceability.

The core flow: a pipeline agent receives each stage as a router delivery, runs the deployment step, escalates a gate to HITL when approval is required, and only then acknowledges delivery — so a crash before acknowledgement redelivers the stage instead of losing it.

- Key capabilities: persistent pipeline state, approval workflows with escalation, Git worktree binding, immutable audit logs.
- Architectural reference: approvals and policies in the [HITL client](../clients/hitl.md), repository context in the [Worktree client](../clients/worktree.md), delivery semantics in [Acknowledgements](../protocol/acks.md).

## 4.2 Data Processing and ETL Pipeline Management

Build resilient streaming and batch pipelines with checkpointing, schema evolution, and quality monitoring. Agents process records with idempotent handlers, route dead letters, and maintain data lineage for governance.

The core flow: records arrive as at-least-once router deliveries, an idempotency token (or a persisted activity buffer) suppresses reprocessing of completed work, and records that exhaust retries are abandoned with a permanent-failure acknowledgement so the router can surface them for operator inspection.

- Key capabilities: checkpoint-based recovery, schema evolution handling, real-time quality checks, dead letter queues.
- Architectural reference: delivery and redelivery in the [Router client](../clients/router.md), deduplication in the [Activity buffer](../protocol/activity-buffer.md), operator-side DLQ rules in [Error Handling Patterns](../clients/error-handling.md).

## 4.3 Where to Start


- Run example agents locally: see [Running the Examples](./index.md) and `sdks/py_sdk/examples/` (equivalents in `sdks/js_sdk/`, `sdks/rust_sdk/`, `sdks/cl/`, `sdks/ex/`).
- Map requirements to primitives: approvals (HITL), repository context (Worktree), durable delivery (Router/ACK), and observability (audit/tracing).
- For production rollouts, review [Deployment Patterns](./deployment.md).
