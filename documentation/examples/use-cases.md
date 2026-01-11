# 4. Use Cases

Representative enterprise scenarios that demonstrate how to apply the SW4RM SDK to real problems. Each use case links to deeper architectural context and concrete patterns.

## 4.1. DevOps Automation and Infrastructure Orchestration

Automate multi-stage deployments with durable state, approvals, and auditability. Agents coordinate pipeline execution, request approvals, and perform Git- and Kubernetes-backed rollouts while preserving at-least-once semantics and full traceability.


- Key capabilities: persistent pipeline state, approval workflows with escalation, Git worktree binding, immutable audit logs.
- Architectural reference: see [DevOps Automation and Infrastructure Orchestration](../index.md).

## 4.2. Data Processing and ETL Pipeline Management

Build resilient streaming and batch pipelines with checkpointing, schema evolution, and quality monitoring. Agents process records with idempotent handlers, route dead letters, and maintain data lineage for governance.


- Key capabilities: checkpoint-based recovery, schema evolution handling, real-time quality checks, dead letter queues.
- Architectural reference: see [Data Processing and ETL Pipeline Management](../index.md).

## 4.3. Where to Start


- Run example agents locally: see [Running the Examples](./index.md) and the `examples/` folder.
- Map requirements to primitives: approvals (HITL), repository context (Worktree), durable delivery (Router/ACK), and observability (audit/tracing).
- For production rollouts, review [Deployment Patterns](./deployment.md).
