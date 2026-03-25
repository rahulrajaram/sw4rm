#!/usr/bin/env npx tsx
/**
 * Negotiation Room Example for SW4RM Protocol.
 *
 * This example demonstrates the producer-critic-coordinator pattern using
 * the real SDK NegotiationRoomClient:
 * - A producer agent submits an artifact (code, plan, requirements)
 * - Multiple critic agents evaluate and vote on the artifact
 * - A coordinator aggregates votes and stores a final decision
 *
 * The negotiation room pattern enables structured multi-agent review
 * with configurable thresholds and HITL escalation for edge cases.
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *
 * Run:
 *   npx tsx examples/negotiationRoomExample.ts
 *
 * Execution mode:
 *   - Local in-memory demo using the SDK's NegotiationRoomClient with a
 *     shared in-memory store. No external services are required. Multiple
 *     client instances share state via the default store, just as they
 *     would in a multi-agent single-process deployment.
 *
 * @packageDocumentation
 */

import {
  NegotiationRoomClient,
  ArtifactType,
  DecisionOutcome,
  aggregateVotes,
  InMemoryNegotiationRoomStore,
  ConfidenceWeightedAggregator,
} from '../src/index.js';
import type {
  NegotiationProposal,
  NegotiationVote,
  NegotiationDecision,
  AggregatedScore,
} from '../src/index.js';

// ============================================================================
// Policy Constants
// ============================================================================

const APPROVAL_THRESHOLD = 7.0;
const MIN_CONFIDENCE = 0.6;
const MIN_VOTES = 2;

// ============================================================================
// Coordinator Decision Logic
// ============================================================================

/**
 * Apply policy thresholds to determine the decision outcome.
 *
 * In production this logic would live in a dedicated coordinator agent
 * or in the policy-store module. Here it shows the decision rules
 * alongside the SDK aggregation helper.
 */
function determineOutcome(
  aggregated: AggregatedScore,
  votes: NegotiationVote[]
): { outcome: DecisionOutcome; reason: string } {
  if (aggregated.voteCount < MIN_VOTES) {
    return {
      outcome: DecisionOutcome.ESCALATED_TO_HITL,
      reason: `Insufficient votes (${aggregated.voteCount}/${MIN_VOTES})`,
    };
  }

  const avgConfidence = votes.reduce((s, v) => s + v.confidence, 0) / votes.length;
  if (avgConfidence < MIN_CONFIDENCE) {
    return {
      outcome: DecisionOutcome.ESCALATED_TO_HITL,
      reason: `Low average confidence (${(avgConfidence * 100).toFixed(0)}% < ${(MIN_CONFIDENCE * 100).toFixed(0)}%)`,
    };
  }

  const allPassed = votes.every((v) => v.passed);

  if (aggregated.weightedMean >= APPROVAL_THRESHOLD && allPassed) {
    return {
      outcome: DecisionOutcome.APPROVED,
      reason: `Weighted mean ${aggregated.weightedMean.toFixed(2)} >= ${APPROVAL_THRESHOLD}, all critics passed`,
    };
  }

  if (aggregated.weightedMean >= APPROVAL_THRESHOLD * 0.8) {
    const weaknesses = votes.flatMap((v) => v.weaknesses);
    return {
      outcome: DecisionOutcome.REVISION_REQUESTED,
      reason: `Score ${aggregated.weightedMean.toFixed(2)} needs improvement. Issues: ${weaknesses.slice(0, 3).join('; ')}`,
    };
  }

  if (aggregated.stdDev > 2.0) {
    return {
      outcome: DecisionOutcome.ESCALATED_TO_HITL,
      reason: `High disagreement among critics (std dev: ${aggregated.stdDev.toFixed(2)})`,
    };
  }

  return {
    outcome: DecisionOutcome.REVISION_REQUESTED,
    reason: `Score ${aggregated.weightedMean.toFixed(2)} below threshold ${APPROVAL_THRESHOLD}`,
  };
}

// ============================================================================
// Agent Simulation
// ============================================================================

/**
 * Simulate a producer agent submitting code for review.
 */
async function simulateProducer(
  client: NegotiationRoomClient,
  roomId: string
): Promise<string> {
  console.log('\n' + '='.repeat(60));
  console.log('PRODUCER: Submitting code for review');
  console.log('='.repeat(60));

  const proposal: NegotiationProposal = {
    artifactType: ArtifactType.CODE,
    artifactId: `artifact-${Date.now()}`,
    producerId: 'producer-agent-1',
    artifact: new TextEncoder().encode(
      JSON.stringify({
        language: 'typescript',
        file: 'auth.ts',
        content: `
export async function authenticate(token: string): Promise<User> {
  const decoded = jwt.verify(token, SECRET_KEY);
  return await UserService.findById(decoded.userId);
}`,
      })
    ),
    artifactContentType: 'application/json',
    requestedCritics: ['security-critic', 'code-quality-critic', 'architecture-critic'],
    negotiationRoomId: roomId,
  };

  const artifactId = await client.submitProposal(proposal);
  console.log(`  Artifact ID: ${artifactId}`);
  console.log(`  Type: ${ArtifactType[proposal.artifactType]}`);
  console.log(`  Producer: ${proposal.producerId}`);
  console.log(`  Requested Critics: ${proposal.requestedCritics.join(', ')}`);

  return artifactId;
}

/**
 * Simulate a security critic evaluating the code.
 */
async function simulateSecurityCritic(
  client: NegotiationRoomClient,
  artifactId: string,
  roomId: string
): Promise<void> {
  console.log('\n' + '-'.repeat(60));
  console.log('CRITIC: Security Review');
  console.log('-'.repeat(60));

  const vote: NegotiationVote = {
    artifactId,
    criticId: 'security-critic',
    score: 6.5,
    confidence: 0.85,
    passed: false,
    strengths: ['Uses JWT verification', 'Async/await pattern for database calls'],
    weaknesses: [
      'SECRET_KEY should not be hardcoded',
      'Missing token expiration check',
      'No rate limiting on authentication',
    ],
    recommendations: [
      'Use environment variables for secrets',
      'Add explicit expiration validation',
      'Implement rate limiting middleware',
    ],
    negotiationRoomId: roomId,
  };

  await client.submitVote(vote);
  console.log(`  Score: ${vote.score}/10  Confidence: ${(vote.confidence * 100).toFixed(0)}%  Passed: ${vote.passed}`);
}

/**
 * Simulate a code quality critic evaluating the code.
 */
async function simulateCodeQualityCritic(
  client: NegotiationRoomClient,
  artifactId: string,
  roomId: string
): Promise<void> {
  console.log('\n' + '-'.repeat(60));
  console.log('CRITIC: Code Quality Review');
  console.log('-'.repeat(60));

  const vote: NegotiationVote = {
    artifactId,
    criticId: 'code-quality-critic',
    score: 8.0,
    confidence: 0.9,
    passed: true,
    strengths: [
      'Clean function signature with types',
      'Proper async/await usage',
      'Single responsibility principle',
    ],
    weaknesses: [
      'Missing error handling for jwt.verify',
      'No input validation for token',
    ],
    recommendations: [
      'Add try-catch for JWT verification',
      'Validate token format before processing',
    ],
    negotiationRoomId: roomId,
  };

  await client.submitVote(vote);
  console.log(`  Score: ${vote.score}/10  Confidence: ${(vote.confidence * 100).toFixed(0)}%  Passed: ${vote.passed}`);
}

/**
 * Simulate an architecture critic evaluating the code.
 */
async function simulateArchitectureCritic(
  client: NegotiationRoomClient,
  artifactId: string,
  roomId: string
): Promise<void> {
  console.log('\n' + '-'.repeat(60));
  console.log('CRITIC: Architecture Review');
  console.log('-'.repeat(60));

  const vote: NegotiationVote = {
    artifactId,
    criticId: 'architecture-critic',
    score: 7.5,
    confidence: 0.75,
    passed: true,
    strengths: ['Clean separation of concerns', 'Uses service layer pattern', 'Async-first design'],
    weaknesses: ['Direct dependency on UserService', 'No dependency injection'],
    recommendations: [
      'Consider dependency injection for UserService',
      'Add interface for service abstraction',
    ],
    negotiationRoomId: roomId,
  };

  await client.submitVote(vote);
  console.log(`  Score: ${vote.score}/10  Confidence: ${(vote.confidence * 100).toFixed(0)}%  Passed: ${vote.passed}`);
}

/**
 * Simulate the coordinator aggregating votes and making a decision.
 *
 * Uses the SDK's aggregateVotes() helper, then applies local policy
 * thresholds and stores the decision via storeDecision().
 */
async function simulateCoordinator(
  client: NegotiationRoomClient,
  artifactId: string,
  roomId: string
): Promise<NegotiationDecision> {
  console.log('\n' + '='.repeat(60));
  console.log('COORDINATOR: Aggregating votes and deciding');
  console.log('='.repeat(60));

  const votes = await client.getVotes(artifactId);

  // Standalone convenience function (uses confidence-weighted aggregation)
  const aggregated = aggregateVotes(votes);

  // Equivalent strategy-based approach (same algorithm, explicit class)
  const strategyAggregated = new ConfidenceWeightedAggregator().aggregate(votes);
  console.log(
    `\n  [Aggregation parity] standalone=${aggregated.weightedMean.toFixed(2)}, ` +
    `strategy=${strategyAggregated.weightedMean.toFixed(2)}`
  );

  const { outcome, reason } = determineOutcome(aggregated, votes);

  const decision: NegotiationDecision = {
    artifactId,
    outcome,
    votes,
    aggregatedScore: aggregated,
    policyVersion: 'v1.0.0',
    reason,
    negotiationRoomId: roomId,
  };

  await client.storeDecision(decision);

  console.log('\n[Decision Summary]');
  console.log(`  Outcome: ${DecisionOutcome[decision.outcome]}`);
  console.log(`  Reason: ${decision.reason}`);
  console.log(`  Vote Count: ${aggregated.voteCount}`);
  console.log(`  Mean Score: ${aggregated.mean.toFixed(2)}`);
  console.log(`  Weighted Mean: ${aggregated.weightedMean.toFixed(2)}`);
  console.log(`  Score Range: ${aggregated.minScore} - ${aggregated.maxScore}`);
  console.log(`  Std Dev: ${aggregated.stdDev.toFixed(2)}`);

  return decision;
}

// ============================================================================
// Main
// ============================================================================

async function main(): Promise<number> {
  console.log('SW4RM Negotiation Room Example');
  console.log('='.repeat(60));
  console.log('\nThis example uses the SDK NegotiationRoomClient to demonstrate');
  console.log('the producer-critic-coordinator pattern for artifact approval.\n');

  // All clients share the same in-memory store (the SDK default)
  const store = new InMemoryNegotiationRoomStore();
  const producerClient = new NegotiationRoomClient({ store });
  const criticClient = new NegotiationRoomClient({ store });
  const coordinatorClient = new NegotiationRoomClient({ store });

  const roomId = `room-${Date.now()}`;

  // Producer submits artifact
  const artifactId = await simulateProducer(producerClient, roomId);

  // Critics evaluate (in production these run as separate agents)
  await simulateSecurityCritic(criticClient, artifactId, roomId);
  await simulateCodeQualityCritic(criticClient, artifactId, roomId);
  await simulateArchitectureCritic(criticClient, artifactId, roomId);

  // Coordinator aggregates and decides
  const decision = await simulateCoordinator(coordinatorClient, artifactId, roomId);

  // Verify: a subsequent getDecision call returns the stored decision
  const retrieved = await coordinatorClient.getDecision(artifactId);
  console.log(`\n[Verification] Decision retrievable: ${retrieved !== null}`);

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log('FINAL RESULT');
  console.log('='.repeat(60));

  switch (decision.outcome) {
    case DecisionOutcome.APPROVED:
      console.log('\nArtifact APPROVED — Ready for deployment');
      break;
    case DecisionOutcome.REVISION_REQUESTED:
      console.log('\nRevision REQUESTED — Producer must address issues:');
      decision.votes.forEach((v) => {
        if (v.weaknesses.length > 0) {
          console.log(`  [${v.criticId}] ${v.weaknesses.join('; ')}`);
        }
      });
      break;
    case DecisionOutcome.ESCALATED_TO_HITL:
      console.log('\nESCALATED to Human-in-the-Loop for manual review');
      console.log(`  Reason: ${decision.reason}`);
      break;
  }

  // --------------------------------------------------------------------------
  // Failure Path: HITL Escalation via high disagreement
  // --------------------------------------------------------------------------
  console.log('\n' + '='.repeat(60));
  console.log('FAILURE PATH: HITL Escalation (Polarized Votes)');
  console.log('='.repeat(60));

  const escalationRoomId = `room-escalation-${Date.now()}`;
  const escalationProposal: NegotiationProposal = {
    artifactType: ArtifactType.CODE,
    artifactId: `artifact-escalation-${Date.now()}`,
    producerId: 'producer-agent-2',
    artifact: new TextEncoder().encode(JSON.stringify({ file: 'experimental.ts' })),
    artifactContentType: 'application/json',
    requestedCritics: ['optimist-critic', 'pessimist-critic'],
    negotiationRoomId: escalationRoomId,
  };

  const escArtifactId = await producerClient.submitProposal(escalationProposal);
  console.log(`\n  Submitted polarizing artifact: ${escArtifactId}`);

  // Two critics with wildly different scores → high stdDev
  const optimistVote: NegotiationVote = {
    artifactId: escArtifactId,
    criticId: 'optimist-critic',
    score: 9.5,
    confidence: 0.9,
    passed: true,
    strengths: ['Innovative approach'],
    weaknesses: [],
    recommendations: [],
    negotiationRoomId: escalationRoomId,
  };

  const pessimistVote: NegotiationVote = {
    artifactId: escArtifactId,
    criticId: 'pessimist-critic',
    score: 3.0,
    confidence: 0.85,
    passed: false,
    strengths: [],
    weaknesses: ['Fundamental design flaw', 'No error handling'],
    recommendations: ['Complete rewrite needed'],
    negotiationRoomId: escalationRoomId,
  };

  await criticClient.submitVote(optimistVote);
  await criticClient.submitVote(pessimistVote);
  console.log('  optimist-critic: 9.5/10   pessimist-critic: 3.0/10');

  const escVotes = await coordinatorClient.getVotes(escArtifactId);
  const escAggregated = aggregateVotes(escVotes);
  const escResult = determineOutcome(escAggregated, escVotes);

  console.log(`\n  Std Dev: ${escAggregated.stdDev.toFixed(2)}`);
  console.log(`  Outcome: ${DecisionOutcome[escResult.outcome]}`);
  console.log(`  Reason: ${escResult.reason}`);

  // Demonstrate vote validation error
  console.log('\n--- Vote Validation Error ---');
  try {
    const badVote: NegotiationVote = {
      ...optimistVote,
      criticId: 'bad-critic',
      score: 15, // Out of range [0, 10]
    };
    await criticClient.submitVote(badVote);
  } catch (err) {
    console.log(`  Caught: ${(err as Error).name}: ${(err as Error).message}`);
  }

  console.log('\nKey takeaways:');
  console.log('1. NegotiationRoomClient uses a shared store so multiple clients see the same state');
  console.log('2. submitVote() validates score/confidence ranges and prevents duplicate votes');
  console.log('3. aggregateVotes() and ConfidenceWeightedAggregator both compute weighted scoring');
  console.log('4. storeDecision() records the coordinator verdict for later retrieval');
  console.log('5. Policy thresholds determine approval/revision/escalation outcomes');
  console.log('6. High vote disagreement (stdDev > 2.0) triggers HITL escalation');
  console.log('7. Out-of-range scores throw NegotiationValidationError');

  return 0;
}

main().catch((err) => {
  console.error('[Fatal] Unhandled error:', err);
  process.exit(1);
});
