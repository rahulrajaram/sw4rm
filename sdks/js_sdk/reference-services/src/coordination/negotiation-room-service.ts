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
 * Negotiation Room Service gRPC Server Implementation.
 *
 * This module provides the gRPC server implementation for the NegotiationRoomService,
 * enabling distributed multi-agent artifact approval workflows with centralized state.
 */

import * as grpc from '@grpc/grpc-js';
import { EventEmitter } from 'events';

// Artifact type enum values (from proto)
export enum ArtifactType {
  ARTIFACT_TYPE_UNSPECIFIED = 0,
  REQUIREMENTS = 1,
  PLAN = 2,
  CODE = 3,
  DEPLOYMENT = 4,
}

// Decision outcome enum values (from proto)
export enum DecisionOutcome {
  DECISION_OUTCOME_UNSPECIFIED = 0,
  APPROVED = 1,
  REVISION_REQUESTED = 2,
  ESCALATED_TO_HITL = 3,
}

// Type definitions matching proto messages
export interface NegotiationProposal {
  artifact_type: number;
  artifact_id: string;
  producer_id: string;
  artifact: Buffer;
  artifact_content_type: string;
  requested_critics: string[];
  negotiation_room_id: string;
  created_at?: { seconds: number; nanos: number };
}

export interface NegotiationVote {
  artifact_id: string;
  critic_id: string;
  score: number;
  confidence: number;
  passed: boolean;
  strengths: string[];
  weaknesses: string[];
  recommendations: string[];
  negotiation_room_id: string;
  voted_at?: { seconds: number; nanos: number };
}

export interface AggregatedScore {
  mean: number;
  min_score: number;
  max_score: number;
  std_dev: number;
  weighted_mean: number;
  vote_count: number;
}

export interface NegotiationDecision {
  artifact_id: string;
  outcome: number;
  votes: NegotiationVote[];
  aggregated_score?: AggregatedScore;
  policy_version: string;
  reason: string;
  negotiation_room_id: string;
  decided_at?: { seconds: number; nanos: number };
}

export interface SubmitProposalRequest {
  proposal: NegotiationProposal;
}

export interface SubmitProposalResponse {
  artifact_id: string;
  negotiation_room_id: string;
}

export interface SubmitVoteRequest {
  vote: NegotiationVote;
}

export interface SubmitVoteResponse {
  artifact_id: string;
  critic_id: string;
}

export interface GetVotesRequest {
  artifact_id: string;
  negotiation_room_id: string;
}

export interface GetVotesResponse {
  votes: NegotiationVote[];
  vote_count: number;
}

export interface GetDecisionRequest {
  artifact_id: string;
  negotiation_room_id: string;
}

export interface GetDecisionResponse {
  decision?: NegotiationDecision;
}

export interface WaitForDecisionRequest {
  artifact_id: string;
  negotiation_room_id: string;
  timeout_seconds: number;
}

export interface WaitForDecisionResponse {
  decision?: NegotiationDecision;
}

function currentTimestamp(): { seconds: number; nanos: number } {
  const now = Date.now();
  return {
    seconds: Math.floor(now / 1000),
    nanos: (now % 1000) * 1_000_000,
  };
}

/**
 * gRPC server implementation for NegotiationRoomService.
 *
 * Provides centralized artifact approval workflows for distributed agent deployments.
 * Thread-safe implementation using Maps for state storage.
 */
export class NegotiationRoomServiceImpl {
  private proposals: Map<string, NegotiationProposal> = new Map();
  private votes: Map<string, NegotiationVote[]> = new Map();
  private decisions: Map<string, NegotiationDecision> = new Map();
  private decisionEmitters: Map<string, EventEmitter> = new Map();

  constructor() {
    console.log('NegotiationRoomService initialized');
  }

  /**
   * Submit an artifact proposal for multi-agent review.
   */
  submitProposal(
    call: grpc.ServerUnaryCall<SubmitProposalRequest, SubmitProposalResponse>,
    callback: grpc.sendUnaryData<SubmitProposalResponse>
  ): void {
    const proposal = call.request.proposal;

    if (!proposal) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'proposal is required',
      });
      return;
    }

    const artifactId = proposal.artifact_id;
    const negotiationRoomId = proposal.negotiation_room_id;

    // Validate required fields
    if (!artifactId) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'artifact_id is required',
      });
      return;
    }

    if (!proposal.producer_id) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'producer_id is required',
      });
      return;
    }

    // Check for duplicates
    if (this.proposals.has(artifactId)) {
      callback({
        code: grpc.status.ALREADY_EXISTS,
        message: `Proposal with artifact_id '${artifactId}' already exists`,
      });
      return;
    }

    // Set created_at if not provided
    if (!proposal.created_at) {
      proposal.created_at = currentTimestamp();
    }

    this.proposals.set(artifactId, proposal);
    this.votes.set(artifactId, []);
    this.decisionEmitters.set(artifactId, new EventEmitter());

    console.log(
      `Proposal submitted: ${artifactId} by ${proposal.producer_id} in room ${negotiationRoomId}`
    );

    callback(null, {
      artifact_id: artifactId,
      negotiation_room_id: negotiationRoomId,
    });
  }

  /**
   * Submit a critic's vote for an artifact.
   */
  submitVote(
    call: grpc.ServerUnaryCall<SubmitVoteRequest, SubmitVoteResponse>,
    callback: grpc.sendUnaryData<SubmitVoteResponse>
  ): void {
    const vote = call.request.vote;

    if (!vote) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'vote is required',
      });
      return;
    }

    const artifactId = vote.artifact_id;
    const criticId = vote.critic_id;

    // Validate required fields
    if (!artifactId) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'artifact_id is required',
      });
      return;
    }

    if (!criticId) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: 'critic_id is required',
      });
      return;
    }

    // Validate score range [0, 10]
    if (vote.score < 0 || vote.score > 10) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: `score must be in range [0, 10], got ${vote.score}`,
      });
      return;
    }

    // Validate confidence range [0, 1]
    if (vote.confidence < 0 || vote.confidence > 1) {
      callback({
        code: grpc.status.INVALID_ARGUMENT,
        message: `confidence must be in range [0, 1], got ${vote.confidence}`,
      });
      return;
    }

    // Check proposal exists
    if (!this.proposals.has(artifactId)) {
      callback({
        code: grpc.status.NOT_FOUND,
        message: `No proposal found for artifact_id '${artifactId}'`,
      });
      return;
    }

    // Check for duplicate votes
    const existingVotes = this.votes.get(artifactId) || [];
    for (const v of existingVotes) {
      if (v.critic_id === criticId) {
        callback({
          code: grpc.status.ALREADY_EXISTS,
          message: `Critic '${criticId}' has already voted for artifact '${artifactId}'`,
        });
        return;
      }
    }

    // Set voted_at if not provided
    if (!vote.voted_at) {
      vote.voted_at = currentTimestamp();
    }

    existingVotes.push(vote);
    this.votes.set(artifactId, existingVotes);

    console.log(
      `Vote submitted: ${criticId} for ${artifactId} (score=${vote.score}, confidence=${vote.confidence})`
    );

    callback(null, {
      artifact_id: artifactId,
      critic_id: criticId,
    });
  }

  /**
   * Retrieve all votes for a specific artifact.
   */
  getVotes(
    call: grpc.ServerUnaryCall<GetVotesRequest, GetVotesResponse>,
    callback: grpc.sendUnaryData<GetVotesResponse>
  ): void {
    const artifactId = call.request.artifact_id;

    // Check proposal exists
    if (!this.proposals.has(artifactId)) {
      callback({
        code: grpc.status.NOT_FOUND,
        message: `No proposal found for artifact_id '${artifactId}'`,
      });
      return;
    }

    const votes = this.votes.get(artifactId) || [];
    console.log(`GetVotes: ${artifactId} has ${votes.length} votes`);

    callback(null, {
      votes,
      vote_count: votes.length,
    });
  }

  /**
   * Retrieve the decision for an artifact (non-blocking).
   */
  getDecision(
    call: grpc.ServerUnaryCall<GetDecisionRequest, GetDecisionResponse>,
    callback: grpc.sendUnaryData<GetDecisionResponse>
  ): void {
    const artifactId = call.request.artifact_id;

    // Check proposal exists
    if (!this.proposals.has(artifactId)) {
      callback({
        code: grpc.status.NOT_FOUND,
        message: `No proposal found for artifact_id '${artifactId}'`,
      });
      return;
    }

    const decision = this.decisions.get(artifactId);
    if (decision) {
      console.log(`GetDecision: ${artifactId} -> ${decision.outcome}`);
    } else {
      console.log(`GetDecision: ${artifactId} -> no decision yet`);
    }

    callback(null, { decision });
  }

  /**
   * Wait for a decision to be made on an artifact (blocking).
   */
  waitForDecision(
    call: grpc.ServerUnaryCall<WaitForDecisionRequest, WaitForDecisionResponse>,
    callback: grpc.sendUnaryData<WaitForDecisionResponse>
  ): void {
    const artifactId = call.request.artifact_id;
    const timeoutSeconds = call.request.timeout_seconds || 30;

    // Check proposal exists
    if (!this.proposals.has(artifactId)) {
      callback({
        code: grpc.status.NOT_FOUND,
        message: `No proposal found for artifact_id '${artifactId}'`,
      });
      return;
    }

    // Check if decision already exists
    const existingDecision = this.decisions.get(artifactId);
    if (existingDecision) {
      callback(null, { decision: existingDecision });
      return;
    }

    // Wait for decision
    const emitter = this.decisionEmitters.get(artifactId);
    if (!emitter) {
      callback({
        code: grpc.status.INTERNAL,
        message: `Decision emitter not found for artifact '${artifactId}'`,
      });
      return;
    }

    const timeout = setTimeout(() => {
      callback({
        code: grpc.status.DEADLINE_EXCEEDED,
        message: `No decision made for artifact '${artifactId}' within ${timeoutSeconds} seconds`,
      });
    }, timeoutSeconds * 1000);

    emitter.once('decision', () => {
      clearTimeout(timeout);
      const decision = this.decisions.get(artifactId);
      callback(null, { decision });
    });
  }

  // Helper methods

  /**
   * Store a decision for an artifact (for coordinator use).
   */
  storeDecision(decision: NegotiationDecision): boolean {
    const artifactId = decision.artifact_id;

    if (!this.proposals.has(artifactId)) {
      return false;
    }

    if (this.decisions.has(artifactId)) {
      return false;
    }

    if (!decision.decided_at) {
      decision.decided_at = currentTimestamp();
    }

    this.decisions.set(artifactId, decision);

    // Notify waiting clients
    const emitter = this.decisionEmitters.get(artifactId);
    if (emitter) {
      emitter.emit('decision');
    }

    console.log(`Decision stored for artifact: ${artifactId}`);
    return true;
  }

  /**
   * Compute aggregated statistics for votes on an artifact.
   */
  aggregateVotes(artifactId: string): AggregatedScore | undefined {
    const votes = this.votes.get(artifactId);
    if (!votes || votes.length === 0) {
      return undefined;
    }

    const scores = votes.map((v) => v.score);
    const confidences = votes.map((v) => v.confidence);

    const mean = scores.reduce((a, b) => a + b, 0) / scores.length;
    const minScore = Math.min(...scores);
    const maxScore = Math.max(...scores);

    const variance = scores.reduce((acc, s) => acc + Math.pow(s - mean, 2), 0) / scores.length;
    const stdDev = Math.sqrt(variance);

    const totalConfidence = confidences.reduce((a, b) => a + b, 0);
    let weightedMean: number;
    if (totalConfidence > 0) {
      weightedMean =
        scores.reduce((acc, s, i) => acc + s * confidences[i], 0) / totalConfidence;
    } else {
      weightedMean = mean;
    }

    return {
      mean,
      min_score: minScore,
      max_score: maxScore,
      std_dev: stdDev,
      weighted_mean: weightedMean,
      vote_count: votes.length,
    };
  }

  getProposal(artifactId: string): NegotiationProposal | undefined {
    return this.proposals.get(artifactId);
  }

  listProposals(negotiationRoomId?: string): NegotiationProposal[] {
    const proposals = Array.from(this.proposals.values());
    if (negotiationRoomId) {
      return proposals.filter((p) => p.negotiation_room_id === negotiationRoomId);
    }
    return proposals;
  }

  clearAll(): void {
    this.proposals.clear();
    this.votes.clear();
    this.decisions.clear();
    // Notify all waiting clients
    for (const emitter of this.decisionEmitters.values()) {
      emitter.emit('decision');
    }
    this.decisionEmitters.clear();
    console.log('NegotiationRoomService state cleared');
  }

  /**
   * Get the service handlers for gRPC registration.
   */
  getHandlers(): { [key: string]: grpc.handleUnaryCall<any, any> } {
    return {
      SubmitProposal: this.submitProposal.bind(this),
      SubmitVote: this.submitVote.bind(this),
      GetVotes: this.getVotes.bind(this),
      GetDecision: this.getDecision.bind(this),
      WaitForDecision: this.waitForDecision.bind(this),
    };
  }
}
