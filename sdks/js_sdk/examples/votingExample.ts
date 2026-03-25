#!/usr/bin/env npx tsx
/**
 * Voting Aggregation Example for SW4RM Protocol.
 *
 * This example demonstrates how to use different aggregation strategies to
 * combine critic votes in a negotiation room scenario:
 * - SimpleAverageAggregator: Treats all votes equally (arithmetic mean)
 * - ConfidenceWeightedAggregator: Weights votes by critic confidence (POMDP-based)
 * - MajorityVoteAggregator: Binary pass/fail count, ignores numerical scores
 * - BordaCountAggregator: Ranked voting with position-based points
 *
 * The VotingAnalyzer wrapper also provides analytical methods for measuring
 * vote entropy, detecting consensus, detecting polarization, and computing
 * confidence variance — all useful signals for HITL escalation decisions.
 *
 * Prerequisites:
 *   - Install dependencies: `npm install`
 *
 * Run:
 *   npx tsx examples/votingExample.ts
 *
 * Execution mode:
 *   - Fully local, no gRPC or external services required. All computation
 *     is performed in-process using the SDK's voting module.
 *
 * @packageDocumentation
 */

import {
  SimpleAverageAggregator,
  ConfidenceWeightedAggregator,
  MajorityVoteAggregator,
  BordaCountAggregator,
  VotingAnalyzer,
  aggregateVotes,
  type NegotiationVote,
  type AggregatedScore,
} from '../src/index.js';

// ---------------------------------------------------------------------------
// Vote construction helpers
// ---------------------------------------------------------------------------

/**
 * Create a realistic set of votes for demonstration.
 *
 * Four critics evaluate the same artifact with varying scores and confidence
 * levels, all returning a passing verdict.
 */
function createExampleVotes(): NegotiationVote[] {
  return [
    {
      artifactId: 'artifact_123',
      criticId: 'security_critic',
      score: 8.5,
      confidence: 0.9,
      passed: true,
      strengths: ['Strong authentication', 'Good input validation'],
      weaknesses: ['Missing rate limiting'],
      recommendations: ['Add rate limiting to API endpoints'],
      negotiationRoomId: 'room_001',
    },
    {
      artifactId: 'artifact_123',
      criticId: 'performance_critic',
      score: 7.0,
      confidence: 0.75,
      passed: true,
      strengths: ['Efficient database queries'],
      weaknesses: ['No caching strategy'],
      recommendations: ['Consider adding Redis cache'],
      negotiationRoomId: 'room_001',
    },
    {
      artifactId: 'artifact_123',
      criticId: 'code_quality_critic',
      score: 6.5,
      confidence: 0.8,
      passed: true,
      strengths: ['Clean code structure', 'Good documentation'],
      weaknesses: ['Some functions are too long'],
      recommendations: ['Refactor large functions into smaller ones'],
      negotiationRoomId: 'room_001',
    },
    {
      artifactId: 'artifact_123',
      criticId: 'testing_critic',
      score: 9.0,
      confidence: 0.95,
      passed: true,
      strengths: ['Excellent test coverage', 'Good edge case handling'],
      weaknesses: [],
      recommendations: ['Add more integration tests'],
      negotiationRoomId: 'room_001',
    },
  ];
}

// ---------------------------------------------------------------------------
// Strategy formatting helper
// ---------------------------------------------------------------------------

function printResult(label: string, result: AggregatedScore): void {
  console.log(`   Mean score:   ${result.mean.toFixed(2)}`);
  console.log(`   Weighted mean: ${result.weightedMean.toFixed(2)}`);
  console.log(`   Std deviation: ${result.stdDev.toFixed(2)}`);
}

// ---------------------------------------------------------------------------
// Main demonstrations
// ---------------------------------------------------------------------------

/**
 * Demonstrate all four aggregation strategies and the analytical methods
 * provided by VotingAnalyzer.
 */
function demonstrateStrategies(): void {
  const votes = createExampleVotes();

  console.log('='.repeat(70));
  console.log('Voting Aggregation Strategies Demonstration');
  console.log('='.repeat(70));
  console.log(`\nNumber of votes: ${votes.length}`);
  console.log('\nIndividual votes:');
  for (const vote of votes) {
    const id = vote.criticId.padEnd(25);
    console.log(
      `  ${id}: score=${vote.score.toFixed(1)}, ` +
        `confidence=${vote.confidence.toFixed(2)}, passed=${vote.passed}`
    );
  }

  console.log('\n' + '='.repeat(70));
  console.log('Strategy Comparison');
  console.log('='.repeat(70));

  // 1. Simple Average
  console.log('\n1. Simple Average Strategy:');
  console.log('   Treats all votes equally');
  const simpleAnalyzer = new VotingAnalyzer(new SimpleAverageAggregator());
  const simpleResult = simpleAnalyzer.aggregate(votes);
  printResult('simple', simpleResult);

  // 2. Confidence Weighted
  console.log('\n2. Confidence-Weighted Strategy:');
  console.log('   Weights votes by critic confidence (POMDP-based)');
  const confAnalyzer = new VotingAnalyzer(new ConfidenceWeightedAggregator());
  const confResult = confAnalyzer.aggregate(votes);
  printResult('confidence-weighted', confResult);
  console.log(
    '   → Testing critic (0.95 conf, 9.0 score) has more influence'
  );

  // 3. Majority Vote
  console.log('\n3. Majority Vote Strategy:');
  console.log('   Based on pass/fail count (ignores numerical scores)');
  const majorityAnalyzer = new VotingAnalyzer(new MajorityVoteAggregator());
  const majorityResult = majorityAnalyzer.aggregate(votes);
  console.log(`   Mean score:    ${majorityResult.mean.toFixed(2)}`);
  console.log(`   Majority outcome: ${majorityResult.weightedMean.toFixed(2)}`);
  console.log('   → All critics passed, so score is 10.0');

  // 4. Borda Count
  console.log('\n4. Borda Count Strategy:');
  console.log('   Ranked voting with position-based points');
  const bordaAnalyzer = new VotingAnalyzer(new BordaCountAggregator());
  const bordaResult = bordaAnalyzer.aggregate(votes);
  console.log(`   Mean score:    ${bordaResult.mean.toFixed(2)}`);
  console.log(`   Borda score:   ${bordaResult.weightedMean.toFixed(2)}`);
  console.log(
    '   → Ranks: testing(9.0)→security(8.5)→performance(7.0)→quality(6.5)'
  );

  // Also demonstrate the standalone aggregateVotes helper
  console.log('\n   [aggregateVotes helper]');
  const quickResult = aggregateVotes(votes);
  console.log(`   Quick aggregate mean: ${quickResult.mean.toFixed(2)}`);

  // Analytical methods
  console.log('\n' + '='.repeat(70));
  console.log('Vote Analysis');
  console.log('='.repeat(70));

  console.log(
    `\nEntropy: ${confAnalyzer.computeEntropy(votes).toFixed(3)} bits`
  );
  console.log(
    '  (Low entropy = high agreement, High entropy = high disagreement)'
  );

  console.log(`\nConsensus detected: ${confAnalyzer.detectConsensus(votes)}`);
  console.log('  (Low std dev + high pass/fail agreement)');

  console.log(
    `\nPolarization detected: ${confAnalyzer.detectPolarization(votes)}`
  );
  console.log('  (Bimodal distribution with votes at extremes)');

  console.log(
    `\nConfidence variance: ${confAnalyzer.computeConfidenceVariance(votes).toFixed(4)}`
  );
  console.log("  (How much critics' confidence levels vary)");

  // Comprehensive summary
  console.log('\n' + '='.repeat(70));
  console.log('Comprehensive Summary');
  console.log('='.repeat(70));
  const summary = confAnalyzer.getVoteSummary(votes);
  console.log(`\nPass rate:            ${(summary.passRate * 100).toFixed(1)}%`);
  console.log(`Entropy:              ${summary.entropy.toFixed(3)} bits`);
  console.log(`Consensus:            ${summary.consensus ? 'Yes' : 'No'}`);
  console.log(`Polarization:         ${summary.polarization ? 'Yes' : 'No'}`);
  console.log(
    `Confidence variance:  ${summary.confidenceVariance.toFixed(4)}`
  );

  console.log('\n' + '='.repeat(70));
}

/**
 * Demonstrate polarization detection with a set of votes that cluster at
 * opposite ends of the scale (2 high, 2 low).
 *
 * This pattern is a signal for HITL escalation — human review is needed
 * when automated critics strongly disagree.
 */
function demonstratePolarization(): void {
  console.log('\n' + '='.repeat(70));
  console.log('Polarization Example');
  console.log('='.repeat(70));

  const polarizedVotes: NegotiationVote[] = [
    {
      artifactId: 'artifact_456',
      criticId: 'critic_1',
      score: 9.0,
      confidence: 0.85,
      passed: true,
      strengths: ['Excellent'],
      weaknesses: [],
      recommendations: [],
      negotiationRoomId: 'room_002',
    },
    {
      artifactId: 'artifact_456',
      criticId: 'critic_2',
      score: 8.5,
      confidence: 0.9,
      passed: true,
      strengths: ['Very good'],
      weaknesses: [],
      recommendations: [],
      negotiationRoomId: 'room_002',
    },
    {
      artifactId: 'artifact_456',
      criticId: 'critic_3',
      score: 2.0,
      confidence: 0.8,
      passed: false,
      strengths: [],
      weaknesses: ['Major issues'],
      recommendations: ['Complete rewrite'],
      negotiationRoomId: 'room_002',
    },
    {
      artifactId: 'artifact_456',
      criticId: 'critic_4',
      score: 1.5,
      confidence: 0.75,
      passed: false,
      strengths: [],
      weaknesses: ['Critical flaws'],
      recommendations: ['Start over'],
      negotiationRoomId: 'room_002',
    },
  ];

  console.log('\nPolarized votes (critics strongly disagree):');
  for (const vote of polarizedVotes) {
    console.log(
      `  ${vote.criticId}: score=${vote.score.toFixed(1)}, passed=${vote.passed}`
    );
  }

  const analyzer = new VotingAnalyzer(new ConfidenceWeightedAggregator());
  const result = analyzer.aggregate(polarizedVotes);

  console.log(`\nSimple mean:   ${result.mean.toFixed(2)}`);
  console.log(`Std deviation: ${result.stdDev.toFixed(2)} (high variance)`);
  console.log(
    `Entropy:       ${analyzer.computeEntropy(polarizedVotes).toFixed(3)} bits`
  );
  console.log(
    `Consensus:     ${analyzer.detectConsensus(polarizedVotes)}`
  );
  console.log(
    `Polarization:  ${analyzer.detectPolarization(polarizedVotes)} <- Detected!`
  );

  console.log(
    '\n-> This indicates the artifact needs human review (HITL escalation)'
  );
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

function main(): void {
  demonstrateStrategies();
  demonstratePolarization();
  console.log('\n' + '='.repeat(70));
  console.log('Example completed successfully!');
  console.log('='.repeat(70));
}

main();
