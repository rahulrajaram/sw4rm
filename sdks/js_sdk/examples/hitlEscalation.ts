#!/usr/bin/env npx tsx
/**
 * Human-in-the-Loop (HITL) Escalation Example for SW4RM Protocol.
 *
 * This example demonstrates:
 * - Triggering HITL escalation when agent confidence is low
 * - Handling HITL decisions for unresolved conflicts
 * - DEBATE_DEADLOCK handling when multi-agent debates fail
 * - Integrating human decisions back into agent workflows
 *
 * HITL is a critical safety mechanism in SW4RM that ensures human
 * oversight for high-stakes decisions and edge cases that agents
 * cannot confidently resolve autonomously.
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *   - Build the SDK: `npm run build`
 *
 * Run:
 *   npx tsx examples/hitlEscalation.ts
 *
 * @packageDocumentation
 */

import { HITLClient } from '../src/clients/hitl.js';
import type { HitlInvocation, HitlDecision } from '../src/clients/hitl.js';

// ============================================================================
// Extended Type Definitions
// ============================================================================

/**
 * HitlReasonType enumerates the reasons for HITL escalation.
 * These map to the HITL service's reason types in hitl.proto.
 */
enum HitlReasonType {
  UNSPECIFIED = 'UNSPECIFIED',
  UNCERTAINTY_HIGH = 'UNCERTAINTY_HIGH',
  RISK_HIGH = 'RISK_HIGH',
  POLICY_REQUIRED = 'POLICY_REQUIRED',
  USER_REQUESTED = 'USER_REQUESTED',
  CONFLICT_UNRESOLVED = 'CONFLICT_UNRESOLVED',
  BUDGET_EXCEEDED = 'BUDGET_EXCEEDED',
  DEBATE_DEADLOCK = 'DEBATE_DEADLOCK',
  SECURITY_APPROVAL = 'SECURITY_APPROVAL',
}

/**
 * Extended HITL invocation with structured context.
 */
interface ExtendedHitlInvocation {
  correlation_id: string;
  reason_type: HitlReasonType;
  context: Record<string, unknown>;
  options: string[];
  timeout_ms: number;
  metadata: Record<string, unknown>;
}

/**
 * Extended HITL decision with additional metadata.
 */
interface ExtendedHitlDecision {
  invocation_id: string;
  chosen_option: string;
  confidence: number;
  reason: string;
  timestamp_ms: number;
}

// ============================================================================
// Mock HITL Service
// ============================================================================

/**
 * Mock HITL service for demonstration purposes.
 *
 * In production, this would connect to a real HITL service via gRPC,
 * which provides UI for human operators to review and decide.
 */
class MockHitlService {
  private autoDecision: string | null;
  private delayMs: number;
  private pendingInvocations = new Map<string, ExtendedHitlInvocation>();
  private decisions = new Map<string, ExtendedHitlDecision>();
  private invocationCounter = 0;

  constructor(options: { autoDecision?: string; delayMs?: number } = {}) {
    this.autoDecision = options.autoDecision ?? null;
    this.delayMs = options.delayMs ?? 100;
  }

  /**
   * Submit a HITL invocation for human decision.
   */
  async submit(invocation: ExtendedHitlInvocation): Promise<string> {
    const invocationId = `hitl-${++this.invocationCounter}-${Date.now()}`;

    console.log(`\n[HITL] Invocation submitted: ${invocationId}`);
    console.log(`  Reason: ${invocation.reason_type}`);
    console.log(`  Options: ${invocation.options.join(', ')}`);
    console.log(`  Context:`, JSON.stringify(invocation.context, null, 2));

    this.pendingInvocations.set(invocationId, invocation);
    return invocationId;
  }

  /**
   * Wait for and retrieve a human decision.
   */
  async getDecision(invocationId: string): Promise<ExtendedHitlDecision | null> {
    const invocation = this.pendingInvocations.get(invocationId);
    if (!invocation) {
      return null;
    }

    // Simulate decision delay
    await new Promise((resolve) => setTimeout(resolve, this.delayMs));

    // Determine decision
    let chosenOption: string;
    let reason: string;
    let confidence: number;

    if (this.autoDecision && invocation.options.includes(this.autoDecision)) {
      chosenOption = this.autoDecision;
      reason = 'Auto-decided by test configuration';
      confidence = 0.9;
    } else {
      // Default: choose first option
      chosenOption = invocation.options[0];
      reason = 'Demo mode: selected first option';
      confidence = 0.8;
    }

    const decision: ExtendedHitlDecision = {
      invocation_id: invocationId,
      chosen_option: chosenOption,
      confidence,
      reason,
      timestamp_ms: Date.now(),
    };

    this.decisions.set(invocationId, decision);
    this.pendingInvocations.delete(invocationId);

    console.log(`\n[HITL] Decision received for ${invocationId}`);
    console.log(`  Chosen: ${decision.chosen_option}`);
    console.log(`  Confidence: ${(decision.confidence * 100).toFixed(0)}%`);
    console.log(`  Reason: ${decision.reason}`);

    return decision;
  }

  /**
   * Set auto-decision mode for testing.
   */
  setAutoDecision(decision: string | null): void {
    this.autoDecision = decision;
  }
}

// ============================================================================
// Escalation Handler
// ============================================================================

/**
 * EscalationHandler provides patterns for escalating to HITL.
 *
 * This class encapsulates common escalation scenarios and handles
 * the interaction with the HITL service.
 */
class EscalationHandler {
  private hitlService: MockHitlService;
  private agentId: string;
  private escalationCount = 0;

  constructor(hitlService: MockHitlService, agentId: string) {
    this.hitlService = hitlService;
    this.agentId = agentId;
  }

  /**
   * Escalate when agent confidence is below threshold.
   *
   * This is the most common escalation pattern - the agent has
   * multiple options but isn't confident enough to choose.
   */
  async escalateUncertainty(
    taskDescription: string,
    confidence: number,
    options: string[],
    threshold = 0.7
  ): Promise<string | null> {
    if (confidence >= threshold) {
      console.log(
        `[Escalation] Confidence ${(confidence * 100).toFixed(0)}% >= threshold ${(threshold * 100).toFixed(0)}%, no escalation needed`
      );
      return null;
    }

    console.log(`\n[Escalation] Low confidence (${(confidence * 100).toFixed(0)}%) for: ${taskDescription}`);
    console.log('[Escalation] Escalating to HITL for human decision...');

    const invocation: ExtendedHitlInvocation = {
      correlation_id: `corr-${Date.now()}`,
      reason_type: HitlReasonType.UNCERTAINTY_HIGH,
      context: {
        agent_id: this.agentId,
        task: taskDescription,
        agent_confidence: confidence,
        threshold,
        escalation_reason: 'Agent confidence below threshold',
      },
      options,
      timeout_ms: 30000,
      metadata: {},
    };

    const invocationId = await this.hitlService.submit(invocation);
    const decision = await this.hitlService.getDecision(invocationId);

    if (decision) {
      this.escalationCount++;
      return decision.chosen_option;
    }

    console.log('[Escalation] HITL timeout - no decision received');
    return null;
  }

  /**
   * Escalate unresolved conflict between agents.
   *
   * When multiple agents have conflicting proposals and cannot
   * reach consensus, escalate to human for resolution.
   */
  async escalateConflict(
    agentsInvolved: string[],
    conflictingProposals: Record<string, Record<string, unknown>>,
    conflictDescription: string
  ): Promise<string | null> {
    console.log(`\n[Escalation] Conflict detected between: ${agentsInvolved.join(', ')}`);
    console.log(`[Escalation] Description: ${conflictDescription}`);

    const options = [...agentsInvolved.map((a) => `accept_${a}`), 'reject_all', 'merge_proposals'];

    const invocation: ExtendedHitlInvocation = {
      correlation_id: `corr-${Date.now()}`,
      reason_type: HitlReasonType.CONFLICT_UNRESOLVED,
      context: {
        escalating_agent: this.agentId,
        agents_involved: agentsInvolved,
        proposals: conflictingProposals,
        conflict_description: conflictDescription,
      },
      options,
      timeout_ms: 30000,
      metadata: { priority: 'high', category: 'multi_agent_conflict' },
    };

    const invocationId = await this.hitlService.submit(invocation);
    const decision = await this.hitlService.getDecision(invocationId);

    if (decision) {
      this.escalationCount++;
      return decision.chosen_option;
    }

    return null;
  }

  /**
   * Escalate when multi-agent debate fails to converge.
   *
   * After N rounds of debate, if agents still disagree significantly,
   * escalate to human to break the deadlock.
   */
  async escalateDebateDeadlock(
    debateId: string,
    debateRounds: number,
    finalPositions: Record<string, { stance: string; confidence: number; arguments: string[] }>,
    maxRounds = 5
  ): Promise<string | null> {
    console.log(`\n[Escalation] Debate deadlock detected!`);
    console.log(`  Debate ID: ${debateId}`);
    console.log(`  Rounds: ${debateRounds}/${maxRounds}`);
    console.log('  Final positions:');

    for (const [agent, position] of Object.entries(finalPositions)) {
      console.log(`    ${agent}:`);
      console.log(`      Stance: ${position.stance}`);
      console.log(`      Confidence: ${(position.confidence * 100).toFixed(0)}%`);
      console.log(`      Arguments: ${position.arguments.join('; ')}`);
    }

    const options = [...Object.keys(finalPositions), 'compromise', 'defer_decision'];

    const invocation: ExtendedHitlInvocation = {
      correlation_id: `corr-${Date.now()}`,
      reason_type: HitlReasonType.DEBATE_DEADLOCK,
      context: {
        debate_id: debateId,
        rounds_completed: debateRounds,
        max_rounds: maxRounds,
        final_positions: finalPositions,
        escalating_agent: this.agentId,
      },
      options,
      timeout_ms: 60000,
      metadata: { debate_intensity: 'high', requires_domain_expertise: true },
    };

    const invocationId = await this.hitlService.submit(invocation);
    const decision = await this.hitlService.getDecision(invocationId);

    if (decision) {
      this.escalationCount++;
      return decision.chosen_option;
    }

    return null;
  }

  /**
   * Escalate for approval when proposed action is high-risk.
   *
   * Certain actions require explicit human approval before execution,
   * such as production deployments or data deletions.
   */
  async escalateHighRisk(
    actionDescription: string,
    riskAssessment: { level: string; impacts: string[]; mitigations: string[] },
    proposedAction: string
  ): Promise<boolean> {
    console.log(`\n[Escalation] High-risk action requiring approval`);
    console.log(`  Action: ${actionDescription}`);
    console.log(`  Risk Level: ${riskAssessment.level}`);
    console.log(`  Impacts: ${riskAssessment.impacts.join(', ')}`);
    console.log(`  Mitigations: ${riskAssessment.mitigations.join(', ')}`);

    const invocation: ExtendedHitlInvocation = {
      correlation_id: `corr-${Date.now()}`,
      reason_type: HitlReasonType.RISK_HIGH,
      context: {
        agent_id: this.agentId,
        action: actionDescription,
        proposed_action: proposedAction,
        risk_assessment: riskAssessment,
      },
      options: ['approve', 'reject', 'modify'],
      timeout_ms: 30000,
      metadata: { requires_immediate_attention: riskAssessment.level === 'critical' },
    };

    const invocationId = await this.hitlService.submit(invocation);
    const decision = await this.hitlService.getDecision(invocationId);

    if (decision && decision.chosen_option === 'approve') {
      this.escalationCount++;
      console.log('[Escalation] Action APPROVED by human operator');
      return true;
    }

    console.log(`[Escalation] Action NOT approved: ${decision?.chosen_option ?? 'timeout'}`);
    return false;
  }

  /**
   * Get total escalation count.
   */
  getEscalationCount(): number {
    return this.escalationCount;
  }
}

// ============================================================================
// Example Scenarios
// ============================================================================

/**
 * Scenario 1: Low confidence classification.
 */
async function scenario1_UncertaintyEscalation(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 1: Uncertainty Escalation');
  console.log('='.repeat(60));

  const hitlService = new MockHitlService({ autoDecision: 'internal' });
  const handler = new EscalationHandler(hitlService, 'classifier-agent');

  // Agent must classify a document but is uncertain
  const result = await handler.escalateUncertainty(
    "Classify document 'project-roadmap-2024.pdf'",
    0.45, // Low confidence
    ['public', 'internal', 'confidential'],
    0.7
  );

  console.log(`\nResult: Document classified as '${result}'`);
}

/**
 * Scenario 2: Multi-agent conflict.
 */
async function scenario2_ConflictEscalation(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 2: Multi-Agent Conflict Escalation');
  console.log('='.repeat(60));

  const hitlService = new MockHitlService({ autoDecision: 'accept_security-agent' });
  const handler = new EscalationHandler(hitlService, 'orchestrator');

  const result = await handler.escalateConflict(
    ['performance-agent', 'security-agent'],
    {
      'performance-agent': {
        recommendation: 'Enable aggressive caching',
        justification: 'Reduces latency by 40%',
        risk_score: 0.2,
      },
      'security-agent': {
        recommendation: 'Disable caching for authenticated endpoints',
        justification: 'Prevents credential leakage',
        risk_score: 0.8,
      },
    },
    'Performance vs Security trade-off for API caching configuration'
  );

  console.log(`\nResult: Conflict resolved with: '${result}'`);
}

/**
 * Scenario 3: Debate deadlock.
 */
async function scenario3_DebateDeadlock(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 3: Debate Deadlock Escalation');
  console.log('='.repeat(60));

  const hitlService = new MockHitlService({ autoDecision: 'agent-gamma' });
  const handler = new EscalationHandler(hitlService, 'moderator');

  const result = await handler.escalateDebateDeadlock(
    'arch-debate-001',
    5,
    {
      'agent-alpha': {
        stance: 'Microservices architecture',
        confidence: 0.85,
        arguments: ['Better scalability', 'Independent deployments', 'Team autonomy'],
      },
      'agent-beta': {
        stance: 'Monolithic architecture',
        confidence: 0.78,
        arguments: ['Simpler development', 'Lower latency', 'Easier debugging'],
      },
      'agent-gamma': {
        stance: 'Modular monolith',
        confidence: 0.72,
        arguments: ['Best of both worlds', 'Clear boundaries', 'Easier migration'],
      },
    },
    5
  );

  console.log(`\nResult: Debate resolved by selecting: '${result}'`);
}

/**
 * Scenario 4: High-risk approval.
 */
async function scenario4_HighRiskApproval(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 4: High-Risk Action Approval');
  console.log('='.repeat(60));

  const hitlService = new MockHitlService({ autoDecision: 'approve' });
  const handler = new EscalationHandler(hitlService, 'deploy-agent');

  const approved = await handler.escalateHighRisk(
    'Deploy v2.5.0 to production during business hours',
    {
      level: 'high',
      impacts: ['Service disruption possible', '50,000 active users', 'Revenue impact if failed'],
      mitigations: ['Canary deployment', 'Automatic rollback', 'Real-time monitoring'],
    },
    'kubectl apply -f prod/deployment-v2.5.0.yaml'
  );

  console.log(`\nResult: Deployment ${approved ? 'APPROVED' : 'REJECTED'}`);
}

/**
 * Scenario 5: Using the actual SDK HITLClient interface.
 */
async function scenario5_SdkClientDemo(): Promise<void> {
  console.log('\n' + '='.repeat(60));
  console.log('SCENARIO 5: SDK HITLClient Interface Demo');
  console.log('='.repeat(60));

  console.log('\nNote: This shows the SDK HITLClient interface.');
  console.log('In production, you would connect to a real HITL service.\n');

  // Demonstrate the SDK interface (without actual connection)
  console.log('HITLClient interface:');
  console.log('  const client = new HITLClient({ address: "hitl.example.com:50053" });');
  console.log('');
  console.log('  // Submit invocation');
  console.log('  const decision = await client.decide({');
  console.log('    reason_type: "UNCERTAINTY_HIGH",');
  console.log('    context: Buffer.from(JSON.stringify({ task: "classify", confidence: 0.45 })),');
  console.log('    proposed_actions: ["public", "internal", "confidential"],');
  console.log('    priority: 1');
  console.log('  });');
  console.log('');
  console.log('  // Process decision');
  console.log('  console.log("Human chose:", decision.action);');
  console.log('  console.log("Rationale:", decision.rationale);');
}

/**
 * Main demonstration function.
 */
async function main(): Promise<number> {
  console.log('SW4RM HITL Escalation Example');
  console.log('='.repeat(60));
  console.log('\nThis example demonstrates Human-in-the-Loop escalation patterns');
  console.log('for handling uncertainty, conflicts, and high-risk decisions.\n');

  // Run all scenarios
  await scenario1_UncertaintyEscalation();
  await scenario2_ConflictEscalation();
  await scenario3_DebateDeadlock();
  await scenario4_HighRiskApproval();
  await scenario5_SdkClientDemo();

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log('SUMMARY');
  console.log('='.repeat(60));

  console.log('\nHITL Reason Types:');
  console.log('  UNCERTAINTY_HIGH   - Agent confidence below threshold');
  console.log('  RISK_HIGH          - Action requires explicit approval');
  console.log('  CONFLICT_UNRESOLVED - Agents cannot agree');
  console.log('  DEBATE_DEADLOCK    - Multi-round debate failed to converge');
  console.log('  POLICY_REQUIRED    - Policy mandates human review');
  console.log('  BUDGET_EXCEEDED    - Resource limits exceeded');
  console.log('  SECURITY_APPROVAL  - Security-sensitive action');
  console.log('  USER_REQUESTED     - Explicit user request for human review');

  console.log('\nKey takeaways:');
  console.log('1. Use UNCERTAINTY_HIGH when agent confidence is below threshold');
  console.log('2. Use CONFLICT_UNRESOLVED when agents cannot agree');
  console.log('3. Use DEBATE_DEADLOCK when multi-round debates fail to converge');
  console.log('4. Use RISK_HIGH for actions requiring explicit human approval');
  console.log('5. Always provide clear context and options for human operators');
  console.log('6. Handle timeout scenarios gracefully with fallback behavior');

  return 0;
}

// Entry point
main().catch((err) => {
  console.error('[Fatal] Unhandled error:', err);
  process.exit(1);
});
