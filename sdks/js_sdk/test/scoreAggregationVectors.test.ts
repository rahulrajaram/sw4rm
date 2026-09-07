import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { aggregateScoreSummary } from '../src/runtime/voting.js';
import type { NegotiationVote } from '../src/clients/negotiationRoom.js';

type Vector = {
  id: string;
  votes: Array<{ score: number; confidence: number }>;
  expected?: {
    mean: number;
    min_score: number;
    max_score: number;
    std_dev: number;
    weighted_mean: number;
    vote_count: number;
  };
  error?: string;
};

const vectorPath = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../../tests/conformance_vectors/score_aggregation_vectors.json',
);
const vectors = (JSON.parse(readFileSync(vectorPath, 'utf8')) as { vectors: Vector[] }).vectors;

function asVotes(votes: Vector['votes']): NegotiationVote[] {
  return votes.map((vote, index) => ({
    artifactId: 'vector-artifact',
    criticId: `critic-${index}`,
    score: vote.score,
    confidence: vote.confidence,
    passed: vote.score >= 5,
    strengths: [],
    weaknesses: [],
    recommendations: [],
  }));
}

describe('shared score-summary conformance vectors', () => {
  for (const vector of vectors) {
    it(`executes ${vector.id}`, () => {
      if (vector.error) {
        expect(() => aggregateScoreSummary(asVotes(vector.votes))).toThrow('empty list of votes');
        return;
      }
      const actual = aggregateScoreSummary(asVotes(vector.votes));
      expect(actual.mean).toBeCloseTo(vector.expected!.mean, 12);
      expect(actual.minScore).toBe(vector.expected!.min_score);
      expect(actual.maxScore).toBe(vector.expected!.max_score);
      expect(actual.stdDev).toBeCloseTo(vector.expected!.std_dev, 12);
      expect(actual.weightedMean).toBeCloseTo(vector.expected!.weighted_mean, 12);
      expect(actual.voteCount).toBe(vector.expected!.vote_count);
    });
  }
});
