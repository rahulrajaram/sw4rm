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

