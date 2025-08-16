3. Scheduler Lanes and Preemption Milestone Context

3.1. Scope
This milestone introduces scheduler lanes representing priority classes with explicit preemption and resume semantics. It provides CLI and shell commands to submit tasks into lanes, preempt running tasks by priority or id, and resume preempted tasks. It does not introduce distributed scheduling across multiple hives or fair-share algorithms beyond strict priority and aging.

3.2. Objectives
The objective is to guarantee that high-priority work can displace lower-priority tasks while preserving the ability to resume preempted tasks without loss. A secondary objective is to provide transparent operator controls via Bee shell slash commands and consistent telemetry of scheduling decisions.

3.3. Deliverables
Deliverables include lane configuration with names and numeric priorities, a preemption policy module, persistent task state transitions, and CLI and shell commands `/submit`, `/preempt`, `/bind`, and `/switch`. It also includes unit and integration tests that drive preemption scenarios and assert fairness within the same lane via aging.

3.4. Architecture and Interfaces
The scheduler introduces a `Lane` abstraction and a `Policy` module implementing strict priority with optional aging. Tasks carry lane and priority metadata. The scheduler maintains separate run queues per lane and a preemption monitor that can signal running workers to checkpoint and yield. The CLI forwards commands to the scheduler API with idempotency keys. The shell exposes the commands as slash verbs with contextual help and argument completion.

3.5. Data Model
Tasks have identifiers, lane, base priority, effective priority, state (queued, running, preempted, completed, failed), and timestamps. Preemption decisions are recorded as events with reasons, previous state, and next state. Checkpoints store serialized task-specific progress in a blob store for resume.

3.6. Edge Cases and Failure Modes
Preemption must avoid starvation by aging queued tasks within each lane. If a worker fails to checkpoint within a deadline, the scheduler marks the task as failed with a retry policy. Dead-letter tasks on repeated failures move to a quarantine lane for operator review. Race conditions between simultaneous preemptions are serialized by the scheduler’s control loop.

3.7. Testing Strategy
Unit tests cover queue ordering, aging logic, and state transitions. Integration tests simulate multiple lanes with synthetic workloads to assert preemption, resume correctness, and throughput under load. Shell command tests validate argument parsing, help text, and API calls. Property tests fuzz sequences of submit, preempt, and resume to ensure invariants: no duplicate running tasks, monotonic state transitions, and bounded starvation.

3.8. Non-Goals
This milestone does not implement multi-tenant quotas, resource-aware scheduling, or distributed consensus among schedulers.

3.9. Dependencies
Depends on existing scheduler client plumbing and event telemetry. No dependency on message bus adapters for core logic.

3.10. Migration and Rollout
Lane configuration ships with sensible defaults and is editable via a config file. Rollout introduces the new commands behind a feature flag, then enables by default after passing soak tests.

3.11. Operational Considerations
Operators can inspect lane depths and preemption rates via metrics. Alerts trigger on repeated failed resumes or excessive preemption churn.


3.12. Prioritized Action Items (Decreasing Priority)

1) Lane configuration and defaults: Define lane names, numeric priorities, feature flags; load from configuration with validation.

2) Core queues and task state: Implement per-lane run queues and a persistent task state machine (queued → running → preempted → completed/failed) with timestamps.

3) Preemption policy: Enforce strict priority with deterministic tie-breakers; serialize concurrent preemptions via a control loop.

4) Preemption monitor: Add worker checkpoint handshake with deadlines, fail on timeout, and idempotent preempt-by-id/above-priority operations.

5) Resume flow: Implement resume-from-checkpoint with validation, idempotency key deduplication, and fallbacks when checkpoints are missing.

6) Aging logic: Add within-lane aging to prevent starvation; cap effective priority and decay on run.

7) Shell controls: Expose `/submit`, `/preempt`, `/bind`, `/switch` with contextual help and argument parsing; route to scheduler API.

8) Telemetry: Emit lane depths, preemption events, resume success/failure, checkpoint latency, and churn rates; trace scheduling decisions.

9) Failure policies: Quarantine lane for repeated failed resumes; clear retry limits and operator-visible reasons.

10) Unit tests: Queue ordering, aging, state transitions, preemption serialization, checkpoint deadlines, and idempotency.

11) Integration tests: Multi-lane workloads exercising preempt/resume correctness and throughput under load.

12) Operator UX: Autocomplete for lanes/task IDs, precise error surfacing, and readable `/help` with examples.

13) Rollout: Feature-flag the scheduler lanes, ship sane defaults, forward-only migration for config/state.

14) Alerts and SLOs: Alerts on repeated failed resumes, excessive churn, or stalled checkpoints; target preempt-to-yield latency.

15) Documentation: Operational guide for preempt/resume, quarantine handling, configuration examples, and troubleshooting.

3.13. Current Progress and Agent Context

The Bee CLI already provides non-interactive scheduler subcommands for submitting tasks, requesting preemption, graceful shutdown, and inspecting or purging activity. These exist under `bee scheduler` and operate against the configured Scheduler endpoint with idempotency where applicable.

Interactive shell slash verbs for scheduler control (`/submit`, `/preempt`, `/bind`, `/switch`) are wired in the Bee shell REPL. The session maintains a default lane binding, and the effective submission scope is resolved via precedence: explicit `scope`, explicit `lane` (alias), then the session's bound lane, falling back to `default`. A pure helper implements this precedence and is unit-tested. The shell surfaces precise usage diagnostics and reuses the same scheduler client API as the non-interactive subcommands. The TUI implementation is owned by a separate agent and will follow the same semantics for parity.

The architecture and invariants described in this context remain the source of truth. The implementation proceeds incrementally: first by exposing consistent CLI controls and deterministic argument handling, then by layering lane-aware scheduling semantics and persistent state transitions with preemption and resume guarantees.

3.14. Immediate Next Steps

- [ ] Define lane configuration and defaults; load/validate from config behind a feature flag.
- [ ] Implement per-lane run queues and persistent task state machine (queued → running → preempted → completed/failed).
- [ ] Add preemption monitor with checkpoint handshake and deadlines; implement resume-from-checkpoint with idempotency.
- [x] Wire shell REPL verbs `/submit`, `/preempt`, `/bind`, `/switch` with contextual help and argument precedence (supports `lane=` alias); unit tests in place for precedence helper.
- [ ] TUI parity for slash verbs (owned by separate agent); ensure help and precedence mirror the REPL.
