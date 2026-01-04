# 4. Examples

Comprehensive examples demonstrating SW4RM SDK usage across Python, JavaScript/TypeScript, and Rust implementations.

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

See [Reference Services](#46-reference-services) for detailed setup instructions.

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

## 4.6. Example READMEs

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
