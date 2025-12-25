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
 * Negotiation Room client for SW4RM.
 *
 * This module provides the NegotiationRoomClient for managing multi-agent
 * artifact approval workflows using the Negotiation Room pattern. The client
 * supports:
 * - Submitting artifacts for review
 * - Collecting votes from critics
 * - Retrieving and waiting for decisions
 * - Coordinating the review process
 *
 * Based on SPEC_REQUESTS.md section 6.1.
 */

/**
 * Type of artifact being negotiated.
 *
 * Maps to the artifact_type field in negotiation proposals to categorize
 * what stage of the workflow the artifact belongs to.
 */
export enum ArtifactType {
  ARTIFACT_TYPE_UNSPECIFIED = 0,
  REQUIREMENTS = 1,
  PLAN = 2,
  CODE = 3,
  DEPLOYMENT = 4,
}

/**
 * Outcome of a negotiation decision.
 *
 * Represents the final decision made by the coordinator after aggregating
 * critic votes and applying policy.
 */
export enum DecisionOutcome {
  DECISION_OUTCOME_UNSPECIFIED = 0,
  APPROVED = 1,
  REVISION_REQUESTED = 2,
  ESCALATED_TO_HITL = 3,
}

/**
 * A proposal for artifact evaluation in a negotiation room.
 *
 * Submitted by a producer agent to request multi-agent review of an artifact.
 * The proposal specifies which critics should evaluate the artifact and
 * includes the artifact content for review.
 */
export interface NegotiationProposal {
  /** Category of artifact (requirements, plan, code, deployment) */
  artifactType: ArtifactType;
  /** Unique identifier for this artifact */
  artifactId: string;
  /** Agent ID of the producer submitting the artifact */
  producerId: string;
  /** Binary artifact content (e.g., serialized JSON, code files) */
  artifact: Uint8Array;
  /** MIME type or content type identifier */
  artifactContentType: string;
  /** List of critic agent IDs requested for evaluation */
  requestedCritics: string[];
  /** Identifier for the negotiation room session */
  negotiationRoomId: string;
  /** Timestamp when proposal was created (ISO-8601 string) */
  createdAt?: string;
}

/**
 * A critic's evaluation of an artifact.
 *
 * Represents a single critic's assessment including numerical scoring,
 * qualitative feedback, and confidence level based on POMDP uncertainty.
 */
export interface NegotiationVote {
  /** Identifier of the artifact being evaluated */
  artifactId: string;
  /** Agent ID of the critic providing this vote */
  criticId: string;
  /** Numerical score from 0-10 (10 = excellent) */
  score: number;
  /** Confidence level from 0-1 (based on POMDP research) */
  confidence: number;
  /** Boolean indicating if artifact meets minimum criteria */
  passed: boolean;
  /** List of identified strengths in the artifact */
  strengths: string[];
  /** List of identified weaknesses or concerns */
  weaknesses: string[];
  /** List of suggestions for improvement */
  recommendations: string[];
  /** Identifier for the negotiation room session */
  negotiationRoomId: string;
  /** Timestamp when vote was cast (ISO-8601 string) */
  votedAt?: string;
}

/**
 * Statistical aggregation of multiple critic votes.
 *
 * Provides multiple views of the voting results including basic statistics
 * and confidence-weighted metrics for decision making.
 */
export interface AggregatedScore {
  /** Arithmetic mean of all scores */
  mean: number;
  /** Minimum score from any critic */
  minScore: number;
  /** Maximum score from any critic */
  maxScore: number;
  /** Standard deviation of scores (measures consensus) */
  stdDev: number;
  /** Confidence-weighted mean (higher confidence votes weighted more) */
  weightedMean: number;
  /** Number of votes included in aggregation */
  voteCount: number;
}

/**
 * Final decision on an artifact after critic evaluation.
 *
 * Represents the coordinator's decision after aggregating all critic votes
 * and applying policy thresholds. Includes full audit trail of votes and
 * reasoning.
 */
export interface NegotiationDecision {
  /** Identifier of the artifact that was evaluated */
  artifactId: string;
  /** Final decision (approved, revision requested, escalated to HITL) */
  outcome: DecisionOutcome;
  /** Complete list of all critic votes considered */
  votes: NegotiationVote[];
  /** Statistical summary of the votes */
  aggregatedScore: AggregatedScore;
  /** Version identifier of the policy used for decision */
  policyVersion: string;
  /** Human-readable explanation of the decision */
  reason: string;
  /** Identifier for the negotiation room session */
  negotiationRoomId: string;
  /** Timestamp when decision was made (ISO-8601 string) */
  decidedAt?: string;
}

/**
 * Error thrown when a negotiation room operation times out.
 */
export class NegotiationTimeoutError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NegotiationTimeoutError';
  }
}

/**
 * Error thrown when a negotiation room operation fails validation.
 */
export class NegotiationValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NegotiationValidationError';
  }
}

/**
 * Validates a NegotiationVote for correctness.
 *
 * @param vote - The vote to validate
 * @throws NegotiationValidationError if validation fails
 */
function validateVote(vote: NegotiationVote): void {
  if (vote.score < 0 || vote.score > 10) {
    throw new NegotiationValidationError(
      `score must be in range [0, 10], got ${vote.score}`
    );
  }
  if (vote.confidence < 0 || vote.confidence > 1) {
    throw new NegotiationValidationError(
      `confidence must be in range [0, 1], got ${vote.confidence}`
    );
  }
}

/**
 * Client for interacting with negotiation rooms.
 *
 * Manages the lifecycle of artifact proposals through the multi-agent
 * review process. Producers submit proposals, critics submit votes,
 * and coordinators retrieve votes to make decisions.
 *
 * This is an in-memory implementation for Phase 2. Future phases
 * will integrate with persistent storage and gRPC services.
 */
export class NegotiationRoomClient {
  private proposals: Map<string, NegotiationProposal> = new Map();
  private votes: Map<string, NegotiationVote[]> = new Map();
  private decisions: Map<string, NegotiationDecision> = new Map();

  /**
   * Submit an artifact proposal for multi-agent review.
   *
   * Stores the proposal and initializes empty vote tracking for the artifact.
   * This method is typically called by producer agents.
   *
   * @param proposal - The negotiation proposal containing artifact details
   * @returns The artifact_id of the submitted proposal
   * @throws NegotiationValidationError if a proposal with the same artifact_id already exists
   *
   * @example
   * ```typescript
   * const client = new NegotiationRoomClient();
   * const proposal: NegotiationProposal = {
   *   artifactType: ArtifactType.CODE,
   *   artifactId: "code-123",
   *   producerId: "agent-producer",
   *   artifact: new TextEncoder().encode("def hello(): pass"),
   *   artifactContentType: "text/x-python",
   *   requestedCritics: ["critic-1", "critic-2"],
   *   negotiationRoomId: "room-1"
   * };
   * const artifactId = await client.submitProposal(proposal);
   * console.log(artifactId); // "code-123"
   * ```
   */
  async submitProposal(proposal: NegotiationProposal): Promise<string> {
    const artifactId = proposal.artifactId;

    if (this.proposals.has(artifactId)) {
      throw new NegotiationValidationError(
        `Proposal with artifact_id '${artifactId}' already exists`
      );
    }

    // Set createdAt if not provided
    const proposalWithTimestamp: NegotiationProposal = {
      ...proposal,
      createdAt: proposal.createdAt || new Date().toISOString(),
    };

    this.proposals.set(artifactId, proposalWithTimestamp);
    this.votes.set(artifactId, []);

    return artifactId;
  }

  /**
   * Submit a critic's vote for an artifact.
   *
   * Adds the vote to the collection for the specified artifact.
   * This method is typically called by critic agents after evaluating
   * an artifact.
   *
   * @param vote - The negotiation vote containing the critic's evaluation
   * @throws NegotiationValidationError if no proposal exists for the vote's artifact_id
   * @throws NegotiationValidationError if the critic has already voted for this artifact
   * @throws NegotiationValidationError if score or confidence are out of range
   *
   * @example
   * ```typescript
   * const vote: NegotiationVote = {
   *   artifactId: "code-123",
   *   criticId: "critic-1",
   *   score: 8.5,
   *   confidence: 0.9,
   *   passed: true,
   *   strengths: ["Good structure"],
   *   weaknesses: ["Needs tests"],
   *   recommendations: ["Add unit tests"],
   *   negotiationRoomId: "room-1"
   * };
   * await client.submitVote(vote);
   * ```
   */
  async submitVote(vote: NegotiationVote): Promise<void> {
    const artifactId = vote.artifactId;

    if (!this.proposals.has(artifactId)) {
      throw new NegotiationValidationError(
        `No proposal found for artifact_id '${artifactId}'`
      );
    }

    // Validate score and confidence ranges
    validateVote(vote);

    // Check if this critic has already voted
    const existingVotes = this.votes.get(artifactId) || [];
    for (const existingVote of existingVotes) {
      if (existingVote.criticId === vote.criticId) {
        throw new NegotiationValidationError(
          `Critic '${vote.criticId}' has already voted for artifact '${artifactId}'`
        );
      }
    }

    // Set votedAt if not provided
    const voteWithTimestamp: NegotiationVote = {
      ...vote,
      votedAt: vote.votedAt || new Date().toISOString(),
    };

    existingVotes.push(voteWithTimestamp);
    this.votes.set(artifactId, existingVotes);
  }

  /**
   * Retrieve all votes for a specific artifact.
   *
   * Returns all critic votes that have been submitted for the artifact.
   * This method is typically called by coordinator agents to aggregate
   * votes and make decisions.
   *
   * @param artifactId - The identifier of the artifact
   * @returns List of all votes for the artifact (empty array if no votes yet)
   * @throws NegotiationValidationError if no proposal exists for the artifact_id
   *
   * @example
   * ```typescript
   * const votes = await client.getVotes("code-123");
   * console.log(votes.length); // 1
   * ```
   */
  async getVotes(artifactId: string): Promise<NegotiationVote[]> {
    if (!this.proposals.has(artifactId)) {
      throw new NegotiationValidationError(
        `No proposal found for artifact_id '${artifactId}'`
      );
    }

    return this.votes.get(artifactId) || [];
  }

  /**
   * Retrieve the decision for a specific artifact if available.
   *
   * Returns the final decision if one has been made, or null if the
   * artifact is still under review.
   *
   * @param artifactId - The identifier of the artifact
   * @returns The negotiation decision if available, null otherwise
   * @throws NegotiationValidationError if no proposal exists for the artifact_id
   *
   * @example
   * ```typescript
   * const decision = await client.getDecision("code-123");
   * if (decision === null) {
   *   console.log("Decision pending");
   * }
   * ```
   */
  async getDecision(artifactId: string): Promise<NegotiationDecision | null> {
    if (!this.proposals.has(artifactId)) {
      throw new NegotiationValidationError(
        `No proposal found for artifact_id '${artifactId}'`
      );
    }

    return this.decisions.get(artifactId) || null;
  }

  /**
   * Store a decision for an artifact.
   *
   * This is an internal method used by coordinators to record the
   * final decision after evaluating votes. Once a decision is stored,
   * it becomes available via getDecision() and waitForDecision().
   *
   * @param decision - The negotiation decision to store
   * @throws NegotiationValidationError if no proposal exists for the decision's artifact_id
   * @throws NegotiationValidationError if a decision already exists for this artifact
   *
   * @example
   * ```typescript
   * const votes = await client.getVotes("code-123");
   * const aggregated = aggregateVotes(votes);
   * const decision: NegotiationDecision = {
   *   artifactId: "code-123",
   *   outcome: DecisionOutcome.APPROVED,
   *   votes: votes,
   *   aggregatedScore: aggregated,
   *   policyVersion: "1.0",
   *   reason: "Met all criteria",
   *   negotiationRoomId: "room-1"
   * };
   * await client.storeDecision(decision);
   * ```
   */
  async storeDecision(decision: NegotiationDecision): Promise<void> {
    const artifactId = decision.artifactId;

    if (!this.proposals.has(artifactId)) {
      throw new NegotiationValidationError(
        `No proposal found for artifact_id '${artifactId}'`
      );
    }

    if (this.decisions.has(artifactId)) {
      throw new NegotiationValidationError(
        `Decision already exists for artifact_id '${artifactId}'`
      );
    }

    // Set decidedAt if not provided
    const decisionWithTimestamp: NegotiationDecision = {
      ...decision,
      decidedAt: decision.decidedAt || new Date().toISOString(),
    };

    this.decisions.set(artifactId, decisionWithTimestamp);
  }

  /**
   * Wait for a decision to be made on an artifact.
   *
   * Polls for a decision until one is available or the timeout is reached.
   * This method is useful for producer agents waiting for the outcome
   * of their artifact review.
   *
   * @param artifactId - The identifier of the artifact
   * @param timeoutMs - Maximum time to wait in milliseconds (default: 30000)
   * @param pollIntervalMs - Time between polling attempts in milliseconds (default: 100)
   * @returns The negotiation decision once available
   * @throws NegotiationValidationError if no proposal exists for the artifact_id
   * @throws NegotiationTimeoutError if no decision is made within the timeout period
   *
   * @example
   * ```typescript
   * // In a separate thread/process, a coordinator makes a decision
   * const decision = await client.waitForDecision("code-123", 10000);
   * console.log(decision.outcome); // DecisionOutcome.APPROVED
   * ```
   */
  async waitForDecision(
    artifactId: string,
    timeoutMs: number = 30000,
    pollIntervalMs: number = 100
  ): Promise<NegotiationDecision> {
    if (!this.proposals.has(artifactId)) {
      throw new NegotiationValidationError(
        `No proposal found for artifact_id '${artifactId}'`
      );
    }

    const startTime = Date.now();

    while (Date.now() - startTime < timeoutMs) {
      const decision = await this.getDecision(artifactId);
      if (decision !== null) {
        return decision;
      }

      await new Promise((resolve) => setTimeout(resolve, pollIntervalMs));
    }

    throw new NegotiationTimeoutError(
      `No decision made for artifact '${artifactId}' within ${timeoutMs} milliseconds`
    );
  }

  /**
   * Retrieve the original proposal for an artifact.
   *
   * Useful for critics that need to review the original artifact
   * before submitting a vote.
   *
   * @param artifactId - The identifier of the artifact
   * @returns The negotiation proposal if it exists, null otherwise
   *
   * @example
   * ```typescript
   * const proposal = await client.getProposal("code-123");
   * console.log(proposal?.artifactType); // ArtifactType.CODE
   * ```
   */
  async getProposal(artifactId: string): Promise<NegotiationProposal | null> {
    return this.proposals.get(artifactId) || null;
  }

  /**
   * List all proposals, optionally filtered by negotiation room.
   *
   * @param negotiationRoomId - If provided, only return proposals for this room
   * @returns List of proposals matching the filter criteria
   *
   * @example
   * ```typescript
   * const proposals = await client.listProposals("room-1");
   * console.log(proposals.length); // 1
   * ```
   */
  async listProposals(
    negotiationRoomId?: string
  ): Promise<NegotiationProposal[]> {
    const allProposals = Array.from(this.proposals.values());

    if (negotiationRoomId === undefined) {
      return allProposals;
    }

    return allProposals.filter(
      (p) => p.negotiationRoomId === negotiationRoomId
    );
  }
}

/**
 * Aggregate multiple critic votes into statistical summary.
 *
 * Computes both basic statistics (mean, min, max, std dev) and a
 * confidence-weighted mean that gives more weight to votes from critics
 * with higher confidence levels.
 *
 * @param votes - List of critic votes to aggregate
 * @returns AggregatedScore with statistical summary of votes
 * @throws NegotiationValidationError if votes list is empty
 */
export function aggregateVotes(votes: NegotiationVote[]): AggregatedScore {
  if (votes.length === 0) {
    throw new NegotiationValidationError(
      'Cannot aggregate empty list of votes'
    );
  }

  const scores = votes.map((v) => v.score);
  const confidences = votes.map((v) => v.confidence);

  // Basic statistics
  const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
  const minScore = Math.min(...scores);
  const maxScore = Math.max(...scores);

  // Standard deviation
  const variance =
    scores.reduce((sum, s) => sum + Math.pow(s - mean, 2), 0) / scores.length;
  const stdDev = Math.sqrt(variance);

  // Confidence-weighted mean
  const totalConfidence = confidences.reduce((a, b) => a + b, 0);
  let weightedMean: number;
  if (totalConfidence > 0) {
    weightedMean =
      scores.reduce((sum, s, i) => sum + s * confidences[i], 0) /
      totalConfidence;
  } else {
    // Fallback to simple mean if all confidences are zero
    weightedMean = mean;
  }

  return {
    mean,
    minScore,
    maxScore,
    stdDev,
    weightedMean,
    voteCount: votes.length,
  };
}
