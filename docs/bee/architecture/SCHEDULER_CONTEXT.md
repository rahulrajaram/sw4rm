1. Scheduler Lanes and Preemption Architecture

1.1. Purpose and Scope

This document specifies the architecture for scheduler lanes and preemption within the Bee ecosystem. It defines the abstractions, state machines, and interfaces that guarantee strict-priority execution, bounded starvation through aging, and resumable preemption. The scope covers a single logical scheduler instance coordinating workers, the submission and control surfaces in the Bee CLI and shell, and the persistence and observability model required to make scheduling decisions transparent and reproducible.

1.2. Design Objectives

The architecture guarantees that a task submitted to a higher-priority lane can displace a running lower-priority task while preserving the displaced task’s ability to resume from a checkpoint. It enforces deterministic queueing and tie-breaking rules within and across lanes, provides idempotent operator controls, and records all relevant decisions and transitions for audit and replay. It avoids distributed consensus and focuses on single-scheduler correctness with clear operational semantics.

1.3. Core Concepts

The scheduler partitions work into lanes. A lane is a priority class with an associated numeric priority and aging policy. Tasks are admitted to a single lane and maintain both a base priority and an effective priority that may increase due to aging while queued. The scheduler maintains a run queue per lane and a global selection policy that always prefers higher effective priority. When a preemption condition holds, the scheduler triggers a cooperative checkpoint-and-yield handshake with the affected worker and records the transition. Tasks are immutable with respect to historical events; only their current state changes in a monotonic sequence.

1.4. Task State Machine

Each task follows a total order of states with monotonic transitions: queued, running, preempted, completed, and failed. The transition from running to preempted requires a successful checkpoint that serializes task-specific progress into a durable blob store. A failed checkpoint results in a failed state and optional retry according to a policy. A preempted task transitions to running when it resumes from its most recent checkpoint. State transitions carry timestamps and reasons. The scheduler serializes transitions per task to prevent concurrent updates.

1.5. Queueing and Selection Policy

Within each lane, tasks are ordered by effective priority and arrival time. Effective priority is computed from base priority plus aging increments capped at a lane-specific maximum. Across lanes, the scheduler always selects the task with the highest effective priority. Ties are broken deterministically by lane priority, then by arrival time and task identifier. The policy is deterministic under equal inputs. The scheduler evaluates preemption opportunities on admission of higher-priority work and periodically to implement aging.

1.6. Preemption Protocol

Preemption is cooperative. The scheduler sends a preemption signal to the worker executing the target task. The worker must checkpoint within a deadline and acknowledge the preemption. Upon acknowledgment, the scheduler marks the task preempted and returns system capacity to admit higher-priority work. If the deadline expires, the scheduler marks the task failed with a reason and applies a configured retry policy. The protocol is idempotent: repeated preemption requests for the same task in the same state have no effect beyond telemetry updates.

1.7. Resume Semantics

Resume operations restore a preempted task to running using the most recent checkpoint. The worker validates the checkpoint version and task metadata before restoration. If the checkpoint is missing or invalid, the scheduler escalates the task to failure according to policy and emits an event for operator review. Resumes are idempotent with respect to the same checkpoint and input parameters. The scheduler records resume attempts, outcomes, and latencies for observability and tuning.

1.8. Data Model

The scheduler persists tasks, events, checkpoints, and summaries. Tasks store identifiers, lane, base and effective priority, current state, and timestamps. Events record preemption decisions and state transitions with reasons and correlation identifiers. Checkpoints store content-addressed blobs with integrity metadata. Summaries compress recent event ranges for fast operator inspection and replay. The store maintains forward-only migrations and a schema version to ensure compatibility and deterministic upgrades.

1.9. Control Interfaces

Operators control the scheduler using two surfaces. The non-interactive Bee CLI exposes subcommands for submitting tasks, requesting preemption, initiating graceful shutdown, and querying or purging activity. The interactive Bee shell exposes slash commands that allow session-scoped defaults. The shell binds an agent identifier and an optional default lane to the session and resolves an effective scope for submissions. Scope resolution follows this precedence: explicit scope, explicit lane, then default lane, with a fallback to a literal default scope. All controls are idempotent and validate arguments deterministically.

1.10. Observability and Telemetry

The scheduler emits metrics and structured logs for lane depths, queue latencies, preemption and resume rates, checkpoint durations, and churn. Traces annotate scheduling decisions with input parameters and tie-breaker outcomes. The activity buffer stores an immutable record of append-only events with integrity checks. Operators can replay events to reconstruct a transcript of scheduling decisions and validate invariants. Alerts trigger on elevated failed-resume rates, prolonged preempt-to-yield latencies, and oscillatory preemption patterns.

1.11. Correctness Invariants

The implementation preserves a set of invariants. No task runs concurrently more than once. State transitions are monotonic and serialized per task. Queue ordering respects effective priority and deterministic tie-breaking. Preemption either yields a preempted state with a valid checkpoint or yields a failed state with a recorded reason. Aging prevents starvation within a lane by increasing effective priority over time. Scope resolution is deterministic and stable under repeated submissions.

1.12. Testing Strategy

The test plan covers unit, property, and integration tests. Unit tests verify queue ordering, aging arithmetic, state transitions, preemption serialization, and checkpoint deadlines. Property tests fuzz event sequences and JSON schemas for failure resistance and idempotency. Integration tests drive multiple synthetic lanes with workload generators that induce preemption and resume under load while asserting throughput and fairness. Shell and CLI tests validate argument parsing, precedence rules for scope resolution, and idempotent request formation. Migrations are tested for forward-only application and data retention.

1.13. Operational Procedures

Operators configure lane definitions, priorities, and aging policies in a versioned configuration file. Rollout enables the feature behind a flag, exercises soak tests, and promotes it to default after validation. Runbooks specify preempt-to-yield targets, quarantine handling for repeated failed resumes, and step-by-step recovery for corrupted checkpoints. The scheduler exposes health checks and integrity checks for early detection of persistence issues. Configuration changes are applied without violating invariants and are validated before activation.

1.14. Non-Goals and Future Work

The current architecture excludes distributed consensus, multi-tenant quotas, and resource-aware placement. Future work may integrate fair-share scheduling, resource constraint solvers, and multi-scheduler coordination protocols. The design intentionally decouples control surfaces and persistence from the scheduling core to facilitate incremental adoption of these features.
