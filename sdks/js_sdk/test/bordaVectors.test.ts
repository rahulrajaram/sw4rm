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

import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { BordaCountAggregator, type NegotiationVote } from '../src/runtime/voting.js';

// Cross-SDK Borda conformance vectors (R22): pin identical score-derived
// Borda outputs across the Python, JavaScript, and Rust SDKs. Lisp and
// Elixir implement classic Borda over ranked preference lists — a distinct
// input format, intentionally not part of this corpus.

const corpus = JSON.parse(
  fs.readFileSync(
    path.resolve(
      path.dirname(fileURLToPath(import.meta.url)),
      '../../../tests/conformance_vectors/borda_vectors.json',
    ),
    'utf-8',
  ),
);

function vote(entry: { critic_id: string; score: number }): NegotiationVote {
  return {
    artifactId: 'conformance',
    criticId: entry.critic_id,
    score: entry.score,
    confidence: 1.0,
    passed: true,
    strengths: [],
    weaknesses: [],
    recommendations: [],
  };
}

describe('Borda conformance vectors', () => {
  for (const vector of corpus.vectors) {
    it(vector.id, () => {
      const outcome = new BordaCountAggregator().aggregate(vector.votes.map(vote));
      const expected = vector.expected;
      expect(outcome.weightedMean).toBeCloseTo(expected.weighted_mean, 9);
      expect(outcome.mean).toBeCloseTo(expected.mean, 9);
      expect(outcome.stdDev).toBeCloseTo(expected.std_dev, 9);
      expect(outcome.minScore).toBe(expected.min_score);
      expect(outcome.maxScore).toBe(expected.max_score);
      expect(outcome.voteCount).toBe(expected.vote_count);
    });
  }

  it('output depends on scores, not just the vote count (R22 regression)', () => {
    const aggregator = new BordaCountAggregator();
    const high = aggregator.aggregate(
      [9, 9, 9].map((score, i) => vote({ critic_id: `c${i}`, score })),
    );
    const low = aggregator.aggregate(
      [1, 1, 1].map((score, i) => vote({ critic_id: `c${i}`, score })),
    );
    expect(high.voteCount).toBe(low.voteCount);
    expect(high.weightedMean).not.toBe(low.weightedMean);
  });
});
