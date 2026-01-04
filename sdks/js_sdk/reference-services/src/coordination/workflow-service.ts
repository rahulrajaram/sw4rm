#!/usr/bin/env tsx

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
 * Workflow Service gRPC Server Implementation.
 *
 * This module provides the gRPC server implementation for the WorkflowService,
 * enabling distributed DAG-based workflow orchestration with centralized state.
 */

import * as grpc from '@grpc/grpc-js';

// Node status enum values (from proto)
export enum NodeStatus {
  NODE_STATUS_UNSPECIFIED = 0,
  PENDING = 1,
  READY = 2,
  RUNNING = 3,
  COMPLETED = 4,
  FAILED = 5,
  SKIPPED = 6,
}

// Trigger type enum values (from proto)
export enum TriggerType {
  TRIGGER_TYPE_UNSPECIFIED = 0,
  EVENT = 1,
  SCHEDULE = 2,
  MANUAL = 3,
  DEPENDENCY = 4,
}

// Type definitions matching proto messages
export interface WorkflowNode {
  node_id: string;
  agent_id: string;
  dependencies: string[];
  trigger_type: number;
  input_mapping: { [key: string]: string };
  output_mapping: { [key: string]: string };
  metadata: { [key: string]: string };
}

export interface WorkflowDefinition {
  workflow_id: string;
  nodes: { [key: string]: WorkflowNode };
  created_at?: { seconds: number; nanos: number };
  metadata: { [key: string]: string };
}

export interface NodeState {
  node_id: string;
  status: number;
  started_at?: { seconds: number; nanos: number };
  completed_at?: { seconds: number; nanos: number };
  output: string;
  error: string;
}

export interface WorkflowState {
  workflow_id: string;
  node_states: { [key: string]: NodeState };
  workflow_data: string;
  started_at?: { seconds: number; nanos: number };
  completed_at?: { seconds: number; nanos: number };
  metadata: { [key: string]: string };
}

export interface CreateWorkflowRequest {
  definition: WorkflowDefinition;
}

export interface CreateWorkflowResponse {
  workflow_id: string;
  success: boolean;
  error: string;
}

export interface StartWorkflowRequest {
  workflow_id: string;
  workflow_data: string;
  metadata: { [key: string]: string };
}

export interface StartWorkflowResponse {
  workflow_id: string;
  state?: WorkflowState;
  success: boolean;
  error: string;
}

export interface GetWorkflowStateRequest {
  workflow_id: string;
}

export interface GetWorkflowStateResponse {
  state?: WorkflowState;
  success: boolean;
  error: string;
}

export interface ResumeWorkflowRequest {
  workflow_id: string;
  node_id: string;
  workflow_data: string;
  metadata: { [key: string]: string };
}

export interface ResumeWorkflowResponse {
  workflow_id: string;
  state?: WorkflowState;
  success: boolean;
  error: string;
}

function currentTimestamp(): { seconds: number; nanos: number } {
  const now = Date.now();
  return {
    seconds: Math.floor(now / 1000),
    nanos: (now % 1000) * 1_000_000,
  };
}

/**
 * gRPC server implementation for WorkflowService.
 *
 * Provides centralized workflow orchestration for distributed agent deployments.
 * Thread-safe implementation using Maps for state storage.
 */
export class WorkflowServiceImpl {
  private definitions: Map<string, WorkflowDefinition> = new Map();
  private instances: Map<string, WorkflowState> = new Map();

  constructor() {
    console.log('WorkflowService initialized');
  }

  /**
   * Validate that the workflow DAG has no cycles.
   */
  private validateDag(definition: WorkflowDefinition): string | null {
    const visited = new Set<string>();
    const recStack = new Set<string>();

    const hasCycle = (nodeId: string): boolean => {
      visited.add(nodeId);
      recStack.add(nodeId);

      const node = definition.nodes[nodeId];
      if (node) {
        for (const dep of node.dependencies) {
          if (!visited.has(dep)) {
            if (hasCycle(dep)) {
              return true;
            }
          } else if (recStack.has(dep)) {
            return true;
          }
        }
      }

      recStack.delete(nodeId);
      return false;
    };

    for (const nodeId of Object.keys(definition.nodes)) {
      if (!visited.has(nodeId)) {
        if (hasCycle(nodeId)) {
          return `Cycle detected in workflow starting from node '${nodeId}'`;
        }
      }
    }

    return null;
  }

  /**
   * Validate that all dependencies reference existing nodes.
   */
  private validateDependencies(definition: WorkflowDefinition): string | null {
    const nodeIds = new Set(Object.keys(definition.nodes));

    for (const [nodeId, node] of Object.entries(definition.nodes)) {
      for (const dep of node.dependencies) {
        if (!nodeIds.has(dep)) {
          return `Node '${nodeId}' has dependency '${dep}' which does not exist`;
        }
      }
    }

    return null;
  }

  /**
   * Create a new workflow from a definition.
   */
  createWorkflow(
    call: grpc.ServerUnaryCall<CreateWorkflowRequest, CreateWorkflowResponse>,
    callback: grpc.sendUnaryData<CreateWorkflowResponse>
  ): void {
    const definition = call.request.definition;

    if (!definition) {
      callback(null, {
        workflow_id: '',
        success: false,
        error: 'WorkflowDefinition is required',
      });
      return;
    }

    const workflowId = definition.workflow_id;

    // Validate required fields
    if (!workflowId) {
      callback(null, {
        workflow_id: '',
        success: false,
        error: 'workflow_id is required',
      });
      return;
    }

    if (!definition.nodes || Object.keys(definition.nodes).length === 0) {
      callback(null, {
        workflow_id: workflowId,
        success: false,
        error: 'workflow must contain at least one node',
      });
      return;
    }

    // Validate dependencies
    const depError = this.validateDependencies(definition);
    if (depError) {
      callback(null, {
        workflow_id: workflowId,
        success: false,
        error: depError,
      });
      return;
    }

    // Validate DAG (no cycles)
    const cycleError = this.validateDag(definition);
    if (cycleError) {
      callback(null, {
        workflow_id: workflowId,
        success: false,
        error: cycleError,
      });
      return;
    }

    // Check for duplicates
    if (this.definitions.has(workflowId)) {
      callback(null, {
        workflow_id: workflowId,
        success: false,
        error: `Workflow with id '${workflowId}' already exists`,
      });
      return;
    }

    // Set created_at if not provided
    if (!definition.created_at) {
      definition.created_at = currentTimestamp();
    }

    this.definitions.set(workflowId, definition);
    console.log(`Workflow created: ${workflowId} with ${Object.keys(definition.nodes).length} nodes`);

    callback(null, {
      workflow_id: workflowId,
      success: true,
      error: '',
    });
  }

  /**
   * Start a new instance of a workflow.
   */
  startWorkflow(
    call: grpc.ServerUnaryCall<StartWorkflowRequest, StartWorkflowResponse>,
    callback: grpc.sendUnaryData<StartWorkflowResponse>
  ): void {
    const workflowId = call.request.workflow_id;

    // Check if definition exists
    const definition = this.definitions.get(workflowId);
    if (!definition) {
      callback(null, {
        workflow_id: workflowId,
        state: undefined,
        success: false,
        error: `Workflow '${workflowId}' not found`,
      });
      return;
    }

    // Check if already running
    if (this.instances.has(workflowId)) {
      callback(null, {
        workflow_id: workflowId,
        state: undefined,
        success: false,
        error: `Workflow '${workflowId}' is already running`,
      });
      return;
    }

    // Initialize node states
    const nodeStates: { [key: string]: NodeState } = {};
    for (const [nodeId, node] of Object.entries(definition.nodes)) {
      // Nodes with no dependencies start as READY, others as PENDING
      const status = node.dependencies.length === 0 ? NodeStatus.READY : NodeStatus.PENDING;

      nodeStates[nodeId] = {
        node_id: nodeId,
        status,
        output: '',
        error: '',
      };
    }

    // Create workflow state
    const state: WorkflowState = {
      workflow_id: workflowId,
      node_states: nodeStates,
      workflow_data: call.request.workflow_data || '{}',
      started_at: currentTimestamp(),
      metadata: call.request.metadata || {},
    };

    this.instances.set(workflowId, state);
    console.log(`Workflow started: ${workflowId}`);

    callback(null, {
      workflow_id: workflowId,
      state,
      success: true,
      error: '',
    });
  }

  /**
   * Get the current state of a workflow instance.
   */
  getWorkflowState(
    call: grpc.ServerUnaryCall<GetWorkflowStateRequest, GetWorkflowStateResponse>,
    callback: grpc.sendUnaryData<GetWorkflowStateResponse>
  ): void {
    const workflowId = call.request.workflow_id;

    const state = this.instances.get(workflowId);
    if (state) {
      console.log(`GetWorkflowState: ${workflowId}`);
      callback(null, {
        state,
        success: true,
        error: '',
      });
      return;
    }

    // Check if definition exists but not started
    if (this.definitions.has(workflowId)) {
      callback(null, {
        state: undefined,
        success: false,
        error: `Workflow '${workflowId}' exists but is not started`,
      });
      return;
    }

    callback(null, {
      state: undefined,
      success: false,
      error: `Workflow '${workflowId}' not found`,
    });
  }

  /**
   * Resume a workflow by completing a node.
   */
  resumeWorkflow(
    call: grpc.ServerUnaryCall<ResumeWorkflowRequest, ResumeWorkflowResponse>,
    callback: grpc.sendUnaryData<ResumeWorkflowResponse>
  ): void {
    const workflowId = call.request.workflow_id;
    const nodeId = call.request.node_id;

    // Get the instance
    const state = this.instances.get(workflowId);
    if (!state) {
      callback(null, {
        workflow_id: workflowId,
        state: undefined,
        success: false,
        error: `Workflow '${workflowId}' not found or not started`,
      });
      return;
    }

    // Get the definition
    const definition = this.definitions.get(workflowId);
    if (!definition) {
      callback(null, {
        workflow_id: workflowId,
        state: undefined,
        success: false,
        error: `Workflow definition '${workflowId}' not found`,
      });
      return;
    }

    // Check if node exists
    if (!state.node_states[nodeId]) {
      callback(null, {
        workflow_id: workflowId,
        state,
        success: false,
        error: `Node '${nodeId}' not found in workflow`,
      });
      return;
    }

    // Update the node to COMPLETED
    state.node_states[nodeId].status = NodeStatus.COMPLETED;
    state.node_states[nodeId].completed_at = currentTimestamp();

    // Update workflow data if provided
    if (call.request.workflow_data) {
      state.workflow_data = call.request.workflow_data;
    }

    // Update metadata
    if (call.request.metadata) {
      Object.assign(state.metadata, call.request.metadata);
    }

    // Update dependent nodes
    for (const [depNodeId, node] of Object.entries(definition.nodes)) {
      if (node.dependencies.includes(nodeId)) {
        const depState = state.node_states[depNodeId];
        if (depState && depState.status === NodeStatus.PENDING) {
          // Check if all dependencies are complete
          const allDepsComplete = node.dependencies.every((dep) => {
            const depS = state.node_states[dep];
            return depS && depS.status === NodeStatus.COMPLETED;
          });

          if (allDepsComplete) {
            depState.status = NodeStatus.READY;
          }
        }
      }
    }

    // Check if workflow is complete
    const terminalStatuses = [NodeStatus.COMPLETED, NodeStatus.FAILED, NodeStatus.SKIPPED];
    const allTerminal = Object.values(state.node_states).every((ns) =>
      terminalStatuses.includes(ns.status)
    );

    if (allTerminal && !state.completed_at) {
      state.completed_at = currentTimestamp();
    }

    console.log(`Workflow resumed: ${workflowId}, node ${nodeId} completed`);

    callback(null, {
      workflow_id: workflowId,
      state,
      success: true,
      error: '',
    });
  }

  // Helper methods

  getDefinition(workflowId: string): WorkflowDefinition | undefined {
    return this.definitions.get(workflowId);
  }

  clearAll(): void {
    this.definitions.clear();
    this.instances.clear();
    console.log('WorkflowService state cleared');
  }

  /**
   * Get the service handlers for gRPC registration.
   */
  getHandlers(): { [key: string]: grpc.handleUnaryCall<any, any> } {
    return {
      CreateWorkflow: this.createWorkflow.bind(this),
      StartWorkflow: this.startWorkflow.bind(this),
      GetWorkflowState: this.getWorkflowState.bind(this),
      ResumeWorkflow: this.resumeWorkflow.bind(this),
    };
  }
}
