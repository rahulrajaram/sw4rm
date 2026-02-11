# 3.11 Advanced Patterns (v0.5.0)

This section documents the advanced multi-agent coordination patterns introduced in SW4RM Protocol v0.5.0. These patterns enable sophisticated workflows for artifact approval, agent delegation, and DAG-based orchestration.

## 3.11.0 Negotiation Foundations

The following subsections document the core negotiation mechanics that underpin the Negotiation Room, Handoff, and Workflow patterns.

### 3.11.0.1 Negotiation Event Fanout (§17.1)

Negotiation events are carried as `NEGOTIATION` envelopes whose payload is a JSON object. Implementations MUST preserve raw payload bytes and `correlation_id`. Unknown fields MUST be ignored by receivers. The following event kinds are defined:

| Kind | Payload Schema | Description |
|------|---------------|-------------|
| `open` | `{ kind, ts, topic: string, corr: string }` | Opens a new negotiation session |
| `policy` | `{ kind, ts, negotiation_id: string, profile?: string, policy: NegotiationPolicy }` | Broadcasts the effective policy |
| `propose` | `{ kind, ts, from: string, ct: string, payload_b64: string }` | Submits a proposal |
| `counter` | `{ kind, ts, from: string, ct: string, payload_b64: string }` | Submits a counter-proposal |
| `evaluate` | `{ kind, ts, from: string, score: number, notes: string }` | Evaluates a proposal |
| `decide` | `{ kind, ts, by: string, ct: string, result_b64: string }` | Issues a final decision |
| `abort` | `{ kind, ts, reason: string }` | Aborts the negotiation |

`payload_b64` and `result_b64` hold opaque bytes for proposals/results; `ct` is the content type. SDKs SHOULD provide convenience helpers to decode on demand. Services MUST NOT reorder events; ordering follows the service stream.

### 3.11.0.2 Negotiation Policy and Effective Policy (§17.2)

The Scheduler is the source of truth for negotiation policy. On `Open`, the Scheduler MUST derive an `EffectivePolicy` from a base `NegotiationPolicy` and any clamped `AgentPreferences`, then broadcast a `policy` event. Policy MAY be selected by a profile hint provided at `Open`.

The base `NegotiationPolicy` includes:

| Field | Type | Description |
|-------|------|-------------|
| `max_rounds` | u32 | Maximum negotiation rounds |
| `score_threshold` | f32 (0..1) | Score required for acceptance |
| `diff_tolerance` | f32 (0..1) | Maximum acceptable structural diff magnitude |
| `round_timeout_ms` | u64 | Timeout per round in milliseconds |
| `token_budget_per_round` | u64 | Token budget per round |
| `total_token_budget` | u64 | Optional total token budget across all rounds |
| `oscillation_limit` | u32 | Maximum allowed score oscillations before abort |
| `hitl` | enum | HITL gate: `None`, `PauseBetweenRounds`, `PauseOnFinalAccept` |
| `scoring.require_schema_valid` | bool | Require JSON Schema validation |
| `scoring.require_examples_pass` | bool | Require executable examples to pass |
| `scoring.llm_weight` | f32 | Weight for LLM confidence in blended scoring |

The `EffectivePolicy` is the scheduler-owned, per-negotiation policy after clamping agent preferences to scheduler guardrails. Implementations MUST persist the effective policy per room and include it in the broadcast.

### 3.11.0.3 Validation, Diff, and Scoring (§17.3)

Implementations SHOULD support early validation of proposals using JSON Schema and executable examples. Invalid drafts MUST be rejected without consuming a round.

Per round, implementations SHOULD compute and record a structural JSON `DeltaSummary` with:

- `magnitude`: Bounded numerical measure of change size.
- `changed_paths`: Set of JSON paths that changed between rounds.

**Scoring pipeline**: Deterministic scoring MUST run first. Optional Inference Engine/LLM confidence in [0,1] MAY be blended per policy `llm_weight`. Acceptance and stop decisions MUST follow `EffectivePolicy` thresholds (score, oscillation, token, and time budgets). Optional HITL pause is enforced per policy.

### 3.11.0.4 Reports and Artifacts (§17.4)

Implementations SHOULD emit and persist structured records per round:

| Record | Contents |
|--------|----------|
| `EvaluationReport` | Deterministic checks, scores, notes |
| `DecisionReport` | Scores, rationale, stop reason |
| `contract_vN.json` | Versioned artifact snapshot |
| `diff_v{N-1}_to_vN.json` | Structural diff between rounds |

Use the [Activity Service](../protocol/services.md#activity-service) `AppendArtifact` RPC to persist these records.

---

## 3.11.1 Negotiation Room Pattern

The Negotiation Room pattern provides a structured multi-agent artifact approval workflow where Producers submit artifacts for evaluation by multiple Critic agents, with a Coordinator aggregating votes and making final decisions.

### Roles

| Role | Description |
|------|-------------|
| **Producer** | Agent that submits an artifact for approval via `NegotiationProposal` |
| **Critic** | Agent that evaluates artifacts and submits `NegotiationVote` with scores and feedback |
| **Coordinator** | Component (typically the Scheduler) that aggregates votes and issues decisions |

### Artifact Types

Implementations support the following artifact categories:

- `REQUIREMENTS`: The artifact contains specifications and requirements documents.
- `PLAN`: The artifact contains implementation plans and architectural designs.
- `CODE`: The artifact contains source code and executable artifacts.
- `DEPLOYMENT`: The artifact contains deployment configurations and infrastructure definitions.

### Proposal Flow

```mermaid
sequenceDiagram
    participant P as Producer
    participant S as Scheduler/Coordinator
    participant C1 as Critic 1
    participant C2 as Critic 2

    P->>S: SubmitProposal(artifact)
    S->>C1: Distribute for review
    S->>C2: Distribute for review

    C1-->>S: NegotiationVote(score: 8, passed: true)
    C2-->>S: NegotiationVote(score: 7, passed: true)

    S->>S: Aggregate votes
    S-->>P: NegotiationDecision(APPROVED)
```

### Proposal Submission

A Producer submits artifacts via `SubmitProposal` RPC with:

```protobuf
message NegotiationProposal {
  string artifact_type = 1;        // REQUIREMENTS, PLAN, CODE, DEPLOYMENT
  string artifact_id = 2;          // Unique identifier
  bytes artifact = 3;              // Binary content
  string artifact_content_type = 4; // MIME type (e.g., application/json)
  repeated string requested_critics = 5; // Critic agent IDs
  string negotiation_room_id = 6;  // Session identifier
}
```

### Voting

Critics evaluate artifacts and submit votes containing:

| Field | Type | Description |
|-------|------|-------------|
| `score` | float | The critic assigns a numerical score from 0 to 10. A score of 10 indicates excellent quality. |
| `confidence` | float | The critic assigns a confidence level from 0 to 1 representing POMDP uncertainty. |
| `passed` | bool | The critic indicates whether the artifact meets minimum criteria. |
| `strengths` | string[] | The critic lists positive aspects of the artifact. |
| `weaknesses` | string[] | The critic lists areas for improvement. |
| `recommendations` | string[] | The critic lists suggested changes. |

### Vote Aggregation

The Coordinator computes `AggregatedScore` from all votes:

```python
# Python SDK example
from sw4rm.voting import VotingAggregator, ConfidenceWeightedAggregator

votes = [vote1, vote2, vote3]  # NegotiationVote objects
aggregator = VotingAggregator(ConfidenceWeightedAggregator())
aggregated = aggregator.aggregate(votes)

print(f"Mean score: {aggregated.mean}")
print(f"Weighted mean: {aggregated.weighted_mean}")
print(f"Std deviation: {aggregated.std_dev}")
print(f"Vote count: {aggregated.vote_count}")
```

### Decision Outcomes

| Outcome | Description |
|---------|-------------|
| `APPROVED` | The artifact meets all thresholds. The workflow proceeds. |
| `REVISION_REQUESTED` | The artifact requires changes. The Producer should iterate. |
| `ESCALATED_TO_HITL` | Human judgment is required. The system escalates via HITL (Section 3.4). |

### Blocking Wait

For synchronous workflows, Producers can block until a decision is rendered:

```python
# Wait for decision with timeout
decision = client.wait_for_decision(
    artifact_id=artifact_id,
    timeout_s=300
)
```

### Policy-Based Auto-Approval (v0.5.0)

Implementations SHOULD support configurable policy thresholds for automatic decision outcomes:

**Approval Thresholds:**

| Threshold | Default | Description |
|-----------|---------|-------------|
| `min_score_threshold` | 7.0 | Minimum aggregated score for auto-approval |
| `min_confidence_threshold` | 0.7 | Minimum average confidence required |
| `min_pass_ratio` | 0.8 | Minimum proportion of critics that passed |
| `max_std_dev` | 2.0 | Maximum score standard deviation for auto-approval |

The Coordinator SHOULD apply auto-approval when ALL conditions are met:

1. `aggregated_score.weighted_mean >= min_score_threshold`
2. Average confidence across votes >= `min_confidence_threshold`
3. Proportion of votes with `passed=true` >= `min_pass_ratio`
4. `aggregated_score.std_dev <= max_std_dev`

The Coordinator MUST escalate to HITL when ANY of these conditions are met:

1. Any critic vote has `confidence < 0.3` (high uncertainty)
2. `aggregated_score.std_dev > 3.0` (extreme disagreement)
3. Any critic explicitly requests escalation via recommendations
4. Policy timeout expires before sufficient votes are received

Decisions MUST include the `policy_version` field identifying which policy configuration was applied.

---

## 3.11.2 Agent Handoff Protocol

The Handoff Protocol enables safe delegation of work between agents when capability requirements change or workload balancing is needed.

### Handoff Lifecycle

```mermaid
stateDiagram-v2
    [*] --> PENDING: RequestHandoff
    PENDING --> ACCEPTED: AcceptHandoff
    PENDING --> REJECTED: RejectHandoff
    PENDING --> EXPIRED: Timeout
    ACCEPTED --> COMPLETED: Context transferred
    REJECTED --> [*]: Find alternative
    EXPIRED --> [*]: Retry or escalate
    COMPLETED --> [*]: Success
```

### Handoff States

| State | Description |
|-------|-------------|
| `PENDING` | The request was submitted. The system awaits a response. |
| `ACCEPTED` | The target agent accepted the handoff. |
| `REJECTED` | The target agent declined the handoff. The response includes a reason. |
| `COMPLETED` | The system executed the handoff. The context was transferred. |
| `EXPIRED` | The timeout was reached before resolution. |

### Handoff Request

An originating agent initiates handoff via `RequestHandoff`:

```protobuf
message HandoffRequest {
  string request_id = 1;           // Unique identifier
  string from_agent = 2;           // Originating agent ID
  string to_agent = 3;             // Target agent ID (or empty for routing)
  string reason = 4;               // Human-readable explanation
  bytes context_snapshot = 5;      // Serialized execution context
  repeated string capabilities_required = 6; // Required capabilities
  int32 priority = 7;              // Priority level
  int64 timeout_ms = 8;            // Maximum wait duration
}
```

### Accept/Reject Semantics

```python
# Python SDK example - initiating and accepting a handoff
from sw4rm.clients import HandoffClient
from sw4rm.handoff import deserialize_context
from sw4rm.handoff.types import HandoffRequest

client = HandoffClient()
request = HandoffRequest(
    from_agent="producer-1",
    to_agent="reviewer-1",
    reason="Needs security review",
    context_snapshot=b"...",
    capabilities_required=["security-review"],
)

response = client.request_handoff(request)
if response.accepted and can_handle(request.capabilities_required):
    client.accept_handoff(response.handoff_id)
    context = deserialize_context(request.context_snapshot)
    process_handoff_work(context)
else:
    client.reject_handoff(
        response.handoff_id,
        reason="Missing required capabilities"
    )
```

### Context Transfer

The `context_snapshot` field carries serialized state necessary for the receiving agent to continue work:

- The originating agent MUST NOT continue work on transferred context after handoff completion.
- Implementations SHOULD define content types for context snapshots.
- Agents SHOULD call `GetPendingHandoffs` periodically after recovery from failures.

---

## 3.11.3 Workflow Orchestration

The Workflow Orchestration pattern enables DAG-based multi-agent task coordination where nodes represent agent-executed steps with explicit dependencies.

### Workflow Structure

```mermaid
graph LR
    subgraph "Workflow DAG"
        A[Parse Input] --> B[Validate]
        B --> C[Transform]
        B --> D[Enrich]
        C --> E[Aggregate]
        D --> E
        E --> F[Output]
    end
```

### Workflow Definition

A `WorkflowDefinition` comprises:

```protobuf
message WorkflowDefinition {
  string workflow_id = 1;          // Unique identifier
  map<string, WorkflowNode> nodes = 2; // Node definitions
  map<string, string> metadata = 3; // Workflow-level configuration
}

message WorkflowNode {
  string node_id = 1;              // Unique within workflow
  string agent_id = 2;             // Responsible agent
  repeated string dependencies = 3; // Must complete before execution
  TriggerType trigger_type = 4;    // Activation mechanism
  map<string, string> input_mapping = 5;  // Workflow state -> node input
  map<string, string> output_mapping = 6; // Node output -> workflow state
}
```

### Node Status Transitions

| Status | Description |
|--------|-------------|
| `PENDING` | The node waits for dependencies to complete. |
| `READY` | All dependencies are satisfied. The node is eligible for execution. |
| `RUNNING` | The node is currently executing. |
| `COMPLETED` | The node finished successfully. |
| `FAILED` | The node encountered an error. |
| `SKIPPED` | The node was bypassed due to conditional logic. |

**Constraint**: Nodes MUST NOT execute until all nodes in their `dependencies` set have reached `COMPLETED` status.

### Trigger Types

| Type | Description |
|------|-------------|
| `EVENT` | The node executes when an external event or message arrives. |
| `SCHEDULE` | The node executes on a time-based schedule (cron-like). |
| `MANUAL` | The node executes when a user explicitly triggers it. |
| `DEPENDENCY` | The node executes when all dependencies complete. This is the default. |

### Workflow Operations

```python
# Python SDK example
from sw4rm.workflow import WorkflowBuilder, WorkflowEngine, TriggerType

builder = WorkflowBuilder("data_pipeline")
builder.add_node("fetch", "fetcher_agent", TriggerType.EVENT)
builder.add_node("transform", "transformer_agent")
builder.add_dependency("fetch", "transform")

workflow = builder.build()

def executor(node, input_data):
    # Replace with real execution logic
    return {"node": node.node_id, "output": input_data}

engine = WorkflowEngine(workflow, executor=executor)
state = engine.execute(initial_data={"input_file": "/data/source.csv"})

for node_id, node_state in state.node_states.items():
    print(f"{node_id}: {node_state.status}")
```

### Input/Output Mapping

Data flows between nodes through shared `workflow_data`:

1. **Before execution**: The system extracts values from `workflow_data` according to `input_mapping`.
2. **After completion**: The system writes node outputs to `workflow_data` according to `output_mapping`.

Example:
```yaml
nodes:
  parse:
    agent_id: "parser-agent"
    output_mapping:
      parsed_records: "records"  # Node output -> workflow state key

  transform:
    agent_id: "transform-agent"
    dependencies: ["parse"]
    input_mapping:
      input_records: "records"   # Workflow state key -> node input
    output_mapping:
      transformed: "results"
```

### DAG Validation and Cycle Detection (v0.5.0)

Implementations MUST validate workflow definitions to ensure they form valid Directed Acyclic Graphs (DAGs). Validation MUST occur during `CreateWorkflow` before the workflow is persisted.

**Cycle Detection:**

1. Implementations MUST detect cycles in the dependency graph before accepting a workflow definition.
2. When a cycle is detected, `CreateWorkflow` MUST fail with `error_code=workflow_cycle_detected`.
3. The error response SHOULD include the nodes involved in the cycle to aid debugging.

**Validation Algorithm:** Implementations SHOULD use topological sort (Kahn's algorithm or DFS-based) to detect cycles. The algorithm MUST complete in O(V + E) time where V is the number of nodes and E is the number of dependency edges.

**Additional Validation Rules:**

- All `node_id` values referenced in `dependencies` MUST exist in the workflow's `nodes` map.
- Self-referential dependencies (a node depending on itself) MUST be rejected.
- Implementations SHOULD warn (but MAY accept) workflows with unreachable nodes.
- A valid workflow MUST have at least one root node (node with empty `dependencies`).

---

## 3.11.4 Three-ID Model

The SW4RM messaging model uses three distinct identifiers to enable reliable message processing with retry safety and correlation tracking.

### Identifier Types

| Identifier | Purpose | Scope | Mutability |
|------------|---------|-------|------------|
| `message_id` | Unique per transmission attempt | Per-attempt | New on each retry |
| `correlation_id` | Links request-response pairs | Conversation/workflow | Stable across related messages |
| `idempotency_token` | Enables exactly-once processing | Retry window | Stable across retries |

### Message ID

- **Format**: The system generates a UUIDv4 per transmission.
- **Purpose**: The ID uniquely identifies each message attempt.
- **Behavior**: The system generates a new `message_id` on every send, including retries.

### Correlation ID

- **Format**: The caller provides a string, typically a UUIDv4.
- **Purpose**: The ID links related messages in a conversation or workflow.
- **Behavior**: Response messages copy the `correlation_id` from the request.

```python
# Request
request = build_envelope(
    message_type=MessageType.DATA,
    correlation_id="workflow-123",
    payload=task_data
)

# Response uses same correlation_id
response = build_envelope(
    message_type=MessageType.DATA,
    correlation_id="workflow-123",  # Same as request
    payload=result_data
)
```

### Idempotency Token

- **Format**: The caller provides a deterministic string.
- **Purpose**: The token enables safe retry of operations.
- **Behavior**: The Router deduplicates messages with the same token within the deduplication window.

```python
# Generate deterministic token for retry safety
token = f"{agent_id}:{task_id}:{content_hash}"

envelope = build_envelope(
    message_type=MessageType.DATA,
    idempotency_token=token,  # Same token on retries
    payload=data
)
```

### Deduplication Window

- The default window is 3600 seconds (1 hour).
- Messages with identical `idempotency_token` within the window return `DUPLICATE_DETECTED`.
- Implementations SHOULD configure the window based on expected retry patterns.

---

## See Also

- [Protocol Specification](index.md) - Core protocol concepts
- [Services Reference](services.md) - Complete service API reference
- [ACK Lifecycle](acks.md) - Acknowledgment handling patterns
- [Messages](messages.md) - Message type specifications
