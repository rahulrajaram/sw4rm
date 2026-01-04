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

import { describe, it, expect, beforeEach } from 'vitest';
import {
  NegotiationRoomClient,
  NegotiationProposal,
  NegotiationVote,
  NegotiationDecision,
  ArtifactType,
  DecisionOutcome,
  NegotiationValidationError,
  NegotiationTimeoutError,
  aggregateVotes,
} from '../src/clients/negotiationRoom.js';
import {
  InMemoryNegotiationRoomStore,
  NegotiationRoomStoreError,
} from '../src/clients/negotiationRoomStore.js';

describe('NegotiationRoomClient', () => {
  let client: NegotiationRoomClient;

  beforeEach(() => {
    // Use isolated store for each test
    const store = new InMemoryNegotiationRoomStore();
    client = new NegotiationRoomClient({ store });
  });

  describe('submitProposal', () => {
    it('should submit a proposal successfully', async () => {
      const proposal: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'code-1',
        producerId: 'producer-1',
        artifact: new TextEncoder().encode('def hello(): pass'),
        artifactContentType: 'text/x-python',
        requestedCritics: ['critic-1', 'critic-2'],
        negotiationRoomId: 'room-1',
      };

      const artifactId = await client.submitProposal(proposal);
      expect(artifactId).toBe('code-1');

      const retrieved = await client.getProposal('code-1');
      expect(retrieved).not.toBeNull();
      expect(retrieved?.producerId).toBe('producer-1');
    });

    it('should reject duplicate proposal', async () => {
      const proposal: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'code-dup',
        producerId: 'producer-1',
        artifact: new Uint8Array(),
        artifactContentType: 'text/plain',
        requestedCritics: ['critic-1'],
        negotiationRoomId: 'room-1',
      };

      await client.submitProposal(proposal);

      await expect(client.submitProposal(proposal)).rejects.toThrow(
        NegotiationRoomStoreError
      );
    });

    it('should preserve artifact content', async () => {
      const code = 'def factorial(n): return 1 if n <= 1 else n * factorial(n-1)';
      const proposal: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'code-content',
        producerId: 'producer-1',
        artifact: new TextEncoder().encode(code),
        artifactContentType: 'text/x-python',
        requestedCritics: ['critic-1'],
        negotiationRoomId: 'room-1',
      };

      await client.submitProposal(proposal);

      const retrieved = await client.getProposal('code-content');
      const decodedArtifact = new TextDecoder().decode(retrieved?.artifact);
      expect(decodedArtifact).toBe(code);
    });
  });

  describe('submitVote', () => {
    beforeEach(async () => {
      // Create a proposal for voting tests
      const proposal: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'vote-test',
        producerId: 'producer-1',
        artifact: new Uint8Array(),
        artifactContentType: 'text/plain',
        requestedCritics: ['critic-1', 'critic-2'],
        negotiationRoomId: 'room-1',
      };
      await client.submitProposal(proposal);
    });

    it('should submit a vote successfully', async () => {
      const vote: NegotiationVote = {
        artifactId: 'vote-test',
        criticId: 'critic-1',
        score: 8.5,
        confidence: 0.9,
        passed: true,
        strengths: ['Well structured'],
        weaknesses: ['Missing tests'],
        recommendations: ['Add unit tests'],
        negotiationRoomId: 'room-1',
      };

      await client.submitVote(vote);

      const votes = await client.getVotes('vote-test');
      expect(votes).toHaveLength(1);
      expect(votes[0].criticId).toBe('critic-1');
      expect(votes[0].score).toBe(8.5);
    });

    it('should reject vote for non-existent artifact', async () => {
      const vote: NegotiationVote = {
        artifactId: 'nonexistent',
        criticId: 'critic-1',
        score: 8.0,
        confidence: 0.9,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      };

      await expect(client.submitVote(vote)).rejects.toThrow(
        NegotiationValidationError
      );
    });

    it('should reject vote with invalid score', async () => {
      const vote: NegotiationVote = {
        artifactId: 'vote-test',
        criticId: 'critic-1',
        score: 15.0, // Out of range
        confidence: 0.9,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      };

      await expect(client.submitVote(vote)).rejects.toThrow(
        NegotiationValidationError
      );
    });

    it('should reject vote with invalid confidence', async () => {
      const vote: NegotiationVote = {
        artifactId: 'vote-test',
        criticId: 'critic-1',
        score: 8.0,
        confidence: 1.5, // Out of range
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      };

      await expect(client.submitVote(vote)).rejects.toThrow(
        NegotiationValidationError
      );
    });

    it('should reject duplicate vote from same critic', async () => {
      const vote1: NegotiationVote = {
        artifactId: 'vote-test',
        criticId: 'critic-1',
        score: 8.0,
        confidence: 0.9,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      };

      await client.submitVote(vote1);

      const vote2: NegotiationVote = {
        ...vote1,
        score: 9.0, // Different score
      };

      await expect(client.submitVote(vote2)).rejects.toThrow(
        NegotiationRoomStoreError
      );
    });

    it('should allow votes from different critics', async () => {
      const vote1: NegotiationVote = {
        artifactId: 'vote-test',
        criticId: 'critic-1',
        score: 8.0,
        confidence: 0.9,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      };

      const vote2: NegotiationVote = {
        artifactId: 'vote-test',
        criticId: 'critic-2',
        score: 7.5,
        confidence: 0.85,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      };

      await client.submitVote(vote1);
      await client.submitVote(vote2);

      const votes = await client.getVotes('vote-test');
      expect(votes).toHaveLength(2);
    });
  });

  describe('getVotes', () => {
    beforeEach(async () => {
      const proposal: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'get-votes-test',
        producerId: 'producer-1',
        artifact: new Uint8Array(),
        artifactContentType: 'text/plain',
        requestedCritics: ['critic-1', 'critic-2', 'critic-3'],
        negotiationRoomId: 'room-1',
      };
      await client.submitProposal(proposal);
    });

    it('should return empty array when no votes', async () => {
      const votes = await client.getVotes('get-votes-test');
      expect(votes).toEqual([]);
    });

    it('should return all votes for an artifact', async () => {
      for (let i = 1; i <= 3; i++) {
        const vote: NegotiationVote = {
          artifactId: 'get-votes-test',
          criticId: `critic-${i}`,
          score: 7.0 + i * 0.5,
          confidence: 0.9,
          passed: true,
          strengths: [],
          weaknesses: [],
          recommendations: [],
          negotiationRoomId: 'room-1',
        };
        await client.submitVote(vote);
      }

      const votes = await client.getVotes('get-votes-test');
      expect(votes).toHaveLength(3);
      expect(new Set(votes.map((v) => v.criticId))).toEqual(
        new Set(['critic-1', 'critic-2', 'critic-3'])
      );
    });

    it('should reject getting votes for non-existent artifact', async () => {
      await expect(client.getVotes('nonexistent')).rejects.toThrow(
        NegotiationValidationError
      );
    });
  });

  describe('storeDecision and getDecision', () => {
    beforeEach(async () => {
      const proposal: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'decision-test',
        producerId: 'producer-1',
        artifact: new Uint8Array(),
        artifactContentType: 'text/plain',
        requestedCritics: ['critic-1'],
        negotiationRoomId: 'room-1',
      };
      await client.submitProposal(proposal);
    });

    it('should store and retrieve a decision', async () => {
      const vote: NegotiationVote = {
        artifactId: 'decision-test',
        criticId: 'critic-1',
        score: 9.0,
        confidence: 0.95,
        passed: true,
        strengths: ['Excellent'],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      };

      const aggregated = aggregateVotes([vote]);

      const decision: NegotiationDecision = {
        artifactId: 'decision-test',
        outcome: DecisionOutcome.APPROVED,
        votes: [vote],
        aggregatedScore: aggregated,
        policyVersion: '1.0',
        reason: 'Meets all criteria',
        negotiationRoomId: 'room-1',
      };

      await client.storeDecision(decision);

      const retrieved = await client.getDecision('decision-test');
      expect(retrieved).not.toBeNull();
      expect(retrieved?.outcome).toBe(DecisionOutcome.APPROVED);
      expect(retrieved?.artifactId).toBe('decision-test');
    });

    it('should return null when no decision exists', async () => {
      const decision = await client.getDecision('decision-test');
      expect(decision).toBeNull();
    });

    it('should reject storing decision for non-existent artifact', async () => {
      const decision: NegotiationDecision = {
        artifactId: 'nonexistent',
        outcome: DecisionOutcome.APPROVED,
        votes: [],
        aggregatedScore: {
          mean: 8.0,
          minScore: 8.0,
          maxScore: 8.0,
          stdDev: 0,
          weightedMean: 8.0,
          voteCount: 1,
        },
        policyVersion: '1.0',
        reason: 'Test',
        negotiationRoomId: 'room-1',
      };

      await expect(client.storeDecision(decision)).rejects.toThrow(
        NegotiationValidationError
      );
    });

    it('should reject storing duplicate decision', async () => {
      const vote: NegotiationVote = {
        artifactId: 'decision-test',
        criticId: 'critic-1',
        score: 9.0,
        confidence: 0.95,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      };

      const decision: NegotiationDecision = {
        artifactId: 'decision-test',
        outcome: DecisionOutcome.APPROVED,
        votes: [vote],
        aggregatedScore: aggregateVotes([vote]),
        policyVersion: '1.0',
        reason: 'Test',
        negotiationRoomId: 'room-1',
      };

      await client.storeDecision(decision);

      await expect(client.storeDecision(decision)).rejects.toThrow(
        NegotiationRoomStoreError
      );
    });
  });

  describe('waitForDecision', () => {
    beforeEach(async () => {
      const proposal: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'wait-test',
        producerId: 'producer-1',
        artifact: new Uint8Array(),
        artifactContentType: 'text/plain',
        requestedCritics: ['critic-1'],
        negotiationRoomId: 'room-1',
      };
      await client.submitProposal(proposal);
    });

    it('should wait and return decision when it arrives', async () => {
      const vote: NegotiationVote = {
        artifactId: 'wait-test',
        criticId: 'critic-1',
        score: 9.0,
        confidence: 0.95,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      };

      const decision: NegotiationDecision = {
        artifactId: 'wait-test',
        outcome: DecisionOutcome.APPROVED,
        votes: [vote],
        aggregatedScore: aggregateVotes([vote]),
        policyVersion: '1.0',
        reason: 'Test',
        negotiationRoomId: 'room-1',
      };

      // Store decision after a short delay
      setTimeout(() => client.storeDecision(decision), 100);

      const result = await client.waitForDecision('wait-test', 2000);
      expect(result.outcome).toBe(DecisionOutcome.APPROVED);
    });

    it('should timeout if no decision arrives', async () => {
      await expect(client.waitForDecision('wait-test', 200)).rejects.toThrow(
        NegotiationTimeoutError
      );
    });

    it('should reject waiting for non-existent artifact', async () => {
      await expect(
        client.waitForDecision('nonexistent', 1000)
      ).rejects.toThrow(NegotiationValidationError);
    });
  });

  describe('listProposals', () => {
    it('should list all proposals', async () => {
      const proposal1: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'code-1',
        producerId: 'producer-1',
        artifact: new Uint8Array(),
        artifactContentType: 'text/plain',
        requestedCritics: ['critic-1'],
        negotiationRoomId: 'room-1',
      };

      const proposal2: NegotiationProposal = {
        artifactType: ArtifactType.PLAN,
        artifactId: 'plan-1',
        producerId: 'producer-2',
        artifact: new Uint8Array(),
        artifactContentType: 'text/plain',
        requestedCritics: ['critic-2'],
        negotiationRoomId: 'room-2',
      };

      await client.submitProposal(proposal1);
      await client.submitProposal(proposal2);

      const proposals = await client.listProposals();
      expect(proposals).toHaveLength(2);
      expect(new Set(proposals.map((p) => p.artifactId))).toEqual(
        new Set(['code-1', 'plan-1'])
      );
    });

    it('should filter proposals by negotiation room', async () => {
      const proposal1: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'code-1',
        producerId: 'producer-1',
        artifact: new Uint8Array(),
        artifactContentType: 'text/plain',
        requestedCritics: ['critic-1'],
        negotiationRoomId: 'room-1',
      };

      const proposal2: NegotiationProposal = {
        artifactType: ArtifactType.PLAN,
        artifactId: 'plan-1',
        producerId: 'producer-2',
        artifact: new Uint8Array(),
        artifactContentType: 'text/plain',
        requestedCritics: ['critic-2'],
        negotiationRoomId: 'room-2',
      };

      await client.submitProposal(proposal1);
      await client.submitProposal(proposal2);

      const room1Proposals = await client.listProposals('room-1');
      expect(room1Proposals).toHaveLength(1);
      expect(room1Proposals[0].artifactId).toBe('code-1');
    });

    it('should return empty array when no proposals', async () => {
      const proposals = await client.listProposals();
      expect(proposals).toEqual([]);
    });
  });

  describe('shared store behavior', () => {
    it('should share state across multiple clients with same store', async () => {
      const store = new InMemoryNegotiationRoomStore();
      const producer = new NegotiationRoomClient({ store });
      const critic = new NegotiationRoomClient({ store });
      const coordinator = new NegotiationRoomClient({ store });

      // Producer submits proposal
      const proposal: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'shared-test',
        producerId: 'producer-1',
        artifact: new TextEncoder().encode('test code'),
        artifactContentType: 'text/x-python',
        requestedCritics: ['critic-1'],
        negotiationRoomId: 'room-1',
      };
      await producer.submitProposal(proposal);

      // Critic can see the proposal
      const retrieved = await critic.getProposal('shared-test');
      expect(retrieved).not.toBeNull();
      expect(retrieved?.artifactId).toBe('shared-test');

      // Critic submits vote
      const vote: NegotiationVote = {
        artifactId: 'shared-test',
        criticId: 'critic-1',
        score: 8.5,
        confidence: 0.9,
        passed: true,
        strengths: ['Good'],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      };
      await critic.submitVote(vote);

      // Coordinator can see the vote
      const votes = await coordinator.getVotes('shared-test');
      expect(votes).toHaveLength(1);
      expect(votes[0].criticId).toBe('critic-1');
    });

    it('should isolate state with different stores', async () => {
      const store1 = new InMemoryNegotiationRoomStore();
      const store2 = new InMemoryNegotiationRoomStore();

      const client1 = new NegotiationRoomClient({ store: store1 });
      const client2 = new NegotiationRoomClient({ store: store2 });

      const proposal: NegotiationProposal = {
        artifactType: ArtifactType.CODE,
        artifactId: 'isolated-test',
        producerId: 'producer-1',
        artifact: new Uint8Array(),
        artifactContentType: 'text/plain',
        requestedCritics: ['critic-1'],
        negotiationRoomId: 'room-1',
      };

      await client1.submitProposal(proposal);

      // client2 should NOT see the proposal
      const retrieved = await client2.getProposal('isolated-test');
      expect(retrieved).toBeNull();
    });
  });
});

describe('aggregateVotes', () => {
  it('should calculate basic statistics', () => {
    const votes: NegotiationVote[] = [
      {
        artifactId: 'test',
        criticId: 'critic-1',
        score: 8.0,
        confidence: 0.9,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      },
      {
        artifactId: 'test',
        criticId: 'critic-2',
        score: 9.0,
        confidence: 0.9,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      },
      {
        artifactId: 'test',
        criticId: 'critic-3',
        score: 7.0,
        confidence: 0.9,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      },
    ];

    const aggregated = aggregateVotes(votes);

    expect(aggregated.mean).toBe(8.0);
    expect(aggregated.minScore).toBe(7.0);
    expect(aggregated.maxScore).toBe(9.0);
    expect(aggregated.voteCount).toBe(3);
  });

  it('should calculate confidence-weighted mean', () => {
    const votes: NegotiationVote[] = [
      {
        artifactId: 'test',
        criticId: 'critic-1',
        score: 9.0,
        confidence: 1.0, // High confidence
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      },
      {
        artifactId: 'test',
        criticId: 'critic-2',
        score: 3.0,
        confidence: 0.1, // Low confidence
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      },
    ];

    const aggregated = aggregateVotes(votes);

    // Weighted mean should be closer to 9.0 due to higher confidence
    expect(aggregated.weightedMean).toBeGreaterThan(aggregated.mean);
    expect(aggregated.weightedMean).toBeGreaterThan(8.0);
  });

  it('should calculate standard deviation', () => {
    const votes: NegotiationVote[] = [
      {
        artifactId: 'test',
        criticId: 'critic-1',
        score: 8.0,
        confidence: 0.9,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      },
      {
        artifactId: 'test',
        criticId: 'critic-2',
        score: 8.0,
        confidence: 0.9,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      },
    ];

    const aggregated = aggregateVotes(votes);

    // All scores identical, so stdDev should be 0
    expect(aggregated.stdDev).toBe(0);
  });

  it('should handle single vote', () => {
    const votes: NegotiationVote[] = [
      {
        artifactId: 'test',
        criticId: 'critic-1',
        score: 8.5,
        confidence: 0.95,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      },
    ];

    const aggregated = aggregateVotes(votes);

    expect(aggregated.mean).toBe(8.5);
    expect(aggregated.minScore).toBe(8.5);
    expect(aggregated.maxScore).toBe(8.5);
    expect(aggregated.weightedMean).toBe(8.5);
    expect(aggregated.stdDev).toBe(0);
    expect(aggregated.voteCount).toBe(1);
  });

  it('should handle zero confidence gracefully', () => {
    const votes: NegotiationVote[] = [
      {
        artifactId: 'test',
        criticId: 'critic-1',
        score: 8.0,
        confidence: 0.0,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      },
      {
        artifactId: 'test',
        criticId: 'critic-2',
        score: 9.0,
        confidence: 0.0,
        passed: true,
        strengths: [],
        weaknesses: [],
        recommendations: [],
        negotiationRoomId: 'room-1',
      },
    ];

    const aggregated = aggregateVotes(votes);

    // Should fallback to simple mean when all confidences are zero
    expect(aggregated.weightedMean).toBe(aggregated.mean);
  });

  it('should reject empty votes array', () => {
    expect(() => aggregateVotes([])).toThrow(NegotiationValidationError);
  });
});
