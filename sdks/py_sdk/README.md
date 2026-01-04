# SW4RM Python SDK

Reference Python SDK for the SW4RM Agentic Protocol. This is one of three SDKs in this repository (Python, Rust, JavaScript) and provides clients, a lightweight runtime, and helpers for ACK lifecycle, worktree/state handling, and more.

## Install

From the repo root (recommended during development):

```bash
python -m pip install -e ".[dev]"
```

## Quick Start with Working Services

🎉 **NEW**: Complete working example with services included! You can now run a full SW4RM setup locally.

### 1. Start the Services

```bash
cd ../../examples/reference-services/
./start_services_local.sh
```

### 2. Test the Setup

```bash
python test_complete_setup.py
```

### 3. Run the Echo Agent

```bash
cd ..
python examples/echo_agent.py --router localhost:50051 --registry localhost:50052
```

You should see:
```
✅ Registered successfully
🚀 Starting message loop for echo-1
```

### 4. Send Test Messages

In another terminal:
```bash
cd examples/reference-services/
python test_complete_setup.py
```

Your echo agent will receive and process the test message!

Runtime-only install (no dev tooling):

```bash
python -m pip install .
```

## Generate Protocol Stubs (dev)

If you plan to modify or regenerate protobuf stubs:

```bash
make protos
```

- Requires `grpcio-tools` (installed via the `dev` extra)
- Generated files live under `sdks/py_sdk/sw4rm/protos`

## Quick Start

```python
import grpc
from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.protos import common_pb2 as common

# Connect to services
router_ch = grpc.insecure_channel("localhost:50051")
registry_ch = grpc.insecure_channel("localhost:50052")
router = RouterClient(router_ch)
registry = RegistryClient(registry_ch)

# Register an agent
registry.register({
    "agent_id": "my-agent",
    "name": "My Agent",
    "description": "Example agent",
    "capabilities": ["processing"],
    "communication_class": common.CommunicationClass.STANDARD,
})

# (optional) Stream incoming messages
for item in router.stream_incoming("my-agent"):
    envelope = item.msg  # protobuf message
    # process envelope...
```

## Client Reference

The Python SDK provides clients for all SW4RM protocol services:

### SchedulerClient

Manages task scheduling and agent execution lifecycle.

```python
from sw4rm.clients.scheduler import SchedulerClient
import grpc

channel = grpc.insecure_channel("localhost:50053")
scheduler = SchedulerClient(channel)

# Submit a task for scheduling
response = scheduler.submit_task(
    agent_id="worker-1",
    task_id="task-123",
    priority=5,  # -19 to 20, higher = more important
    scope="global.resource",  # For conflict detection
    params=b'{"action": "process"}',
    content_type="application/json"
)

# Request preemption of a running task
scheduler.request_preemption(
    agent_id="worker-1",
    task_id="task-123",
    reason="Higher priority task arrived"
)

# Poll activity buffer for completed/failed tasks
from datetime import timedelta
activities = scheduler.poll_activity_buffer(agent_id="worker-1")
for activity in activities.entries:
    print(f"Task {activity.task_id}: {activity.status}")

# Purge completed tasks from activity buffer
scheduler.purge_activity(
    agent_id="worker-1",
    task_ids=["task-123", "task-124"]
)

# Graceful agent shutdown
scheduler.shutdown_agent(
    agent_id="worker-1",
    grace_period=timedelta(seconds=30)
)
```

### WorktreeClient

Manages worktree bindings and state transitions for agents that need file system access.

```python
from sw4rm.clients.worktree import WorktreeClient
import grpc

channel = grpc.insecure_channel("localhost:50062")  # Worktree service port
worktree = WorktreeClient(channel)

# Bind agent to a worktree (UNBOUND -> BOUND_HOME)
worktree.bind(
    agent_id="dev-agent-1",
    repo_id="repo-main",
    worktree_id="wt-feature-123"
)

# Check worktree status
status = worktree.status(agent_id="dev-agent-1")
print(f"State: {status.state}, Worktree: {status.worktree_id}")

# Request switch to different worktree (BOUND_HOME -> SWITCH_PENDING)
worktree.request_switch(
    agent_id="dev-agent-1",
    target_worktree_id="wt-hotfix-456",
    requires_hitl=True  # Human approval required
)

# Approve switch (HITL approval) (SWITCH_PENDING -> BOUND_NON_HOME)
worktree.approve_switch(
    agent_id="dev-agent-1",
    target_worktree_id="wt-hotfix-456",
    ttl_ms=300000  # 5 minute TTL
)

# Or reject switch (SWITCH_PENDING -> BOUND_HOME)
worktree.reject_switch(
    agent_id="dev-agent-1",
    reason="Security policy violation"
)

# Unbind when done (Any -> UNBOUND)
worktree.unbind(agent_id="dev-agent-1")
```

### ToolClient

Executes tool calls with unary and streaming support.

```python
from sw4rm.clients.tool import ToolClient
import grpc

channel = grpc.insecure_channel("localhost:50063")  # Tool service port
tool_client = ToolClient(channel)

# Execute a unary tool call
call_config = {
    "call_id": "call-001",
    "tool_name": "code_analyzer",
    "provider_id": "static-analyzer-v2",
    "args": b'{"file": "main.py"}',
    "content_type": "application/json",
    "policy": {
        "timeout_ms": 5000,
        "max_retries": 2,
        "worktree_required": True
    },
    "stream": False
}

result = tool_client.call(call_config)
print(f"Result: {result.payload}")

# Execute a streaming tool call
call_config["stream"] = True
for frame in tool_client.call_stream(call_config):
    print(f"Frame {frame.sequence}: {frame.payload}")
    if frame.is_final:
        break

# Cancel a running tool call
tool_client.cancel({"call_id": "call-001"})
```

### SchedulerPolicyClient

Manages negotiation policies, profiles, and evaluations.

```python
from sw4rm.clients.scheduler_policy import SchedulerPolicyClient
from sw4rm.policy_types import NegotiationPolicy, PolicyProfile, EffectivePolicy
import grpc

channel = grpc.insecure_channel("localhost:50053")
policy_client = SchedulerPolicyClient(channel)

# Set negotiation policy
policy = NegotiationPolicy(
    max_rounds=5,
    score_threshold=0.75,
    diff_tolerance=0.15,
    round_timeout_ms=60000,
    token_budget_per_round=8000,
    oscillation_limit=3,
    hitl_mode="PauseOnFinalAccept"
)

# Convert to protobuf and set
from sw4rm.protos import policy_pb2
proto_policy = policy_pb2.NegotiationPolicy(
    max_rounds=policy.max_rounds,
    score_threshold=policy.score_threshold,
    # ... other fields
)
policy_client.set_negotiation_policy(proto_policy)

# Get current policy
current_policy = policy_client.get_negotiation_policy()

# Get effective policy for a negotiation
effective = policy_client.get_effective_policy(negotiation_id="neg-456")

# Submit evaluation report
from sw4rm.policy_types import EvaluationReport
report = EvaluationReport(
    negotiation_id="neg-456",
    round_number=2,
    scores={"quality": 8.5, "security": 9.0},
    summary="Good progress, minor issues addressed"
)
# Convert to protobuf and submit
policy_client.submit_evaluation(negotiation_id="neg-456", report=report)

# HITL action
policy_client.hitl_action(
    negotiation_id="neg-456",
    action="approve",
    rationale="Manual review completed, looks good"
)
```

### NegotiationClient

Manages multi-agent negotiation sessions for collaborative decision-making.

```python
from sw4rm.clients.negotiation import NegotiationClient
import grpc

channel = grpc.insecure_channel("localhost:50064")  # Negotiation service port
neg_client = NegotiationClient(channel)

# Open a negotiation session
neg_client.open(
    negotiation_id="neg-feature-design",
    correlation_id="workflow-789",
    topic="Feature API Design",
    participants=["architect-1", "security-agent", "reviewer-1"],
    intensity=2,  # MEDIUM debate intensity
    debate_timeout_seconds=300
)

# Submit initial proposal
neg_client.propose(
    negotiation_id="neg-feature-design",
    from_agent="architect-1",
    content_type="application/json",
    payload=b'{"endpoint": "/api/v2/users", "method": "POST"}'
)

# Submit counter-proposal
neg_client.counter(
    negotiation_id="neg-feature-design",
    from_agent="security-agent",
    content_type="application/json",
    payload=b'{"endpoint": "/api/v2/users", "method": "POST", "auth": "required"}'
)

# Evaluate proposal
neg_client.evaluate(
    negotiation_id="neg-feature-design",
    from_agent="reviewer-1",
    confidence_score=0.85,
    notes="Looks good with auth requirement"
)

# Make final decision
neg_client.decide(
    negotiation_id="neg-feature-design",
    decided_by="architect-1",
    content_type="application/json",
    result=b'{"endpoint": "/api/v2/users", "method": "POST", "auth": "required", "approved": true}'
)

# Abort if needed
neg_client.abort(
    negotiation_id="neg-feature-design",
    reason="Requirements changed"
)
```

## Agent Runtime

The SDK provides a state machine-based agent runtime for building robust agents.

```python
from sw4rm.runtime.agent import Agent, AgentState

class MyWorkerAgent(Agent):
    def on_state_change(self, old_state: int, new_state: int) -> None:
        print(f"State: {AgentState.name(old_state)} -> {AgentState.name(new_state)}")

    def on_scheduled(self, task_id: str) -> None:
        print(f"Scheduled for task: {task_id}")

    def on_preempt_request(self, reason: str) -> None:
        print(f"Preemption requested: {reason}")
        # Save state and prepare to yield

    def on_suspend(self) -> None:
        # Persist state before suspension
        self.save_checkpoint()

    def on_resume(self) -> None:
        # Restore state after resumption
        self.load_checkpoint()

# Create and initialize agent
agent = MyWorkerAgent("worker-1", "My Worker")
assert agent.state == AgentState.INITIALIZING

# Start the agent
agent.start()
assert agent.state == AgentState.RUNNABLE

# Simulate scheduler assigning a task
agent.schedule("task-001")
assert agent.state == AgentState.SCHEDULED

# Begin execution
agent.run()
assert agent.state == AgentState.RUNNING

# Check for preemption in work loop
while not agent.safe_point():
    # Do work
    process_item()

# Critical section that cannot be preempted
with agent.non_preemptible(deadline_ms=5000):
    perform_critical_operation()

# Wait for external input
agent.wait()
assert agent.state == AgentState.WAITING

# Resume after receiving input
agent.run()

# Complete the task
agent.complete()
assert agent.state == AgentState.COMPLETED
```

### State Machine

The agent runtime implements a 12-state lifecycle state machine:

- INITIALIZING: Agent is being set up
- RUNNABLE: Ready to be scheduled
- SCHEDULED: Assigned a task
- RUNNING: Actively executing
- WAITING: Waiting for external input
- WAITING_RESOURCES: Waiting for resources
- SUSPENDED: Preempted/suspended
- RESUMED: Resuming from suspension
- COMPLETED: Successfully finished
- FAILED: Encountered a failure
- SHUTTING_DOWN: Shutting down
- RECOVERING: Recovering from failure

Valid transitions are enforced automatically. See the implementation plan for the complete transition matrix.

## Advanced Features

### NegotiationRoomClient

Implements the producer-critic-coordinator pattern for multi-agent artifact approval.

```python
from sw4rm.clients import NegotiationRoomClient
from sw4rm.negotiation_types import (
    NegotiationProposal,
    NegotiationVote,
    ArtifactType,
    DecisionOutcome,
)

client = NegotiationRoomClient()

# Producer submits an artifact for review
proposal = NegotiationProposal(
    artifact_type=ArtifactType.CODE,
    artifact_id="code-review-123",
    producer_id="developer-agent",
    artifact=b'def hello(): return "world"',
    artifact_content_type="text/x-python",
    requested_critics=["security-critic", "style-critic"],
    negotiation_room_id="room-1"
)
artifact_id = client.submit_proposal(proposal)

# Critics submit votes
vote = NegotiationVote(
    artifact_id=artifact_id,
    critic_id="security-critic",
    score=8.5,
    passed=True,
    confidence=0.9,
    strengths=["No security vulnerabilities"],
    weaknesses=["Missing input validation"],
    recommendations=["Add type hints"]
)
client.submit_vote(vote)

# Coordinator retrieves votes and makes decision
votes = client.get_votes(artifact_id)
decision = client.wait_for_decision(artifact_id, timeout_s=30.0)
```

### Workflow Engine

DAG-based workflow orchestration for multi-agent pipelines.

> **Note:** `WorkflowClient` is also available via `from sw4rm.clients import WorkflowClient` for SDK parity with Rust/JS. It is an alias for `WorkflowEngine`.

```python
from sw4rm.workflow import WorkflowBuilder, WorkflowEngine, TriggerType
# Or: from sw4rm.clients import WorkflowClient  # Same as WorkflowEngine

# Build a workflow DAG
builder = WorkflowBuilder("data_pipeline")
builder.add_node("fetch", "fetcher-agent")
builder.add_node("validate", "validator-agent")
builder.add_node("process", "processor-agent")
builder.add_node("store", "storage-agent")

# Define dependencies (creates DAG edges)
builder.add_dependency("fetch", "validate")
builder.add_dependency("validate", "process")
builder.add_dependency("process", "store")

# Set triggers
builder.set_trigger("fetch", TriggerType.MANUAL)

# Build immutable workflow definition
workflow = builder.build()

# Execute with custom executor
def my_executor(node_id: str, agent_id: str, input_data: dict) -> dict:
    # Your agent execution logic here
    return {"result": f"processed by {agent_id}"}

engine = WorkflowEngine(workflow, executor=my_executor)
final_state = engine.execute(initial_data={"input": "raw_data"})

# Check results
for node_id, node_state in final_state.node_states.items():
    print(f"{node_id}: {node_state.status} - {node_state.output}")
```

### Voting and Aggregation

Confidence-weighted voting strategies for negotiation decisions.

```python
from sw4rm.voting import (
    VotingAggregator,
    ConfidenceWeightedAggregator,
    SimpleAverageAggregator,
    MajorityVoteAggregator,
    BordaCountAggregator,
)
from sw4rm.negotiation_types import NegotiationVote

# Create votes from critics
votes = [
    NegotiationVote(
        artifact_id="art-1", critic_id="c1",
        score=8.0, passed=True, confidence=0.9
    ),
    NegotiationVote(
        artifact_id="art-1", critic_id="c2",
        score=6.0, passed=True, confidence=0.7
    ),
    NegotiationVote(
        artifact_id="art-1", critic_id="c3",
        score=9.0, passed=True, confidence=0.95
    ),
]

# Use confidence-weighted aggregation (recommended)
aggregator = VotingAggregator(ConfidenceWeightedAggregator())
result = aggregator.aggregate(votes)
print(f"Weighted score: {result.mean:.2f}")

# Detect consensus or polarization
if aggregator.detect_polarization(votes):
    print("Critics strongly disagree - escalate to HITL")
elif aggregator.detect_consensus(votes, threshold=0.8):
    print("Strong consensus reached")

# Get comprehensive summary
summary = aggregator.get_vote_summary(votes)
print(f"Entropy: {summary['entropy']:.2f}")
```

### Policy Store

Versioned policy storage with immutable snapshots.

```python
from sw4rm.policy_store import InMemoryPolicyStore, JSONFilePolicyStore
from sw4rm.policy_types import EffectivePolicy, NegotiationPolicy

# Create a policy
policy = EffectivePolicy(
    policy_id="prod-standard",
    negotiation=NegotiationPolicy(
        max_rounds=5,
        score_threshold=0.75,
        auto_approve_threshold=0.95
    )
)

# In-memory store (for testing)
store = InMemoryPolicyStore()
policy_id = store.save_policy(policy)

# Retrieve latest version
retrieved = store.get_policy(policy_id)

# Get version history
history = store.get_policy_history(policy_id)
for version in history:
    print(f"Version: {version.version}")

# Persistent JSON store
persistent_store = JSONFilePolicyStore("/path/to/policies")
persistent_store.save_policy(policy)
```

### Handoff Protocol

Agent-to-agent task handoff with context preservation.

```python
from sw4rm.clients import HandoffClient
from sw4rm.handoff import (
    HandoffRequest,
    HandoffContext,
    serialize_context,
)

client = HandoffClient()

# Create handoff context
context = HandoffContext(
    conversation_history=[
        {"role": "user", "content": "Analyze this code"},
        {"role": "assistant", "content": "I see a Python file..."},
    ],
    tool_states={"current_file": "main.py"},
    metadata={"task_type": "code_review"}
)

# Request handoff to specialist agent
request = HandoffRequest(
    from_agent="generalist-agent",
    to_agent="security-specialist",
    reason="Security analysis required",
    context_snapshot=serialize_context(context),
    capabilities_required=["security_analysis", "vulnerability_detection"]
)

response = client.request_handoff(request)
if response.accepted:
    print(f"Handoff accepted by {response.accepting_agent}")
```

### Content Types

Semantic content type registry for message validation.

```python
from sw4rm.content_types import (
    ContentTypeRegistry,
    SCHEDULER_SEED,
    SCHEDULER_COMMAND,
    AGENT_REPORT,
    NEGOTIATION_PROPOSAL,
)

registry = ContentTypeRegistry()

# Register schema for validation
seed_schema = {
    "type": "object",
    "properties": {"seed": {"type": "string"}},
    "required": ["seed"]
}
registry.register(SCHEDULER_SEED, seed_schema)

# Validate payloads
is_valid = registry.validate(SCHEDULER_SEED, b'{"seed": "task-123"}')

# Parse content type with version
base_type, params = registry.parse("application/vnd.sw4rm.scheduler.seed+json;v=1")
print(f"Version: {params.get('v')}")  # "1"
```

### Cross-Cutting Concerns

The SDK provides structured logging, distributed tracing, and feature flags.

```python
# Structured logging
from sw4rm.logging import get_logger, LogContext

logger = get_logger("my_agent")
with LogContext(correlation_id="wf-123", agent_id="agent-1"):
    logger.info("Processing task", extra={"task_id": "t-456"})

# Distributed tracing
from sw4rm.tracing import Tracer, SpanContext

tracer = Tracer(service_name="my-agent")
with tracer.start_span("process_message") as span:
    span.set_attribute("message_type", "DATA")
    # ... do work ...

# Feature flags
from sw4rm.feature_flags import FeatureFlags

flags = FeatureFlags()
flags.set("enable_caching", True)
flags.set("max_retries", 3)

if flags.is_enabled("enable_caching"):
    # Use cache
    pass
```

## Troubleshooting

### Protobuf Stubs Not Generated

If you see errors like "Protobuf stubs not generated. Run `make protos`":

```bash
# Regenerate protobuf stubs
make protos

# Or manually with protoc
python -m grpc_tools.protoc \
    --python_out=sw4rm/protos \
    --grpc_python_out=sw4rm/protos \
    --proto_path=../../protos \
    ../../protos/*.proto
```

### Invalid State Transition

If you encounter `StateTransitionError`, check that your state transitions follow the valid transition matrix. For example:

```python
# ERROR: Cannot go directly from INITIALIZING to RUNNING
agent = Agent("id", "name")
agent.run()  # StateTransitionError!

# CORRECT: Must go through RUNNABLE and SCHEDULED first
agent = Agent("id", "name")
agent.start()           # INITIALIZING -> RUNNABLE
agent.schedule("t1")    # RUNNABLE -> SCHEDULED
agent.run()             # SCHEDULED -> RUNNING
```

### gRPC Connection Errors

Ensure services are running and accessible:

```bash
# Check if services are up
nc -zv localhost 50051  # Router
nc -zv localhost 50052  # Registry
nc -zv localhost 50053  # Scheduler
nc -zv localhost 50062  # Worktree
nc -zv localhost 50063  # Tool
nc -zv localhost 50064  # Negotiation

# Start reference services
cd ../../examples/reference-services/
./start_services_local.sh
```

### Priority Validation Error

Task priority must be in range -19 to 20:

```python
# ERROR: Priority out of range
scheduler.submit_task(agent_id="w1", task_id="t1", priority=25)  # ValueError!

# CORRECT: Use valid priority
scheduler.submit_task(agent_id="w1", task_id="t1", priority=10)
```

### Missing Type Hints

If your IDE complains about missing types, ensure you have the latest stubs:

```bash
pip install -e ".[dev]"
make protos
```

## Operational Contracts

For production deployments, see the **[Operational Contracts](../docs/OPERATIONAL_CONTRACTS.md)** documentation, which defines:

- Connection timeouts and keep-alive settings
- Retry policies and error handling
- Data consistency guarantees
- Idempotency contracts
- State persistence guarantees

These are protocol-level contracts that all SW4RM SDKs honor.

## Links

- Top-level README (overview and API): `../../README.md`
- Quickstart for running local services: `../../QUICKSTART.md`
- Operational Contracts: `../docs/OPERATIONAL_CONTRACTS.md`
- Rust SDK: `../rust_sdk/README.md`
- JavaScript SDK: `../js_sdk/README.md`
