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
 * JSON file-based storage backend for NegotiationRoomClient.
 *
 * This is a Colony module - an optional persistence backend that is not part
 * of the core SW4RM protocol. For production deployments requiring horizontal
 * scaling, consider the Redis or PostgreSQL backends instead.
 *
 * @example
 * ```typescript
 * import { NegotiationRoomClient } from 'sw4rm-sdk';
 * import { JsonFileNegotiationRoomStore } from 'colony/stores/typescript/jsonFileStore';
 *
 * const store = new JsonFileNegotiationRoomStore('/var/lib/sw4rm/negotiation');
 * const client = new NegotiationRoomClient({ store });
 * ```
 *
 * @packageDocumentation
 */

import fsp from 'node:fs/promises';
import path from 'node:path';

import type {
  NegotiationRoomStore,
  NegotiationProposal,
  NegotiationVote,
  NegotiationDecision,
} from 'sw4rm-sdk';

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
 * File-based implementation of NegotiationRoomStore using JSON.
 *
 * Persists proposals, votes, and decisions to disk as JSON files. This enables
 * state sharing across multiple processes on the same machine, as well as
 * persistence across process restarts.
 *
 * Storage format:
 * ```
 * {storage_dir}/
 *     proposals/
 *         {artifact_id}.json
 *     votes/
 *         {artifact_id}.json  # Array of votes
 *     decisions/
 *         {artifact_id}.json
 * ```
 *
 * Uses atomic writes (temp file + rename) to prevent corruption.
 *
 * Limitations:
 * - Not suitable for multi-node deployments (use Redis/PostgreSQL instead)
 * - No file locking for cross-process safety
 * - No crash recovery for partial writes
 */
export class JsonFileNegotiationRoomStore implements NegotiationRoomStore {
  private readonly proposalsDir: string;
  private readonly votesDir: string;
  private readonly decisionsDir: string;
  private initialized = false;

  /**
   * Create a new JSON file-based store.
   *
   * @param storageDir - Directory to store JSON files
   */
  constructor(private readonly storageDir: string) {
    this.proposalsDir = path.join(storageDir, 'proposals');
    this.votesDir = path.join(storageDir, 'votes');
    this.decisionsDir = path.join(storageDir, 'decisions');
  }

  /**
   * Initialize the store, creating directories if needed.
   */
  private async ensureInitialized(): Promise<void> {
    if (this.initialized) return;

    await fsp.mkdir(this.proposalsDir, { recursive: true });
    await fsp.mkdir(this.votesDir, { recursive: true });
    await fsp.mkdir(this.decisionsDir, { recursive: true });

    this.initialized = true;
  }

  /**
   * Sanitize artifact_id for filesystem safety.
   */
  private sanitizeId(artifactId: string): string {
    return artifactId.replace(/[/\\]/g, '_');
  }

  /**
   * Get file paths for an artifact.
   */
  private getPaths(artifactId: string) {
    const safeId = this.sanitizeId(artifactId);
    return {
      proposal: path.join(this.proposalsDir, `${safeId}.json`),
      votes: path.join(this.votesDir, `${safeId}.json`),
      decision: path.join(this.decisionsDir, `${safeId}.json`),
    };
  }

  async hasProposal(artifactId: string): Promise<boolean> {
    await this.ensureInitialized();
    const { proposal } = this.getPaths(artifactId);
    try {
      await fsp.access(proposal);
      return true;
    } catch {
      return false;
    }
  }

  async getProposal(artifactId: string): Promise<NegotiationProposal | null> {
    await this.ensureInitialized();
    const { proposal } = this.getPaths(artifactId);

    try {
      const data = await fsp.readFile(proposal, 'utf-8');
      return JSON.parse(data) as NegotiationProposal;
    } catch {
      return null;
    }
  }

  async saveProposal(proposal: NegotiationProposal): Promise<void> {
    await this.ensureInitialized();
    const paths = this.getPaths(proposal.artifactId);

    // Check if already exists
    try {
      await fsp.access(paths.proposal);
      throw new NegotiationRoomStoreError(
        `Proposal with artifact_id '${proposal.artifactId}' already exists`
      );
    } catch (e) {
      if (e instanceof NegotiationRoomStoreError) throw e;
      // File doesn't exist, continue
    }

    // Set createdAt if not provided
    const proposalWithTimestamp: NegotiationProposal = {
      ...proposal,
      createdAt: proposal.createdAt || new Date().toISOString(),
    };

    // Atomic write
    const tempPath = `${paths.proposal}.tmp.${Date.now()}`;
    await fsp.writeFile(tempPath, JSON.stringify(proposalWithTimestamp, null, 2));
    await fsp.rename(tempPath, paths.proposal);

    // Initialize empty votes file
    try {
      await fsp.access(paths.votes);
    } catch {
      await fsp.writeFile(paths.votes, '[]');
    }
  }

  async listProposals(negotiationRoomId?: string): Promise<NegotiationProposal[]> {
    await this.ensureInitialized();

    const proposals: NegotiationProposal[] = [];

    try {
      const files = await fsp.readdir(this.proposalsDir);

      for (const file of files) {
        if (!file.endsWith('.json')) continue;

        try {
          const filePath = path.join(this.proposalsDir, file);
          const data = await fsp.readFile(filePath, 'utf-8');
          const proposal = JSON.parse(data) as NegotiationProposal;

          if (negotiationRoomId === undefined) {
            proposals.push(proposal);
          } else if (proposal.negotiationRoomId === negotiationRoomId) {
            proposals.push(proposal);
          }
        } catch {
          // Skip malformed files
        }
      }
    } catch {
      // Directory doesn't exist or is empty
    }

    return proposals;
  }

  async getVotes(artifactId: string): Promise<NegotiationVote[]> {
    await this.ensureInitialized();
    const { votes } = this.getPaths(artifactId);

    try {
      const data = await fsp.readFile(votes, 'utf-8');
      return JSON.parse(data) as NegotiationVote[];
    } catch {
      return [];
    }
  }

  async addVote(vote: NegotiationVote): Promise<void> {
    await this.ensureInitialized();
    const paths = this.getPaths(vote.artifactId);

    // Load existing votes
    let existingVotes: NegotiationVote[] = [];
    try {
      const data = await fsp.readFile(paths.votes, 'utf-8');
      existingVotes = JSON.parse(data) as NegotiationVote[];
    } catch {
      // No existing votes
    }

    // Check for duplicate
    for (const existingVote of existingVotes) {
      if (existingVote.criticId === vote.criticId) {
        throw new NegotiationRoomStoreError(
          `Critic '${vote.criticId}' has already voted for artifact '${vote.artifactId}'`
        );
      }
    }

    // Set votedAt if not provided
    const voteWithTimestamp: NegotiationVote = {
      ...vote,
      votedAt: vote.votedAt || new Date().toISOString(),
    };

    existingVotes.push(voteWithTimestamp);

    // Atomic write
    const tempPath = `${paths.votes}.tmp.${Date.now()}`;
    await fsp.writeFile(tempPath, JSON.stringify(existingVotes, null, 2));
    await fsp.rename(tempPath, paths.votes);
  }

  async getDecision(artifactId: string): Promise<NegotiationDecision | null> {
    await this.ensureInitialized();
    const { decision } = this.getPaths(artifactId);

    try {
      const data = await fsp.readFile(decision, 'utf-8');
      return JSON.parse(data) as NegotiationDecision;
    } catch {
      return null;
    }
  }

  async saveDecision(decision: NegotiationDecision): Promise<void> {
    await this.ensureInitialized();
    const paths = this.getPaths(decision.artifactId);

    // Check if already exists
    try {
      await fsp.access(paths.decision);
      throw new NegotiationRoomStoreError(
        `Decision already exists for artifact_id '${decision.artifactId}'`
      );
    } catch (e) {
      if (e instanceof NegotiationRoomStoreError) throw e;
      // File doesn't exist, continue
    }

    // Set decidedAt if not provided
    const decisionWithTimestamp: NegotiationDecision = {
      ...decision,
      decidedAt: decision.decidedAt || new Date().toISOString(),
    };

    // Atomic write
    const tempPath = `${paths.decision}.tmp.${Date.now()}`;
    await fsp.writeFile(tempPath, JSON.stringify(decisionWithTimestamp, null, 2));
    await fsp.rename(tempPath, paths.decision);
  }
}
