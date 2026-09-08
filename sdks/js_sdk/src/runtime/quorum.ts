/** Runtime-neutral quorum policy evaluation shared by negotiation workflows. */

export class MinimumVotes {
  readonly kind = 'minimum_votes' as const;
  constructor(readonly n: number) {}
}

export class MinimumFraction {
  readonly kind = 'minimum_fraction' as const;
  constructor(readonly fraction: number) {}
}

export class RequireAll {
  readonly kind = 'require_all' as const;
  constructor(readonly enabled = true) {}
}

export type QuorumRule = MinimumVotes | MinimumFraction | RequireAll;

export class EscalateHitl {
  readonly kind = 'escalate_hitl' as const;
  constructor(readonly reason: string) {}
}

export class DecidedWithAbstains<T = Record<string, unknown>> {
  readonly kind = 'decided_with_abstains' as const;
  readonly injectedVotes: readonly T[];
  constructor(injectedVotes: readonly T[] = []) {
    this.injectedVotes = [...injectedVotes];
  }
}

export class DecidedWithAvailable {
  readonly kind = 'decided_with_available' as const;
}

export type QuorumFailureAction =
  | 'fail_closed'
  | 'fail_with_abstain'
  | 'fail_with_available';

export class QuorumPolicy {
  constructor(
    readonly rule: QuorumRule,
    readonly onFailure: QuorumFailureAction,
  ) {}
}

export interface QuorumOutcome<Vote> {
  readonly met: boolean;
  readonly votesReceived: number;
  readonly votesExpected: number;
  readonly threshold: number;
  readonly action?: EscalateHitl | DecidedWithAbstains | DecidedWithAvailable;
  readonly allVotes: readonly Vote[];
}

export type QuorumVote = {
  criticId?: string;
  critic_id?: string;
  [key: string]: unknown;
};

function criticId(vote: QuorumVote): string {
  const id = vote.criticId ?? vote.critic_id;
  if (typeof id !== 'string') {
    throw new TypeError('quorum votes must contain criticId or critic_id');
  }
  return id;
}

function threshold(rule: QuorumRule, expected: number): number {
  if (rule instanceof MinimumVotes) return rule.n;
  if (rule instanceof MinimumFraction) return Math.ceil(expected * rule.fraction);
  if (rule instanceof RequireAll) return rule.enabled ? expected : 0;
  throw new TypeError(`Unknown quorum rule: ${String(rule)}`);
}

export function defaultPolicy(): QuorumPolicy {
  return new QuorumPolicy(new MinimumFraction(0.5), 'fail_closed');
}

/** Evaluate distinct requested critics without mutating votes or policy. */
export function evaluateQuorum<Vote extends QuorumVote>(
  votes: readonly Vote[],
  requestedCritics: readonly string[],
  policy: QuorumPolicy,
): QuorumOutcome<Vote> {
  const votedIds = new Set(votes.map(criticId));
  const requestedIds = new Set(requestedCritics);
  const received = [...votedIds].filter((id) => requestedIds.has(id)).length;
  const expected = requestedCritics.length;
  const required = threshold(policy.rule, expected);
  const allVotes = [...votes];
  if (received >= required) {
    return { met: true, votesReceived: received, votesExpected: expected, threshold: required, allVotes };
  }

  if (policy.onFailure === 'fail_closed') {
    return {
      met: false,
      votesReceived: received,
      votesExpected: expected,
      threshold: required,
      action: new EscalateHitl('Quorum not met — escalating to HITL'),
      allVotes,
    };
  }
  if (policy.onFailure === 'fail_with_abstain') {
    const injectedVotes = requestedCritics
      .filter((critic) => !votedIds.has(critic))
      .map((critic) => ({
        critic_id: critic,
        score: 0.0,
        confidence: 0.0,
        passed: false,
        abstain: true,
      }));
    return {
      met: false,
      votesReceived: received,
      votesExpected: expected,
      threshold: required,
      action: new DecidedWithAbstains(injectedVotes),
      allVotes: [...allVotes, ...injectedVotes] as readonly Vote[],
    };
  }
  if (policy.onFailure === 'fail_with_available') {
    return {
      met: false,
      votesReceived: received,
      votesExpected: expected,
      threshold: required,
      action: new DecidedWithAvailable(),
      allVotes,
    };
  }
  throw new TypeError(`Unknown quorum failure action: ${String(policy.onFailure)}`);
}

// Python's compatibility module calls this operation simply `evaluate`.
export const evaluate = evaluateQuorum;
export const default_policy = defaultPolicy;
