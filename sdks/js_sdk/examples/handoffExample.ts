#!/usr/bin/env npx tsx
/**
 * Agent Handoff Example for SW4RM Protocol.
 *
 * This example demonstrates agent-to-agent task handoff using the real
 * SDK HandoffClient:
 * - Requesting a handoff when current agent lacks capabilities
 * - Accepting or rejecting handoffs based on agent state
 * - Transferring context between agents via contextSnapshot
 * - Concurrent request/response flow
 *
 * Handoffs enable seamless task transfer between specialized agents
 * when work requires capabilities the current agent does not possess.
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *
 * Run:
 *   npx tsx examples/handoffExample.ts
 *
 * Execution mode:
 *   - Local in-memory demo using the SDK's HandoffClient. No external
 *     services are required. The HandoffClient stores request/response
 *     state in process memory and uses polling to unblock callers when
 *     a target agent accepts or rejects a handoff.
 *
 * @packageDocumentation
 */

import {
  HandoffClient,
  HandoffValidationError,
} from '../src/index.js';
import type {
  HandoffRequest,
  HandoffResponse,
  BudgetEnvelope,
  SwarmDelegationPolicy,
} from '../src/index.js';

// ============================================================================
// Agent Abstraction
// ============================================================================

/**
 * Simulated agent with capabilities and availability state.
 *
 * In a real deployment each agent would run as a separate process with
 * its own HandoffClient instance. Here we share a single in-memory
 * client so the polling-based handoff protocol is visible in one script.
 */
class Agent {
  readonly agentId: string;
  readonly capabilities: string[];
  private busy = false;
  private currentHandoff: string | null = null;

  constructor(agentId: string, capabilities: string[]) {
    this.agentId = agentId;
    this.capabilities = capabilities;
  }

  hasCapability(cap: string): boolean {
    return this.capabilities.includes(cap);
  }

  canAcceptWork(): boolean {
    return !this.busy;
  }

  markBusy(handoffId: string): void {
    this.busy = true;
    this.currentHandoff = handoffId;
  }

  markFree(): string | null {
    const previous = this.currentHandoff;
    this.busy = false;
    this.currentHandoff = null;
    return previous;
  }
}

// ============================================================================
// Helper: process pending handoffs for an agent
// ============================================================================

/**
 * Evaluate pending handoffs and accept/reject based on capability match
 * and availability. Returns the IDs of accepted handoffs.
 */
async function processPendingHandoffs(
  client: HandoffClient,
  agent: Agent
): Promise<string[]> {
  const pending = await client.getPendingHandoffs(agent.agentId);
  const accepted: string[] = [];

  for (const request of pending) {
    console.log(`\n[${agent.agentId}] Evaluating handoff ${request.requestId}`);
    console.log(`  From: ${request.fromAgent}`);
    console.log(`  Required: ${request.capabilitiesRequired.join(', ')}`);

    const hasAll = request.capabilitiesRequired.every((c) => agent.hasCapability(c));

    if (!hasAll) {
      const missing = request.capabilitiesRequired.filter((c) => !agent.hasCapability(c));
      await client.rejectHandoff(request.requestId, `Missing capabilities: ${missing.join(', ')}`);
      console.log(`  -> Rejected (missing: ${missing.join(', ')})`);
      continue;
    }

    if (!agent.canAcceptWork()) {
      await client.rejectHandoff(request.requestId, 'Agent is busy with another task');
      console.log('  -> Rejected (busy)');
      continue;
    }

    await client.acceptHandoff(request.requestId);
    agent.markBusy(request.requestId);
    accepted.push(request.requestId);
    console.log(`  -> Accepted`);
  }

  return accepted;
}

// ============================================================================
// Scenario 1: Successful Handoff (Code → Security)
// ============================================================================

async function scenario1_SuccessfulHandoff(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 1: Successful Handoff (Code -> Security)');
  console.log('='.repeat(60));

  const client = new HandoffClient();
  const codeAgent = new Agent('code-agent', ['coding', 'refactoring', 'documentation']);
  const securityAgent = new Agent('security-agent', ['security-audit', 'vulnerability-scan']);

  console.log('\n[code-agent] Found security-sensitive code, requesting security review...');

  const request: HandoffRequest = {
    requestId: `handoff-${Date.now()}-1`,
    fromAgent: codeAgent.agentId,
    toAgent: securityAgent.agentId,
    reason: 'Security review needed for authentication module',
    contextSnapshot: new TextEncoder().encode(
      JSON.stringify({
        file_path: 'src/auth/login.ts',
        code_hash: 'abc123',
        concern: 'Handling of user credentials',
        lines_affected: [45, 67, 89],
      })
    ),
    capabilitiesRequired: ['security-audit'],
    priority: 5,
    timeoutMs: 5000,
  };

  // requestHandoff polls until a response arrives or times out.
  // We run it concurrently with the target agent's accept logic.
  const [response] = await Promise.all([
    client.requestHandoff(request),
    (async () => {
      // Small delay so the request is stored before we query pending
      await new Promise((r) => setTimeout(r, 200));
      await processPendingHandoffs(client, securityAgent);
    })(),
  ]);

  console.log(`\n[Handoff] Result: accepted=${response.accepted}`);

  // Simulate the security agent completing work, then releasing
  console.log('\n[security-agent] Performing security audit...');
  await new Promise((r) => setTimeout(r, 100));
  securityAgent.markFree();
  console.log('[security-agent] Audit complete.');
}

// ============================================================================
// Scenario 2: Rejected Handoff (Missing Capabilities)
// ============================================================================

async function scenario2_RejectedHandoff(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 2: Rejected Handoff (Missing Capabilities)');
  console.log('='.repeat(60));

  const client = new HandoffClient();
  const codeAgent = new Agent('code-agent-2', ['coding']);
  const docsAgent = new Agent('docs-agent', ['documentation', 'markdown']);

  console.log('\n[code-agent-2] Requesting deployment assistance from docs agent (wrong agent)...');

  const request: HandoffRequest = {
    requestId: `handoff-${Date.now()}-2`,
    fromAgent: codeAgent.agentId,
    toAgent: docsAgent.agentId,
    reason: 'Need help with Kubernetes deployment',
    contextSnapshot: new TextEncoder().encode(
      JSON.stringify({
        deployment_config: 'k8s/deployment.yaml',
        environment: 'production',
      })
    ),
    capabilitiesRequired: ['kubernetes', 'deployment'],
    priority: 5,
    timeoutMs: 5000,
  };

  const [response] = await Promise.all([
    client.requestHandoff(request),
    (async () => {
      await new Promise((r) => setTimeout(r, 200));
      await processPendingHandoffs(client, docsAgent);
    })(),
  ]);

  console.log(`\n[Handoff] Result: accepted=${response.accepted}`);
  console.log(`  Reason: ${response.rejectionReason}`);
}

// ============================================================================
// Scenario 3: Rejected Handoff (Busy Agent)
// ============================================================================

async function scenario3_BusyAgent(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 3: Rejected Handoff (Busy Agent)');
  console.log('='.repeat(60));

  const client = new HandoffClient();
  const agent1 = new Agent('agent-1', ['task-a']);
  const agent2 = new Agent('agent-2', ['task-a', 'task-b']);

  // First handoff — agent2 accepts
  console.log('\n[agent-1] First handoff request...');
  const req1: HandoffRequest = {
    requestId: `handoff-${Date.now()}-3a`,
    fromAgent: agent1.agentId,
    toAgent: agent2.agentId,
    reason: 'Task A work',
    contextSnapshot: new TextEncoder().encode(JSON.stringify({ task: 'first' })),
    capabilitiesRequired: ['task-a'],
    priority: 5,
    timeoutMs: 5000,
  };

  const [response1] = await Promise.all([
    client.requestHandoff(req1),
    (async () => {
      await new Promise((r) => setTimeout(r, 200));
      await processPendingHandoffs(client, agent2);
    })(),
  ]);
  console.log(`\nFirst request: accepted=${response1.accepted}`);

  // Second handoff — agent2 is now busy, should reject
  console.log('\n[agent-1] Second handoff request while agent-2 is busy...');
  const req2: HandoffRequest = {
    requestId: `handoff-${Date.now()}-3b`,
    fromAgent: agent1.agentId,
    toAgent: agent2.agentId,
    reason: 'More Task A work',
    contextSnapshot: new TextEncoder().encode(JSON.stringify({ task: 'second' })),
    capabilitiesRequired: ['task-a'],
    priority: 5,
    timeoutMs: 5000,
  };

  const [response2] = await Promise.all([
    client.requestHandoff(req2),
    (async () => {
      await new Promise((r) => setTimeout(r, 200));
      await processPendingHandoffs(client, agent2);
    })(),
  ]);
  console.log(`\nSecond request: accepted=${response2.accepted}`);
  console.log(`  Reason: ${response2.rejectionReason}`);

  // Agent2 finishes first task
  agent2.markFree();
}

// ============================================================================
// Scenario 4: Context Preservation
// ============================================================================

async function scenario4_ContextPreservation(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 4: Context Preservation');
  console.log('='.repeat(60));

  const client = new HandoffClient();
  const codeAgent = new Agent('code-agent-3', ['coding']);
  const reviewAgent = new Agent('review-agent', ['code-review', 'quality-check']);

  const complexContext = {
    pull_request: {
      id: 'PR-123',
      title: 'Add user authentication',
      files_changed: 15,
      additions: 450,
      deletions: 120,
    },
    code_analysis: {
      complexity_score: 7.5,
      test_coverage: 85.2,
      lint_warnings: 3,
    },
    previous_reviews: [
      { reviewer: 'auto-lint', status: 'passed', timestamp: '2024-01-15T10:00:00Z' },
      { reviewer: 'type-check', status: 'passed', timestamp: '2024-01-15T10:01:00Z' },
    ],
    priority: 'high',
    deadline: '2024-01-16T18:00:00Z',
  };

  console.log('\n[code-agent-3] Handing off for code review with rich context...');

  const request: HandoffRequest = {
    requestId: `handoff-${Date.now()}-4`,
    fromAgent: codeAgent.agentId,
    toAgent: reviewAgent.agentId,
    reason: 'PR ready for human-like code review',
    contextSnapshot: new TextEncoder().encode(JSON.stringify(complexContext)),
    capabilitiesRequired: ['code-review'],
    priority: 3,
    timeoutMs: 5000,
  };

  const [response] = await Promise.all([
    client.requestHandoff(request),
    (async () => {
      await new Promise((r) => setTimeout(r, 200));
      await processPendingHandoffs(client, reviewAgent);
    })(),
  ]);

  console.log(`\n[Handoff] Result: accepted=${response.accepted}`);

  // Verify context was preserved by reading it back from the stored request
  const storedRequest = await client.getHandoffRequest(request.requestId);
  if (storedRequest) {
    const receivedContext = JSON.parse(
      new TextDecoder().decode(storedRequest.contextSnapshot)
    );
    console.log('\n[review-agent] Received context:');
    console.log(JSON.stringify(receivedContext, null, 2));
  }

  reviewAgent.markFree();
}

// ============================================================================
// Scenario 5: Handoff Timeout (No Agent Responds)
// ============================================================================

async function scenario5_Timeout(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 5: Handoff Timeout (No Agent Responds)');
  console.log('='.repeat(60));

  const client = new HandoffClient();
  const agent = new Agent('timeout-requester', ['coding']);

  console.log('\n[timeout-requester] Requesting handoff with very short timeout...');

  const request: HandoffRequest = {
    requestId: `handoff-${Date.now()}-5`,
    fromAgent: agent.agentId,
    toAgent: 'ghost-agent',
    reason: 'Need help from an unavailable agent',
    contextSnapshot: new TextEncoder().encode(JSON.stringify({ task: 'timeout-demo' })),
    capabilitiesRequired: ['unknown-capability'],
    priority: 5,
    timeoutMs: 500, // Very short timeout — no one will respond
  };

  const response = await client.requestHandoff(request);
  console.log(`\n[Handoff] Result: accepted=${response.accepted}`);
  console.log(`  Reason: ${response.rejectionReason}`);
  console.log(`  Rejection code: ${response.rejectionCode}`);
}

// ============================================================================
// Scenario 6: Cross-Swarm Delegation with BudgetEnvelope
// ============================================================================

async function scenario6_BudgetDelegation(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 6: Cross-Swarm Delegation with BudgetEnvelope');
  console.log('='.repeat(60));

  const client = new HandoffClient();
  const orchestratorAgent = new Agent('orchestrator', ['planning']);
  const workerAgent = new Agent('worker', ['data-processing']);

  console.log('\n[orchestrator] Delegating with budget constraints...');

  const budget: BudgetEnvelope = {
    deadlineEpochMs: Date.now() + 30_000, // 30 s from now
    tokenBudgetRemaining: 10_000,
    wallTimeRemainingMs: 25_000,
    currentDepth: 1,
    maxDelegationDepth: 3,
  };

  const policy: SwarmDelegationPolicy = {
    maxRetriesOnOverloaded: 3,
    initialBackoffMs: 200,
    backoffMultiplier: 2.0,
    maxBackoffMs: 5000,
    allowSpilloverRouting: true,
    maxRedirects: 2,
  };

  const request: HandoffRequest = {
    requestId: `handoff-${Date.now()}-6`,
    fromAgent: orchestratorAgent.agentId,
    toAgent: workerAgent.agentId,
    reason: 'Cross-swarm data processing delegation',
    contextSnapshot: new TextEncoder().encode(
      JSON.stringify({ dataset: 'batch-42', rows: 50000 })
    ),
    capabilitiesRequired: ['data-processing'],
    priority: 2,
    timeoutMs: 5000,
    budget,
    delegationPolicy: policy,
  };

  const [response] = await Promise.all([
    client.requestHandoff(request),
    (async () => {
      await new Promise((r) => setTimeout(r, 200));
      await processPendingHandoffs(client, workerAgent);
    })(),
  ]);

  console.log(`\n[Handoff] Result: accepted=${response.accepted}`);

  // Show the stored request preserves budget/policy
  const stored = await client.getHandoffRequest(request.requestId);
  if (stored?.budget) {
    console.log(`  Budget deadline: ${new Date(stored.budget.deadlineEpochMs).toISOString()}`);
    console.log(`  Token budget: ${stored.budget.tokenBudgetRemaining}`);
    console.log(`  Delegation depth: ${stored.budget.currentDepth}/${stored.budget.maxDelegationDepth}`);
  }
  if (stored?.delegationPolicy) {
    console.log(`  Max retries on overloaded: ${stored.delegationPolicy.maxRetriesOnOverloaded}`);
    console.log(`  Spillover routing: ${stored.delegationPolicy.allowSpilloverRouting}`);
  }

  // Demonstrate validation: budget with invalid deadline
  console.log('\n--- Budget Validation Error ---');
  try {
    const badRequest: HandoffRequest = {
      requestId: `handoff-${Date.now()}-6-bad`,
      fromAgent: 'test',
      toAgent: 'test2',
      reason: 'Bad budget',
      contextSnapshot: new Uint8Array(),
      capabilitiesRequired: [],
      priority: 5,
      timeoutMs: 1000,
      budget: { deadlineEpochMs: 0 }, // Invalid: zero deadline
    };
    await client.requestHandoff(badRequest);
  } catch (err) {
    console.log(`  Caught: ${(err as Error).name}: ${(err as Error).message}`);
  }

  workerAgent.markFree();
}

// ============================================================================
// Main
// ============================================================================

async function main(): Promise<number> {
  console.log('SW4RM Agent Handoff Example');
  console.log('='.repeat(60));
  console.log('\nThis example uses the SDK HandoffClient to demonstrate');
  console.log('agent-to-agent task handoff with capability-based routing.\n');

  await scenario1_SuccessfulHandoff();
  await scenario2_RejectedHandoff();
  await scenario3_BusyAgent();
  await scenario4_ContextPreservation();
  await scenario5_Timeout();
  await scenario6_BudgetDelegation();

  console.log('\n' + '='.repeat(60));
  console.log('SUMMARY');
  console.log('='.repeat(60));

  console.log('\nKey takeaways:');
  console.log('1. HandoffClient.requestHandoff() polls until the target agent responds');
  console.log('2. Target agents call acceptHandoff() or rejectHandoff() via getPendingHandoffs()');
  console.log('3. Context is preserved in contextSnapshot (Uint8Array) during handoff');
  console.log('4. Busy agents can reject with an appropriate reason');
  console.log('5. Requests time out automatically if no response arrives');
  console.log('6. Timed-out requests return accepted=false with ACK_TIMEOUT rejection code');
  console.log('7. BudgetEnvelope + SwarmDelegationPolicy enable cross-swarm delegation with constraints');

  return 0;
}

main().catch((err) => {
  console.error('[Fatal] Unhandled error:', err);
  process.exit(1);
});
