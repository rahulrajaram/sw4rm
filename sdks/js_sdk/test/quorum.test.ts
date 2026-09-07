import { describe, expect, it } from 'vitest';
import {
  DecidedWithAbstains,
  DecidedWithAvailable,
  EscalateHitl,
  MinimumFraction,
  MinimumVotes,
  QuorumPolicy,
  RequireAll,
  defaultPolicy,
  evaluateQuorum,
} from '../src/runtime/quorum.js';

const critics = ['critic-1', 'critic-2', 'critic-3', 'critic-4'];
const vote = (criticId: string) => ({ criticId, score: 8, confidence: 0.9, passed: true });

describe('runtime-neutral quorum policy', () => {
  it('uses a majority threshold rounded up and ignores unrequested critics', () => {
    const outcome = evaluateQuorum(
      [vote('critic-1'), vote('outside')],
      critics.slice(0, 3),
      defaultPolicy(),
    );
    expect(outcome).toMatchObject({ met: false, votesReceived: 1, votesExpected: 3, threshold: 2 });
    expect(outcome.action).toBeInstanceOf(EscalateHitl);
  });

  it('supports minimum votes and require-all rules', () => {
    expect(evaluateQuorum([vote('critic-1'), vote('critic-2')], critics, new QuorumPolicy(new MinimumVotes(2), 'fail_closed')).met).toBe(true);
    expect(evaluateQuorum([vote('critic-1')], critics, new QuorumPolicy(new MinimumVotes(2), 'fail_closed')).met).toBe(false);
    expect(evaluateQuorum([], critics, new QuorumPolicy(new RequireAll(false), 'fail_closed')).met).toBe(true);
    expect(evaluateQuorum([vote('critic-1')], critics.slice(0, 3), new QuorumPolicy(new MinimumFraction(0.5), 'fail_closed')).threshold).toBe(2);
  });

  it('creates the same explicit failure actions as Python', () => {
    const abstain = evaluateQuorum([vote('critic-1'), vote('critic-2')], critics, new QuorumPolicy(new MinimumVotes(4), 'fail_with_abstain'));
    expect(abstain.action).toBeInstanceOf(DecidedWithAbstains);
    expect((abstain.action as DecidedWithAbstains).injectedVotes).toHaveLength(2);
    expect((abstain.action as DecidedWithAbstains).injectedVotes[0]).toMatchObject({ critic_id: 'critic-3', abstain: true });

    const available = evaluateQuorum([vote('critic-1')], critics, new QuorumPolicy(new MinimumVotes(4), 'fail_with_available'));
    expect(available.action).toBeInstanceOf(DecidedWithAvailable);
    expect(available.allVotes).toHaveLength(1);
  });
});
