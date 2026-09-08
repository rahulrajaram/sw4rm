# Service and wire contract reference

SW4RM's service surface is defined by the canonical protobuf files in
[source-derived schema reference](../reference/protobuf.md). This page explains which services are exercised by
Python reference servers and where the remaining wire contracts stand. The
source schemas and generated [RPC inventory](../reference/release-contract.md)
are authoritative for method names, request fields, response fields, and field
tags.

## Running Python reference services

The Python reference deployment currently implements four services with
persistent local state:

| Service | Canonical schema | Python implementation | Scope |
| --- | --- | --- | --- |
| Registry | [`registry.proto`](../reference/protobuf.md#registryproto) | `sdks/py_sdk/reference-services/hive/registry_service.py` | Agent registration, heartbeat, and deregistration backed by SQLite. |
| Router | [`router.proto`](../reference/protobuf.md#routerproto) | `sdks/py_sdk/reference-services/hive/router_service.py` | Recipient queues, pending delivery rows, consumer delivery ACK, and lease redelivery. |
| Scheduler | [`scheduler.proto`](../reference/protobuf.md#schedulerproto) | `sdks/py_sdk/reference-services/hive/scheduler_service.py` | Task submission, preemption, shutdown, and activity-buffer operations. |
| Negotiation room | [`negotiation_room.proto`](../reference/protobuf.md#negotiation_roomproto) | `sdks/py_sdk/reference-services/coordination/negotiation_room_service.py` | Proposal, vote, decision persistence, and startup replay. |

Registry, Router, and Scheduler use the hive state store; NegotiationRoom has
its own SQLite store. The
router's delivery ACK releases a pending delivery row only after the consumer
identifies itself and reports an accepted outcome. Application ACK stages are
separate and do not release router delivery rows.

The reference services are local single-process implementations. They do not
provide replicated consensus, multi-host failover, recipient authentication,
or an exactly-once external-effect transaction. See
[implementation coverage](implementation.md) for the boundary between shipped
services and protocol requirements.

## Contract-only services

The other canonical services have generated wire bindings and may have SDK
helpers or examples, but they do not have a Python reference server in this
release:

| Service | Canonical schema | Contract |
| --- | --- | --- |
| Activity | [`activity.proto`](../reference/protobuf.md#activityproto) | Artifact append and listing. |
| Connector | [`connector.proto`](../reference/protobuf.md#connectorproto) | Provider and tool descriptor registration. |
| Handoff | [`handoff.proto`](../reference/protobuf.md#handoffproto) | Handoff, cancellation, and completion operations. |
| HITL | [`hitl.proto`](../reference/protobuf.md#hitlproto) | Human decision invocation and response. |
| Logging | [`logging.proto`](../reference/protobuf.md#loggingproto) | Structured log ingestion. |
| Negotiation | [`negotiation.proto`](../reference/protobuf.md#negotiationproto) | Lower-level negotiation lifecycle operations. |
| Reasoning proxy | [`reasoning.proto`](../reference/protobuf.md#reasoningproto) | Parallelism, debate evaluation, and summarization. |
| Scheduler policy | [`scheduler_policy.proto`](../reference/protobuf.md#scheduler_policyproto) | Policy profiles, effective policy, evaluations, and HITL actions. |
| Tool | [`tool.proto`](../reference/protobuf.md#toolproto) | Unary, streaming, and cancellation tool calls. |
| Workflow | [`workflow.proto`](../reference/protobuf.md#workflowproto) | Workflow creation, execution, state lookup, and resume. |
| Worktree | [`worktree.proto`](../reference/protobuf.md#worktreeproto) | Bind, switch, approval, rejection, and status operations. |

A generated client or a schema entry in this table does not imply a running
server. Deployments may supply their own implementations subject to the
canonical wire contract.

## Canonical service inventory

Use the [generated RPC inventory](../reference/release-contract.md#rpc-inventory)
for all current method names and input/output types. The full
[schema reference](../reference/protobuf.md) includes exact fields and tags.
Both pages are regenerated and checked against source in CI.

For SDK client behavior, see the [router client reference](../clients/router.md),
[negotiation room guide](../clients/negotiation-room.md) (the lower-level
[negotiation client](../clients/negotiation.md) is separate), and the
language-specific SDK documentation. For the normative requirements, see the
[protocol specification](spec.md).

## Core service workflows

The following procedures explain how to use the contracts. Request examples
use Python generated protobuf bindings from this checkout; the same fields
are available in the other SDKs. They construct requests without contacting a
server. Configure a channel and use the linked client guide to execute them.

### Registry: register, report health, deregister

Register the agent's identity and capabilities before starting its work loop.
`RegisterAgentRequest.agent` contains the descriptor; registration returns
`accepted` and `reason`, not a registration token or heartbeat interval.

```python
from sw4rm.protos import common_pb2, registry_pb2

registration = registry_pb2.RegisterAgentRequest(
    agent=registry_pb2.AgentDescriptor(
        agent_id="log-analyzer-001",
        name="Log Analyzer",
        description="Parses logs and reports anomalies",
        capabilities=["log_parsing", "anomaly_detection"],
        modalities_supported=["application/json"],
        communication_class=common_pb2.STANDARD,
    )
)
heartbeat = registry_pb2.HeartbeatRequest(
    agent_id=registration.agent.agent_id,
    state=common_pb2.RUNNABLE,
    health={"queue_depth": "0", "status": "ready"},
)
```

Check registration acceptance, send `Heartbeat` on the deployment's configured
schedule, and inspect `ok`. On graceful exit, stop accepting work, finish or
checkpoint in-flight work, then call `DeregisterAgent` with a reason.
Capabilities describe what the agent can do; they are not authorization grants.
The core Registry has no `DiscoverAgents` or list RPC. Supply discovery through
your deployment's configured agent inventory or an explicitly supported
extension. See [Registry Client](../clients/registry.md).

### Router: publish, consume, acknowledge responsibility

1. Start `StreamIncoming` with the receiving `agent_id` and keep both `msg` and
   `seq` from each `StreamItem`.
2. Publish an Envelope inside `SendMessageRequest.msg`. Check `accepted` and
   `reason`; acceptance does not mean the handler completed.
3. Process the item, or durably transfer responsibility to an application inbox.
4. Call `AckDelivery` with the receiving agent ID, delivery sequence, and
   message ID. This releases that recipient's pending row.

```python
from sw4rm.protos import router_pb2

def delivery_receipt(agent_id, item):
    return router_pb2.DeliveryAckRequest(
        agent_id=agent_id,
        seq=item.seq,
        message_id=item.msg.message_id,
        outcome=router_pb2.DELIVERY_ACK_OUTCOME_DELIVERED,
    )
```

If the consumer crashes before the receipt is recorded, the item can return on
reconnect or lease expiry. Deduplicate logical work using the idempotency token
and a durable outcome record. `recorded=false` can mean the row is already gone;
it is not evidence that the business operation failed. A permanent-failure
receipt releases the row without retry, so preserve diagnostic evidence first.

The Python reference router broadcasts to eligible known queues other than the
producer; the Envelope has no general destination field. There is no
`GetMessageStatus` RPC or per-send `DeliveryOptions` object. Track application
ACKs and outcomes in your own lifecycle state. See [Router Client](../clients/router.md)
for runnable send/receive examples and [ACK Lifecycle](acks.md) for the two ACK layers.

### Scheduler: submit work and manage interruption

`SubmitTask` names the target `agent_id`, a `task_id`, priority, serialized
`params`, `content_type`, and resource `scope`. Lower priority numbers are more
urgent in the specified range, −19 through 20.

```python
import json
from sw4rm.protos import scheduler_pb2

task = scheduler_pb2.SubmitTaskRequest(
    agent_id="log-analyzer-001",
    task_id="analyze-batch-42",
    priority=0,
    params=json.dumps({"batch_id": "batch-42"}).encode("utf-8"),
    content_type="application/json",
    scope="logs/batch-42",
)
```

Check `accepted` before recording a successful submission. Request cooperative
interruption with `RequestPreemption(agent_id, task_id, reason)`; `enqueued`
means the request was queued, not that execution has stopped. `ShutdownAgent`
carries a protobuf `Duration` grace period. The agent runtime and deployment
must implement the actual safe points and shutdown behavior.

Use `PollActivityBuffer` to inspect activity entries and `PurgeActivity` only
after selecting the completed task IDs you intend to remove. The response
reports `purged`. This activity list is not a task-status query API and is
distinct from both the SDK's local message buffer and ActivityService artifacts.
See [Scheduler Client](../clients/scheduler.md).

## Coordination and capability service workflows

The procedures below describe the wire contract. Apart from NegotiationRoom,
these require a server supplied by your deployment; constructing a client does
not start one. Local SDK helpers are identified in the linked client pages.

### NegotiationRoom: submit an artifact and collect a decision

The producer sends `SubmitProposalRequest.proposal` with an artifact ID, room
ID, producer ID, artifact type, bytes, MIME type, and requested critics. Each
critic sends `SubmitVoteRequest.vote` for the same artifact and room. Scores
are 0–10; confidence is 0–1, and `passed` records the critic's acceptance judgment.

Use `GetVotes` to inspect participation, `GetDecision` for an available result,
or `WaitForDecision` with `timeout_seconds` to wait. Set the RPC deadline to
accommodate that wait. A wait timeout is not a negative vote or an approval.
Inspect `decision.outcome`, `reason`, `policy_version`, votes, and aggregate
statistics before acting on the artifact. Outcomes are `APPROVED`,
`REVISION_REQUESTED`, and `ESCALATED_TO_HITL`.

The Python reference server persists proposals, votes, and decisions. Actual
critic work and a human approval interface remain application responsibilities.
See [Negotiation Room Client](../clients/negotiation-room.md) for tabbed examples
and [Voting Strategies](voting-strategies.md) for aggregation choices.

### Negotiation: manage a debate lifecycle

Use `Open` to declare a negotiation ID, correlation ID, topic, participants,
intensity, and debate timeout. Participants then `Propose`, `Counter`, and
`Evaluate`; `Decide` records the chosen result and `Abort` carries a reason for
stopping. Proposals and results carry bytes with a declared content type.

These calls return `Empty`. They do not return NegotiationRoom proposals,
votes, or blocking decisions. Retain lifecycle state and use the event fanout
contract when implementing a debate coordinator. See
[Negotiation Client](../clients/negotiation.md) and RFC §17.

### Scheduler policy: bound negotiation and explain outcomes

Set and retrieve the base policy with `SetNegotiationPolicy` and
`GetNegotiationPolicy`. Use `SetPolicyProfiles` and `ListPolicyProfiles` for
named profiles. Before a negotiation round, retrieve `GetEffectivePolicy` for
its negotiation ID so participants use the authoritative policy rather than
their advisory preferences alone.

Send deterministic scores, confidence, notes, and change summaries through
`SubmitEvaluation`. Apply an authorized human decision through `HitlAction`,
including its rationale. Inspect each response's `ok` or `accepted` flag and
`reason`. A policy object does not itself execute a round or enforce a budget;
the coordinator must do that. See [Scheduler Policy Client](../clients/scheduler-policy.md).

### Handoff: transfer responsibility with an explicit decision

The source calls `RequestHandoff` with `request_id`, `from_agent`, `to_agent`,
reason, serialized `context_snapshot`, required capabilities, priority, and
timeout. The recipient discovers requests with `GetPendingHandoffs` and either
`AcceptHandoff`s or `RejectHandoff`s using the same request ID. An `Empty` RPC
response is not proof that the recipient accepted or completed the work.

Keep the source's recovery state until responsibility has been accepted.
The eventual `CompleteHandoff` includes an explicit status; inspect `success`
and `message`. A rejected request does not pass through completion. For
cross-swarm cancellation, `CancelDelegation.acknowledged` confirms receipt,
while cleanup and terminal outcome happen separately. See
[Handoff Client](../clients/handoff.md), [serialization](handoff-serialization.md),
and [SW4-004](extensions/SW4-004-inter-swarm-composition.md).

### Workflow: define dependencies, start, inspect, resume

Build a `WorkflowDefinition` whose `nodes` map contains unique node IDs, target
agent IDs, dependency IDs, trigger types, and input/output mappings. Validate
that dependencies exist and the graph is acyclic before `CreateWorkflow`.
Inspect `success` and `error`; this response has no `error_code` field.

`StartWorkflow` supplies initial `workflow_data` as a JSON string. Inspect
`GetWorkflowState.state.node_states` to distinguish pending dependencies from
running, completed, failed, or skipped nodes. `ResumeWorkflow` specifies a node
ID and updated data; do not restart already completed side effects blindly.
The wire client requires a server. The separate local
[Workflow Engine](../clients/workflow-engine.md) executes an in-process DAG.
See [Workflow Client](../clients/workflow.md) for wire examples.

### HITL: obtain a human decision

`Decide` takes a `HitlInvocation`: a canonical `reason_type`, context bytes,
proposed action strings, and priority. The result has `action`,
`decision_payload`, and `rationale`. Validate the returned action against your
allowed choices and preserve the decision before proceeding.

If the human service is unavailable or the deadline expires, pause, defer, or
reject according to the workflow's policy. Never convert a timeout into an
implicit approval. Approval routing, authentication, and the human interface
belong to the server you supply. See [HITL Client](../clients/hitl.md).

### Worktree: bind a context and control switches

Call `Bind(agent_id, repo_id, worktree_id)` and inspect `ok` and `reason`.
`Status` returns the current repository, worktree, and binding state. To move
to another context, use `RequestSwitch` with `requires_hitl`; an authorized
decision calls `ApproveSwitch` with a TTL or `RejectSwitch` with a reason.
Confirm the resulting status before issuing file operations. Use `Unbind`
when releasing the association.

These operations manage binding state. They are not an `ExecuteGitCommand`
API, and a worktree ID alone does not enforce filesystem isolation. The
deployment must resolve allowed paths and confine its tools. See
[Worktree Client](../clients/worktree.md).

### Connector and Tool: discover a descriptor, then execute

Connector `RegisterProvider` associates a provider ID with tool descriptors.
`DescribeTools(provider_id)` returns their input/output schemas, idempotency,
worktree requirement, default timeout, concurrency limit, and side-effect class.
Use those descriptors to validate arguments and decide whether retries are safe.

Execution goes to ToolService: `Call` for unary completion or `CallStream` for
frames. A `ToolCall` carries `call_id`, tool/provider IDs, argument bytes,
content type, execution policy, and stream flag. Track each `ToolFrame` by
`call_id` and `frame_no`; consume `data` and inspect `final` and optional
`summary`. Preserve partial output if the stream fails. `Cancel` is best effort
and returns a `ToolError` shape; it does not guarantee rollback of prior effects.

ExecutionPolicy expresses timeout, retry budget, worktree requirement, network
and privilege policy, and CPU/wall budgets. Enforcement belongs to the tool
server. See [Connector Client](../clients/connector.md) and
[Tool Client](../clients/tool.md).

### Reasoning: request an assessment

Use `CheckParallelism` with two resource scope descriptions, `EvaluateDebate`
with the negotiation ID and two proposals, or `Summarize` with ordered text
segments and a token limit. The first two return a confidence score and notes;
summarization returns summary, tokens, cost, and model metadata.

Treat confidence as input to your scheduling or review policy, not authority
to bypass resource locks or human approval. The service contract neither
launches a debate nor supplies an inference engine. See
[Reasoning Client](../clients/reasoning.md).

### Logging and Activity: preserve evidence

Logging `Ingest` accepts a `LogEvent` with timestamp, correlation ID, agent ID,
event type, level string, and `details_json`. Record the operation, resource,
result, and message IDs in details when useful; redact sensitive payloads.
Inspect `ok`. Retrieval, retention, and immutable storage are backend concerns,
not additional Logging RPCs.

Activity `AppendArtifact` stores a negotiation artifact's kind, version,
content type, bytes, and creation time. Check `ok` and `reason`. Use
`ListArtifacts` with the negotiation ID and optional kind filter to reconstruct
contracts, diffs, scores, or decisions. This is artifact evidence, not the
Scheduler activity list or the SDK's message recovery buffer. See
[Logging Client](../clients/logging.md) and [Activity Client](../clients/activity.md).

## Operating a service boundary

### Discovery, health, and balancing

Configure each endpoint explicitly or resolve it through your deployment's
service discovery. Agent heartbeats report agent health; they do not prove
every dependency is ready. Before accepting work, probe the required RPCs and
verify that persistent storage is writable. The canonical schemas do not
define a generic `ServiceRegistration` or `CircuitBreakerConfig` message.

For a custom replicated service, choose load balancing according to state
ownership: round-robin fits interchangeable stateless workers; weighted or
least-connections routing can suit unequal capacity; locality routing can
reduce network cost. Exclude unhealthy endpoints. Do not put independent
reference SQLite routers behind round-robin and assume they share pending
deliveries. Stream affinity and shared/partitioned durable state must be
designed together.

### Failure and retry procedure

First distinguish a gRPC transport failure from a negative application response
(`accepted=false`, `ok=false`, or `success=false`) and from a terminal application
ACK. Preserve the corresponding status, reason, and identifiers.

Retry only when the operation is safe to repeat and the failure is transient.
Use bounded exponential backoff with jitter and an overall deadline; stop on
validation or permission failures until their cause is corrected. A timeout
may occur after the server committed a mutation, so inspect existing state or
deduplicate before repeating it. See [Error Handling](../clients/error-handling.md).

If your integration uses a circuit breaker, CLOSED admits normal traffic,
OPEN fails fast while the dependency recovers, and HALF_OPEN admits limited
probes. Keep failed work pending or explicitly terminalize it; a fallback must
not report successful processing of work it skipped. Circuit breakers and
retry loops are deployment/SDK-specific, not universal wire behavior.

### Authentication, authorization, and audit

For deployment beyond the local reference setup, configure authenticated
transport, bind the peer identity to the claimed agent ID, and authorize each
method and resource. Verify this at the server boundary: possession of a
descriptor or a message's `producer_id` is not proof of identity. Configure
certificate/key loading through your server and channel implementation; there
is no universal SW4RM `tls_config` YAML object.

Record actor, service, method, resource, result, correlation ID, and timing for
privileged operations. Define payload redaction, access to logs, and retention
before exporting evidence. RFC §6 and §23 describe security requirements;
the local reference services do not supply a complete mTLS/RBAC/audit platform.
