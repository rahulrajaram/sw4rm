# 6.16. Workflow Client

The Workflow Client orchestrates DAG-based multi-agent workflows. Use it to:

- Define workflows as directed acyclic graphs (DAGs) of agent nodes.
- Start workflow instances and track node-level execution state.
- Cancel workflows or update node status during execution.
- Validate dependencies and detect cycles before execution.

Current SDKs provide in-memory implementations. JavaScript/TypeScript and Rust store definitions and instances locally, while Python's `WorkflowClient` is an alias for the in-process `WorkflowEngine`. A gRPC `WorkflowService` is defined in `protos/workflow.proto` but is not yet wired into SDK clients.

## 6.16.1. Service Overview

The service exposes four RPCs:

- `CreateWorkflow(CreateWorkflowRequest) -> CreateWorkflowResponse`
- `StartWorkflow(StartWorkflowRequest) -> StartWorkflowResponse`
- `GetWorkflowState(GetWorkflowStateRequest) -> GetWorkflowStateResponse`
- `ResumeWorkflow(ResumeWorkflowRequest) -> ResumeWorkflowResponse`

Field names are snake_case in Python/Rust and camelCase in JS/TS.

### NodeStatus values

| Value | Description |
|-------|-------------|
| `PENDING` | Node waiting for dependencies. |
| `READY` | Node ready to execute (JS/TS + Rust). |
| `RUNNING` | Node currently executing. |
| `COMPLETED` | Node finished successfully. |
| `FAILED` | Node encountered an error. |
| `SKIPPED` | Node skipped due to conditional logic. |

### TriggerType values

| Value | Description |
|-------|-------------|
| `EVENT` | Triggered by specific events. |
| `SCHEDULE` | Triggered on a schedule (cron-like). |
| `MANUAL` | Triggered by explicit user action. |
| `DEPENDENCY` | Triggered by dependency completion (JS/TS + Rust). |

### WorkflowDefinition fields

| Field | Type | Description |
|-------|------|-------------|
| `workflow_id` | string | Unique workflow identifier. |
| `nodes` | map<string, WorkflowNode> | Node definitions keyed by node_id. |
| `created_at` | timestamp | Creation time (auto-set if omitted). |
| `metadata` | map<string, string> | Workflow-level metadata. |

### WorkflowState / WorkflowInstance fields

| Field | Type | Description |
|-------|------|-------------|
| `workflow_id` | string | Workflow identifier. |
| `node_states` | map<string, NodeState> | Node execution status map. |
| `workflow_data` | string | Shared workflow data (JSON string). |
| `started_at` | timestamp | Start time. |
| `completed_at` | timestamp | Completion time. |
| `metadata` | map<string, string> | Runtime metadata. |

## 6.16.2. Constructors

### Python

`WorkflowClient(workflow: WorkflowDefinition, executor: Callable[[WorkflowNode, dict], dict] | None = None)`

- `workflow`: The workflow definition to execute in-process.
- `executor`: Optional callable to execute nodes; if omitted, nodes are marked completed without execution.

### JavaScript/TypeScript

`new WorkflowClient()`

- In-memory client that stores definitions and instances in-process.

### Rust

`WorkflowClient::new() -> WorkflowClient`

- In-memory client backed by an internal workflow store.

## 6.16.3. Key Methods

Python's `WorkflowClient` is an engine for a single workflow definition, while JS/TS and Rust expose a registry of definitions and instances. The sections below call out the available methods per SDK.

### Definition registry (JavaScript/TypeScript + Rust)

### `create_workflow` / `createWorkflow`

**JavaScript/TypeScript**
`createWorkflow(definition: WorkflowDefinition): Promise<string>`

**Rust**
`create_workflow(&self, definition: WorkflowDefinition) -> Result<String>`

### `start_workflow` / `startWorkflow`

**JavaScript/TypeScript**
`startWorkflow(workflowId: string, initialData?: string, metadata?: Record<string, string>): Promise<WorkflowInstance>`

**Rust**
`start_workflow(&self, workflow_id: &str) -> Result<WorkflowInstance>`

### `get_workflow_status` / `getWorkflowStatus`

**JavaScript/TypeScript**
`getWorkflowStatus(instanceId: string): Promise<WorkflowInstance>`

**Rust**
`get_workflow_status(&self, instance_id: &str) -> Result<WorkflowInstance>`

### `cancel_workflow` / `cancelWorkflow`

**JavaScript/TypeScript**
`cancelWorkflow(instanceId: string): Promise<void>`

**Rust**
`cancel_workflow(&self, instance_id: &str) -> Result<()>`

### `update_node_state` / `updateNodeState`

**JavaScript/TypeScript**
`updateNodeState(instanceId: string, nodeId: string, status: NodeStatus, output?: string, error?: string): Promise<void>`

**Rust**
`update_node_state(&self, instance_id: &str, node_id: &str, status: NodeStatus, output: Option<String>, error: Option<String>) -> Result<()>`

### `get_workflow_definition` / `getWorkflowDefinition`

**JavaScript/TypeScript**
`getWorkflowDefinition(workflowId: string): Promise<WorkflowDefinition | null>`

**Rust**
`get_workflow_definition(&self, workflow_id: &str) -> Result<Option<WorkflowDefinition>>`

### `list_workflows` / `listWorkflowInstances`

**JavaScript/TypeScript**
`listWorkflowInstances(workflowId: string): Promise<WorkflowInstance[]>`

**Rust**
`list_workflows(&self) -> Result<Vec<String>>`

### Execution engine (Python)

### `execute`

**Python**
`execute(initial_data: dict[str, Any] | None = None, checkpoint_interval: int | None = None) -> WorkflowState`

### `resume_from_checkpoint`

**Python**
`resume_from_checkpoint(state: WorkflowState) -> WorkflowState`

### `get_execution_plan`

**Python**
`get_execution_plan() -> list[set[str]]`

## 6.16.4. Usage Examples

=== "Python"
    ```python
    from sw4rm.clients import WorkflowClient
    from sw4rm.workflow import WorkflowBuilder, TriggerType

    builder = WorkflowBuilder("review_flow")
    builder.add_node("draft", "writer", TriggerType.MANUAL)
    builder.add_node("review", "critic")
    builder.add_dependency("draft", "review")

    workflow = builder.build()
    engine = WorkflowClient(workflow)

    state = engine.execute(initial_data={"doc_id": "doc-1"})
    for node_id, node_state in state.node_states.items():
        print(node_id, node_state.status)
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { WorkflowClient, TriggerType, NodeStatus } from '@sw4rm/js-sdk';

    const client = new WorkflowClient();

    const workflowId = await client.createWorkflow({
      workflowId: 'review-flow',
      nodes: {
        draft: {
          nodeId: 'draft',
          agentId: 'writer',
          dependencies: [],
          triggerType: TriggerType.MANUAL,
          inputMapping: {},
          outputMapping: { draft: 'draft_text' },
          metadata: {},
        },
        review: {
          nodeId: 'review',
          agentId: 'critic',
          dependencies: ['draft'],
          triggerType: TriggerType.DEPENDENCY,
          inputMapping: { draft: 'draft_text' },
          outputMapping: { verdict: 'review_verdict' },
          metadata: {},
        },
      },
      metadata: {},
    });

    const instance = await client.startWorkflow(
      workflowId,
      JSON.stringify({ doc_id: 'doc-1' })
    );

    await client.updateNodeState(
      instance.instanceId,
      'draft',
      NodeStatus.COMPLETED,
      JSON.stringify({ draft: 'ready' })
    );

    const status = await client.getWorkflowStatus(instance.instanceId);
    console.log(status.status, status.nodeStates.review.status);
    ```

=== "Rust"
    ```rust
    use std::collections::HashMap;
    use sw4rm_sdk::clients::workflow::{NodeStatus, TriggerType, WorkflowClient, WorkflowDefinition, WorkflowNode};

    fn main() -> sw4rm_sdk::Result<()> {
        let client = WorkflowClient::new();

        let draft = WorkflowNode::new("draft".to_string(), "writer".to_string())?
            .with_trigger(TriggerType::Manual);
        let review = WorkflowNode::new("review".to_string(), "critic".to_string())?
            .with_dependency("draft".to_string())
            .with_trigger(TriggerType::Dependency);

        let mut nodes = HashMap::new();
        nodes.insert("draft".to_string(), draft);
        nodes.insert("review".to_string(), review);

        let definition = WorkflowDefinition::new("review-flow".to_string(), nodes)?;
        let workflow_id = client.create_workflow(definition)?;
        let instance = client.start_workflow(&workflow_id)?;

        client.update_node_state(
            &instance.instance_id,
            "draft",
            NodeStatus::Completed,
            Some("{\"draft\":\"ready\"}".to_string()),
            None,
        )?;

        Ok(())
    }
    ```

## 6.16.5. Error Handling

- JavaScript/TypeScript throws `WorkflowValidationError` for invalid definitions and `WorkflowCycleError` for cycles; missing workflows or instances raise `WorkflowValidationError`.
- Rust returns `Error::Config` for invalid definitions, missing workflows, and missing instances.
- Python raises `WorkflowValidationError` or `CycleDetectedError` during DAG validation in the engine.
