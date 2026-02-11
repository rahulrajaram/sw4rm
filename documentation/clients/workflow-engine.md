# 6.17. Workflow Engine

The Workflow Engine is the in-process Python runtime that validates and executes
DAG-based workflows. It powers `WorkflowClient` (an alias for `WorkflowEngine`)
and is designed for single-process orchestration with optional data passing
between nodes.

Use the Workflow Engine when you want:

- Local execution of a `WorkflowDefinition` without a remote workflow service.
- Deterministic ordering of DAG nodes and validation (cycle detection).
- Execution planning for parallelizable stages.

## 6.17.1. Overview

The engine operates entirely in-memory and expects a `WorkflowDefinition` built
by `WorkflowBuilder`. Each node can be executed by an optional `executor`
callable that receives the node and prepared input data, returning an output
dictionary that is stored in the workflow's shared state.

During execution, node inputs are assembled from `WorkflowNode.input_mapping`
(workflow state key -> node parameter name). Outputs returned by the executor are
stored into `WorkflowState.shared_data` using `WorkflowNode.output_mapping`
(output key -> workflow state key).

For service-backed workflows, see the [Workflow Client](workflow.md) instead.

## 6.17.2. Constructor

### Python

`WorkflowEngine(workflow: WorkflowDefinition, executor: Callable[[WorkflowNode, dict[str, Any]], dict[str, Any]] | None = None)`

- `workflow`: The immutable workflow definition to execute.
- `executor`: Optional callable invoked for each node. If omitted, nodes are
  marked `COMPLETED` with an empty result.

Initialization validates the DAG structure. Cycle detection uses depth-first
search and raises `CycleDetectedError` with the cycle path (for example,
`A -> B -> A`). Invalid dependency references are rejected earlier when the
`WorkflowDefinition` is created.

**Raises**

- `CycleDetectedError`: If the workflow DAG contains a cycle.
- `ValueError`: If the workflow definition itself is invalid (raised when the
  `WorkflowDefinition` is constructed).

## 6.17.3. Core Methods

### `topological_sort`

`topological_sort() -> list[str]`

Returns a deterministic, dependency-respecting order of node IDs.
The engine uses Kahn's algorithm and sorts each available batch to keep the
order stable across runs.

### `is_node_ready`

`is_node_ready(node_id: str, state: WorkflowState) -> bool`

Returns `True` when the node is `PENDING` and all dependencies have completed.

### `get_runnable_nodes`

`get_runnable_nodes(state: WorkflowState) -> list[str]`

Returns all nodes that are ready to run in parallel based on the current state.

### `execute`

`execute(initial_data: dict[str, Any] | None = None, checkpoint_interval: int | None = None) -> WorkflowState`

Executes nodes in topological order. `initial_data` seeds `state.shared_data`.
`checkpoint_interval` is accepted for API compatibility but is not yet
implemented in the engine.

Each node execution sets `NodeState.start_time`/`end_time` in milliseconds. If
the executor raises, the node is marked `FAILED`, `NodeState.error` captures the
exception string, and the error is re-raised to the caller.

### `resume_from_checkpoint`

`resume_from_checkpoint(state: WorkflowState) -> WorkflowState`

Resumes execution from a previously captured `WorkflowState`, skipping nodes
already marked `COMPLETED`.
Nodes only execute when their dependencies have completed.

### `get_execution_plan`

`get_execution_plan() -> list[set[str]]`

Returns a list of execution stages, where each set contains nodes that can run
in parallel.

If no runnable nodes can be found for a stage, the engine raises
`WorkflowValidationError` because the execution plan cannot advance.

## 6.17.4. Related Types

- `WorkflowDefinition`: Immutable DAG definition containing `WorkflowNode` items.
- `WorkflowState`: Mutable runtime state (`node_states`, `shared_data`, metadata).
- `NodeState`: Execution status and timing for a node.
- `NodeStatus`: `PENDING`, `RUNNING`, `COMPLETED`, `FAILED`, `SKIPPED`.
- `TriggerType`: `EVENT`, `SCHEDULE`, `MANUAL`.

## 6.17.5. Usage Example

=== "Python"
    ```python
    from sw4rm.workflow import WorkflowBuilder, WorkflowEngine, TriggerType

    def executor(node, input_data):
        return {"result": f"ran-{node.node_id}", "input": input_data}

    builder = WorkflowBuilder("review_flow")
    builder.add_node("draft", "writer", TriggerType.MANUAL)
    builder.add_node("review", "critic")
    builder.add_dependency("draft", "review")

    workflow = builder.build()
    engine = WorkflowEngine(workflow, executor=executor)

    state = engine.execute(initial_data={"doc_id": "doc-1"})
    plan = engine.get_execution_plan()
    print(state.workflow_id, plan)
    ```

## 6.17.6. Error Handling

- `WorkflowEngineError`: Base exception for engine-specific errors.
- `CycleDetectedError`: Raised when a cycle is detected during validation.
- `WorkflowValidationError`: Raised for invalid DAGs or execution plans.
- Executor errors are propagated after the node is marked `FAILED`.
