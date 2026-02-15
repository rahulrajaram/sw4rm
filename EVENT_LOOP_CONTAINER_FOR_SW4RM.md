# Event-Loop Container for SW4RM Instances

## Purpose

Define an optional control-plane abstraction, `LoopContainer`, that orchestrates one SW4RM instance or a collection of SW4RM instances through explicit decision cycles (iterations), while preserving existing SW4RM scheduler semantics.

This model is additive: it does not replace `SchedulerService` or core SW4RM task/agent lifecycle behavior.

## Key Semantics

1. `iteration` means one orchestrator decision/execution cycle.
2. Iteration increments only on explicit container tick/decision boundaries.
3. Iteration does not increment on scheduler ticks, heartbeats, partial logs, or streaming chunks.
4. `LoopContainer` enforces policy limits like `max_iterations`, runtime, and idle timeout.

---

## Scenario A: Single SW4RM Instance in One Loop Container

### Topology

```text
+--------------------------------------------------------------+
|                    LoopContainer (LC-1)                     |
|  policy: max_iterations=10, max_runtime=2h, idle=15m        |
|  state : iteration=3, stop_reason=""                        |
|                                                              |
|  [TickContainer] --> decide next step --> dispatch task      |
+-------------------------------+------------------------------+
                                |
                                v
                    +---------------------------+
                    |   SW4RM Instance (S-1)    |
                    | +-----------------------+ |
                    | | SchedulerService      | |
                    | | WorkflowService       | |
                    | | Router/Registry       | |
                    | +-----------------------+ |
                    |      |           |        |
                    |    Agent A     Agent B    |
                    +---------------------------+
```

### Iteration Timeline

```text
t0  tick#1 -> run tranche I8A on S-1 -> complete
t1  tick#2 -> run tranche I8B on S-1 -> complete
t2  tick#3 -> run verification on S-1 -> complete
t3  stop_reason=completed
```

Operationally, this gives deterministic stop behavior and clean audit boundaries for each cycle.

---

## Scenario B: One Loop Container Orchestrating Multiple SW4RM Instances

### Topology

```text
+-------------------------------------------------------------------+
|                    LoopContainer (LC-Federated)                   |
| policy: max_iterations=0(unlimited), max_runtime=6h               |
| role: meta-orchestrator across members                            |
+------------------------+-------------------------+-----------------+
                         |                         |
                         v                         v
              +-------------------+      +-------------------+
              | SW4RM Instance S-A|      | SW4RM Instance S-B|
              | Scheduler/Workflow|      | Scheduler/Workflow|
              | Agents A1..A3     |      | Agents B1..B4     |
              +-------------------+      +-------------------+
                         \                         /
                          \                       /
                           v                     v
                        +---------------------------+
                        | SW4RM Instance S-C        |
                        | Scheduler/Workflow         |
                        | Agents C1..C2             |
                        +---------------------------+
```

### Iteration Timeline

```text
tick#1 -> choose S-A for Plan I8A
tick#2 -> choose S-B for Plan I8B
tick#3 -> parallel fanout: S-A (tests), S-C (security checks)
tick#4 -> aggregate results, run final verification on S-B
tick#5 -> stop_reason=completed
```

This enables cross-instance planning without changing per-instance scheduler guarantees.

---

## Proposed Container API (Additive)

1. `CreateContainer`
2. `TickContainer`
3. `GetContainerState`
4. `PauseContainer`
5. `ResumeContainer`
6. `CancelContainer`

### Suggested State Fields

- `container_id`
- `members[]` (instance IDs/endpoints)
- `iteration_index`
- `max_iterations` (`0` means unlimited)
- `started_at`, `last_progress_at`, `stopped_at`
- `stop_reason` (`completed|max_iterations|max_runtime|idle_timeout|cancelled|error`)
- `next_actions[]` (planned dispatches)

---

## Policy and Termination

Container-level policies should be explicit and deterministic:

- `max_iterations`
- `max_runtime_ms`
- `idle_timeout_ms`
- `checkpoint_interval`

Termination precedence (recommended):

1. explicit cancellation
2. fatal error
3. completed objective
4. max runtime exceeded
5. idle timeout exceeded
6. max iterations reached

---

## Observability Requirements

For each iteration, emit structured events:

1. `iteration_started`
2. `iteration_dispatched`
3. `iteration_completed`
4. `iteration_stopped`

Each event should include:

- `correlation_id`
- `container_id`
- `iteration_index`
- affected `member_id`/task identifiers
- decision rationale and policy snapshot

This aligns with SW4RM observability requirements around state transition/event logging.

---

## Compatibility Notes

1. Keep `SchedulerService` unchanged as execution substrate.
2. Keep agent lifecycle semantics unchanged.
3. Make container orchestration optional; minimal deployments continue to work.
4. Implementations can phase in container orchestration first for single-instance mode, then federated mode.

---

## Why This Helps

1. Makes iteration semantics first-class and auditable.
2. Prevents control-plane ambiguity in multi-step orchestration.
3. Enables deterministic limits (`max_iterations`, runtime, idle) without overloading scheduler internals.
4. Supports both local and federated SW4RM execution models with a single control abstraction.
