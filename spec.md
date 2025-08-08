# RFC: Interruptible, Message-Driven CLI Agent Framework (Consolidated)

## 1. Status of this Memo

This document specifies a protocol and runtime architecture for a CLI framework that schedules, routes, and supervises interruptible, message-driven agents. Distribution is unlimited. Implementations that claim conformance MUST satisfy all normative requirements herein.

## 2. Abstract

The framework defines a central scheduler that orders and preempts task execution, a routed messaging plane with explicit lifecycles and acknowledgements, a Human-In-The-Loop (HITL) escalation channel, first-class repository/worktree isolation, an inter-agent negotiation protocol, and MCP-compatible tool calling. Agents are process-isolated participants that register capabilities, exchange typed messages, and MAY run multiple instances subject to concurrency policy. A technology-agnostic **Reasoning Engine** provides contextual analysis when requested. The system is suitable for single-node deployment and MUST be extensible to distributed environments.

## 3. Terminology

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” follow RFC 2119.

**Agent**: execution participant supervised by the Scheduler.
**Task**: unit of work enqueued to an Agent.
**Message**: routed unit of communication with normative lifecycle.
**Scheduler**: sole authority for ordering, preemption, routing, and HITL invocation.
**Reasoning Engine**: external decision service; MAY be deterministic or not; SHOULD return `confidence_score` when consulted for parallelism checks or negotiation evaluation; MUST NOT mutate Agent/Scheduler state directly.
**Tool**: external capability invoked via routing; MCP optional, MCP-like required.
**Worktree**: Git worktree bound to an Agent.
**Communication Class**: agent-level preference for routing (PRIVILEGED, STANDARD, BULK).
**Connector**: binding to a Tool provider or Reasoning Engine.

## 4. Architecture

Components: Scheduler, Agents, routed Messaging plane, HITL service, optional Tool/Connector layer, Observability sink. All inter-component RPCs SHALL use gRPC. The Scheduler maintains authoritative task and message state, performs reconciliation, and is the only entity that may preempt execution or escalate to HITL. Routing is **unicast** in this version. HLC MAY be enabled for causal analysis.

## 5. Transport

gRPC unary + server-streaming. Define `.proto` contracts for Registry, Scheduler control, Routing, HITL, Logging, ToolService, ConnectorService, Negotiation, Worktree. Messages and streams SHALL carry `correlation_id` and MAY include an HLC timestamp.

## 6. Identity and Security

Stable `agent_id`. Signing is pluggable: MAY be disabled locally; MUST be enabled in distributed/multi-tenant mode (Ed25519/ECDSA over metadata+payload; keys via registry handshake). ACLs MUST constrain message types and tools. Worktree confinement MUST be enforced at the syscall boundary.

## 7. Scheduler: Priority, Ordering, Cooperative Preemption

**Task** priority: −19 (highest) to 20 (lowest); default 0. Order by priority then FIFO. If a new task has strictly higher priority, the Scheduler MUST preempt the running task. **Cooperative** by default: agents implement safe points; agents MAY declare bounded **non-preemptible sections** for critical regions; Scheduler defers preemption until section closes or timeout elapses. Forced preemption MAY be issued (soft terminate with grace → hard kill), marking task FAILED with `error_code=forced_preemption`.

**Communication Class**: PRIVILEGED messages insert into an urgent lane to run **next after** the in-flight message (no hard preempt). Rate-limit urgent bursts; overflow falls back to normal insertion.

## 8. Agent Lifecycle

States: INITIALIZING, RUNNABLE, SCHEDULED, RUNNING, WAITING, WAITING\_RESOURCES, SUSPENDED, RESUMED, COMPLETED, FAILED, SHUTTING\_DOWN, RECOVERING. In SHUTTING\_DOWN the agent MAY finish its current task; Scheduler MUST NOT dispatch new tasks/messages; on grace timeout mark FAILED (`agent_shutdown_timeout`).

## 9. Concurrency Model and Reasoning

`max_parallel_instances` per agent. Two instances MUST NOT process the same job unless HITL authorizes. Jobs carry a **scope** descriptor for conflict assessment. For potentially overlapping work, the Scheduler SHOULD consult the Reasoning Engine. If a returned `confidence_score` is below threshold, escalate via HITL (`CONFLICT`). If engine is down, act conservatively and escalate unless policy allows unconditional parallelism.

## 10. Activity Buffer

Each agent maintains `<task_id, repo_id, worktree_id, branch, timestamp, description≤200 words>`. Create before execution; remove on completion. Scheduler reconciles and purges entries for COMPLETED/FAILED/unknown tasks. Buffer is advisory and MUST NOT block scheduling.

## 11. Messaging Model

Lifecycle: SENT → RECEIVED → ACKNOWLEDGED → READ → FULFILLED. Errors: REJECTED, FAILED, TIMED\_OUT, RETRYING. Default 10 s to `RECEIVED`; on timeout set `TIMED_OUT` and NACK with `ack_timeout`. Late ACKs MUST be reconciled.

Every message MUST include:
`message_id` (UUIDv4 per attempt), `producer_id`, `correlation_id` (UUIDv4), `sequence_number` (monotonic per producer stream), `retry_count`, `message_type` (CONTROL, DATA, HEARTBEAT, NOTIFICATION, ACKNOWLEDGEMENT, HITL\_INVOCATION, WORKTREE\_CONTROL, NEGOTIATION, TOOL\_CALL, TOOL\_RESULT, TOOL\_ERROR), and `content_type`/`content_length` when payload present. MAY include `idempotency_token` (constant across retries of same logical op). When HLC is enabled include `hlc_timestamp`. MAY include `ttl_ms` (expired → FAILED `ttl_expired`). Core error codes include: `buffer_full`, `no_route`, `ack_timeout`, `agent_unavailable`, `agent_shutdown`, `validation_error`, `permission_denied`, `unsupported_message_type`, `oversize_payload`, `tool_timeout`, `partial_delivery`(reserved), `forced_preemption`, `internal_error`.

### 11.1 Idempotency Guarantees

`idempotency_token` MAY be supplied for exactly-once semantics. If present, MUST be constant across retries. The Scheduler SHALL maintain a cache mapping tokens to terminal outcomes for at least `deduplication_window` (default 3600 s; persisted).
On arrival with token:
• Token → terminal: return cached outcome (no re-exec).
• Token → non-terminal: do not start new execution; return `ALREADY_IN_PROGRESS`.
• New token: record RECEIVED and proceed.
Tokens SHOULD follow `{producer_id}:{operation_type}:{deterministic_hash}` over canonical parameters. Router dedups by token if present; else by `(producer_id, sequence_number)`. Retries MUST generate new `message_id` while preserving token.

## 12. Addressing and Modalities

**Unicast** only in this version. Payloads MUST declare `content_type`. Support `application/json`, `application/protobuf`; SHOULD support `text/plain`; MAY support `image/*`, `audio/*`. Router enforces agent modality declarations.

## 13. Buffers and Back-Pressure

Default inbound buffer per agent: 10; configurable. On overflow, reject with `buffer_full` and NACK sender. No silent drops. Scheduler SHOULD surface back-pressure metrics and MAY pace senders.

## 14. Registry, Discovery, Heartbeats

Agents register with name, ≤200-word description, capabilities, communication class, modalities, tool descriptors, ≥1 Reasoning Engine connector, and public key if signing enabled. Scheduler emits heartbeats; agents MUST respond. Join/leave broadcast; recipients maintain discovery. Debounce before removal for missed heartbeats. Deregistration MUST be explicit.

## 15. Human-In-The-Loop (HITL)

Scheduler issues `HITL_INVOCATION` with `reason_type` in {CONFLICT, SECURITY\_APPROVAL, TASK\_ESCALATION, MANUAL\_OVERRIDE, WORKTREE\_OVERRIDE, DEBATE\_DEADLOCK, TOOL\_PRIVILEGE\_ESCALATION, CONNECTOR\_APPROVAL}. Context SHOULD include case facts and Reasoning metadata when present. HITL responds with `HITL_DECISION`; Scheduler applies immediately and logs.

## 16. Repository and Worktree Binding

Agents operate from a single **home worktree** (`repo_id`, `worktree_id`). Enforce confinement: forbid path escapes, forbid device nodes, prefer `noexec,nodev,nosuid` mounts; on weaker platforms, enforce via in-process VFS and dirfd-relative opens with `O_NOFOLLOW`. Non-home worktree operation is forbidden by default; Scheduler MAY request switch with policy + HITL approval. Binding state machine: UNBOUND → BOUND\_HOME → SWITCH\_PENDING → BOUND\_NON\_HOME → …; log transitions. `WORKTREE_CONTROL` ops: BIND, UNBIND, SWITCH\_REQUEST, SWITCH\_APPROVE, SWITCH\_REJECT, SWITCH\_REVOKE, STATUS. Tools with `needs_worktree=true` MUST fail with `worktree_not_bound` if agent is unbound.

## 17. Inter-Agent Negotiation (“Debate”)

Negotiations are scheduler-mediated, identified by `negotiation_id`, scoped by `correlation_id`. Open with topic, participants, `debate_intensity_factor ∈ {LOWEST,LOW,MEDIUM,HIGH,HIGHEST}`; map intensity to guardrails (rounds/time/thresholds). Participants exchange PROPOSAL/COUNTER/EVALUATION messages in `NEGOTIATION`. Scheduler enforces `debate_timeout`; on deadlock/timeout, apply tie-break or escalate with `DEBATE_DEADLOCK`. At minimum support two-party unanimity. Negotiation does not mutate repos; subsequent CONTROL/DATA does.

## 18. MCP Integration and Tool Calling

Tool calling is first-class; MCP optional, MCP-like required. `TOOL_CALL` includes `tool_name`, `provider_id`, typed `args`, `content_type`, `execution_policy` (timeout, retries, isolation, budgets), optional `stream=true`. Scheduler assigns `call_id`; provider returns `TOOL_RESULT` (frames if streaming) or `TOOL_ERROR`. Idempotent tools MUST ensure retries are safe or compensated. Providers run under invoking agent’s confinement and ACLs. MCP providers expose manifests + schema; non-MCP expose DescribeTools. Each Agent MUST register ≥1 Reasoning connector; Scheduler MAY proxy calls.

## 19. Observability

Log every state transition and event with timestamp (UTC ISO-8601), `correlation_id`, actor, event type, details. Flag urgent-lane dispatches; track per-agent urgent burst usage and warn on starvation risk. Streaming tool calls record frame counts + byte totals. Include `repo_id`/`worktree_id` and `negotiation_id` where relevant. For idempotency, log cache decisions and link to original attempt.

## 20. Defaults and Operational Considerations

Defaults: ACK 10s to RECEIVED; inbound buffer 10; task priority 0; idempotency `deduplication_window=3600s` (persisted). Reasoning Engine unreachable → conservative behavior: deny risky parallelism, shorten debates, escalate to HITL as policy requires.

## 21. Error Handling

Set terminal state (REJECTED/FAILED/TIMED\_OUT) with `error_code`. NACKs include precipitating `message_id`, failed stage, error code. Late-ACK reconciliation MUST correct to truthful terminal stage. For idempotent duplicates, return `DUPLICATE_DETECTED` with original attempt ID, status, cached result/error, and `cached_at`.

## 22. Conformance

Implement §§7–8, §9, §10, §11–11.1, §12–§16, §17–§19. MCP compatibility is OPTIONAL; MCP-like tool descriptors are REQUIRED.

## 23. Security Considerations

Signing risks without key hygiene; document rotation/revocation. PRIVILEGED lane can starve; rate-limit and monitor. Worktree confinement at syscall boundary; forbid symlink escape/device nodes. HITL decisions SHOULD be authenticated. Reasoning outputs are advisory; bound by policy. Protect idempotency cache from poisoning; derive tokens from stable, authenticated parameters.

## 24. Implementation Notes (Non-Normative)

Redact secrets; set retention policies. Consider hard ceilings or mandatory interleave for urgent-lane fairness. Prefer idempotent tools for mutations; gate non-idempotent with policy/HITL. HLC is advisory; document skew budgets and never use HLC alone for correctness-critical ordering. Version and log Reasoning requests/responses.

## 25. Future Work (Non-Normative)

Scheduler HA (WAL + leader election + replay), group addressing, formal Reasoning API/circuit breaker.

---

## Annex A — Architecture Diagrams (Mermaid)

```mermaid
flowchart LR
  subgraph Scheduler
    R[Router]
    Q[Queues: Urgent + Normal]
    SM[State Manager (tasks/messages/idempotency)]
    HE[HITL Adapter]
    RE[Reasoning Proxy]
    REG[Registry + Heartbeats]
    LOG[Observability Sink]
  end
  subgraph AgentA[Agent A]
    A_in[Inbound Buffer]
    A_exec[Executor (safe points)]
    A_abuf[Activity Buffer]
    A_tools[Tool Connectors]
  end
  subgraph AgentB[Agent B]
    B_in[Inbound Buffer]
    B_exec[Executor]
    B_abuf[Activity Buffer]
    B_tools[Tool Connectors]
  end
  subgraph Tools[Tool Providers]
    T1[(Tool 1)]
    T2[(Tool 2 - MCP)]
  end
  subgraph HITL[HITL Service/UI] end
  subgraph Reasoning[Reasoning Engine] end

  REG --- R
  R <--> Q
  R --- SM
  SM --- HE
  HE --- HITL
  SM --- RE
  RE --- Reasoning
  SM --- LOG

  R -->|unicast| A_in
  R -->|unicast| B_in
  A_exec --> A_tools
  B_exec --> B_tools
  A_tools --> T1
  B_tools --> T2
```

```mermaid
flowchart TB
  subgraph Repo[Git Repository]
    WT_A[[Worktree A (Agent A home)]]
    WT_B[[Worktree B (Agent B home)]]
    WT_TMP[[Worktree TMP (non-home)]]
  end
  subgraph Scheduler
    WTC[Worktree Controller]
    POL[Policy: non-home requires HITL]
  end
  A_exec[Agent A Executor] -- confined IO --> WT_A
  B_exec[Agent B Executor] -- confined IO --> WT_B
  A_exec -. request switch .-> WTC
  WTC --> POL
  POL -->|HITL_INVOCATION(WORKTREE_OVERRIDE)| HITL
  HITL -->|HITL_DECISION| WTC
  WTC -->|SWITCH_APPROVE| A_exec
  A_exec -- confined IO --> WT_TMP
```

---

## Annex B — Finite-State Diagrams (Mermaid)

**Agent lifecycle**

```mermaid
stateDiagram-v2
    [*] --> INITIALIZING
    INITIALIZING --> RUNNABLE
    RUNNABLE --> SCHEDULED
    SCHEDULED --> RUNNING
    RUNNING --> WAITING
    WAITING --> RUNNING
    RUNNING --> SUSPENDED
    SUSPENDED --> RESUMED
    RESUMED --> RUNNING
    RUNNING --> COMPLETED
    RUNNING --> FAILED
    RUNNING --> SHUTTING_DOWN
    SHUTTING_DOWN --> FAILED: agent_shutdown_timeout
    FAILED --> RECOVERING
    RECOVERING --> RUNNABLE
```

**Message lifecycle**

```mermaid
stateDiagram-v2
    [*] --> SENT
    SENT --> RECEIVED: admitted to buffer
    RECEIVED --> ACKNOWLEDGED: ack_stage=RECEIVED
    ACKNOWLEDGED --> READ
    READ --> FULFILLED: ack_stage=FULFILLED
    RECEIVED --> TIMED_OUT: ack timeout
    TIMED_OUT --> RETRYING: new message_id, same idempotency_token
    RETRYING --> SENT
    RECEIVED --> REJECTED: buffer_full|validation_error
    RECEIVED --> FAILED: internal_error|permission_denied|forced_preemption
```

---

## Annex C — Sequence Diagrams (Mermaid) and JSON Examples

Below are canonical flows. All messages are **unicast** and include the RFC envelope fields.

### C.1 Task submission success

```mermaid
sequenceDiagram
    participant OP as Operator/CLI
    participant S as Scheduler/Router
    participant B as Agent B
    OP->>S: DATA(TaskCreate v1)
    S->>B: deliver (buffer admit)
    B-->>S: ACK{ack_stage="RECEIVED"}
    B->>B: execute
    B-->>S: ACK{ack_stage="FULFILLED"}
    S-->>OP: NOTIFICATION{status:"FULFILLED"}
```

```json
{
  "message_id": "msg001",
  "producer_id": "cli",
  "correlation_id": "wf-1111",
  "sequence_number": 1,
  "message_type": "DATA",
  "content_type": "application/json",
  "payload": {"task_type":"CreateTicket","title":"Fix header overlap"}
}
```

### C.2 Timeout, retry, late ACK, idempotent reconcile

```mermaid
sequenceDiagram
    participant A as Agent A
    participant S as Scheduler
    participant B as Agent B
    A->>S: DATA (m1, token=T)
    S->>B: deliver
    Note over B: >10s delay
    S-->>A: NACK (ack_timeout)
    A->>S: DATA (m2, token=T, retry_count=1)
    S->>B: deliver (dedup by token -> no second exec)
    B-->>S: ACK RECEIVED (late for m1)
    S->>S: reconcile token T
    B-->>S: ACK FULFILLED
    S-->>A: DUPLICATE_DETECTED (original m1)
```

```json
{
  "status": "DUPLICATE_DETECTED",
  "original_message_id": "m1",
  "original_status": "FULFILLED",
  "cached_at": "2025-08-08T14:03:22Z"
}
```

### C.3 Buffer overflow rejection

```mermaid
sequenceDiagram
    participant A as Agent A
    participant S as Scheduler
    participant B as Agent B
    A->>S: DATA (to B)
    S->>B: deliver
    B-->>S: ACK REJECTED (buffer_full)
    S-->>A: ACK REJECTED (buffer_full)
```

```json
{
  "message_id": "ack_rej_77",
  "producer_id": "scheduler",
  "correlation_id": "wf-3333",
  "message_type": "ACKNOWLEDGEMENT",
  "content_type": "application/json",
  "payload": {
    "ack_for_message_id": "mX",
    "ack_stage": "REJECTED",
    "error_code": "buffer_full"
  }
}
```

### C.4 Cooperative preemption by higher-priority task

```mermaid
sequenceDiagram
    participant S as Scheduler
    participant B as Agent B
    S->>B: CONTROL RUN lowP
    S->>B: CONTROL PREEMPT_REQUEST
    B-->>S: ACK RECEIVED
    B->>B: safe point reached
    B-->>S: ACK FULFILLED (yielded)
    S->>B: CONTROL RUN highP
```

### C.5 Forced preemption after non-preemptible timeout

```mermaid
sequenceDiagram
    participant S as Scheduler
    participant B as Agent B
    S->>B: PREEMPT_REQUEST
    Note over B: still in non-preemptible; max_duration exceeded
    S->>B: TERMINATE{grace_ms:3000}
    alt responds
      B-->>S: ACK FULFILLED (terminated)
    else
      S->>B: KILL
      S->>S: mark FAILED{forced_preemption}
    end
```

### C.6 HITL escalation for conflict

```mermaid
sequenceDiagram
    participant S as Scheduler
    participant RE as Reasoning
    participant H as HITL
    participant X as Agent X
    participant Y as Agent Y
    S->>RE: parallelism_check(scope X,Y)
    RE-->>S: {confidence_score:0.58}
    S->>H: HITL_INVOCATION(CONFLICT)
    H-->>S: HITL_DECISION(QUEUE_TASKS)
    S->>X: CONTROL RUN tX
    S->>Y: NOTIFICATION deferred
```

### C.7 Worktree bind/switch/unbind

```mermaid
sequenceDiagram
    participant S as Scheduler
    participant A as Agent A
    participant H as HITL
    S->>A: WORKTREE_CONTROL BIND(repo42, wt_frontend)
    A-->>S: ACK FULFILLED
    S->>A: CONTROL RUN build
    S->>A: WORKTREE_CONTROL SWITCH_REQUEST(wt_shared_proto, requires_hitl=true)
    S->>H: HITL_INVOCATION(WORKTREE_OVERRIDE)
    H-->>S: HITL_DECISION(APPROVE)
    S->>A: WORKTREE_CONTROL SWITCH_APPROVE(wt_shared_proto, ttl_ms=900000)
    S->>A: WORKTREE_CONTROL UNBIND
```

### C.8 Tool call (streaming)

```mermaid
sequenceDiagram
    participant A as Agent A
    participant S as Scheduler
    participant TP as Tool Provider
    A->>S: TOOL_CALL (stream=true)
    S->>TP: CallStream
    TP-->>S: TOOL_RESULT frame 1
    TP-->>S: TOOL_RESULT frame n (final)
    S-->>A: stream frames + final summary
```

### C.9 Negotiation with timeout + HITL decision

```mermaid
sequenceDiagram
    participant S as Scheduler
    participant FE as Frontend
    participant GQL as GraphQL
    participant RE as Reasoning
    participant H as HITL
    S->>FE: NEGOTIATION OPEN (topic=/api/v3/orders, intensity=HIGH)
    FE->>S: PROPOSAL A
    S->>GQL: route
    GQL->>S: COUNTERPROPOSAL B
    S->>RE: evaluate(A,B)
    RE-->>S: {confidence_score:0.71}
    Note over S: debate_timeout
    S->>H: HITL_INVOCATION(DEBATE_DEADLOCK)
    H-->>S: HITL_DECISION(decide=B)
    S->>FE: DECISION B
    S->>GQL: DECISION B
```

---

## Annex D — Representative JSON Payloads

I’ve already embedded JSON for success, retry/late-ACK, buffer overflow, worktree, tool, negotiation, and HITL above. If you want these as a fixture pack, I can hand you a tarball structure later.

---

# Protobuf Stubs (proto3)

**Notes:**
• All strings expecting UUIDs are plain `string` here.
• Use `google.protobuf.Timestamp` and `Duration` where helpful.
• Payloads are `bytes` + `content_type` for maximum flexibility (JSON or protobuf within).
• Split into logical files for clarity; you can merge if you prefer one file.

---

## `common.proto`

```proto
syntax = "proto3";

package agentos.common;

import "google/protobuf/timestamp.proto";
import "google/protobuf/duration.proto";

enum MessageType {
  MESSAGE_TYPE_UNSPECIFIED = 0;
  CONTROL = 1;
  DATA = 2;
  HEARTBEAT = 3;
  NOTIFICATION = 4;
  ACKNOWLEDGEMENT = 5;
  HITL_INVOCATION = 6;
  WORKTREE_CONTROL = 7;
  NEGOTIATION = 8;
  TOOL_CALL = 9;
  TOOL_RESULT = 10;
  TOOL_ERROR = 11;
}

enum AckStage {
  ACK_STAGE_UNSPECIFIED = 0;
  RECEIVED = 1;
  READ = 2;
  FULFILLED = 3;
  REJECTED = 4;
  FAILED = 5;
  TIMED_OUT = 6;
}

enum ErrorCode {
  ERROR_CODE_UNSPECIFIED = 0;
  BUFFER_FULL = 1;
  NO_ROUTE = 2;
  ACK_TIMEOUT = 3;
  AGENT_UNAVAILABLE = 4;
  AGENT_SHUTDOWN = 5;
  VALIDATION_ERROR = 6;
  PERMISSION_DENIED = 7;
  UNSUPPORTED_MESSAGE_TYPE = 8;
  OVERSIZE_PAYLOAD = 9;
  TOOL_TIMEOUT = 10;
  PARTIAL_DELIVERY = 11; // reserved
  FORCED_PREEMPTION = 12;
  TTL_EXPIRED = 13;
  INTERNAL_ERROR = 99;
}

enum AgentState {
  AGENT_STATE_UNSPECIFIED = 0;
  INITIALIZING = 1;
  RUNNABLE = 2;
  SCHEDULED = 3;
  RUNNING = 4;
  WAITING = 5;
  WAITING_RESOURCES = 6;
  SUSPENDED = 7;
  RESUMED = 8;
  COMPLETED = 9;
  FAILED_STATE = 10;
  SHUTTING_DOWN = 11;
  RECOVERING = 12;
}

enum CommunicationClass {
  COMM_CLASS_UNSPECIFIED = 0;
  PRIVILEGED = 1;
  STANDARD = 2;
  BULK = 3;
}

enum DebateIntensity {
  DEBATE_INTENSITY_UNSPECIFIED = 0;
  LOWEST = 1;
  LOW = 2;
  MEDIUM = 3;
  HIGH = 4;
  HIGHEST = 5;
}

enum HitlReasonType {
  HITL_REASON_UNSPECIFIED = 0;
  CONFLICT = 1;
  SECURITY_APPROVAL = 2;
  TASK_ESCALATION = 3;
  MANUAL_OVERRIDE = 4;
  WORKTREE_OVERRIDE = 5;
  DEBATE_DEADLOCK = 6;
  TOOL_PRIVILEGE_ESCALATION = 7;
  CONNECTOR_APPROVAL = 8;
}

message Envelope {
  string message_id = 1;                // UUIDv4 per attempt
  string idempotency_token = 2;         // stable across retries (optional)
  string producer_id = 3;
  string correlation_id = 4;
  uint64 sequence_number = 5;
  uint32 retry_count = 6;
  MessageType message_type = 7;
  string content_type = 8;              // e.g., application/json
  uint64 content_length = 9;
  string repo_id = 10;                  // optional
  string worktree_id = 11;              // optional
  string hlc_timestamp = 12;            // optional, string-form HLC
  uint64 ttl_ms = 13;                   // optional
  google.protobuf.Timestamp timestamp = 14;
  bytes payload = 15;                    // serialized content per content_type
}

message Ack {
  string ack_for_message_id = 1;
  AckStage ack_stage = 2;
  ErrorCode error_code = 3;
  string note = 4;
}

message Empty {}
```

---

## `registry.proto`

```proto
syntax = "proto3";

package agentos.registry;

import "google/protobuf/timestamp.proto";
import "common.proto";

message AgentDescriptor {
  string agent_id = 1;
  string name = 2;
  string description = 3; // ≤200 words
  repeated string capabilities = 4;
  agentos.common.CommunicationClass communication_class = 5;
  repeated string modalities_supported = 6; // MIME types
  repeated string reasoning_connectors = 7; // URIs
  bytes public_key = 8; // optional
}

message RegisterAgentRequest { AgentDescriptor agent = 1; }
message RegisterAgentResponse { bool accepted = 1; string reason = 2; }

message HeartbeatRequest {
  string agent_id = 1;
  agentos.common.AgentState state = 2;
  map<string,string> health = 3;
}
message HeartbeatResponse { bool ok = 1; }

message DeregisterAgentRequest { string agent_id = 1; string reason = 2; }
message DeregisterAgentResponse { bool ok = 1; }

service RegistryService {
  rpc RegisterAgent(RegisterAgentRequest) returns (RegisterAgentResponse);
  rpc Heartbeat(HeartbeatRequest) returns (HeartbeatResponse);
  rpc DeregisterAgent(DeregisterAgentRequest) returns (DeregisterAgentResponse);
}
```

---

## `router.proto`

```proto
syntax = "proto3";

package agentos.router;

import "common.proto";

message SendMessageRequest { agentos.common.Envelope msg = 1; }
message SendMessageResponse { bool accepted = 1; string reason = 2; }

message StreamRequest { string agent_id = 1; }
message StreamItem { agentos.common.Envelope msg = 1; }

service RouterService {
  rpc SendMessage(SendMessageRequest) returns (SendMessageResponse);
  rpc StreamIncoming(StreamRequest) returns (stream StreamItem); // per-agent inbound stream
}
```

---

## `scheduler.proto`

```proto
syntax = "proto3";

package agentos.scheduler;

import "google/protobuf/duration.proto";
import "common.proto";

message SubmitTaskRequest {
  string agent_id = 1;
  string task_id = 2;
  int32 priority = 3; // -19..20
  bytes params = 4;
  string content_type = 5;
  string scope = 6; // resource scope descriptor
}

message SubmitTaskResponse { bool accepted = 1; string reason = 2; }

message PreemptRequest {
  string agent_id = 1;
  string task_id = 2;
  string reason = 3;
}
message PreemptResponse { bool enqueued = 1; }

message ShutdownAgentRequest {
  string agent_id = 1;
  google.protobuf.Duration grace_period = 2;
}
message ShutdownAgentResponse { bool ok = 1; }

message PollActivityBufferRequest { string agent_id = 1; }
message ActivityEntry {
  string task_id = 1;
  string repo_id = 2;
  string worktree_id = 3;
  string branch = 4;
  string description = 5;
  string timestamp = 6;
}
message PollActivityBufferResponse { repeated ActivityEntry entries = 1; }

message PurgeActivityRequest { string agent_id = 1; repeated string task_ids = 2; }
message PurgeActivityResponse { uint32 purged = 1; }

service SchedulerService {
  rpc SubmitTask(SubmitTaskRequest) returns (SubmitTaskResponse);
  rpc RequestPreemption(PreemptRequest) returns (PreemptResponse);
  rpc ShutdownAgent(ShutdownAgentRequest) returns (ShutdownAgentResponse);
  rpc PollActivityBuffer(PollActivityBufferRequest) returns (PollActivityBufferResponse);
  rpc PurgeActivity(PurgeActivityRequest) returns (PurgeActivityResponse);
}
```

---

## `hitl.proto`

```proto
syntax = "proto3";

package agentos.hitl;

import "common.proto";

message HitlInvocation {
  agentos.common.HitlReasonType reason_type = 1;
  bytes context = 2;             // JSON or protobuf, see content_type in envelope
  repeated string proposed_actions = 3;
  int32 priority = 4;
}

message HitlDecision {
  string action = 1;
  bytes decision_payload = 2;
  string rationale = 3;
}

service HitlService {
  // Invocation is carried in Envelope.payload; this service handles the decision side.
  rpc Decide(HitlInvocation) returns (HitlDecision);
}
```

---

## `worktree.proto`

```proto
syntax = "proto3";

package agentos.worktree;

message BindRequest { string agent_id = 1; string repo_id = 2; string worktree_id = 3; }
message BindResponse { bool ok = 1; string reason = 2; }

message UnbindRequest { string agent_id = 1; }
message UnbindResponse { bool ok = 1; }

message SwitchRequest {
  string agent_id = 1;
  string target_worktree_id = 2;
  bool requires_hitl = 3;
}
message SwitchApprove { string agent_id = 1; string target_worktree_id = 2; uint64 ttl_ms = 3; }
message SwitchReject { string agent_id = 1; string reason = 2; }

message StatusRequest { string agent_id = 1; }
message StatusResponse {
  string repo_id = 1;
  string worktree_id = 2;
  string state = 3; // UNBOUND|BOUND_HOME|SWITCH_PENDING|BOUND_NON_HOME|BIND_FAILED
}

service WorktreeService {
  rpc Bind(BindRequest) returns (BindResponse);
  rpc Unbind(UnbindRequest) returns (UnbindResponse);
  rpc RequestSwitch(SwitchRequest) returns (StatusResponse);
  rpc ApproveSwitch(SwitchApprove) returns (StatusResponse);
  rpc RejectSwitch(SwitchReject) returns (StatusResponse);
  rpc Status(StatusRequest) returns (StatusResponse);
}
```

---

## `tool.proto`

```proto
syntax = "proto3";

package agentos.tool;

import "google/protobuf/duration.proto";

message ExecutionPolicy {
  google.protobuf.Duration timeout = 1;
  uint32 max_retries = 2;
  string backoff = 3; // "exponential", etc.
  bool worktree_required = 4;
  string network_policy = 5;     // e.g., "egress_restricted"
  string privilege_level = 6;    // e.g., "default"
  uint64 budget_cpu_ms = 7;
  uint64 budget_wall_ms = 8;
}

message ToolCall {
  string call_id = 1;
  string tool_name = 2;
  string provider_id = 3;
  string content_type = 4;
  bytes args = 5;
  ExecutionPolicy policy = 6;
  bool stream = 7;
}

message ToolFrame {
  string call_id = 1;
  uint64 frame_no = 2;
  bool final = 3;
  string content_type = 4;
  bytes data = 5;
  bytes summary = 6; // optional final summary
}

message ToolError {
  string call_id = 1;
  string error_code = 2;
  string message = 3;
}

service ToolService {
  rpc Call(ToolCall) returns (ToolFrame);                 // unary completion
  rpc CallStream(ToolCall) returns (stream ToolFrame);    // streaming frames
  rpc Cancel(ToolCall) returns (ToolError);               // best effort
}
```

---

## `connector.proto`

```proto
`syntax = "proto3";

package agentos.connector;

message ToolDescriptor {
  string tool_name = 1;
  string input_schema = 2;   // JSON Schema or URL
  string output_schema = 3;
  bool idempotent = 4;
  bool needs_worktree = 5;
  uint32 default_timeout_s = 6;
  uint32 max_concurrency = 7;
  string side_effects = 8;   // "filesystem","network", etc.
}

message ProviderRegisterRequest {
  string provider_id = 1;
  repeated ToolDescriptor tools = 2;
}

message ProviderRegisterResponse { bool ok = 1; string reason = 2; }

message DescribeToolsRequest { string provider_id = 1; }
message DescribeToolsResponse { repeated ToolDescriptor tools = 1; }

service ConnectorService {
  rpc RegisterProvider(ProviderRegisterRequest) returns (ProviderRegisterResponse);
  rpc DescribeTools(DescribeToolsRequest) returns (DescribeToolsResponse);
}
```

---

## `negotiation.proto`

```proto
syntax = "proto3";

package agentos.negotiation;

import "common.proto";
import "google/protobuf/duration.proto";

message NegotiationOpen {
  string negotiation_id = 1;
  string correlation_id = 2;
  string topic = 3;
  repeated string participants = 4;
  agentos.common.DebateIntensity intensity = 5;
  google.protobuf.Duration debate_timeout = 6;
}

message Proposal {
  string negotiation_id = 1;
  string from_agent = 2;
  string content_type = 3;
  bytes payload = 4; // schema/proto/text as declared
}

message CounterProposal {
  string negotiation_id = 1;
  string from_agent = 2;
  string content_type = 3;
  bytes payload = 4;
}

message Evaluation {
  string negotiation_id = 1;
  string from_agent = 2;
  double confidence_score = 3; // optional; 0 if absent
  string notes = 4;
}

message Decision {
  string negotiation_id = 1;
  string decided_by = 2; // "consensus"|"hitl"|"policy"
  string content_type = 3;
  bytes result = 4;
}

message Abort {
  string negotiation_id = 1;
  string reason = 2;
}

service NegotiationService {
  rpc Open(NegotiationOpen) returns (agentos.common.Empty);
  rpc Propose(Proposal) returns (agentos.common.Empty);
  rpc Counter(CounterProposal) returns (agentos.common.Empty);
  rpc Evaluate(Evaluation) returns (agentos.common.Empty);
  rpc Decide(Decision) returns (agentos.common.Empty);
  rpc Abort(Abort) returns (agentos.common.Empty);
}
```

---

## `reasoning.proto` (proxy is optional but handy)

```proto
syntax = "proto3";

package agentos.reasoning;

message ParallelismCheckRequest { string scope_a = 1; string scope_b = 2; }
message ParallelismCheckResponse { double confidence_score = 1; string notes = 2; }

message DebateEvaluateRequest {
  string negotiation_id = 1;
  string proposal_a = 2;
  string proposal_b = 3;
  string intensity = 4; // map from enum if needed
}
message DebateEvaluateResponse { double confidence_score = 1; string notes = 2; }

service ReasoningProxy {
  rpc CheckParallelism(ParallelismCheckRequest) returns (ParallelismCheckResponse);
  rpc EvaluateDebate(DebateEvaluateRequest) returns (DebateEvaluateResponse);
}
```

---

## `logging.proto`

```proto
syntax = "proto3";

package agentos.logging;

import "google/protobuf/timestamp.proto";

message LogEvent {
  google.protobuf.Timestamp ts = 1;
  string correlation_id = 2;
  string agent_id = 3;
  string event_type = 4;
  string level = 5; // INFO|WARN|ERROR
  string details_json = 6;
}

message IngestResponse { bool ok = 1; }

service LoggingService {
  rpc Ingest(LogEvent) returns (IngestResponse);
}
```

---

## Quick Python SDK Generation

Once you save the above files, generate Python stubs:

```bash
python -m pip install grpcio grpcio-tools googleapis-common-protos
python -m grpc_tools.protoc \
  -I. \
  --python_out=./py_sdk \
  --grpc_python_out=./py_sdk \
  common.proto registry.proto router.proto scheduler.proto hitl.proto \
  worktree.proto tool.proto connector.proto negotiation.proto reasoning.proto logging.proto
```

You’ll get `*_pb2.py` and `*_pb2_grpc.py` modules in `./py_sdk`. From there, Claude Code (or your IDE) can scaffold client/server classes. If you want, I can also spit out a minimal Python server skeleton and a client snippet for each service on the next pass.
