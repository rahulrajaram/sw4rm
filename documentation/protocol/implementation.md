# Implementation coverage

SW4RM has three distinct surfaces: normative protocol requirements, SDK helpers,
and running services. A generated client does not imply that its server exists.
The [source-derived RPC inventory](../reference/release-contract.md) lists the
wire contract; this page describes implementation boundaries for the 0.7.0 target.

## Reference servers

| Service | Python reference implementation | Scope |
|---|---|---|
| Registry | `reference-services/hive/registry_service.py` | Agent registration, heartbeat, SQLite state |
| Router | `reference-services/hive/router_service.py` | Per-recipient queues, SQLite pending rows, consumer ACK and lease redelivery |
| Scheduler | `reference-services/hive/scheduler_service.py` | Task scheduling/preemption and persisted task/activity state; demo orchestration is separate |
| NegotiationRoom | `reference-services/coordination/negotiation_room_service.py` | SQLite/WAL proposal, vote, and decision storage and startup replay |
| Activity, Connector, Handoff, HITL, Logging, Negotiation, ReasoningProxy, SchedulerPolicy, Tool, Workflow, Worktree | No reference server | Wire contracts; some SDKs provide local helpers or examples |

The usual Docker Compose stack runs Registry, Router, Scheduler, and the A2A
gateway. NegotiationRoom is a separate service. JavaScript and Rust also contain
reference/demo servers; those do not inherit the Python router's durability
implementation. Use the Python reference router when testing the delivery
contract described in this release.

## SDK contract and runtime boundaries

All SDKs target the canonical root proto schema. Python, JavaScript, Rust, and
Elixir expose generated gRPC bindings; Common Lisp uses descriptor-derived
bindings and its native transport. Each SDK exposes all 57 canonical RPCs; see
the [SDK parity contract](../sdk-parity.md) for the complete interfaces and tests. The ACK API is exposed in each SDK, but transport availability and
platform support must be verified for the application being deployed.

| Capability | Meaning of parity | Evidence |
|---|---|---|
| Complete wire surface | Generated bindings expose the canonical services, messages, and enum values | Source-derived RPC inventory and per-SDK binding tests |
| Router delivery | Preserve int64 delivery sequence; acknowledge correct recipient; encode outcomes consistently | SDK router tests and reference router ACK tests |
| ACK lifecycle | Represent application ACK stages and delivery ACK separately; preserve the message attempt ID | Common proto, router ACK tests, and SDK lifecycle tests |
| Persistence | Explicit write/load failure; durable atomic snapshots on supported local backends | Per-SDK failure tests; Python process-kill scenarios |
| Idempotency | Preserve the three IDs and stable retry token; deduplicate according to each runtime’s documented boundary | Shared vectors and per-SDK retry/deduplication tests |
| Score aggregation | Keep named voting strategies and score summaries numerically consistent | Voting strategy tests and shared aggregation examples |
| Quorum | Expose quorum decisions independently from score weighting and critic authority | Negotiation and aggregation tests |

Complete wire surface, portable idempotency, score aggregation, and quorum
parity are defined with their full evidence in the
[SDK parity contract](../sdk-parity.md); this page records only the runtime
boundaries that differ when running against the reference stack.

Named voting strategies remain distinct from the shared score-summary function.
For example, an arithmetic-average strategy need not become confidence weighted.
Quorum is a rule for counting participating critics; it does not establish critic
independence, factual correctness, or authority to perform a deployment.

Persistence formats and local runtime APIs are language-specific. Filesystem
snapshot stores assume a single writer. Python/JS/Rust/Elixir/Lisp test results
must be reported separately; a passing Python crash test is not evidence for
another language. Lisp fsync support is explicitly platform dependent.

## Requirements that are not implemented guarantees

The specification includes security, scheduling, resource-control, HITL, and
operational requirements beyond the reference stack. In particular:

- The reference router is a single-process SQLite-backed service. It has no
  replicated consensus, high-availability failover, or arbitrary exactly-once
  side-effect guarantee.
- The reference routing profile broadcasts to known eligible queues except the
  producer. It does not implement general recipient addressing, durable offline
  actor activation, or per-recipient authorization.
- Consumer identity fields are not authentication. TLS, access policy,
  isolation, and deployment supervision require application/operator work.
- Application ACK stages do not release router delivery rows automatically.
- A2A gateway endpoints are an implemented subset, not certification against
  every operation or the latest A2A release.
- Extension drafts are proposals. Their presence does not add wire fields or
  SDK behavior. See [extension status](extensions/index.md).

## How coverage stays current

The offline release-contract check verifies every version carrier, packaged
Rust proto copies, and source-generated reference pages. SDK suites exercise
behavior, including shared vectors. Package checks import built artifacts rather
than relying on an editable source tree. Documentation CI runs for source and
schema changes as well as prose changes.

These gates make drift visible. They do not replace review of security or
product claims; new claims need a named implementation and a test demonstrating
the promised failure behavior. See [documentation maintenance](../documentation-contract.md).
