#!/usr/bin/env npx tsx
/**
 * Workflow Orchestration Example for SW4RM Protocol.
 *
 * This example demonstrates DAG-based workflow execution using the real
 * SDK WorkflowClient:
 * - Creating workflow definitions with nodes and dependencies
 * - Starting workflow instances and tracking node states
 * - Advancing nodes through READY → RUNNING → COMPLETED transitions
 * - Using `resumeWorkflow` for automatic dependency advancement
 * - Automatic workflow completion detection
 *
 * Workflows in SW4RM enable complex multi-agent task orchestration
 * with dependency management, conditional execution, and state tracking.
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *
 * Run:
 *   npx tsx examples/workflowExample.ts
 *
 * Execution mode:
 *   - Local in-memory demo using the SDK's WorkflowClient. No external
 *     services are required. The client validates the DAG, manages node
 *     state transitions, and detects workflow completion automatically.
 *
 * @packageDocumentation
 */

import {
  WorkflowClient,
  NodeStatus,
  TriggerType,
  WorkflowStatus,
} from '../src/index.js';
import type {
  WorkflowDefinition,
  WorkflowInstance,
} from '../src/index.js';

// ============================================================================
// Pipeline Definition
// ============================================================================

/**
 * Create a sample CI/CD pipeline workflow definition.
 *
 * Pipeline structure:
 *   build → test → (security_scan, quality_check) → deploy
 *
 * security_scan and quality_check run in parallel after test completes.
 * deploy only runs after both security_scan and quality_check complete.
 */
function createCICDPipeline(): WorkflowDefinition {
  return {
    workflowId: 'cicd-pipeline-1',
    nodes: {
      build: {
        nodeId: 'build',
        agentId: 'build-agent',
        dependencies: [],
        triggerType: TriggerType.MANUAL,
        inputMapping: { source_repo: 'source_repo', branch: 'branch' },
        outputMapping: { artifact_path: 'build_artifact' },
        metadata: { timeout_ms: '300000' },
      },
      test: {
        nodeId: 'test',
        agentId: 'test-agent',
        dependencies: ['build'],
        triggerType: TriggerType.DEPENDENCY,
        inputMapping: { artifact: 'build_artifact' },
        outputMapping: { test_results: 'test_results', coverage: 'coverage' },
        metadata: { test_type: 'unit,integration' },
      },
      security_scan: {
        nodeId: 'security_scan',
        agentId: 'security-agent',
        dependencies: ['test'],
        triggerType: TriggerType.DEPENDENCY,
        inputMapping: { artifact: 'build_artifact' },
        outputMapping: { vulnerabilities: 'security_report' },
        metadata: { scan_type: 'SAST,DAST' },
      },
      quality_check: {
        nodeId: 'quality_check',
        agentId: 'quality-agent',
        dependencies: ['test'],
        triggerType: TriggerType.DEPENDENCY,
        inputMapping: { coverage: 'coverage' },
        outputMapping: { quality_score: 'quality_score' },
        metadata: { min_coverage: '80' },
      },
      deploy: {
        nodeId: 'deploy',
        agentId: 'deploy-agent',
        dependencies: ['security_scan', 'quality_check'],
        triggerType: TriggerType.DEPENDENCY,
        inputMapping: {
          artifact: 'build_artifact',
          security: 'security_report',
          quality: 'quality_score',
        },
        outputMapping: { deployment_url: 'deployment_url' },
        metadata: { environment: 'staging' },
      },
    },
    metadata: { pipeline_type: 'cicd', version: '1.0.0' },
  };
}

// ============================================================================
// Node Simulation
// ============================================================================

/**
 * Simulate node execution with realistic outputs.
 */
function simulateNodeOutput(nodeId: string): string {
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

// ============================================================================
// Workflow Execution Loop
// ============================================================================

/**
 * Find ready nodes in a workflow instance.
 */
function getReadyNodes(instance: WorkflowInstance): string[] {
  return Object.entries(instance.nodeStates)
    .filter(([, ns]) => ns.status === NodeStatus.READY)
    .map(([id]) => id);
}

/**
 * Check if a workflow instance is in a terminal state.
 */
function isComplete(instance: WorkflowInstance): boolean {
  return (
    instance.status === WorkflowStatus.COMPLETED ||
    instance.status === WorkflowStatus.FAILED ||
    instance.status === WorkflowStatus.CANCELLED
  );
}

/**
 * Run a workflow instance to completion using the SDK client's
 * resumeWorkflow method, which marks a node as COMPLETED and
 * automatically advances dependents from PENDING to READY.
 */
async function runWorkflow(
  client: WorkflowClient,
  instanceId: string
): Promise<void> {
  let iteration = 0;
  const maxIterations = 10;

  while (iteration < maxIterations) {
    iteration++;
    const instance = await client.getWorkflowStatus(instanceId);

    if (isComplete(instance)) {
      break;
    }

    const readyNodes = getReadyNodes(instance);
    if (readyNodes.length === 0) {
      break;
    }

    console.log(`\n${'='.repeat(60)}`);
    console.log(`Workflow Iteration ${iteration}`);
    console.log(`${'='.repeat(60)}`);
    console.log(`Ready nodes: ${readyNodes.join(', ')}`);

    // Execute all ready nodes (could be truly parallel in production)
    for (const nodeId of readyNodes) {
      // Mark as RUNNING
      await client.updateNodeState(instanceId, nodeId, NodeStatus.RUNNING);
      console.log(`\n[Node] Executing: ${nodeId}`);

      // Simulate work
      await new Promise((r) => setTimeout(r, 50));
      const output = simulateNodeOutput(nodeId);

      // resumeWorkflow marks the node COMPLETED and auto-promotes dependents
      const updated = await client.resumeWorkflow(instanceId, nodeId);
      console.log(`[Node] Completed: ${nodeId}`);
      console.log(`  Output: ${output.substring(0, 100)}${output.length > 100 ? '...' : ''}`);
      console.log(`  Workflow status: ${WorkflowStatus[updated.status]}`);
    }

    // Print current state
    const updated = await client.getWorkflowStatus(instanceId);
    console.log('\nCurrent node states:');
    for (const [nodeId, nodeState] of Object.entries(updated.nodeStates)) {
      console.log(`  ${nodeId}: ${NodeStatus[nodeState.status]}`);
    }
  }
}

// ============================================================================
// Main
// ============================================================================

async function main(): Promise<number> {
  console.log('SW4RM Workflow Orchestration Example');
  console.log('='.repeat(60));
  console.log('\nThis example uses the SDK WorkflowClient to demonstrate');
  console.log('DAG-based workflow execution for multi-agent orchestration.\n');

  const client = new WorkflowClient();

  // Create the CI/CD pipeline workflow
  const definition = createCICDPipeline();

  console.log('Workflow Structure:');
  console.log('  build → test → (security_scan, quality_check) → deploy');
  console.log('  * security_scan and quality_check run in parallel');
  console.log('  * deploy waits for both to complete\n');

  const workflowId = await client.createWorkflow(definition);
  console.log(`Created workflow: ${workflowId}`);

  // Start the workflow
  const initialData = JSON.stringify({
    source_repo: 'https://github.com/example/app',
    branch: 'main',
  });

  const instance = await client.startWorkflow(workflowId, initialData);
  console.log(`Started instance: ${instance.instanceId}`);

  // Run to completion
  await runWorkflow(client, instance.instanceId);

  // Print final state
  const final = await client.getWorkflowStatus(instance.instanceId);
  console.log('\n' + '='.repeat(60));
  console.log('WORKFLOW COMPLETE');
  console.log('='.repeat(60));
  console.log(`\nStatus: ${WorkflowStatus[final.status]}`);

  if (final.completedAt && final.startedAt) {
    const start = new Date(final.startedAt).getTime();
    const end = new Date(final.completedAt).getTime();
    console.log(`Duration: ${end - start}ms`);
  }

  console.log('\nFinal workflow data:');
  console.log(JSON.stringify(JSON.parse(final.workflowData), null, 2));

  // --------------------------------------------------------------------------
  // Failure Path: Node failure cascades to WorkflowStatus.FAILED
  // --------------------------------------------------------------------------
  console.log('\n' + '='.repeat(60));
  console.log('FAILURE PATH: Node failure cascade');
  console.log('='.repeat(60));

  const failDef = createCICDPipeline();
  failDef.workflowId = 'cicd-pipeline-fail';
  const failWfId = await client.createWorkflow(failDef);
  const failInstance = await client.startWorkflow(failWfId, initialData);
  console.log(`\nStarted failure-demo instance: ${failInstance.instanceId}`);

  // Advance build → COMPLETED via resumeWorkflow
  await client.updateNodeState(failInstance.instanceId, 'build', NodeStatus.RUNNING);
  await client.resumeWorkflow(failInstance.instanceId, 'build');
  console.log('  build: COMPLETED');

  // Mark test as FAILED with an error message
  await client.updateNodeState(failInstance.instanceId, 'test', NodeStatus.RUNNING);
  await client.updateNodeState(
    failInstance.instanceId, 'test', NodeStatus.FAILED, undefined, 'Integration tests timed out'
  );
  console.log('  test: FAILED (Integration tests timed out)');

  const failFinal = await client.getWorkflowStatus(failInstance.instanceId);
  console.log(`\n  Workflow status: ${WorkflowStatus[failFinal.status]}`);
  console.log('  Downstream nodes (security_scan, quality_check, deploy) remain PENDING');
  for (const [nid, ns] of Object.entries(failFinal.nodeStates)) {
    console.log(`    ${nid}: ${NodeStatus[ns.status]}`);
  }

  console.log('\nKey takeaways:');
  console.log('1. WorkflowClient validates the DAG on createWorkflow (cycle detection)');
  console.log('2. startWorkflow initializes root nodes as READY, dependent nodes as PENDING');
  console.log('3. resumeWorkflow marks a node COMPLETED and auto-promotes dependents to READY');
  console.log('4. The client detects workflow completion and sets the final status');
  console.log('5. Parallel execution is possible for independent branches');
  console.log('6. A single FAILED node cascades to WorkflowStatus.FAILED');

  return 0;
}

main().catch((err) => {
  console.error('[Fatal] Unhandled error:', err);
  process.exit(1);
});
