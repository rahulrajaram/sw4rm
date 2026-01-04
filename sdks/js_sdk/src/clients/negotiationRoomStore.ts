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
 * Negotiation Room storage backend abstraction.
 *
 * This module provides a pluggable storage layer for NegotiationRoomClient,
 * enabling shared state across multiple client instances.
 *
 * The key insight is that NegotiationRoomClient previously used instance-local
 * storage (private Maps), which broke multi-instance deployments. By extracting
 * storage into a separate abstraction that can be shared, we enable:
 *
 * 1. Multiple client instances sharing the same storage
 * 2. Producer/Critic/Coordinator agents in different processes sharing state
 * 3. Future gRPC integration where the server becomes the source of truth
 *
 * For persistent storage backends (JSON file, Redis, PostgreSQL), see the
 * colony/stores module which provides optional persistence implementations.
 *
 * Based on the PolicyStore pattern established in policyStore.ts.
 */

import {
  NegotiationProposal,
  NegotiationVote,
  NegotiationDecision,
} from './negotiationRoom.js';

/**
 * Error thrown when a negotiation room store operation fails.
 */
export class NegotiationRoomStoreError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'NegotiationRoomStoreError';
  }
}

/**
 * Interface defining the contract for negotiation room storage backends.
 *
 * All storage implementations must support these operations for proposals,
 * votes, and decisions. This follows the same pattern as PolicyStore,
 * enabling pluggable backends ranging from in-memory to file-based to gRPC-based.
 */
export interface NegotiationRoomStore {
  /**
   * Check if a proposal exists for the given artifact_id.
   *
   * @param artifactId - Unique identifier for the artifact
   * @returns True if a proposal exists, false otherwise
   */
  hasProposal(artifactId: string): Promise<boolean>;

  /**
   * Retrieve a proposal by artifact_id.
   *
   * @param artifactId - Unique identifier for the artifact
   * @returns The proposal if found, null otherwise
   */
  getProposal(artifactId: string): Promise<NegotiationProposal | null>;

  /**
   * Save a proposal to storage.
   *
   * @param proposal - The proposal to save
   * @throws NegotiationRoomStoreError if a proposal with the same artifact_id already exists
   */
  saveProposal(proposal: NegotiationProposal): Promise<void>;

  /**
   * List all proposals, optionally filtered by negotiation room.
   *
   * @param negotiationRoomId - If provided, only return proposals for this room
   * @returns List of proposals matching the filter criteria
   */
  listProposals(negotiationRoomId?: string): Promise<NegotiationProposal[]>;

  /**
   * Retrieve all votes for a specific artifact.
   *
   * @param artifactId - The identifier of the artifact
   * @returns List of all votes for the artifact (empty array if no votes)
   */
  getVotes(artifactId: string): Promise<NegotiationVote[]>;

  /**
   * Add a vote for an artifact.
   *
   * @param vote - The vote to add
   * @throws NegotiationRoomStoreError if the critic has already voted for this artifact
   */
  addVote(vote: NegotiationVote): Promise<void>;

  /**
   * Retrieve the decision for an artifact.
   *
   * @param artifactId - The identifier of the artifact
   * @returns The decision if available, null otherwise
   */
  getDecision(artifactId: string): Promise<NegotiationDecision | null>;

  /**
   * Save a decision for an artifact.
   *
   * @param decision - The decision to save
   * @throws NegotiationRoomStoreError if a decision already exists for this artifact
   */
  saveDecision(decision: NegotiationDecision): Promise<void>;
}

/**
 * In-memory implementation of NegotiationRoomStore.
 *
 * Stores proposals, votes, and decisions in memory. Data is lost when the
 * process terminates. Suitable for testing and single-process deployments.
 *
 * Thread-safety: JavaScript is single-threaded, but async operations are
 * properly sequenced.
 *
 * @example
 * ```typescript
 * // Create a single shared store
 * const sharedStore = new InMemoryNegotiationRoomStore();
 *
 * // Pass to multiple clients
 * const producerClient = new NegotiationRoomClient({ store: sharedStore });
 * const criticClient = new NegotiationRoomClient({ store: sharedStore });
 * const coordinatorClient = new NegotiationRoomClient({ store: sharedStore });
 *
 * // Now all clients share the same state
 * ```
 */
export class InMemoryNegotiationRoomStore implements NegotiationRoomStore {
  private proposals: Map<string, NegotiationProposal> = new Map();
  private votes: Map<string, NegotiationVote[]> = new Map();
  private decisions: Map<string, NegotiationDecision> = new Map();

  async hasProposal(artifactId: string): Promise<boolean> {
    return this.proposals.has(artifactId);
  }

  async getProposal(artifactId: string): Promise<NegotiationProposal | null> {
    return this.proposals.get(artifactId) || null;
  }

  async saveProposal(proposal: NegotiationProposal): Promise<void> {
    const artifactId = proposal.artifactId;

    if (this.proposals.has(artifactId)) {
      throw new NegotiationRoomStoreError(
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
  }

  async listProposals(negotiationRoomId?: string): Promise<NegotiationProposal[]> {
    const allProposals = Array.from(this.proposals.values());

    if (negotiationRoomId === undefined) {
      return allProposals;
    }

    return allProposals.filter((p) => p.negotiationRoomId === negotiationRoomId);
  }

  async getVotes(artifactId: string): Promise<NegotiationVote[]> {
    return [...(this.votes.get(artifactId) || [])];
  }

  async addVote(vote: NegotiationVote): Promise<void> {
    const artifactId = vote.artifactId;
    const criticId = vote.criticId;

    // Check if this critic has already voted
    const existingVotes = this.votes.get(artifactId) || [];
    for (const existingVote of existingVotes) {
      if (existingVote.criticId === criticId) {
        throw new NegotiationRoomStoreError(
          `Critic '${criticId}' has already voted for artifact '${artifactId}'`
        );
      }
    }

    // Set votedAt if not provided
    const voteWithTimestamp: NegotiationVote = {
      ...vote,
      votedAt: vote.votedAt || new Date().toISOString(),
    };

    // Initialize votes array if needed
    if (!this.votes.has(artifactId)) {
      this.votes.set(artifactId, []);
    }

    this.votes.get(artifactId)!.push(voteWithTimestamp);
  }

  async getDecision(artifactId: string): Promise<NegotiationDecision | null> {
    return this.decisions.get(artifactId) || null;
  }

  async saveDecision(decision: NegotiationDecision): Promise<void> {
    const artifactId = decision.artifactId;

    if (this.decisions.has(artifactId)) {
      throw new NegotiationRoomStoreError(
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
}

// Singleton for easy sharing across the application
let defaultStore: InMemoryNegotiationRoomStore | null = null;

/**
 * Get the default shared in-memory store.
 *
 * This provides a convenient way to share state across multiple
 * NegotiationRoomClient instances within the same process without
 * explicitly passing a store instance.
 *
 * @returns The default shared InMemoryNegotiationRoomStore instance
 *
 * @example
 * ```typescript
 * // All clients automatically share the same store
 * const client1 = new NegotiationRoomClient();  // Uses default store
 * const client2 = new NegotiationRoomClient();  // Uses same default store
 *
 * // Equivalent to:
 * const store = getDefaultStore();
 * const client1 = new NegotiationRoomClient({ store });
 * const client2 = new NegotiationRoomClient({ store });
 * ```
 */
export function getDefaultStore(): InMemoryNegotiationRoomStore {
  if (defaultStore === null) {
    defaultStore = new InMemoryNegotiationRoomStore();
  }
  return defaultStore;
}

/**
 * Reset the default store (primarily for testing).
 *
 * This clears the default store singleton, causing a new store
 * to be created on the next call to getDefaultStore().
 */
export function resetDefaultStore(): void {
  defaultStore = null;
}
