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

import { describe, it, expect } from 'vitest';
import {
  SimpleAverageAggregator,
  ConfidenceWeightedAggregator,
  MajorityVoteAggregator,
  BordaCountAggregator,
  VotingAnalyzer,
} from '../src/runtime/voting.js';
import type { NegotiationVote } from '../src/clients/negotiationRoom.js';

/**
 * Tests for voting aggregation strategies and VotingAnalyzer.
 *
 * Tests cover:
 * - All aggregation strategies (SimpleAverage, ConfidenceWeighted, MajorityVote, BordaCount)
 * - Edge cases (empty votes, single vote, all same score, ties)
 * - Entropy calculation
 * - Consensus detection
 * - Polarization detection
 * - Confidence variance
 *
 * Ported from: sdks/py_sdk/tests/test_voting_aggregation.py
 */

function createVote(
  score: number,
  confidence: number = 0.8,
  passed: boolean = true,
  criticId: string = 'critic_1'
): NegotiationVote {
  return {
    artifactId: 'test_artifact',
    criticId,
    score,
    confidence,
    passed,
    strengths: ['good'],
    weaknesses: ['bad'],
    recommendations: ['improve'],
  };
}

describe('VotingAggregation', () => {
  describe('SimpleAverageAggregator', () => {
    it('should compute basic arithmetic mean', () => {
      const votes = [
        createVote(8.0, 0.8, true, 'c1'),
        createVote(6.0, 0.8, true, 'c2'),
        createVote(7.0, 0.8, true, 'c3'),
      ];

      const aggregator = new SimpleAverageAggregator();
      const result = aggregator.aggregate(votes);

      expect(result.mean).toBe(7.0);
      expect(result.weightedMean).toBe(7.0); // Same as mean for simple average
      expect(result.minScore).toBe(6.0);
      expect(result.maxScore).toBe(8.0);
      expect(result.voteCount).toBe(3);
      expect(result.stdDev).toBeGreaterThan(0);
    });

    it('should handle all same scores', () => {
      const votes = Array.from({ length: 5 }, (_, i) => createVote(5.0, 0.8, true, `c${i}`));

      const aggregator = new SimpleAverageAggregator();
      const result = aggregator.aggregate(votes);

      expect(result.mean).toBe(5.0);
      expect(result.weightedMean).toBe(5.0);
      expect(result.minScore).toBe(5.0);
      expect(result.maxScore).toBe(5.0);
      expect(result.stdDev).toBe(0.0);
      expect(result.voteCount).toBe(5);
    });

    it('should handle single vote', () => {
      const votes = [createVote(7.5)];

      const aggregator = new SimpleAverageAggregator();
      const result = aggregator.aggregate(votes);

      expect(result.mean).toBe(7.5);
      expect(result.weightedMean).toBe(7.5);
      expect(result.minScore).toBe(7.5);
      expect(result.maxScore).toBe(7.5);
      expect(result.stdDev).toBe(0.0);
      expect(result.voteCount).toBe(1);
    });

    it('should throw on empty vote list', () => {
      const aggregator = new SimpleAverageAggregator();
      expect(() => aggregator.aggregate([])).toThrow('Cannot aggregate empty list');
    });
  });

  describe('ConfidenceWeightedAggregator', () => {
    it('should compute confidence-weighted aggregation', () => {
      const votes = [
        createVote(8.0, 0.9, true, 'c1'),
        createVote(4.0, 0.5, true, 'c2'),
        createVote(6.0, 0.7, true, 'c3'),
      ];

      const aggregator = new ConfidenceWeightedAggregator();
      const result = aggregator.aggregate(votes);

      // Mean should be simple average
      expect(result.mean).toBe(6.0);

      // Weighted mean: (8*0.9 + 4*0.5 + 6*0.7) / (0.9 + 0.5 + 0.7)
      const expectedWeighted = (8.0 * 0.9 + 4.0 * 0.5 + 6.0 * 0.7) / (0.9 + 0.5 + 0.7);
      expect(Math.abs(result.weightedMean - expectedWeighted)).toBeLessThan(0.01);

      expect(result.minScore).toBe(4.0);
      expect(result.maxScore).toBe(8.0);
      expect(result.voteCount).toBe(3);
    });

    it('should favor high confidence votes', () => {
      const votes = [
        createVote(9.0, 0.95, true, 'c1'),
        createVote(2.0, 0.1, true, 'c2'),
        createVote(3.0, 0.1, true, 'c3'),
      ];

      const aggregator = new ConfidenceWeightedAggregator();
      const result = aggregator.aggregate(votes);

      // Simple mean should be around 4.67
      expect(Math.abs(result.mean - 4.67)).toBeLessThan(0.1);

      // Weighted mean should be much closer to 9.0 (high confidence vote)
      expect(result.weightedMean).toBeGreaterThan(7.0);
    });

    it('should fallback to simple mean when all confidences are zero', () => {
      const votes = [
        createVote(8.0, 0.0, true, 'c1'),
        createVote(6.0, 0.0, true, 'c2'),
      ];

      const aggregator = new ConfidenceWeightedAggregator();
      const result = aggregator.aggregate(votes);

      expect(result.weightedMean).toBe(7.0);
    });

    it('should throw on empty vote list', () => {
      const aggregator = new ConfidenceWeightedAggregator();
      expect(() => aggregator.aggregate([])).toThrow('Cannot aggregate empty list');
    });
  });

  describe('MajorityVoteAggregator', () => {
    it('should return 10.0 when all passed', () => {
      const votes = Array.from({ length: 5 }, (_, i) => createVote(8.0, 0.8, true, `c${i}`));

      const aggregator = new MajorityVoteAggregator();
      const result = aggregator.aggregate(votes);

      expect(result.weightedMean).toBe(10.0);
      expect(result.voteCount).toBe(5);
    });

    it('should return 0.0 when all failed', () => {
      const votes = Array.from({ length: 5 }, (_, i) => createVote(3.0, 0.8, false, `c${i}`));

      const aggregator = new MajorityVoteAggregator();
      const result = aggregator.aggregate(votes);

      expect(result.weightedMean).toBe(0.0);
    });

    it('should return 7.5 when majority passed', () => {
      const votes = [
        createVote(8.0, 0.8, true, 'c1'),
        createVote(7.0, 0.8, true, 'c2'),
        createVote(6.5, 0.8, true, 'c3'),
        createVote(4.0, 0.8, false, 'c4'),
      ];

      const aggregator = new MajorityVoteAggregator();
      const result = aggregator.aggregate(votes);

      expect(result.weightedMean).toBe(7.5);
    });

    it('should return 2.5 when majority failed', () => {
      const votes = [
        createVote(5.0, 0.8, false, 'c1'),
        createVote(4.0, 0.8, false, 'c2'),
        createVote(3.0, 0.8, false, 'c3'),
        createVote(7.0, 0.8, true, 'c4'),
      ];

      const aggregator = new MajorityVoteAggregator();
      const result = aggregator.aggregate(votes);

      expect(result.weightedMean).toBe(2.5);
    });

    it('should return 5.0 on tie', () => {
      const votes = [
        createVote(8.0, 0.8, true, 'c1'),
        createVote(7.0, 0.8, true, 'c2'),
        createVote(4.0, 0.8, false, 'c3'),
        createVote(3.0, 0.8, false, 'c4'),
      ];

      const aggregator = new MajorityVoteAggregator();
      const result = aggregator.aggregate(votes);

      expect(result.weightedMean).toBe(5.0);
    });

    it('should throw on empty vote list', () => {
      const aggregator = new MajorityVoteAggregator();
      expect(() => aggregator.aggregate([])).toThrow('Cannot aggregate empty list');
    });
  });

  describe('BordaCountAggregator', () => {
    it('should compute Borda count', () => {
      const votes = [
        createVote(9.0, 0.8, true, 'c1'), // Rank 1: 3 points
        createVote(7.0, 0.8, true, 'c2'), // Rank 2: 2 points
        createVote(5.0, 0.8, true, 'c3'), // Rank 3: 1 point
      ];

      const aggregator = new BordaCountAggregator();
      const result = aggregator.aggregate(votes);

      // Total points: 3 + 2 + 1 = 6
      // Average points: 6 / 3 = 2
      // Normalized: (2 / 3) * 10 = 6.67
      expect(Math.abs(result.weightedMean - 6.67)).toBeLessThan(0.1);
      expect(result.voteCount).toBe(3);
    });

    it('should handle all same scores', () => {
      const votes = Array.from({ length: 4 }, (_, i) => createVote(7.0, 0.8, true, `c${i}`));

      const aggregator = new BordaCountAggregator();
      const result = aggregator.aggregate(votes);

      // All same scores: points are 4,3,2,1 = 10 total, avg = 2.5
      // Normalized: (2.5 / 4) * 10 = 6.25
      expect(Math.abs(result.weightedMean - 6.25)).toBeLessThan(0.1);
    });

    it('should handle extreme scores', () => {
      const votes = [
        createVote(10.0, 0.8, true, 'c1'),
        createVote(0.0, 0.8, true, 'c2'),
      ];

      const aggregator = new BordaCountAggregator();
      const result = aggregator.aggregate(votes);

      // 2 votes: 2 points + 1 point = 3 total, avg = 1.5
      // Normalized: (1.5 / 2) * 10 = 7.5
      expect(Math.abs(result.weightedMean - 7.5)).toBeLessThan(0.1);
    });

    it('should handle single vote', () => {
      const votes = [createVote(7.0)];

      const aggregator = new BordaCountAggregator();
      const result = aggregator.aggregate(votes);

      // Single vote gets 1 point, normalized: (1/1) * 10 = 10.0
      expect(result.weightedMean).toBe(10.0);
    });

    it('should throw on empty vote list', () => {
      const aggregator = new BordaCountAggregator();
      expect(() => aggregator.aggregate([])).toThrow('Cannot aggregate empty list');
    });
  });

  describe('VotingAnalyzer', () => {
    describe('aggregate', () => {
      it('should delegate to strategy', () => {
        const votes = [
          createVote(8.0, 0.8, true, 'c1'),
          createVote(6.0, 0.8, true, 'c2'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const result = analyzer.aggregate(votes);

        expect(result.mean).toBe(7.0);
        expect(result.weightedMean).toBe(7.0);
      });
    });

    describe('computeEntropy', () => {
      it('should compute entropy for uniform distribution', () => {
        // One vote in each bin (0-2, 2-4, 4-6, 6-8, 8-10)
        const votes = [
          createVote(1.0, 0.8, true, 'c1'),
          createVote(3.0, 0.8, true, 'c2'),
          createVote(5.0, 0.8, true, 'c3'),
          createVote(7.0, 0.8, true, 'c4'),
          createVote(9.0, 0.8, true, 'c5'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const entropy = analyzer.computeEntropy(votes);

        // Uniform distribution over 5 bins: log2(5) = 2.32
        expect(Math.abs(entropy - Math.log2(5))).toBeLessThan(0.01);
      });

      it('should compute zero entropy for perfect consensus', () => {
        const votes = Array.from({ length: 5 }, (_, i) => createVote(7.0, 0.8, true, `c${i}`));

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const entropy = analyzer.computeEntropy(votes);

        expect(entropy).toBe(0.0);
      });

      it('should throw on empty votes', () => {
        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        expect(() => analyzer.computeEntropy([])).toThrow('Cannot compute entropy');
      });
    });

    describe('detectConsensus', () => {
      it('should detect strong consensus', () => {
        const votes = [
          createVote(7.5, 0.8, true, 'c1'),
          createVote(7.8, 0.8, true, 'c2'),
          createVote(7.2, 0.8, true, 'c3'),
          createVote(7.6, 0.8, true, 'c4'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const consensus = analyzer.detectConsensus(votes);

        expect(consensus).toBe(true);
      });

      it('should not detect consensus with high variance', () => {
        const votes = [
          createVote(9.0, 0.8, true, 'c1'),
          createVote(8.0, 0.8, true, 'c2'),
          createVote(2.0, 0.8, false, 'c3'),
          createVote(3.0, 0.8, false, 'c4'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const consensus = analyzer.detectConsensus(votes);

        expect(consensus).toBe(false);
      });

      it('should not detect consensus with low agreement', () => {
        const votes = [
          createVote(7.1, 0.8, true, 'c1'),
          createVote(7.2, 0.8, true, 'c2'),
          createVote(7.0, 0.8, false, 'c3'),
          createVote(6.9, 0.8, false, 'c4'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const consensus = analyzer.detectConsensus(votes, 0.8);

        expect(consensus).toBe(false);
      });

      it('should respect custom threshold', () => {
        const votes = [
          createVote(7.0, 0.8, true, 'c1'),
          createVote(7.0, 0.8, true, 'c2'),
          createVote(7.0, 0.8, false, 'c3'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());

        // With 66% threshold, should detect consensus (2/3 = 66.7%)
        expect(analyzer.detectConsensus(votes, 0.66)).toBe(true);

        // With 70% threshold, should not detect consensus
        expect(analyzer.detectConsensus(votes, 0.70)).toBe(false);
      });

      it('should throw on invalid threshold', () => {
        const votes = [createVote(7.0)];
        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());

        expect(() => analyzer.detectConsensus(votes, 1.5)).toThrow('Threshold must be in');
      });

      it('should throw on empty votes', () => {
        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        expect(() => analyzer.detectConsensus([])).toThrow('Cannot detect consensus');
      });
    });

    describe('detectPolarization', () => {
      it('should detect clear polarization', () => {
        const votes = [
          createVote(9.0, 0.8, true, 'c1'),
          createVote(9.5, 0.8, true, 'c2'),
          createVote(8.5, 0.8, true, 'c3'),
          createVote(2.0, 0.8, false, 'c4'),
          createVote(1.5, 0.8, false, 'c5'),
          createVote(2.5, 0.8, false, 'c6'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const polarization = analyzer.detectPolarization(votes);

        expect(polarization).toBe(true);
      });

      it('should not detect polarization for normal distribution', () => {
        const votes = [
          createVote(6.0, 0.8, true, 'c1'),
          createVote(6.5, 0.8, true, 'c2'),
          createVote(7.0, 0.8, true, 'c3'),
          createVote(6.8, 0.8, true, 'c4'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const polarization = analyzer.detectPolarization(votes);

        expect(polarization).toBe(false);
      });

      it('should not detect polarization with too few votes', () => {
        const votes = [
          createVote(9.0, 0.8, true, 'c1'),
          createVote(1.0, 0.8, true, 'c2'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const polarization = analyzer.detectPolarization(votes);

        expect(polarization).toBe(false);
      });

      it('should throw on empty votes', () => {
        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        expect(() => analyzer.detectPolarization([])).toThrow('Cannot detect polarization');
      });
    });

    describe('computeConfidenceVariance', () => {
      it('should compute zero variance for uniform confidence', () => {
        const votes = Array.from({ length: 5 }, (_, i) => createVote(7.0, 0.8, true, `c${i}`));

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const variance = analyzer.computeConfidenceVariance(votes);

        expect(variance).toBe(0.0);
      });

      it('should compute variance for varied confidence', () => {
        const votes = [
          createVote(7.0, 0.9, true, 'c1'),
          createVote(7.0, 0.5, true, 'c2'),
          createVote(7.0, 0.7, true, 'c3'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const variance = analyzer.computeConfidenceVariance(votes);

        expect(variance).toBeGreaterThan(0);
      });

      it('should throw on empty votes', () => {
        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        expect(() => analyzer.computeConfidenceVariance([])).toThrow('Cannot compute confidence variance');
      });
    });

    describe('getVoteSummary', () => {
      it('should provide comprehensive summary', () => {
        const votes = [
          createVote(8.0, 0.9, true, 'c1'),
          createVote(7.5, 0.8, true, 'c2'),
          createVote(7.8, 0.85, true, 'c3'),
        ];

        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        const summary = analyzer.getVoteSummary(votes);

        expect(summary).toHaveProperty('entropy');
        expect(summary).toHaveProperty('consensus');
        expect(summary).toHaveProperty('polarization');
        expect(summary).toHaveProperty('confidenceVariance');
        expect(summary).toHaveProperty('passRate');

        expect(summary.passRate).toBe(1.0); // All passed
        expect(summary.consensus).toBe(true);
        expect(summary.polarization).toBe(false);
        expect(summary.entropy).toBeGreaterThanOrEqual(0);
        expect(summary.confidenceVariance).toBeGreaterThanOrEqual(0);
      });

      it('should throw on empty votes', () => {
        const analyzer = new VotingAnalyzer(new SimpleAverageAggregator());
        expect(() => analyzer.getVoteSummary([])).toThrow('Cannot summarize empty vote list');
      });
    });
  });

  describe('Edge cases', () => {
    it('should handle extreme scores across all aggregators', () => {
      const votes = [
        createVote(0.0, 0.8, false, 'c1'),
        createVote(10.0, 0.8, true, 'c2'),
      ];

      const strategies = [
        new SimpleAverageAggregator(),
        new ConfidenceWeightedAggregator(),
        new MajorityVoteAggregator(),
        new BordaCountAggregator(),
      ];

      for (const strategy of strategies) {
        const result = strategy.aggregate(votes);
        expect(result.minScore).toBe(0.0);
        expect(result.maxScore).toBe(10.0);
        expect(result.voteCount).toBe(2);
        expect(result.weightedMean).toBeGreaterThanOrEqual(0.0);
        expect(result.weightedMean).toBeLessThanOrEqual(10.0);
      }
    });

    it('should handle many votes', () => {
      const votes = Array.from({ length: 100 }, (_, i) => createVote(i % 10, 0.8, i % 2 === 0, `c${i}`));

      const strategies = [
        new SimpleAverageAggregator(),
        new ConfidenceWeightedAggregator(),
        new MajorityVoteAggregator(),
        new BordaCountAggregator(),
      ];

      for (const strategy of strategies) {
        const result = strategy.aggregate(votes);
        expect(result.voteCount).toBe(100);
        expect(result.weightedMean).toBeGreaterThanOrEqual(0.0);
        expect(result.weightedMean).toBeLessThanOrEqual(10.0);
      }
    });

    it('should weight confidence appropriately', () => {
      const votes = [
        createVote(9.0, 1.0, true, 'c1'),
        createVote(1.0, 0.0, true, 'c2'),
        createVote(5.0, 0.5, true, 'c3'),
      ];

      // Confidence weighted should be heavily influenced by high confidence vote
      const weightedAgg = new ConfidenceWeightedAggregator();
      const weightedResult = weightedAgg.aggregate(votes);

      // Simple average should be (9 + 1 + 5) / 3 = 5.0
      const simpleAgg = new SimpleAverageAggregator();
      const simpleResult = simpleAgg.aggregate(votes);

      expect(simpleResult.weightedMean).toBe(5.0);
      // Weighted: (9*1.0 + 1*0.0 + 5*0.5) / (1.0 + 0.0 + 0.5) = 11.5 / 1.5 = 7.67
      expect(weightedResult.weightedMean).toBeGreaterThan(7.0);
    });
  });
});
