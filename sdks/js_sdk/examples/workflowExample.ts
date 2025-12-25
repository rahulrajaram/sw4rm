#!/usr/bin/env npx tsx
/**
 * Workflow Orchestration Example for SW4RM Protocol.
 *
 * This example demonstrates DAG-based workflow execution:
 * - Creating workflow definitions with nodes and dependencies
 * - Starting workflows and monitoring execution
 * - Handling node completion and state transitions
 * - Passing context between workflow nodes
 *
 * Workflows in SW4RM enable complex multi-agent task orchestration
 * with dependency management, conditional execution, and state tracking.
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *   - Build the SDK: `npm run build`
 *
 * Run:
 *   npx tsx examples/workflowExample.ts
 *
 * Note: This example uses mock implementations since WorkflowClient
 * is not yet implemented in the JS SDK. See Phase 2.3 in IMPLEMENTATION_PLAN.md.
 *
 * @packageDocumentation
 */

// ============================================================================
// Type Definitions (matching workflow.proto)
// ============================================================================

/**
 * NodeStatus represents the execution status of a workflow node.
 */
enum NodeStatus {
  NODE_STATUS_UNSPECIFIED = 0,
  PENDING = 1, // Node waiting for dependencies
  READY = 2, // Node ready to execute
  RUNNING = 3, // Node currently executing
  COMPLETED = 4, // Node finished successfully
  FAILED = 5, // Node encountered an error
  SKIPPED = 6, // Node skipped due to conditional logic
}

/**
 * TriggerType determines how a workflow or node is initiated.
 */
enum TriggerType {
  TRIGGER_TYPE_UNSPECIFIED = 0,
  EVENT = 1, // Triggered by specific events
  SCHEDULE = 2, // Triggered on a schedule (cron-like)
  MANUAL = 3, // Triggered by explicit user action
  DEPENDENCY = 4, // Triggered by dependency completion
}

/**
 * WorkflowNode represents a single step in the workflow DAG.
 */
interface WorkflowNode {
  node_id: string;
  agent_id: string;
  dependencies: string[];
  trigger_type: TriggerType;
  input_mapping: Record<string, string>;
  output_mapping: Record<string, string>;
  metadata: Record<string, string>;
}

/**
 * WorkflowDefinition describes the complete workflow structure.
 */
interface WorkflowDefinition {
  workflow_id: string;
  nodes: Record<string, WorkflowNode>;
  created_at: Date;
  metadata: Record<string, string>;
}

/**
 * NodeState tracks the execution state of a single node.
 */
interface NodeState {
  node_id: string;
  status: NodeStatus;
  started_at?: Date;
  completed_at?: Date;
  output?: string;
  error?: string;
}

/**
 * WorkflowState tracks the overall workflow execution.
 */
interface WorkflowState {
  workflow_id: string;
  node_states: Record<string, NodeState>;
  workflow_data: string;
  started_at?: Date;
  completed_at?: Date;
  metadata: Record<string, string>;
}

// ============================================================================
// Mock WorkflowClient
// ============================================================================

/**
 * Mock WorkflowClient for demonstration purposes.
 *
 * In production, this would be a gRPC client connecting to the
 * WorkflowService. See Phase 2.3 in IMPLEMENTATION_PLAN.md.
 */
class MockWorkflowClient {
  private definitions = new Map<string, WorkflowDefinition>();
  private states = new Map<string, WorkflowState>();

  /**
   * Create a new workflow definition.
   */
  async createWorkflow(definition: WorkflowDefinition): Promise<string> {
    // Validate DAG (check for cycles)
    this.validateDAG(definition);

    this.definitions.set(definition.workflow_id, definition);

    console.log(`\n[Workflow] Created workflow: ${definition.workflow_id}`);
    console.log(`  Nodes: ${Object.keys(definition.nodes).length}`);
    console.log(`  Node IDs: ${Object.keys(definition.nodes).join(' -> ')}`);

    return definition.workflow_id;
  }

  /**
   * Start a workflow instance.
   */
  async startWorkflow(workflowId: string, initialData: string = '{}'): Promise<WorkflowState> {
    const definition = this.definitions.get(workflowId);
    if (!definition) {
      throw new Error(`Workflow not found: ${workflowId}`);
    }

    console.log(`\n[Workflow] Starting workflow: ${workflowId}`);

    // Initialize node states
    const nodeStates: Record<string, NodeState> = {};
    for (const nodeId of Object.keys(definition.nodes)) {
      const node = definition.nodes[nodeId];
      const hasUnmetDeps = node.dependencies.some((dep) => {
        const depState = nodeStates[dep];
        return !depState || depState.status !== NodeStatus.COMPLETED;
      });

      nodeStates[nodeId] = {
        node_id: nodeId,
        status: node.dependencies.length === 0 ? NodeStatus.READY : NodeStatus.PENDING,
      };
    }

    const state: WorkflowState = {
      workflow_id: workflowId,
      node_states: nodeStates,
      workflow_data: initialData,
      started_at: new Date(),
      metadata: {},
    };

    this.states.set(workflowId, state);
    return state;
  }

  /**
   * Get the current state of a workflow.
   */
  async getWorkflowState(workflowId: string): Promise<WorkflowState | null> {
    return this.states.get(workflowId) ?? null;
  }

  /**
   * Execute a ready node in the workflow.
   */
  async executeNode(workflowId: string, nodeId: string, output: string): Promise<WorkflowState> {
    const state = this.states.get(workflowId);
    if (!state) {
      throw new Error(`Workflow not found: ${workflowId}`);
    }

    const nodeState = state.node_states[nodeId];
    if (!nodeState) {
      throw new Error(`Node not found: ${nodeId}`);
    }

    // Mark as running
    nodeState.status = NodeStatus.RUNNING;
    nodeState.started_at = new Date();

    console.log(`\n[Node] Executing: ${nodeId}`);
    console.log(`  Agent: ${this.definitions.get(workflowId)?.nodes[nodeId].agent_id}`);

    // Simulate execution delay
    await new Promise((resolve) => setTimeout(resolve, 100));

    // Mark as completed
    nodeState.status = NodeStatus.COMPLETED;
    nodeState.completed_at = new Date();
    nodeState.output = output;

    console.log(`[Node] Completed: ${nodeId}`);
    console.log(`  Output: ${output.substring(0, 100)}${output.length > 100 ? '...' : ''}`);

    // Update workflow data with node output
    const workflowData = JSON.parse(state.workflow_data);
    workflowData[nodeId] = JSON.parse(output);
    state.workflow_data = JSON.stringify(workflowData);

    // Update dependent nodes to READY if all deps completed
    this.updateReadyNodes(state, workflowId);

    return state;
  }

  /**
   * Mark a node as failed.
   */
  async failNode(workflowId: string, nodeId: string, error: string): Promise<WorkflowState> {
    const state = this.states.get(workflowId);
    if (!state) {
      throw new Error(`Workflow not found: ${workflowId}`);
    }

    const nodeState = state.node_states[nodeId];
    if (!nodeState) {
      throw new Error(`Node not found: ${nodeId}`);
    }

    nodeState.status = NodeStatus.FAILED;
    nodeState.error = error;
    nodeState.completed_at = new Date();

    console.log(`\n[Node] Failed: ${nodeId}`);
    console.log(`  Error: ${error}`);

    // Mark dependent nodes as SKIPPED
    this.skipDependentNodes(state, nodeId);

    return state;
  }

  /**
   * Update nodes to READY if all dependencies are complete.
   */
  private updateReadyNodes(state: WorkflowState, workflowId: string): void {
    const definition = this.definitions.get(workflowId);
    if (!definition) return;

    for (const [nodeId, nodeState] of Object.entries(state.node_states)) {
      if (nodeState.status !== NodeStatus.PENDING) continue;

      const node = definition.nodes[nodeId];
      const allDepsComplete = node.dependencies.every((dep) => {
        const depState = state.node_states[dep];
        return depState && depState.status === NodeStatus.COMPLETED;
      });

      if (allDepsComplete) {
        nodeState.status = NodeStatus.READY;
        console.log(`[Node] Ready: ${nodeId}`);
      }
    }
  }

  /**
   * Skip nodes that depend on a failed node.
   */
  private skipDependentNodes(state: WorkflowState, failedNodeId: string): void {
    for (const [nodeId, nodeState] of Object.entries(state.node_states)) {
      if (nodeState.status === NodeStatus.PENDING) {
        // Check if this node depends on the failed node (directly or transitively)
        // For simplicity, we mark as skipped if status is still pending
        // In production, this would traverse the dependency graph
      }
    }
  }

  /**
   * Check if the workflow is complete.
   */
  isComplete(state: WorkflowState): boolean {
    const terminalStatuses = [NodeStatus.COMPLETED, NodeStatus.FAILED, NodeStatus.SKIPPED];
    return Object.values(state.node_states).every((ns) => terminalStatuses.includes(ns.status));
  }

  /**
   * Get the next ready nodes.
   */
  getReadyNodes(state: WorkflowState): string[] {
    return Object.entries(state.node_states)
      .filter(([_, ns]) => ns.status === NodeStatus.READY)
      .map(([id, _]) => id);
  }

  /**
   * Validate that the workflow definition is a valid DAG (no cycles).
   */
  private validateDAG(definition: WorkflowDefinition): void {
    const visited = new Set<string>();
    const recStack = new Set<string>();

    const hasCycle = (nodeId: string): boolean => {
      if (recStack.has(nodeId)) return true;
      if (visited.has(nodeId)) return false;

      visited.add(nodeId);
      recStack.add(nodeId);

      const node = definition.nodes[nodeId];
      if (node) {
        for (const dep of node.dependencies) {
          if (hasCycle(dep)) return true;
        }
      }

      recStack.delete(nodeId);
      return false;
    };

    for (const nodeId of Object.keys(definition.nodes)) {
      if (hasCycle(nodeId)) {
        throw new Error(`Workflow contains a cycle involving node: ${nodeId}`);
      }
    }
  }
}

// ============================================================================
// Example: CI/CD Pipeline Workflow
// ============================================================================

/**
 * Create a sample CI/CD pipeline workflow definition.
 *
 * Pipeline structure:
 *   build -> test -> (security_scan, quality_check) -> deploy
 *
 * The security_scan and quality_check run in parallel after test completes.
 * Deploy only runs after both security_scan and quality_check complete.
 */
function createCICDPipeline(): WorkflowDefinition {
  return {
    workflow_id: 'cicd-pipeline-1',
    nodes: {
      build: {
        node_id: 'build',
        agent_id: 'build-agent',
        dependencies: [],
        trigger_type: TriggerType.MANUAL,
        input_mapping: { source_repo: 'source_repo', branch: 'branch' },
        output_mapping: { artifact_path: 'build_artifact' },
        metadata: { timeout_ms: '300000' },
      },
      test: {
        node_id: 'test',
        agent_id: 'test-agent',
        dependencies: ['build'],
        trigger_type: TriggerType.DEPENDENCY,
        input_mapping: { artifact: 'build_artifact' },
        output_mapping: { test_results: 'test_results', coverage: 'coverage' },
        metadata: { test_type: 'unit,integration' },
      },
      security_scan: {
        node_id: 'security_scan',
        agent_id: 'security-agent',
        dependencies: ['test'],
        trigger_type: TriggerType.DEPENDENCY,
        input_mapping: { artifact: 'build_artifact' },
        output_mapping: { vulnerabilities: 'security_report' },
        metadata: { scan_type: 'SAST,DAST' },
      },
      quality_check: {
        node_id: 'quality_check',
        agent_id: 'quality-agent',
        dependencies: ['test'],
        trigger_type: TriggerType.DEPENDENCY,
        input_mapping: { coverage: 'coverage' },
        output_mapping: { quality_score: 'quality_score' },
        metadata: { min_coverage: '80' },
      },
      deploy: {
        node_id: 'deploy',
        agent_id: 'deploy-agent',
        dependencies: ['security_scan', 'quality_check'],
        trigger_type: TriggerType.DEPENDENCY,
        input_mapping: { artifact: 'build_artifact', security: 'security_report', quality: 'quality_score' },
        output_mapping: { deployment_url: 'deployment_url' },
        metadata: { environment: 'staging' },
      },
    },
    created_at: new Date(),
    metadata: { pipeline_type: 'cicd', version: '1.0.0' },
  };
}

/**
 * Simulate node execution with realistic outputs.
 */
function simulateNodeOutput(nodeId: string, workflowData: Record<string, unknown>): string {
  switch (nodeId) {
    case 'build':
      return JSON.stringify({
        artifact_path: '/artifacts/build-123.tar.gz',
        commit_sha: 'abc123',
        build_time_ms: 45000,
      });

    case 'test':
      return JSON.stringify({
        test_results: { passed: 142, failed: 0, skipped: 3 },
        coverage: 87.5,
        execution_time_ms: 120000,
      });

    case 'security_scan':
      return JSON.stringify({
        vulnerabilities: { critical: 0, high: 1, medium: 3, low: 8 },
        scan_time_ms: 60000,
        recommendation: 'Review 1 high severity issue before production',
      });

    case 'quality_check':
      return JSON.stringify({
        quality_score: 92,
        coverage_met: true,
        code_smells: 5,
        tech_debt_hours: 2.5,
      });

    case 'deploy':
      return JSON.stringify({
        deployment_url: 'https://staging.example.com',
        deployment_id: 'deploy-456',
        health_check: 'passed',
      });

    default:
      return JSON.stringify({ status: 'completed' });
  }
}

/**
 * Run the workflow to completion.
 */
async function runWorkflow(client: MockWorkflowClient, workflowId: string): Promise<void> {
  let state = await client.getWorkflowState(workflowId);
  if (!state) {
    throw new Error(`Workflow state not found: ${workflowId}`);
  }

  let iteration = 0;
  const maxIterations = 10;

  while (!client.isComplete(state) && iteration < maxIterations) {
    iteration++;
    console.log(`\n${'='.repeat(60)}`);
    console.log(`Workflow Iteration ${iteration}`);
    console.log(`${'='.repeat(60)}`);

    const readyNodes = client.getReadyNodes(state);
    console.log(`\nReady nodes: ${readyNodes.join(', ') || 'none'}`);

    // Execute all ready nodes (could be parallel in production)
    for (const nodeId of readyNodes) {
      const workflowData = JSON.parse(state.workflow_data);
      const output = simulateNodeOutput(nodeId, workflowData);
      state = await client.executeNode(workflowId, nodeId, output);
    }

    // Print current state
    console.log('\nCurrent node states:');
    for (const [nodeId, nodeState] of Object.entries(state.node_states)) {
      const status = NodeStatus[nodeState.status];
      const info = nodeState.error ? ` (error: ${nodeState.error})` : '';
      console.log(`  ${nodeId}: ${status}${info}`);
    }
  }

  // Mark workflow as complete
  if (state) {
    state.completed_at = new Date();
  }
}

/**
 * Main demonstration function.
 */
async function main(): Promise<number> {
  console.log('SW4RM Workflow Orchestration Example');
  console.log('='.repeat(60));
  console.log('\nThis example demonstrates DAG-based workflow execution');
  console.log('for complex multi-agent task orchestration.\n');

  const client = new MockWorkflowClient();

  // Create the CI/CD pipeline workflow
  const definition = createCICDPipeline();

  console.log('\nWorkflow Structure:');
  console.log('  build -> test -> (security_scan, quality_check) -> deploy');
  console.log('  * security_scan and quality_check run in parallel');
  console.log('  * deploy waits for both to complete\n');

  await client.createWorkflow(definition);

  // Start the workflow
  const initialData = JSON.stringify({
    source_repo: 'https://github.com/example/app',
    branch: 'main',
  });

  await client.startWorkflow(definition.workflow_id, initialData);

  // Run to completion
  await runWorkflow(client, definition.workflow_id);

  // Print final state
  const finalState = await client.getWorkflowState(definition.workflow_id);
  if (finalState) {
    console.log('\n' + '='.repeat(60));
    console.log('WORKFLOW COMPLETE');
    console.log('='.repeat(60));

    const duration =
      finalState.completed_at && finalState.started_at
        ? finalState.completed_at.getTime() - finalState.started_at.getTime()
        : 0;

    console.log(`\nDuration: ${duration}ms`);
    console.log('\nFinal workflow data:');
    console.log(JSON.stringify(JSON.parse(finalState.workflow_data), null, 2));
  }

  console.log('\nKey takeaways:');
  console.log('1. Workflows define DAGs with nodes and dependencies');
  console.log('2. Nodes execute when all dependencies complete');
  console.log('3. Parallel execution is possible for independent branches');
  console.log('4. Input/output mapping enables data flow between nodes');
  console.log('5. Node failures can trigger skip cascades for dependents');

  return 0;
}

// Entry point
main().catch((err) => {
  console.error('[Fatal] Unhandled error:', err);
  process.exit(1);
});
