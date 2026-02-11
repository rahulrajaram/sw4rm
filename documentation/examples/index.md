# 4. Examples

Comprehensive examples demonstrating SW4RM SDK usage across Python, JavaScript/TypeScript, and Rust implementations. For domain-specific application patterns, see [Use Cases](use-cases.md).

## 4.1. LLM-Integrated Multi-Agent Systems {#41-llm-integrated-multi-agent-systems}

**Real-world examples** showing agents using Claude (Anthropic) for reasoning and task execution.

<div class="grid cards" markdown>

-   :material-robot-outline:{ .lg .middle } **Backend Agent + Frontend Agent**

    ---

    **Two-agent system with LLM orchestration**: Scheduler dispatches tasks to specialized agents (frontend/backend) who use Claude CLI to generate code, make decisions, and execute commands.

    **Features:**

    - Uses Claude API for reasoning and code generation
    - CONTROL message orchestration via Scheduler
    - Agents call LLM to confirm/adjust execution commands
    - Generates full-stack applications (backend API + frontend UI)
    - Real file I/O and subprocess execution

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/py_sdk/reference-services/hive) - `client_server_llm/{backend,frontend}_agent.py`
    - [:simple-typescript: TypeScript](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/js_sdk/reference-services/agents) - `{backend,frontend}_agent.ts`
    - [:simple-rust: Rust](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/rust_sdk/reference-services/src/bin) - `{backend,frontend}_agent.rs`

    **Prerequisites:** Install and authenticate the [Claude CLI](https://docs.anthropic.com/claude/docs/claude-cli)

</div>

See the Reference Services section for detailed setup instructions.

## 4.2. SDK Feature Examples {#42-sdk-feature-examples}

**Protocol demonstrations** showing SDK capabilities without LLM dependencies (useful for testing and learning the protocol).

### Basic Examples

<div class="grid cards" markdown>

-   :material-repeat:{ .lg .middle } **Echo Agent**

    ---

    Simple agent demonstrating registration and message echoing

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/echo_agent.py)
    - [:simple-typescript: TypeScript](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/echoAgent.ts)
    - [:simple-rust: Rust](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/echo_agent.rs)

-   :material-robot:{ .lg .middle } **Advanced Agent**

    ---

    Full-featured agent with persistence, worktree management, and ACK lifecycle

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/three_id_demo.py) (Three-ID & ActivityBuffer)
    - [:simple-typescript: TypeScript](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/advancedAgent.ts)
    - [:simple-rust: Rust](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/advanced_agent.rs)

-   :material-test-tube:{ .lg .middle } **Test Client**

    ---

    Client for testing agent functionality with various message types

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/test_client.py)

</div>

### Multi-Agent Patterns

<div class="grid cards" markdown>

-   :material-account-group:{ .lg .middle } **Negotiation Room**

    ---

    Producer-critic-coordinator pattern with confidence-weighted voting

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/negotiation_debate_example.py)
    - [:simple-typescript: TypeScript](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/negotiationRoomExample.ts)
    - [:simple-rust: Rust](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/negotiation_room.rs)

-   :material-transit-transfer:{ .lg .middle } **Agent Handoff**

    ---

    Agent-to-agent task delegation with capability matching and context transfer

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/handoff_example.py)
    - [:simple-typescript: TypeScript](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/handoffExample.ts)
    - [:simple-rust: Rust](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/handoff.rs)

-   :material-sitemap:{ .lg .middle } **Workflow Orchestration**

    ---

    DAG-based workflow with parallel execution and dependency management

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/workflow_orchestration_example.py)
    - [:simple-typescript: TypeScript](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/workflowExample.ts)
    - [:simple-rust: Rust](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/workflow.rs)

</div>

### Advanced Features

<div class="grid cards" markdown>

-   :material-human:{ .lg .middle } **HITL Escalation**

    ---

    Human-in-the-loop decision making for uncertainty and conflict resolution

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/hitl_escalation_example.py)
    - [:simple-typescript: TypeScript](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/hitlEscalation.ts)

-   :material-vote:{ .lg .middle } **Voting & Aggregation**

    ---

    Confidence-weighted voting with multiple aggregation strategies

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/voting_example.py)

-   :material-tools:{ .lg .middle } **Tool Streaming**

    ---

    Streaming tool call execution with real-time progress updates

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/tool_streaming_example.py)

-   :material-identifier:{ .lg .middle } **Three-ID Envelope Model**

    ---

    Message envelope construction with message_id, correlation_id, and idempotency_token

    **Available in:**

    - [:simple-python: Python](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/three_id_demo.py)

-   :material-buffer:{ .lg .middle } **Activity Buffer**

    ---

    Activity tracking with persistence and ACK lifecycle management

    **Available in:**

    - [:simple-rust: Rust](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/activity_demo.rs)

</div>

## 4.3. Running the Examples

### Python Examples

```bash
# Navigate to Python SDK
cd sdks/py_sdk

# Basic echo agent
python examples/echo_agent.py --agent-id echo-1

# Advanced patterns
python examples/negotiation_debate_example.py
python examples/workflow_orchestration_example.py
python examples/handoff_example.py
python examples/hitl_escalation_example.py

# Feature-specific
python examples/voting_example.py
python examples/tool_streaming_example.py
python examples/three_id_demo.py
```

### JavaScript/TypeScript Examples

```bash
# Navigate to JavaScript SDK
cd sdks/js_sdk

# Basic echo agent
npx tsx examples/echoAgent.ts --agent-id echo-1

# Advanced agent with full features
npx tsx examples/advancedAgent.ts --data-dir ./agent_data

# Multi-agent patterns
npx tsx examples/negotiationRoomExample.ts
npx tsx examples/workflowExample.ts
npx tsx examples/handoffExample.ts
npx tsx examples/hitlEscalation.ts
```

### Rust Examples

```bash
# Navigate to Rust SDK
cd sdks/rust_sdk

# Basic echo agent
cargo run --example echo_agent

# Advanced patterns
cargo run --example advanced_agent
cargo run --example negotiation_room
cargo run --example workflow
cargo run --example handoff

# Feature-specific
cargo run --example activity_demo
```

## 4.4. Example Categories

### Core SDK Features

These examples demonstrate fundamental SDK capabilities:

- **Agent Registration**: How to register agents with the registry service
- **Message Routing**: Sending and receiving messages via the router
- **ACK Lifecycle**: Implementing the full acknowledgment state machine
- **Persistence**: Saving and restoring agent state across restarts
- **Worktree Binding**: Managing agent workspace isolation

### Multi-Agent Coordination

These examples show how agents collaborate:

- **Negotiation**: Producer-critic-coordinator pattern with voting
- **Handoff**: Delegating tasks between specialized agents
- **Workflow**: Orchestrating complex multi-step processes
- **HITL**: Escalating decisions to human operators

### Advanced Patterns

These examples demonstrate sophisticated use cases:

- **Confidence-Weighted Voting**: Aggregating decisions with uncertainty
- **Tool Streaming**: Real-time tool execution with progress updates
- **Three-ID Envelope Model**: Message deduplication and correlation
- **Activity Buffer**: Comprehensive message tracking and reconciliation

## 4.5. Prerequisites

Before running examples, ensure you have the appropriate runtime and dependencies:

=== "Python"

    ```bash
    # Python 3.9+
    python --version

    # Install SDK dependencies
    cd sdks/py_sdk
    pip install -e ".[dev]"
    ```

=== "JavaScript/TypeScript"

    ```bash
    # Node.js 20+
    node --version

    # Install SDK dependencies
    cd sdks/js_sdk
    npm install
    npm run build
    ```

=== "Rust"

    ```bash
    # Rust 1.70+
    rustc --version

    # Dependencies are managed by Cargo
    cd sdks/rust_sdk
    cargo build
    ```

## 4.6. Step-by-Step Walkthroughs

Detailed walkthroughs for understanding and extending the Python SDK examples.

### Echo Agent Walkthrough

**File:** `sdks/py_sdk/examples/echo_agent.py`

**Concepts:** Agent registration, message streaming, signal handling, graceful shutdown

#### Prerequisites

- Running Registry service on localhost:50052
- Running Router service on localhost:50051
- Generated protobuf stubs (`make protos`)

#### Step-by-Step

1. **Parse arguments** (lines 31-37) - Agent ID, name, router/registry addresses from command line or environment
2. **Create gRPC channels** (lines 44-45) - Insecure channels to Router and Registry services
3. **Create clients** (lines 47-48) - `RegistryClient` and `RouterClient` instances
4. **Register agent** (lines 51-65) - Submit `AgentDescriptor` with capabilities to Registry
5. **Set up signal handler** (lines 67-73) - Catch SIGINT for graceful shutdown
6. **Stream messages** (lines 76-97) - Use `router.stream_incoming(agent_id)` for message loop
7. **Echo DATA messages** (lines 86-97) - Build response envelope with same payload
8. **Graceful shutdown** (lines 98-105) - Deregister from Registry on exit

#### Key Code Sections

```python
# Registration (lines 51-63)
descriptor = {
    "agent_id": args.agent_id,
    "name": args.name,
    "capabilities": ["echo"],
    "communication_class": 2,  # STANDARD
}
registry.register(descriptor)

# Message loop (lines 76-97)
for item in router.stream_incoming(args.agent_id):
    if stop:
        break
    if msg.message_type == 2:  # DATA
        env = build_envelope(
            producer_id=args.agent_id,
            message_type=2,
            payload=msg.payload,
            correlation_id=msg.correlation_id,
        )
        router.send_message(env)
```

#### Common Issues

| Issue | Solution |
|-------|----------|
| "Protobuf stubs not generated" | Generate protobuf stubs in `sdks/py_sdk/` (command below). |
| Connection refused | Ensure Router/Registry services are running |
| Agent not receiving messages | Verify agent_id matches sender's target |

```bash
make protos
```

---

### Three-ID Demo Walkthrough

**File:** `sdks/py_sdk/examples/three_id_demo.py`

**Concepts:** Message envelope, Three-ID model, deduplication, workflow correlation

#### Prerequisites

- SDK installed (`pip install -e ".[dev]"`)
- No services required (standalone demo)

#### Step-by-Step

1. **Envelope lifecycle** (lines 21-45) - Create envelope, transition through states
2. **Three-ID semantics** (lines 48-101) - Demonstrate message_id vs correlation_id vs idempotency_token
3. **Deduplication** (lines 104-161) - Use ActivityBuffer with idempotency tokens
4. **Workflow correlation** (lines 164-208) - Link messages in a workflow

#### Key Concepts

| ID | Scope | Changes on Retry |
|----|-------|------------------|
| `message_id` | Per-attempt | Yes (new UUID) |
| `correlation_id` | Workflow/session | No (stable) |
| `idempotency_token` | Operation | No (stable for dedup) |

#### Key Code Sections

```python
# Generate idempotency token (lines 60-65)
op_hash = compute_deterministic_hash(operation_params)
idem_token = make_idempotency_token("agent-dev", "git_commit", op_hash)

# Deduplication check (lines 137-149)
existing = buffer.get_by_idempotency_token(token)
if existing:
    if is_terminal_state(existing.state):
        # Return cached result
        ...
    else:
        # Reject - operation in progress
        ...
```

---

### Negotiation Debate Walkthrough

**File:** `sdks/py_sdk/examples/negotiation_debate_example.py`

**Concepts:** Multi-agent negotiation, producer-critic-coordinator pattern, voting, decision policies

#### Prerequisites

- SDK installed (`pip install -e ".[dev]"`)
- No services required (uses in-memory NegotiationRoomClient)

#### Step-by-Step

1. **Create agents** (lines 364-370) - Producer, Critics (with expertise), Coordinator
2. **Submit proposal** (lines 401-406) - Producer creates artifact and requests critics
3. **Critics evaluate** (lines 414-476) - Each critic scores, identifies strengths/weaknesses
4. **Aggregate votes** (lines 483) - Coordinator collects and aggregates votes
5. **Apply policy** (lines 285-334) - Check thresholds, determine outcome
6. **Store decision** (lines 281) - Record decision with full audit trail

#### Decision Policy

| Outcome | Condition |
|---------|-----------|
| APPROVED | `weighted_mean >= 7.0` AND all critics passed |
| REVISION_REQUESTED | `weighted_mean < 5.0` OR any critic failed |
| ESCALATED_TO_HITL | `std_dev > 2.0` (high disagreement) |

#### Key Code Sections

```python
# Producer submits (lines 89-99)
proposal = NegotiationProposal(
    artifact_type=ArtifactType.CODE,
    artifact_id=artifact_id,
    producer_id=self.agent_id,
    artifact=json.dumps(artifact_content).encode(),
    requested_critics=critics,
)
self.room_client.submit_proposal(proposal)

# Critic votes (lines 172-184)
vote = NegotiationVote(
    artifact_id=artifact_id,
    critic_id=self.agent_id,
    score=7.5,
    confidence=0.78,
    passed=True,
    strengths=["..."],
    weaknesses=["..."],
)
self.room_client.submit_vote(vote)

# Coordinator decides (lines 249-283)
votes = self.room_client.get_votes(artifact_id)
aggregated = aggregate_votes(votes)
outcome, reason = self._apply_policy(votes, aggregated)
```

#### Scenarios Demonstrated

1. **Revision Requested** - Security critic fails the artifact
2. **Approved** - All critics pass with high scores
3. **HITL Escalation** - Critics strongly disagree (high std_dev)

---

### Handoff Example Walkthrough

**File:** `sdks/py_sdk/examples/handoff_example.py`

**Concepts:** Agent-to-agent handoff, capability matching, context transfer

#### Prerequisites

- SDK installed
- No services required (standalone demo)

#### Key Flow

1. Source agent determines it needs specialist help
2. Creates `HandoffRequest` with context and required capabilities
3. Target agent evaluates request via `on_handoff_request()`
4. If accepted, target receives context via `on_handoff_received()`
5. Source agent transitions or completes

---

### Workflow Orchestration Walkthrough

**File:** `sdks/py_sdk/examples/workflow_orchestration_example.py`

**Concepts:** DAG workflows, dependency management, parallel execution

#### Key Components

- `WorkflowDefinition` - DAG of workflow nodes
- `WorkflowEngine` - Validates DAG, detects cycles, executes
- `WorkflowNode` - Individual task with dependencies

#### Common Issues

| Issue | Solution |
|-------|----------|
| `CycleDetectedError` | Remove circular dependencies in workflow |
| Node not executing | Check `depends_on` list is correct |

---

### HITL Escalation Walkthrough

**File:** `sdks/py_sdk/examples/hitl_escalation_example.py`

**Concepts:** Human-in-the-loop, escalation triggers, decision waiting

#### Escalation Triggers

| Reason Type | When Used |
|-------------|-----------|
| `CONFLICT` | Agents cannot reach consensus |
| `SECURITY_APPROVAL` | Action requires security review |
| `TASK_ESCALATION` | Complexity exceeds agent capability |
| `DEBATE_DEADLOCK` | Negotiation cannot resolve |

---

## 4.7. Example READMEs

Each SDK has comprehensive README files in the examples directory:

- [Python Examples README](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/)
- [JavaScript Examples README](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/README.md)
- [Rust Examples README](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/README.md)

These READMEs provide:

- Detailed descriptions of each example
- Command-line arguments and environment variables
- Prerequisites and service requirements
- Troubleshooting tips
- Feature matrices showing SDK component usage

## 4.7. Reference Services

Many examples require SW4RM reference services to be running. See the reference services documentation:

- [Python Reference Services](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/py_sdk/reference-services)
- [JavaScript Reference Services](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/js_sdk/reference-services)
- [Rust Reference Services](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/rust_sdk/reference-services)

Quick start:

```bash
# Python services
cd sdks/py_sdk/reference-services
./start_services.sh

# JavaScript services
cd sdks/js_sdk/reference-services
./start_services.sh

# Rust services
cd sdks/rust_sdk/reference-services
./start_services.sh
```
