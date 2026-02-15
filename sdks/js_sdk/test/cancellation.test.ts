import { describe, expect, it } from 'vitest';
import {
  CancellationManager,
  ErrorCode,
  MIN_GRACE_PERIOD_MS,
} from '../src/index.js';

describe('CancellationManager', () => {
  it('acknowledges cancellation with minimum grace and normalized metadata', () => {
    const clock = { nowMs: 1_000 };
    const manager = new CancellationManager({ nowMsFn: () => clock.nowMs });

    const response = manager.handleCancelDelegation({
      correlationId: ' corr-1 ',
      reason: ' stop ',
      gracePeriodMs: 0,
      metadata: {
        ' trace_id ': ' abc ',
        retries: 2,
        cancellable: true,
        nested: { stage: 'handoff' },
        skipped: undefined,
        invalid: Number.POSITIVE_INFINITY,
      },
    });

    expect(response.acknowledged).toBe(true);
    expect(response.correlationId).toBe('corr-1');
    expect(response.gracePeriodMs).toBe(MIN_GRACE_PERIOD_MS);
    expect(response.metadata).toEqual({
      trace_id: 'abc',
      retries: 2,
      cancellable: true,
      nested: '{"stage":"handoff"}',
      reason: 'stop',
      grace_period_ms: MIN_GRACE_PERIOD_MS,
    });

    expect(manager.isCancelled('corr-1')).toBe(true);
    const flag = manager.cancellationFlags.get('corr-1');
    expect(flag).toBeDefined();
    expect(flag?.cancelTimeMs).toBe(1_000);
    expect(flag?.gracePeriodMs).toBe(MIN_GRACE_PERIOD_MS);
    expect(flag?.metadata.reason).toBe('stop');
  });

  it('cascades cancellation to registered child correlations', () => {
    const clock = { nowMs: 42_000 };
    const manager = new CancellationManager({ nowMsFn: () => clock.nowMs });
    manager.registerChildDelegation('parent-corr', 'child-a');
    manager.registerChildDelegation('parent-corr', 'child-b');

    manager.handleCancelDelegation({
      correlationId: 'parent-corr',
      reason: 'abort',
      gracePeriodMs: 10_000,
    });

    expect(manager.isCancelled('parent-corr')).toBe(true);
    expect(manager.isCancelled('child-a')).toBe(true);
    expect(manager.isCancelled('child-b')).toBe(true);
    expect(manager.cancellationFlags.get('child-a')?.gracePeriodMs).toBe(10_000);
    expect(manager.cancellationFlags.get('child-b')?.cancelTimeMs).toBe(42_000);
  });

  it('evaluates grace expiry using optional now override', () => {
    const manager = new CancellationManager({ nowMsFn: () => 5_000 });
    manager.handleCancelDelegation({
      correlationId: 'corr-grace',
      reason: 'stop',
      gracePeriodMs: 6_000,
    });

    expect(manager.isGraceExpired('corr-grace', 10_999)).toBe(false);
    expect(manager.isGraceExpired('corr-grace', 11_000)).toBe(true);
  });

  it('returns FORCED_PREEMPTION only after grace expiry', () => {
    const manager = new CancellationManager({ nowMsFn: () => 1_000 });
    manager.handleCancelDelegation({
      correlationId: 'corr-preempt',
      reason: 'stop',
      gracePeriodMs: 5_000,
    });

    expect(manager.forcedPreemptionErrorCode('corr-preempt', 5_999)).toBe(
      ErrorCode.ERROR_CODE_UNSPECIFIED
    );
    expect(manager.forcedPreemptionErrorCode('corr-preempt', 6_000)).toBe(
      ErrorCode.FORCED_PREEMPTION
    );
  });

  it('collects only correlations whose grace period has expired', () => {
    const clock = { nowMs: 10_000 };
    const manager = new CancellationManager({ nowMsFn: () => clock.nowMs });

    manager.handleCancelDelegation({
      correlationId: 'expired-corr',
      reason: 'stop',
      gracePeriodMs: 5_000,
    });

    clock.nowMs = 13_000;
    manager.handleCancelDelegation({
      correlationId: 'within-grace',
      reason: 'stop',
      gracePeriodMs: 8_000,
    });

    const forced = manager.collectForcedPreemptions(
      new Set(['expired-corr', 'within-grace', 'not-cancelled']),
      16_000
    );

    expect(forced).toEqual(new Set(['expired-corr']));
  });
});
