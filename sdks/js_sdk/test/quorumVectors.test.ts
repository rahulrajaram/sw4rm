import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  MinimumFraction,
  MinimumVotes,
  QuorumPolicy,
  RequireAll,
  evaluateQuorum,
} from '../src/runtime/quorum.js';

type Vector = {
  id: string;
  requested: string[];
  votes: Array<{ critic_id: string }>;
  rule: { kind: 'minimum_votes' | 'minimum_fraction' | 'require_all'; value: number | boolean };
  on_failure: 'fail_closed' | 'fail_with_abstain' | 'fail_with_available';
  expected: {
    met: boolean;
    received: number;
    expected: number;
    threshold: number;
    action: string;
    injected: string[];
    all_vote_count: number;
  };
};

const vectorPath = resolve(
  dirname(fileURLToPath(import.meta.url)),
  '../../../tests/conformance_vectors/quorum_vectors.json',
);
const vectors = (JSON.parse(readFileSync(vectorPath, 'utf8')) as { vectors: Vector[] }).vectors;

function rule(value: Vector['rule']): MinimumVotes | MinimumFraction | RequireAll {
  if (value.kind === 'minimum_votes') return new MinimumVotes(value.value as number);
  if (value.kind === 'minimum_fraction') return new MinimumFraction(value.value as number);
  return new RequireAll(value.value as boolean);
}

describe('shared quorum conformance vectors', () => {
  for (const vector of vectors) {
    it(`executes ${vector.id}`, () => {
      const outcome = evaluateQuorum(
        vector.votes,
        vector.requested,
        new QuorumPolicy(rule(vector.rule), vector.on_failure),
      );
      expect(outcome.met).toBe(vector.expected.met);
      expect(outcome.votesReceived).toBe(vector.expected.received);
      expect(outcome.votesExpected).toBe(vector.expected.expected);
      expect(outcome.threshold).toBe(vector.expected.threshold);
      expect(outcome.action?.kind ?? 'none').toBe(vector.expected.action);
      expect(outcome.allVotes).toHaveLength(vector.expected.all_vote_count);
      if (vector.expected.injected.length) {
        const injected = (outcome.action as { injectedVotes: ReadonlyArray<{ critic_id: string }> }).injectedVotes;
        expect(injected.map((vote) => vote.critic_id)).toEqual(vector.expected.injected);
      }
    });
  }
});
