// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * Workflow client for SW4RM.
 *
 * This module provides the WorkflowClient for managing DAG-based workflow
 * orchestration. Workflows enable:
 * - Multi-step task coordination
 * - Dependency-based execution ordering
 * - Node-level state tracking
 * - Context passing between nodes
 *
 * Based on workflow.proto definitions.
 */

/**
 * Status of a workflow node.
 */
export enum NodeStatus {
  NODE_STATUS_UNSPECIFIED = 0,
  /** Node waiting for dependencies */
  PENDING = 1,
  /** Node ready to execute */
  READY = 2,
  /** Node currently executing */
  RUNNING = 3,
  /** Node finished successfully */
  COMPLETED = 4,
  /** Node encountered an error */
  FAILED = 5,
  /** Node skipped due to conditional logic */
  SKIPPED = 6,
}

/**
 * Type of trigger for a workflow node.
 */
export enum TriggerType {
  TRIGGER_TYPE_UNSPECIFIED = 0,
  /** Triggered by specific events */
  EVENT = 1,
  /** Triggered on a schedule (cron-like) */
  SCHEDULE = 2,
  /** Triggered by explicit user action */
  MANUAL = 3,
  /** Triggered by dependency completion */
  DEPENDENCY = 4,
}

/**
 * Status of a workflow instance.
 */
export enum WorkflowStatus {
  WORKFLOW_STATUS_UNSPECIFIED = 0,
  /** Workflow has been created but not started */
  CREATED = 1,
  /** Workflow is currently running */
  RUNNING = 2,
  /** Workflow completed successfully */
  COMPLETED = 3,
  /** Workflow failed with error */
  FAILED = 4,
  /** Workflow was cancelled */
  CANCELLED = 5,
  /** Workflow is paused */
  PAUSED = 6,
}

/**
 * A node in a workflow definition.
 *
 * Represents a single step in the workflow DAG with its dependencies,
 * trigger conditions, and input/output mappings.
 */
export interface WorkflowNode {
  /** Unique identifier for this node */
  nodeId: string;
  /** Identifier of the agent executing this node */
  agentId: string;
  /** Set of node_ids that must complete before this node runs */
  dependencies: string[];
  /** How this node is triggered */
  triggerType: TriggerType;
  /** Maps workflow state keys to node input parameters */
  inputMapping: Record<string, string>;
  /** Maps node output keys to workflow state keys */
  outputMapping: Record<string, string>;
  /** Additional node configuration and context */
  metadata: Record<string, string>;
}

/**
 * A workflow definition.
 *
 * Describes a complete workflow as a DAG of nodes with their
 * dependencies and configuration.
 */
export interface WorkflowDefinition {
  /** Unique identifier for this workflow */
  workflowId: string;
  /** Map of node_id to WorkflowNode */
  nodes: Record<string, WorkflowNode>;
  /** When the workflow was created (ISO-8601 string) */
  createdAt?: string;
  /** Additional workflow-level configuration */
  metadata: Record<string, string>;
}

/**
 * State of a single node during execution.
 */
export interface NodeState {
  /** The node this state belongs to */
  nodeId: string;
  /** Current execution status */
  status: NodeStatus;
  /** When node execution started (ISO-8601 string) */
  startedAt?: string;
  /** When node execution completed (ISO-8601 string) */
  completedAt?: string;
  /** Output data from node execution (JSON string) */
  output?: string;
  /** Error information if node failed */
  error?: string;
}

/**
 * A running instance of a workflow.
 *
 * Tracks the execution state of all nodes and the shared workflow data.
 */
export interface WorkflowInstance {
  /** Identifier of this workflow instance */
  instanceId: string;
  /** Identifier of the workflow definition */
  workflowId: string;
  /** Current status of the workflow */
  status: WorkflowStatus;
  /** Map of node_id to NodeState for tracking execution */
  nodeStates: Record<string, NodeState>;
  /** Shared workflow data (JSON string) */
  workflowData: string;
  /** When the workflow execution started (ISO-8601 string) */
  startedAt?: string;
  /** When the workflow execution completed (ISO-8601 string) */
  completedAt?: string;
  /** Additional runtime metadata */
  metadata: Record<string, string>;
}

/**
 * Error thrown when a workflow operation fails validation.
 */
export class WorkflowValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'WorkflowValidationError';
  }
}

/**
 * Error thrown when a workflow contains a cycle.
 */
export class WorkflowCycleError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'WorkflowCycleError';
  }
}

/**
 * Validates a workflow definition for correctness.
 *
 * Checks that all dependencies reference existing nodes and that
 * the workflow DAG is acyclic.
 *
 * @param definition - The workflow definition to validate
 * @throws WorkflowValidationError if validation fails
 * @throws WorkflowCycleError if the workflow contains a cycle
 */
function validateWorkflowDefinition(definition: WorkflowDefinition): void {
  const nodeIds = new Set(Object.keys(definition.nodes));

  // Check that all dependencies reference existing nodes
  for (const [nodeId, node] of Object.entries(definition.nodes)) {
    for (const dep of node.dependencies) {
      if (!nodeIds.has(dep)) {
        throw new WorkflowValidationError(
          `Node '${nodeId}' has dependency '${dep}' which does not exist`
        );
      }
      if (dep === nodeId) {
        throw new WorkflowCycleError(
          `Node '${nodeId}' has a self-dependency`
        );
      }
    }
  }

  // Check for cycles using DFS
  const visited = new Set<string>();
  const recursionStack = new Set<string>();

  function hasCycle(nodeId: string): boolean {
    if (recursionStack.has(nodeId)) {
      return true;
    }
    if (visited.has(nodeId)) {
      return false;
    }

    visited.add(nodeId);
    recursionStack.add(nodeId);

    const node = definition.nodes[nodeId];
    for (const dep of node.dependencies) {
      if (hasCycle(dep)) {
        return true;
      }
    }

    recursionStack.delete(nodeId);
    return false;
  }

  for (const nodeId of nodeIds) {
    if (hasCycle(nodeId)) {
      throw new WorkflowCycleError(
        `Workflow contains a cycle involving node '${nodeId}'`
      );
    }
  }
}

/**
 * Generates a unique ID for workflow instances.
 */
function generateInstanceId(): string {
  return `wf-${Date.now()}-${Math.random().toString(36).substring(2, 9)}`;
}

/**
 * Client for managing workflow orchestration.
 *
 * Enables creation and execution of DAG-based workflows that coordinate
 * multiple agents. This is an in-memory implementation for Phase 2;
 * future phases will integrate with gRPC services.
 */
export class WorkflowClient {
  private definitions: Map<string, WorkflowDefinition> = new Map();
  private instances: Map<string, WorkflowInstance> = new Map();
  private instancesByWorkflow: Map<string, Set<string>> = new Map();

  /**
   * Create a new workflow from a definition.
   *
   * Validates the workflow definition and stores it for later execution.
   *
   * @param definition - The workflow definition to create
   * @returns The workflow_id of the created workflow
   * @throws WorkflowValidationError if the definition is invalid
   * @throws WorkflowCycleError if the workflow contains a cycle
   *
   * @example
   * ```typescript
   * const client = new WorkflowClient();
   * const definition: WorkflowDefinition = {
   *   workflowId: "review-workflow",
   *   nodes: {
   *     "produce": {
   *       nodeId: "produce",
   *       agentId: "producer-agent",
   *       dependencies: [],
   *       triggerType: TriggerType.MANUAL,
   *       inputMapping: {},
   *       outputMapping: { "artifact": "produced_artifact" },
   *       metadata: {}
   *     },
   *     "review": {
   *       nodeId: "review",
   *       agentId: "critic-agent",
   *       dependencies: ["produce"],
   *       triggerType: TriggerType.DEPENDENCY,
   *       inputMapping: { "artifact": "produced_artifact" },
   *       outputMapping: { "result": "review_result" },
   *       metadata: {}
   *     }
   *   },
   *   metadata: {}
   * };
   * const workflowId = await client.createWorkflow(definition);
   * ```
   */
  async createWorkflow(definition: WorkflowDefinition): Promise<string> {
    // Validate the definition
    validateWorkflowDefinition(definition);

    if (this.definitions.has(definition.workflowId)) {
      throw new WorkflowValidationError(
        `Workflow with ID '${definition.workflowId}' already exists`
      );
    }

    // Set createdAt if not provided
    const definitionWithTimestamp: WorkflowDefinition = {
      ...definition,
      createdAt: definition.createdAt || new Date().toISOString(),
    };

    this.definitions.set(definition.workflowId, definitionWithTimestamp);
    this.instancesByWorkflow.set(definition.workflowId, new Set());

    return definition.workflowId;
  }

  /**
   * Start a new instance of a workflow.
   *
   * Creates a new workflow instance and initializes all nodes to their
   * starting states based on dependencies.
   *
   * @param workflowId - The ID of the workflow to start
   * @param initialData - Optional initial workflow data (JSON string)
   * @param metadata - Optional runtime metadata
   * @returns The created workflow instance
   * @throws WorkflowValidationError if the workflow does not exist
   *
   * @example
   * ```typescript
   * const instance = await client.startWorkflow("review-workflow");
   * console.log(instance.status); // WorkflowStatus.RUNNING
   * ```
   */
  async startWorkflow(
    workflowId: string,
    initialData?: string,
    metadata?: Record<string, string>
  ): Promise<WorkflowInstance> {
    const definition = this.definitions.get(workflowId);
    if (!definition) {
      throw new WorkflowValidationError(
        `Workflow with ID '${workflowId}' does not exist`
      );
    }

    const instanceId = generateInstanceId();
    const now = new Date().toISOString();

    // Initialize node states
    const nodeStates: Record<string, NodeState> = {};
    for (const [nodeId, node] of Object.entries(definition.nodes)) {
      // Nodes with no dependencies start as READY, others start as PENDING
      const status = node.dependencies.length === 0
        ? NodeStatus.READY
        : NodeStatus.PENDING;

      nodeStates[nodeId] = {
        nodeId,
        status,
      };
    }

    const instance: WorkflowInstance = {
      instanceId,
      workflowId,
      status: WorkflowStatus.RUNNING,
      nodeStates,
      workflowData: initialData || '{}',
      startedAt: now,
      metadata: metadata || {},
    };

    this.instances.set(instanceId, instance);
    this.instancesByWorkflow.get(workflowId)!.add(instanceId);

    return instance;
  }

  /**
   * Get the current status of a workflow instance.
   *
   * @param instanceId - The ID of the workflow instance
   * @returns The workflow instance with current state
   * @throws WorkflowValidationError if the instance does not exist
   *
   * @example
   * ```typescript
   * const instance = await client.getWorkflowStatus("wf-123-abc");
   * console.log(instance.status);
   * for (const [nodeId, state] of Object.entries(instance.nodeStates)) {
   *   console.log(`${nodeId}: ${NodeStatus[state.status]}`);
   * }
   * ```
   */
  async getWorkflowStatus(instanceId: string): Promise<WorkflowInstance> {
    const instance = this.instances.get(instanceId);
    if (!instance) {
      throw new WorkflowValidationError(
        `Workflow instance with ID '${instanceId}' does not exist`
      );
    }

    return instance;
  }

  /**
   * Cancel a running workflow instance.
   *
   * Marks the workflow as cancelled and stops any pending nodes.
   *
   * @param instanceId - The ID of the workflow instance to cancel
   * @throws WorkflowValidationError if the instance does not exist
   * @throws WorkflowValidationError if the workflow is not in a cancellable state
   *
   * @example
   * ```typescript
   * await client.cancelWorkflow("wf-123-abc");
   * const instance = await client.getWorkflowStatus("wf-123-abc");
   * console.log(instance.status); // WorkflowStatus.CANCELLED
   * ```
   */
  async cancelWorkflow(instanceId: string): Promise<void> {
    const instance = this.instances.get(instanceId);
    if (!instance) {
      throw new WorkflowValidationError(
        `Workflow instance with ID '${instanceId}' does not exist`
      );
    }

    if (
      instance.status === WorkflowStatus.COMPLETED ||
      instance.status === WorkflowStatus.FAILED ||
      instance.status === WorkflowStatus.CANCELLED
    ) {
      throw new WorkflowValidationError(
        `Workflow instance '${instanceId}' is already in terminal state '${WorkflowStatus[instance.status]}'`
      );
    }

    instance.status = WorkflowStatus.CANCELLED;
    instance.completedAt = new Date().toISOString();

    // Mark all pending/ready nodes as skipped
    for (const nodeState of Object.values(instance.nodeStates)) {
      if (
        nodeState.status === NodeStatus.PENDING ||
        nodeState.status === NodeStatus.READY
      ) {
        nodeState.status = NodeStatus.SKIPPED;
      }
    }

    this.instances.set(instanceId, instance);
  }

  /**
   * Get the workflow definition.
   *
   * @param workflowId - The ID of the workflow
   * @returns The workflow definition if it exists, null otherwise
   */
  async getWorkflowDefinition(
    workflowId: string
  ): Promise<WorkflowDefinition | null> {
    return this.definitions.get(workflowId) || null;
  }

  /**
   * List all instances of a workflow.
   *
   * @param workflowId - The ID of the workflow
   * @returns List of all instances for the workflow
   */
  async listWorkflowInstances(workflowId: string): Promise<WorkflowInstance[]> {
    const instanceIds = this.instancesByWorkflow.get(workflowId);
    if (!instanceIds) {
      return [];
    }

    const instances: WorkflowInstance[] = [];
    for (const instanceId of instanceIds) {
      const instance = this.instances.get(instanceId);
      if (instance) {
        instances.push(instance);
      }
    }

    return instances;
  }

  /**
   * Update the state of a node in a workflow instance.
   *
   * This is an internal method used by node executors to report progress.
   *
   * @param instanceId - The ID of the workflow instance
   * @param nodeId - The ID of the node to update
   * @param status - The new status of the node
   * @param output - Optional output data from the node
   * @param error - Optional error message if the node failed
   * @throws WorkflowValidationError if the instance or node does not exist
   */
  async updateNodeState(
    instanceId: string,
    nodeId: string,
    status: NodeStatus,
    output?: string,
    error?: string
  ): Promise<void> {
    const instance = this.instances.get(instanceId);
    if (!instance) {
      throw new WorkflowValidationError(
        `Workflow instance with ID '${instanceId}' does not exist`
      );
    }

    const nodeState = instance.nodeStates[nodeId];
    if (!nodeState) {
      throw new WorkflowValidationError(
        `Node '${nodeId}' does not exist in workflow instance '${instanceId}'`
      );
    }

    const now = new Date().toISOString();

    // Update node state
    nodeState.status = status;
    if (status === NodeStatus.RUNNING && !nodeState.startedAt) {
      nodeState.startedAt = now;
    }
    if (
      status === NodeStatus.COMPLETED ||
      status === NodeStatus.FAILED ||
      status === NodeStatus.SKIPPED
    ) {
      nodeState.completedAt = now;
    }
    if (output !== undefined) {
      nodeState.output = output;
    }
    if (error !== undefined) {
      nodeState.error = error;
    }

    // Update dependent nodes if this node completed successfully
    if (status === NodeStatus.COMPLETED) {
      const definition = this.definitions.get(instance.workflowId);
      if (definition) {
        this.updateDependentNodes(instance, definition, nodeId);
      }
    }

    // Check if workflow is complete
    this.checkWorkflowCompletion(instance);

    this.instances.set(instanceId, instance);
  }

  /**
   * Update the status of nodes that depend on a completed node.
   */
  private updateDependentNodes(
    instance: WorkflowInstance,
    definition: WorkflowDefinition,
    completedNodeId: string
  ): void {
    for (const [nodeId, node] of Object.entries(definition.nodes)) {
      if (node.dependencies.includes(completedNodeId)) {
        const nodeState = instance.nodeStates[nodeId];
        if (nodeState.status === NodeStatus.PENDING) {
          // Check if all dependencies are now complete
          const allDepsComplete = node.dependencies.every((dep) => {
            const depState = instance.nodeStates[dep];
            return depState && depState.status === NodeStatus.COMPLETED;
          });

          if (allDepsComplete) {
            nodeState.status = NodeStatus.READY;
          }
        }
      }
    }
  }

  /**
   * Check if a workflow instance is complete and update its status.
   */
  private checkWorkflowCompletion(instance: WorkflowInstance): void {
    const nodeStatuses = Object.values(instance.nodeStates).map((s) => s.status);

    // Check for any failed nodes
    if (nodeStatuses.some((s) => s === NodeStatus.FAILED)) {
      instance.status = WorkflowStatus.FAILED;
      instance.completedAt = new Date().toISOString();
      return;
    }

    // Check if all nodes are complete (COMPLETED or SKIPPED)
    const allComplete = nodeStatuses.every(
      (s) => s === NodeStatus.COMPLETED || s === NodeStatus.SKIPPED
    );

    if (allComplete) {
      instance.status = WorkflowStatus.COMPLETED;
      instance.completedAt = new Date().toISOString();
    }
  }

  /**
   * Resume a workflow by marking a node as completed and advancing dependents.
   *
   * Implements the ResumeWorkflow RPC (spec §17.7 MUST). Marks the specified
   * node as COMPLETED, updates workflow data if provided, then transitions
   * dependent nodes from PENDING to READY when all their dependencies are met.
   *
   * @param instanceId - The ID of the workflow instance
   * @param nodeId - The ID of the node to mark as completed
   * @param workflowData - Optional updated workflow data (JSON string)
   * @param metadata - Optional metadata for the resume operation
   * @returns The updated workflow instance
   * @throws WorkflowValidationError if the instance or node does not exist
   */
  async resumeWorkflow(
    instanceId: string,
    nodeId: string,
    workflowData?: string,
    metadata?: Record<string, string>
  ): Promise<WorkflowInstance> {
    // Mark node as completed
    await this.updateNodeState(instanceId, nodeId, NodeStatus.COMPLETED);

    // Update workflow data if provided
    if (workflowData !== undefined) {
      await this.updateWorkflowData(instanceId, workflowData);
    }

    // Merge metadata if provided
    if (metadata) {
      const instance = this.instances.get(instanceId)!;
      Object.assign(instance.metadata, metadata);
    }

    return this.getWorkflowStatus(instanceId);
  }

  /**
   * Update the shared workflow data.
   *
   * @param instanceId - The ID of the workflow instance
   * @param workflowData - The new workflow data (JSON string)
   * @throws WorkflowValidationError if the instance does not exist
   */
  async updateWorkflowData(
    instanceId: string,
    workflowData: string
  ): Promise<void> {
    const instance = this.instances.get(instanceId);
    if (!instance) {
      throw new WorkflowValidationError(
        `Workflow instance with ID '${instanceId}' does not exist`
      );
    }

    instance.workflowData = workflowData;
    this.instances.set(instanceId, instance);
  }
}
