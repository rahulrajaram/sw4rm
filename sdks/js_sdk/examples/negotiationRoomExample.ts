#!/usr/bin/env npx tsx
/**
 * Negotiation Room Example for SW4RM Protocol.
 *
 * This example demonstrates the producer-critic-coordinator pattern:
 * - A producer agent submits an artifact (code, plan, requirements)
 * - Multiple critic agents evaluate and vote on the artifact
 * - A coordinator aggregates votes and makes a final decision
 *
 * The negotiation room pattern enables structured multi-agent review
 * with configurable thresholds and HITL escalation for edge cases.
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *   - Build the SDK: `npm run build`
 *
 * Run:
 *   npx tsx examples/negotiationRoomExample.ts
 *
 * Note: This example uses mock implementations since NegotiationRoomClient
 * is not yet implemented in the JS SDK. See Phase 2.1 in IMPLEMENTATION_PLAN.md.
 *
 * @packageDocumentation
 */

// ============================================================================
// Type Definitions (matching negotiation_room.proto)
// ============================================================================

/**
 * ArtifactType represents the category of artifact being negotiated.
 * Maps to different stages of the workflow process.
 */
enum ArtifactType {
  ARTIFACT_TYPE_UNSPECIFIED = 0,
  REQUIREMENTS = 1,
  PLAN = 2,
  CODE = 3,
  DEPLOYMENT = 4,
}

/**
 * DecisionOutcome represents the final decision made by the coordinator
 * after aggregating critic votes and applying policy.
 */
enum DecisionOutcome {
  DECISION_OUTCOME_UNSPECIFIED = 0,
  APPROVED = 1,
  REVISION_REQUESTED = 2,
  ESCALATED_TO_HITL = 3,
}

/**
 * NegotiationProposal represents a proposal for artifact evaluation.
 * Submitted by a producer agent to request multi-agent review.
 */
interface NegotiationProposal {
  artifact_type: ArtifactType;
  artifact_id: string;
  producer_id: string;
  artifact: Uint8Array;
  artifact_content_type: string;
  requested_critics: string[];
  negotiation_room_id: string;
  created_at: Date;
}

/**
 * NegotiationVote represents a critic's evaluation of an artifact.
 * Includes numerical scoring, qualitative feedback, and confidence level.
 */
interface NegotiationVote {
  artifact_id: string;
  critic_id: string;
  score: number; // 0-10
  confidence: number; // 0-1
  passed: boolean;
  strengths: string[];
  weaknesses: string[];
  recommendations: string[];
  negotiation_room_id: string;
  voted_at: Date;
}

/**
 * AggregatedScore provides statistical aggregation of multiple critic votes.
 */
interface AggregatedScore {
  mean: number;
  min_score: number;
  max_score: number;
  std_dev: number;
  weighted_mean: number;
  vote_count: number;
}

/**
 * NegotiationDecision represents the final decision on an artifact.
 */
interface NegotiationDecision {
  artifact_id: string;
  outcome: DecisionOutcome;
  votes: NegotiationVote[];
  aggregated_score: AggregatedScore;
  policy_version: string;
  reason: string;
  negotiation_room_id: string;
  decided_at: Date;
}

// ============================================================================
// Mock NegotiationRoomClient
// ============================================================================

/**
 * Mock NegotiationRoomClient for demonstration purposes.
 *
 * In production, this would be a gRPC client connecting to the
 * NegotiationRoomService. See Phase 2.1 in IMPLEMENTATION_PLAN.md
 * for the real implementation roadmap.
 */
class MockNegotiationRoomClient {
  private proposals = new Map<string, NegotiationProposal>();
  private votes = new Map<string, NegotiationVote[]>();
  private decisions = new Map<string, NegotiationDecision>();

  // Policy thresholds (would come from PolicyStore in production)
  private readonly approvalThreshold = 7.0;
  private readonly minConfidence = 0.6;
  private readonly minVotes = 2;

  /**
   * Submit a proposal for review.
   */
  async submitProposal(proposal: NegotiationProposal): Promise<string> {
    console.log(`\n[NegotiationRoom] Proposal submitted:`);
    console.log(`  Artifact ID: ${proposal.artifact_id}`);
    console.log(`  Type: ${ArtifactType[proposal.artifact_type]}`);
    console.log(`  Producer: ${proposal.producer_id}`);
    console.log(`  Requested Critics: ${proposal.requested_critics.join(', ')}`);

    this.proposals.set(proposal.artifact_id, proposal);
    this.votes.set(proposal.artifact_id, []);

    return proposal.artifact_id;
  }

  /**
   * Submit a vote for an artifact.
   */
  async submitVote(vote: NegotiationVote): Promise<void> {
    const votes = this.votes.get(vote.artifact_id) ?? [];
    votes.push(vote);
    this.votes.set(vote.artifact_id, votes);

    console.log(`\n[NegotiationRoom] Vote received:`);
    console.log(`  Critic: ${vote.critic_id}`);
    console.log(`  Score: ${vote.score}/10`);
    console.log(`  Confidence: ${(vote.confidence * 100).toFixed(0)}%`);
    console.log(`  Passed: ${vote.passed}`);
    console.log(`  Strengths: ${vote.strengths.join(', ')}`);
    console.log(`  Weaknesses: ${vote.weaknesses.join(', ')}`);
  }

  /**
   * Get all votes for an artifact.
   */
  async getVotes(artifactId: string): Promise<NegotiationVote[]> {
    return this.votes.get(artifactId) ?? [];
  }

  /**
   * Get the decision for an artifact (non-blocking).
   */
  async getDecision(artifactId: string): Promise<NegotiationDecision | null> {
    return this.decisions.get(artifactId) ?? null;
  }

  /**
   * Wait for and compute a decision (blocks until all critics vote).
   */
  async waitForDecision(artifactId: string, timeoutMs = 30000): Promise<NegotiationDecision> {
    const proposal = this.proposals.get(artifactId);
    const votes = this.votes.get(artifactId) ?? [];

    if (!proposal) {
      throw new Error(`Proposal not found: ${artifactId}`);
    }

    // In production, this would poll or use streaming
    // For demo, we check if we have enough votes
    if (votes.length < this.minVotes) {
      console.log(`\n[NegotiationRoom] Waiting for more votes (${votes.length}/${this.minVotes})...`);
    }

    // Compute aggregated score
    const aggregated = this.aggregateVotes(votes);

    // Determine outcome based on policy
    const outcome = this.determineOutcome(aggregated, votes);

    const decision: NegotiationDecision = {
      artifact_id: artifactId,
      outcome: outcome.outcome,
      votes,
      aggregated_score: aggregated,
      policy_version: 'v1.0.0',
      reason: outcome.reason,
      negotiation_room_id: proposal.negotiation_room_id,
      decided_at: new Date(),
    };

    this.decisions.set(artifactId, decision);
    return decision;
  }

  /**
   * Aggregate votes using multiple strategies.
   */
  private aggregateVotes(votes: NegotiationVote[]): AggregatedScore {
    if (votes.length === 0) {
      return {
        mean: 0,
        min_score: 0,
        max_score: 0,
        std_dev: 0,
        weighted_mean: 0,
        vote_count: 0,
      };
    }

    const scores = votes.map((v) => v.score);
    const confidences = votes.map((v) => v.confidence);

    // Basic statistics
    const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
    const minScore = Math.min(...scores);
    const maxScore = Math.max(...scores);

    // Standard deviation
    const variance = scores.reduce((sum, s) => sum + Math.pow(s - mean, 2), 0) / scores.length;
    const stdDev = Math.sqrt(variance);

    // Confidence-weighted mean
    const totalConfidence = confidences.reduce((a, b) => a + b, 0);
    const weightedMean = votes.reduce((sum, v) => sum + v.score * v.confidence, 0) / totalConfidence;

    return {
      mean,
      min_score: minScore,
      max_score: maxScore,
      std_dev: stdDev,
      weighted_mean: weightedMean,
      vote_count: votes.length,
    };
  }

  /**
   * Determine outcome based on aggregated scores and policy.
   */
  private determineOutcome(
    aggregated: AggregatedScore,
    votes: NegotiationVote[]
  ): { outcome: DecisionOutcome; reason: string } {
    // Check if we have enough votes
    if (aggregated.vote_count < this.minVotes) {
      return {
        outcome: DecisionOutcome.ESCALATED_TO_HITL,
        reason: `Insufficient votes (${aggregated.vote_count}/${this.minVotes})`,
      };
    }

    // Check average confidence
    const avgConfidence = votes.reduce((sum, v) => sum + v.confidence, 0) / votes.length;
    if (avgConfidence < this.minConfidence) {
      return {
        outcome: DecisionOutcome.ESCALATED_TO_HITL,
        reason: `Low average confidence (${(avgConfidence * 100).toFixed(0)}% < ${(this.minConfidence * 100).toFixed(0)}%)`,
      };
    }

    // Check if all critics passed
    const allPassed = votes.every((v) => v.passed);

    // Check weighted mean against threshold
    if (aggregated.weighted_mean >= this.approvalThreshold && allPassed) {
      return {
        outcome: DecisionOutcome.APPROVED,
        reason: `Weighted mean ${aggregated.weighted_mean.toFixed(2)} >= ${this.approvalThreshold}, all critics passed`,
      };
    }

    // Request revision if score is close but not quite there
    if (aggregated.weighted_mean >= this.approvalThreshold * 0.8) {
      const weaknesses = votes.flatMap((v) => v.weaknesses);
      return {
        outcome: DecisionOutcome.REVISION_REQUESTED,
        reason: `Score ${aggregated.weighted_mean.toFixed(2)} needs improvement. Issues: ${weaknesses.slice(0, 3).join('; ')}`,
      };
    }

    // Escalate if scores are too divergent (high std dev)
    if (aggregated.std_dev > 2.0) {
      return {
        outcome: DecisionOutcome.ESCALATED_TO_HITL,
        reason: `High disagreement among critics (std dev: ${aggregated.std_dev.toFixed(2)})`,
      };
    }

    return {
      outcome: DecisionOutcome.REVISION_REQUESTED,
      reason: `Score ${aggregated.weighted_mean.toFixed(2)} below threshold ${this.approvalThreshold}`,
    };
  }
}

// ============================================================================
// Example Simulation
// ============================================================================

/**
 * Simulate a producer agent submitting code for review.
 */
async function simulateProducer(client: MockNegotiationRoomClient, roomId: string): Promise<string> {
  console.log('\n' + '='.repeat(60));
  console.log('PRODUCER: Submitting code for review');
  console.log('='.repeat(60));

  const proposal: NegotiationProposal = {
    artifact_type: ArtifactType.CODE,
    artifact_id: `artifact-${Date.now()}`,
    producer_id: 'producer-agent-1',
    artifact: Buffer.from(
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
    artifact_content_type: 'application/json',
    requested_critics: ['security-critic', 'code-quality-critic', 'architecture-critic'],
    negotiation_room_id: roomId,
    created_at: new Date(),
  };

  return client.submitProposal(proposal);
}

/**
 * Simulate a security critic evaluating the code.
 */
async function simulateSecurityCritic(
  client: MockNegotiationRoomClient,
  artifactId: string,
  roomId: string
): Promise<void> {
  console.log('\n' + '-'.repeat(60));
  console.log('CRITIC: Security Review');
  console.log('-'.repeat(60));

  const vote: NegotiationVote = {
    artifact_id: artifactId,
    critic_id: 'security-critic',
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
    negotiation_room_id: roomId,
    voted_at: new Date(),
  };

  await client.submitVote(vote);
}

/**
 * Simulate a code quality critic evaluating the code.
 */
async function simulateCodeQualityCritic(
  client: MockNegotiationRoomClient,
  artifactId: string,
  roomId: string
): Promise<void> {
  console.log('\n' + '-'.repeat(60));
  console.log('CRITIC: Code Quality Review');
  console.log('-'.repeat(60));

  const vote: NegotiationVote = {
    artifact_id: artifactId,
    critic_id: 'code-quality-critic',
    score: 8.0,
    confidence: 0.9,
    passed: true,
    strengths: [
      'Clean function signature with types',
      'Proper async/await usage',
      'Single responsibility principle',
    ],
    weaknesses: ['Missing error handling for jwt.verify', 'No input validation for token'],
    recommendations: ['Add try-catch for JWT verification', 'Validate token format before processing'],
    negotiation_room_id: roomId,
    voted_at: new Date(),
  };

  await client.submitVote(vote);
}

/**
 * Simulate an architecture critic evaluating the code.
 */
async function simulateArchitectureCritic(
  client: MockNegotiationRoomClient,
  artifactId: string,
  roomId: string
): Promise<void> {
  console.log('\n' + '-'.repeat(60));
  console.log('CRITIC: Architecture Review');
  console.log('-'.repeat(60));

  const vote: NegotiationVote = {
    artifact_id: artifactId,
    critic_id: 'architecture-critic',
    score: 7.5,
    confidence: 0.75,
    passed: true,
    strengths: ['Clean separation of concerns', 'Uses service layer pattern', 'Async-first design'],
    weaknesses: ['Direct dependency on UserService', 'No dependency injection'],
    recommendations: ['Consider dependency injection for UserService', 'Add interface for service abstraction'],
    negotiation_room_id: roomId,
    voted_at: new Date(),
  };

  await client.submitVote(vote);
}

/**
 * Simulate the coordinator aggregating and deciding.
 */
async function simulateCoordinator(
  client: MockNegotiationRoomClient,
  artifactId: string
): Promise<NegotiationDecision> {
  console.log('\n' + '='.repeat(60));
  console.log('COORDINATOR: Aggregating votes and deciding');
  console.log('='.repeat(60));

  const decision = await client.waitForDecision(artifactId);

  console.log('\n[Decision Summary]');
  console.log(`  Outcome: ${DecisionOutcome[decision.outcome]}`);
  console.log(`  Reason: ${decision.reason}`);
  console.log(`  Vote Count: ${decision.aggregated_score.vote_count}`);
  console.log(`  Mean Score: ${decision.aggregated_score.mean.toFixed(2)}`);
  console.log(`  Weighted Mean: ${decision.aggregated_score.weighted_mean.toFixed(2)}`);
  console.log(`  Score Range: ${decision.aggregated_score.min_score} - ${decision.aggregated_score.max_score}`);
  console.log(`  Std Dev: ${decision.aggregated_score.std_dev.toFixed(2)}`);

  return decision;
}

/**
 * Main demonstration function.
 */
async function main(): Promise<number> {
  console.log('SW4RM Negotiation Room Example');
  console.log('='.repeat(60));
  console.log('\nThis example demonstrates the producer-critic-coordinator pattern');
  console.log('for multi-agent artifact approval workflows.\n');

  const client = new MockNegotiationRoomClient();
  const roomId = `room-${Date.now()}`;

  // Producer submits artifact
  const artifactId = await simulateProducer(client, roomId);

  // Critics evaluate (in production these would be separate agents)
  await simulateSecurityCritic(client, artifactId, roomId);
  await simulateCodeQualityCritic(client, artifactId, roomId);
  await simulateArchitectureCritic(client, artifactId, roomId);

  // Coordinator aggregates and decides
  const decision = await simulateCoordinator(client, artifactId);

  // Summary
  console.log('\n' + '='.repeat(60));
  console.log('FINAL RESULT');
  console.log('='.repeat(60));

  switch (decision.outcome) {
    case DecisionOutcome.APPROVED:
      console.log('\nArtifact APPROVED - Ready for deployment');
      break;
    case DecisionOutcome.REVISION_REQUESTED:
      console.log('\nRevision REQUESTED - Producer must address issues:');
      decision.votes.forEach((v) => {
        if (v.weaknesses.length > 0) {
          console.log(`  [${v.critic_id}] ${v.weaknesses.join('; ')}`);
        }
      });
      break;
    case DecisionOutcome.ESCALATED_TO_HITL:
      console.log('\nESCALATED to Human-in-the-Loop for manual review');
      console.log(`  Reason: ${decision.reason}`);
      break;
  }

  console.log('\nKey takeaways:');
  console.log('1. Producers submit artifacts with requested critics');
  console.log('2. Critics provide scores, confidence, and qualitative feedback');
  console.log('3. Coordinator aggregates using confidence-weighted scoring');
  console.log('4. Policy thresholds determine approval/revision/escalation');
  console.log('5. High disagreement (std dev) triggers HITL escalation');

  return 0;
}

// Entry point
main().catch((err) => {
  console.error('[Fatal] Unhandled error:', err);
  process.exit(1);
});
