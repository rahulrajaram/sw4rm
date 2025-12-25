#!/usr/bin/env npx tsx
/**
 * Agent Handoff Example for SW4RM Protocol.
 *
 * This example demonstrates agent-to-agent task handoff:
 * - Requesting a handoff when current agent lacks capabilities
 * - Accepting or rejecting handoffs based on agent state
 * - Transferring context between agents
 * - Completing handoffs with proper state management
 *
 * Handoffs enable seamless task transfer between specialized agents
 * when work requires capabilities the current agent does not possess.
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *   - Build the SDK: `npm run build`
 *
 * Run:
 *   npx tsx examples/handoffExample.ts
 *
 * Note: This example uses mock implementations since HandoffClient
 * is not yet implemented in the JS SDK. See Phase 2.2 in IMPLEMENTATION_PLAN.md.
 *
 * @packageDocumentation
 */

// ============================================================================
// Type Definitions (matching handoff.proto)
// ============================================================================

/**
 * HandoffStatus tracks the state of a handoff request.
 */
enum HandoffStatus {
  HANDOFF_STATUS_UNSPECIFIED = 0,
  PENDING = 1,
  ACCEPTED = 2,
  REJECTED = 3,
  COMPLETED = 4,
  EXPIRED = 5,
}

/**
 * HandoffRequest represents a request to transfer work to another agent.
 */
interface HandoffRequest {
  request_id: string;
  from_agent: string;
  to_agent: string;
  reason: string;
  context_snapshot: Uint8Array;
  capabilities_required: string[];
  priority: number;
  timeout_ms: number;
}

/**
 * HandoffResponse represents an agent's response to a handoff request.
 */
interface HandoffResponse {
  request_id: string;
  accepted: boolean;
  accepting_agent: string;
  rejection_reason?: string;
}

/**
 * Stored handoff with full state tracking.
 */
interface StoredHandoff {
  request: HandoffRequest;
  status: HandoffStatus;
  response?: HandoffResponse;
  created_at: Date;
  updated_at: Date;
}

// ============================================================================
// Mock HandoffClient
// ============================================================================

/**
 * Mock HandoffClient for demonstration purposes.
 *
 * In production, this would be a gRPC client connecting to the
 * HandoffService. See Phase 2.2 in IMPLEMENTATION_PLAN.md.
 */
class MockHandoffClient {
  private handoffs = new Map<string, StoredHandoff>();
  private pendingByAgent = new Map<string, string[]>();

  /**
   * Request a handoff to another agent.
   */
  async requestHandoff(request: HandoffRequest): Promise<void> {
    console.log(`\n[Handoff] Request created:`);
    console.log(`  ID: ${request.request_id}`);
    console.log(`  From: ${request.from_agent}`);
    console.log(`  To: ${request.to_agent}`);
    console.log(`  Reason: ${request.reason}`);
    console.log(`  Required Capabilities: ${request.capabilities_required.join(', ')}`);
    console.log(`  Priority: ${request.priority}`);

    const stored: StoredHandoff = {
      request,
      status: HandoffStatus.PENDING,
      created_at: new Date(),
      updated_at: new Date(),
    };

    this.handoffs.set(request.request_id, stored);

    // Add to pending list for target agent
    const pending = this.pendingByAgent.get(request.to_agent) ?? [];
    pending.push(request.request_id);
    this.pendingByAgent.set(request.to_agent, pending);
  }

  /**
   * Accept a handoff request.
   */
  async acceptHandoff(response: HandoffResponse): Promise<void> {
    const stored = this.handoffs.get(response.request_id);
    if (!stored) {
      throw new Error(`Handoff not found: ${response.request_id}`);
    }

    if (stored.status !== HandoffStatus.PENDING) {
      throw new Error(`Handoff not pending: ${response.request_id}`);
    }

    stored.status = HandoffStatus.ACCEPTED;
    stored.response = response;
    stored.updated_at = new Date();

    console.log(`\n[Handoff] Accepted:`);
    console.log(`  ID: ${response.request_id}`);
    console.log(`  Accepting Agent: ${response.accepting_agent}`);

    // Remove from pending list
    this.removePending(stored.request.to_agent, response.request_id);
  }

  /**
   * Reject a handoff request.
   */
  async rejectHandoff(response: HandoffResponse): Promise<void> {
    const stored = this.handoffs.get(response.request_id);
    if (!stored) {
      throw new Error(`Handoff not found: ${response.request_id}`);
    }

    if (stored.status !== HandoffStatus.PENDING) {
      throw new Error(`Handoff not pending: ${response.request_id}`);
    }

    stored.status = HandoffStatus.REJECTED;
    stored.response = response;
    stored.updated_at = new Date();

    console.log(`\n[Handoff] Rejected:`);
    console.log(`  ID: ${response.request_id}`);
    console.log(`  Reason: ${response.rejection_reason}`);

    // Remove from pending list
    this.removePending(stored.request.to_agent, response.request_id);
  }

  /**
   * Complete a handoff after work is done.
   */
  async completeHandoff(requestId: string): Promise<void> {
    const stored = this.handoffs.get(requestId);
    if (!stored) {
      throw new Error(`Handoff not found: ${requestId}`);
    }

    if (stored.status !== HandoffStatus.ACCEPTED) {
      throw new Error(`Handoff not accepted: ${requestId}`);
    }

    stored.status = HandoffStatus.COMPLETED;
    stored.updated_at = new Date();

    console.log(`\n[Handoff] Completed: ${requestId}`);
  }

  /**
   * Get pending handoffs for an agent.
   */
  async getPendingHandoffs(agentId: string): Promise<HandoffRequest[]> {
    const pendingIds = this.pendingByAgent.get(agentId) ?? [];
    const requests: HandoffRequest[] = [];

    for (const id of pendingIds) {
      const stored = this.handoffs.get(id);
      if (stored && stored.status === HandoffStatus.PENDING) {
        requests.push(stored.request);
      }
    }

    return requests;
  }

  /**
   * Get handoff status.
   */
  getStatus(requestId: string): HandoffStatus | null {
    const stored = this.handoffs.get(requestId);
    return stored?.status ?? null;
  }

  /**
   * Get context from a handoff.
   */
  getContext(requestId: string): Record<string, unknown> | null {
    const stored = this.handoffs.get(requestId);
    if (!stored) return null;

    try {
      return JSON.parse(Buffer.from(stored.request.context_snapshot).toString('utf-8'));
    } catch {
      return null;
    }
  }

  private removePending(agentId: string, requestId: string): void {
    const pending = this.pendingByAgent.get(agentId) ?? [];
    const index = pending.indexOf(requestId);
    if (index !== -1) {
      pending.splice(index, 1);
      this.pendingByAgent.set(agentId, pending);
    }
  }
}

// ============================================================================
// Mock Agent
// ============================================================================

/**
 * Simulated agent with capabilities and state.
 */
class MockAgent {
  readonly agentId: string;
  readonly capabilities: string[];
  private busy = false;
  private currentTask: string | null = null;
  private handoffClient: MockHandoffClient;

  constructor(agentId: string, capabilities: string[], handoffClient: MockHandoffClient) {
    this.agentId = agentId;
    this.capabilities = capabilities;
    this.handoffClient = handoffClient;
  }

  /**
   * Check if agent has a required capability.
   */
  hasCapability(capability: string): boolean {
    return this.capabilities.includes(capability);
  }

  /**
   * Check if agent can accept new work.
   */
  canAcceptWork(): boolean {
    return !this.busy;
  }

  /**
   * Request handoff to another agent.
   */
  async requestHandoff(
    toAgent: string,
    reason: string,
    requiredCapabilities: string[],
    context: Record<string, unknown>
  ): Promise<string> {
    const requestId = `handoff-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

    const request: HandoffRequest = {
      request_id: requestId,
      from_agent: this.agentId,
      to_agent: toAgent,
      reason,
      context_snapshot: Buffer.from(JSON.stringify(context)),
      capabilities_required: requiredCapabilities,
      priority: 5,
      timeout_ms: 30000,
    };

    await this.handoffClient.requestHandoff(request);
    return requestId;
  }

  /**
   * Process pending handoff requests.
   */
  async processPendingHandoffs(): Promise<void> {
    const pending = await this.handoffClient.getPendingHandoffs(this.agentId);

    console.log(`\n[${this.agentId}] Processing ${pending.length} pending handoffs`);

    for (const request of pending) {
      console.log(`\n[${this.agentId}] Evaluating handoff ${request.request_id}:`);
      console.log(`  From: ${request.from_agent}`);
      console.log(`  Required: ${request.capabilities_required.join(', ')}`);

      // Check if we have required capabilities
      const hasAllCapabilities = request.capabilities_required.every((cap) => this.hasCapability(cap));

      if (!hasAllCapabilities) {
        const missingCaps = request.capabilities_required.filter((cap) => !this.hasCapability(cap));
        await this.handoffClient.rejectHandoff({
          request_id: request.request_id,
          accepted: false,
          accepting_agent: this.agentId,
          rejection_reason: `Missing capabilities: ${missingCaps.join(', ')}`,
        });
        continue;
      }

      // Check if we can accept work
      if (!this.canAcceptWork()) {
        await this.handoffClient.rejectHandoff({
          request_id: request.request_id,
          accepted: false,
          accepting_agent: this.agentId,
          rejection_reason: 'Agent is busy with another task',
        });
        continue;
      }

      // Accept the handoff
      await this.handoffClient.acceptHandoff({
        request_id: request.request_id,
        accepted: true,
        accepting_agent: this.agentId,
      });

      // Start working on the task
      this.busy = true;
      this.currentTask = request.request_id;

      // Get context
      const context = this.handoffClient.getContext(request.request_id);
      console.log(`[${this.agentId}] Starting work with context:`, context);
    }
  }

  /**
   * Complete current task.
   */
  async completeTask(): Promise<void> {
    if (!this.currentTask) {
      console.log(`[${this.agentId}] No task to complete`);
      return;
    }

    console.log(`\n[${this.agentId}] Completing task ${this.currentTask}`);

    await this.handoffClient.completeHandoff(this.currentTask);

    this.busy = false;
    this.currentTask = null;
  }
}

// ============================================================================
// Example Scenarios
// ============================================================================

/**
 * Scenario 1: Successful handoff from code agent to security agent.
 */
async function scenario1_SuccessfulHandoff(client: MockHandoffClient): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 1: Successful Handoff (Code -> Security)');
  console.log('='.repeat(60));

  // Create agents
  const codeAgent = new MockAgent('code-agent', ['coding', 'refactoring', 'documentation'], client);
  const securityAgent = new MockAgent('security-agent', ['security-audit', 'vulnerability-scan', 'penetration-test'], client);

  // Code agent encounters security-sensitive code and needs review
  console.log('\n[code-agent] Found security-sensitive code, requesting security review...');

  const requestId = await codeAgent.requestHandoff('security-agent', 'Security review needed for authentication module', ['security-audit'], {
    file_path: 'src/auth/login.ts',
    code_hash: 'abc123',
    concern: 'Handling of user credentials',
    lines_affected: [45, 67, 89],
  });

  // Security agent processes the request
  await securityAgent.processPendingHandoffs();

  // Security agent completes the review
  console.log('\n[security-agent] Performing security audit...');
  await new Promise((resolve) => setTimeout(resolve, 100));

  await securityAgent.completeTask();

  console.log('\nHandoff Status:', HandoffStatus[client.getStatus(requestId) ?? 0]);
}

/**
 * Scenario 2: Rejected handoff due to missing capabilities.
 */
async function scenario2_RejectedHandoff(client: MockHandoffClient): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 2: Rejected Handoff (Missing Capabilities)');
  console.log('='.repeat(60));

  // Create agents with non-overlapping capabilities
  const codeAgent = new MockAgent('code-agent-2', ['coding'], client);
  const docsAgent = new MockAgent('docs-agent', ['documentation', 'markdown'], client);

  // Code agent tries to hand off to docs agent for something docs agent cannot do
  console.log('\n[code-agent-2] Requesting deployment assistance from docs agent (wrong agent)...');

  const requestId = await codeAgent.requestHandoff('docs-agent', 'Need help with Kubernetes deployment', ['kubernetes', 'deployment'], {
    deployment_config: 'k8s/deployment.yaml',
    environment: 'production',
  });

  // Docs agent processes but will reject
  await docsAgent.processPendingHandoffs();

  console.log('\nHandoff Status:', HandoffStatus[client.getStatus(requestId) ?? 0]);
}

/**
 * Scenario 3: Rejected handoff due to busy agent.
 */
async function scenario3_BusyAgent(client: MockHandoffClient): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 3: Rejected Handoff (Busy Agent)');
  console.log('='.repeat(60));

  // Create agents
  const agent1 = new MockAgent('agent-1', ['task-a'], client);
  const agent2 = new MockAgent('agent-2', ['task-a', 'task-b'], client);

  // First, agent1 hands off to agent2 successfully
  console.log('\n[agent-1] First handoff request...');
  const request1 = await agent1.requestHandoff('agent-2', 'Task A work', ['task-a'], { task: 'first' });

  await agent2.processPendingHandoffs();

  // While agent2 is busy, another agent tries to hand off
  console.log('\n[agent-1] Second handoff request while agent-2 is busy...');
  const request2 = await agent1.requestHandoff('agent-2', 'More Task A work', ['task-a'], { task: 'second' });

  await agent2.processPendingHandoffs();

  console.log('\nFirst Request Status:', HandoffStatus[client.getStatus(request1) ?? 0]);
  console.log('Second Request Status:', HandoffStatus[client.getStatus(request2) ?? 0]);

  // Agent2 finishes first task
  await agent2.completeTask();
}

/**
 * Scenario 4: Context preservation during handoff.
 */
async function scenario4_ContextPreservation(client: MockHandoffClient): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 4: Context Preservation');
  console.log('='.repeat(60));

  const codeAgent = new MockAgent('code-agent-3', ['coding'], client);
  const reviewAgent = new MockAgent('review-agent', ['code-review', 'quality-check'], client);

  // Rich context to be preserved
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

  const requestId = await codeAgent.requestHandoff(
    'review-agent',
    'PR ready for human-like code review',
    ['code-review'],
    complexContext
  );

  // Review agent accepts
  await reviewAgent.processPendingHandoffs();

  // Verify context was preserved
  const receivedContext = client.getContext(requestId);
  console.log('\n[review-agent] Received context:');
  console.log(JSON.stringify(receivedContext, null, 2));

  await reviewAgent.completeTask();
}

/**
 * Main demonstration function.
 */
async function main(): Promise<number> {
  console.log('SW4RM Agent Handoff Example');
  console.log('='.repeat(60));
  console.log('\nThis example demonstrates agent-to-agent task handoff');
  console.log('for seamless capability-based work distribution.\n');

  const client = new MockHandoffClient();

  // Run all scenarios
  await scenario1_SuccessfulHandoff(client);
  await scenario2_RejectedHandoff(client);
  await scenario3_BusyAgent(client);
  await scenario4_ContextPreservation(client);

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log('SUMMARY');
  console.log('='.repeat(60));

  console.log('\nKey takeaways:');
  console.log('1. Handoffs enable task transfer when capabilities are lacking');
  console.log('2. Target agents can accept or reject based on state/capabilities');
  console.log('3. Context is preserved and transferred during handoff');
  console.log('4. Busy agents can reject with appropriate reason');
  console.log('5. Handoff lifecycle: PENDING -> ACCEPTED/REJECTED -> COMPLETED');

  console.log('\nHandoff Status Flow:');
  console.log('  PENDING    - Request created, awaiting response');
  console.log('  ACCEPTED   - Target agent accepted the handoff');
  console.log('  REJECTED   - Target agent declined (with reason)');
  console.log('  COMPLETED  - Work finished by accepting agent');
  console.log('  EXPIRED    - Request timed out without response');

  return 0;
}

// Entry point
main().catch((err) => {
  console.error('[Fatal] Unhandled error:', err);
  process.exit(1);
});
