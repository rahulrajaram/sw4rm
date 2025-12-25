# SW4RM Workflow Orchestration

Multi-agent workflow orchestration for the SW4RM Protocol, inspired by CrewAI Flows. Define and execute complex agent workflows as directed acyclic graphs (DAGs) with dependencies, triggers, and state management.

## Overview

The workflow module provides:

- **WorkflowBuilder**: Fluent API for constructing workflow definitions
- **WorkflowEngine**: Execution engine with DAG validation and orchestration
- **WorkflowDefinition**: Immutable workflow structure with nodes and dependencies
- **WorkflowState**: Mutable runtime execution state with results and data passing

## Core Features

### 1. DAG Validation
- Automatic cycle detection using depth-first search
- Validation of dependency references
- Ensures workflow is executable

### 2. Topological Sort
- Computes valid execution order respecting all dependencies
- Uses Kahn's algorithm for deterministic ordering

### 3. Parallel Execution Support
- Identifies nodes that can run in parallel
- Execution plan shows parallelizable stages
- `get_runnable_nodes()` returns nodes ready for concurrent execution

### 4. Data Passing
- Input/output mappings between nodes
- Shared workflow state for inter-node communication
- Type-safe data flow

### 5. Checkpoint/Resume
- Save workflow state at any point
- Resume from checkpoint, skipping completed nodes
- Support for long-running workflows

## Quick Start

### Basic Linear Workflow

```python
from sw4rm.workflow import WorkflowBuilder, WorkflowEngine

# Build workflow
builder = WorkflowBuilder("data_pipeline")
builder.add_node("fetch", "fetcher_agent")
builder.add_node("process", "processor_agent")
builder.add_node("store", "storage_agent")
builder.add_dependency("fetch", "process")
builder.add_dependency("process", "store")

workflow = builder.build()

# Define executor
def my_executor(node, input_data):
    # Execute the agent for this node
    return {"result": "completed"}

# Execute
engine = WorkflowEngine(workflow, executor=my_executor)
state = engine.execute()
```

### Parallel Workflow

```python
# Diamond pattern with parallel branches
builder = WorkflowBuilder("parallel_flow")
builder.add_node("start", "starter")
builder.add_node("branch_a", "agent_a")
builder.add_node("branch_b", "agent_b")
builder.add_node("combine", "combiner")

builder.add_dependency("start", "branch_a")
builder.add_dependency("start", "branch_b")
builder.add_dependency("branch_a", "combine")
builder.add_dependency("branch_b", "combine")

workflow = builder.build()

# Check execution plan
engine = WorkflowEngine(workflow)
plan = engine.get_execution_plan()
# plan = [{"start"}, {"branch_a", "branch_b"}, {"combine"}]
```

### Data Passing Between Nodes

```python
builder = WorkflowBuilder("data_flow")
builder.add_node("producer", "producer_agent")
builder.add_node("consumer", "consumer_agent")
builder.add_dependency("producer", "consumer")

# Configure data mappings
builder.set_output_mapping("producer", {"result": "shared_data"})
builder.set_input_mapping("consumer", {"input": "shared_data"})

workflow = builder.build()

def data_executor(node, input_data):
    if node.node_id == "producer":
        return {"result": [1, 2, 3, 4, 5]}
    elif node.node_id == "consumer":
        data = input_data.get("input", [])
        return {"processed": [x * 2 for x in data]}
    return {}

engine = WorkflowEngine(workflow, executor=data_executor)
state = engine.execute()

# Access shared data
print(state.shared_data["shared_data"])  # [1, 2, 3, 4, 5]
```

## API Reference

### WorkflowBuilder

Fluent API for building workflows:

```python
builder = WorkflowBuilder("my_workflow")

# Add nodes
builder.add_node(node_id, agent_id, trigger_type=TriggerType.EVENT)

# Add dependencies
builder.add_dependency(from_node, to_node)
builder.add_dependencies([from_node1, from_node2], to_node)

# Configure I/O mappings
builder.set_input_mapping(node_id, {"param": "state_key"})
builder.set_output_mapping(node_id, {"output_key": "state_key"})

# Set triggers and metadata
builder.set_trigger(node_id, TriggerType.MANUAL)
builder.set_node_metadata(node_id, {"timeout": 5000})
builder.set_workflow_metadata({"version": "1.0"})

# Build and validate
workflow = builder.build(validate=True)
```

### WorkflowEngine

Execution engine:

```python
engine = WorkflowEngine(workflow, executor=my_executor)

# Validate DAG (happens automatically in constructor)
# Raises CycleDetectedError if cycles found

# Get execution information
order = engine.topological_sort()  # List of node_ids in order
plan = engine.get_execution_plan()  # List of parallel stages
runnable = engine.get_runnable_nodes(state)  # Nodes ready to run

# Check node readiness
is_ready = engine.is_node_ready(node_id, state)

# Execute workflow
state = engine.execute(initial_data={"key": "value"})

# Resume from checkpoint
state = engine.resume_from_checkpoint(checkpoint_state)
```

### WorkflowDefinition

Immutable workflow structure:

```python
workflow.workflow_id  # Workflow identifier
workflow.nodes  # Dict of node_id -> WorkflowNode
workflow.metadata  # Workflow metadata

workflow.get_node(node_id)  # Get specific node
workflow.get_root_nodes()  # Nodes with no dependencies
workflow.get_leaf_nodes()  # Nodes not depended upon
```

### WorkflowState

Mutable execution state:

```python
state.workflow_id  # Workflow identifier
state.node_states  # Dict of node_id -> NodeState
state.shared_data  # Shared key-value store
state.checkpoint_data  # Checkpoint data
state.metadata  # Runtime metadata

state.get_node_state(node_id)  # Get node execution state
state.is_completed()  # All nodes in terminal states
state.has_failures()  # Any nodes failed
state.get_completed_nodes()  # Set of completed node_ids
state.get_failed_nodes()  # Set of failed node_ids
```

### NodeState

Node execution state:

```python
node_state.node_id  # Node identifier
node_state.status  # NodeStatus enum
node_state.result  # Output data (if completed)
node_state.error  # Error message (if failed)
node_state.start_time  # Start timestamp (ms)
node_state.end_time  # End timestamp (ms)

node_state.is_terminal  # In terminal state?
node_state.duration_ms  # Execution duration
```

### Enums

```python
# Node execution status
class NodeStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"

# Trigger types
class TriggerType(str, Enum):
    EVENT = "event"
    SCHEDULE = "schedule"
    MANUAL = "manual"
```

## Advanced Usage

### Checkpoint and Resume

```python
# Execute and save checkpoint
state = engine.execute()
# ... save state.checkpoint_data to disk ...

# Later, resume from checkpoint
# ... load checkpoint_data ...
restored_state = WorkflowState(
    workflow_id=workflow.workflow_id,
    checkpoint_data=checkpoint_data
)
# Restore node states
for node_id, node_data in checkpoint_data["nodes"].items():
    restored_state.node_states[node_id] = NodeState(**node_data)

final_state = engine.resume_from_checkpoint(restored_state)
```

### Custom Executors

```python
def custom_executor(node: WorkflowNode, input_data: dict) -> dict:
    """Execute a workflow node.

    Args:
        node: The node to execute with agent_id and metadata
        input_data: Input parameters mapped from workflow state

    Returns:
        Output dictionary to be mapped to workflow state

    Raises:
        Exception: Any execution error (node will be marked FAILED)
    """
    # Use node.metadata for configuration
    timeout = node.metadata.get("timeout", 5000)
    retries = node.metadata.get("retries", 0)

    # Execute the agent
    result = execute_agent(node.agent_id, input_data, timeout, retries)

    return result

engine = WorkflowEngine(workflow, executor=custom_executor)
```

### Error Handling

```python
try:
    state = engine.execute()
except CycleDetectedError as e:
    print(f"Workflow has cycle: {e.cycle_path}")
except WorkflowValidationError as e:
    print(f"Validation failed: {e}")
except Exception as e:
    # Individual node failure
    print(f"Execution failed: {e}")
    # Check state to see which nodes failed
    failed = state.get_failed_nodes()
    for node_id in failed:
        node_state = state.get_node_state(node_id)
        print(f"  {node_id}: {node_state.error}")
```

## Design Patterns

### Fan-Out/Fan-In

Process data in parallel and combine results:

```python
builder.add_node("split", "splitter")
builder.add_node("process_1", "processor")
builder.add_node("process_2", "processor")
builder.add_node("process_3", "processor")
builder.add_node("combine", "combiner")

builder.add_dependency("split", "process_1")
builder.add_dependency("split", "process_2")
builder.add_dependency("split", "process_3")
builder.add_dependencies(["process_1", "process_2", "process_3"], "combine")
```

### Pipeline

Sequential processing stages:

```python
stages = ["ingest", "clean", "transform", "validate", "store"]
for i in range(len(stages)):
    builder.add_node(stages[i], f"{stages[i]}_agent")
    if i > 0:
        builder.add_dependency(stages[i-1], stages[i])
```

### Conditional Branching

Use node metadata and executor logic:

```python
builder.add_node("check", "checker_agent")
builder.add_node("path_a", "agent_a")
builder.add_node("path_b", "agent_b")

def conditional_executor(node, input_data):
    if node.node_id == "check":
        return {"should_use_path_a": True}
    elif node.node_id == "path_a":
        # Only execute if condition met
        if input_data.get("should_use_path_a"):
            return {"result": "path_a_result"}
    # ... similar for path_b
```

## Testing

Run the test suite:

```bash
pytest tests/test_workflow_engine.py -v
```

Test coverage includes:
- DAG validation and cycle detection
- Topological sort correctness
- Parallel node identification
- Workflow execution
- Data passing
- Checkpoint/resume
- Builder API
- Error handling

## Examples

See `example.py` for comprehensive examples demonstrating:
1. Basic linear workflows
2. Parallel execution
3. Data passing between nodes
4. Complex multi-agent workflows
5. Checkpoint and resume

Run examples:

```bash
python -m sw4rm.workflow.example
```

## Implementation Notes

### DAG Validation
Uses depth-first search with recursion stack tracking to detect cycles in O(V + E) time.

### Topological Sort
Uses Kahn's algorithm for stable, deterministic ordering in O(V + E) time.

### Parallel Execution
The current implementation executes nodes sequentially in topological order. The `get_runnable_nodes()` and `get_execution_plan()` methods identify parallelizable nodes, but actual parallel execution would require a concurrent executor (future enhancement).

### State Management
WorkflowDefinition is immutable for thread-safety and reproducibility. WorkflowState is mutable to track execution progress. Use separate WorkflowState instances for concurrent executions of the same workflow.

## License

Copyright 2025 Rahul Rajaram

Licensed under the Apache License, Version 2.0
