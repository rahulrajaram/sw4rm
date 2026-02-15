import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import {
  CancellationManager,
  delegateToSwarm,
  ErrorCode,
  type HandoffRequest,
  type HandoffResponse,
} from '../src/index.js';

type DelegationVector = {
  id: string;
  request_id: string;
  from_agent: string;
  to_agent: string;
  reason: string;
  budget: {
    deadline_epoch_ms: number;
    wall_time_remaining_ms: number;
  };
  policy: {
    allow_spillover_routing: boolean;
    max_redirects: number;
  };
  redirect_map: Record<string, string>;
  expected: {
    accepted: boolean;
    rejection_code: 'VALIDATION_ERROR' | 'REDIRECT';
    attempts: string[];
    reason_contains?: string;
    redirect_to_agent_id?: string;
  };
};

type DelegationVectorSuite = {
  vectors: DelegationVector[];
};

type CancellationVector = {
  id: string;
  children: Array<{ parent: string; child: string }>;
  request: {
    correlation_id: string;
    reason: string;
    grace_period_ms: number;
  };
  expected: {
    acknowledged: boolean;
    effective_grace_period_ms: number;
    cancelled: string[];
    grace_expiry_checks: Array<{
      correlation_id: string;
      offset_ms: number;
      expired: boolean;
    }>;
    forced_preemption_checks: Array<{
      correlation_id: string;
      offset_ms: number;
      error_code: 'ERROR_CODE_UNSPECIFIED' | 'FORCED_PREEMPTION';
    }>;
    collect_forced?: {
      active_correlations: string[];
      offset_ms: number;
      expected: string[];
    };
  };
};

type CancellationVectorSuite = {
  vectors: CancellationVector[];
};

const __dirname = dirname(fileURLToPath(import.meta.url));
const delegationVectorsPath = resolve(
  __dirname,
  '../../../tests/conformance_vectors/sw4_005_delegation_vectors.json'
);
const cancellationVectorsPath = resolve(
  __dirname,
  '../../../tests/conformance_vectors/sw4_004_cancellation_vectors.json'
);

const delegationVectorSuite: DelegationVectorSuite = JSON.parse(
  readFileSync(delegationVectorsPath, 'utf-8')
) as DelegationVectorSuite;
const cancellationVectorSuite: CancellationVectorSuite = JSON.parse(
  readFileSync(cancellationVectorsPath, 'utf-8')
) as CancellationVectorSuite;

const delegationRejectionCodeByName: Record<
  DelegationVector['expected']['rejection_code'],
  ErrorCode
> = {
  VALIDATION_ERROR: ErrorCode.VALIDATION_ERROR,
  REDIRECT: ErrorCode.REDIRECT,
};

const cancellationErrorCodeByName: Record<
  CancellationVector['expected']['forced_preemption_checks'][number]['error_code'],
  ErrorCode
> = {
  ERROR_CODE_UNSPECIFIED: ErrorCode.ERROR_CODE_UNSPECIFIED,
  FORCED_PREEMPTION: ErrorCode.FORCED_PREEMPTION,
};

describe('Shared SW4-005 gateway/delegation conformance vectors', () => {
  for (const vector of delegationVectorSuite.vectors) {
    it(`executes vector ${vector.id}`, async () => {
      const attempts: string[] = [];

      const response = await delegateToSwarm({
        sendHandoffFn: (request: HandoffRequest): HandoffResponse => {
          attempts.push(request.toAgent);
          return {
            requestId: request.requestId,
            accepted: false,
            rejectionCode: ErrorCode.REDIRECT,
            redirectToAgentId: vector.redirect_map[request.toAgent],
          };
        },
        fromAgent: vector.from_agent,
        toAgent: vector.to_agent,
        reason: vector.reason,
        requestId: vector.request_id,
        budget: {
          deadlineEpochMs: vector.budget.deadline_epoch_ms,
          wallTimeRemainingMs: vector.budget.wall_time_remaining_ms,
        },
        delegationPolicy: {
          allowSpilloverRouting: vector.policy.allow_spillover_routing,
          maxRedirects: vector.policy.max_redirects,
        },
        nowMsFn: () => vector.budget.deadline_epoch_ms - 1_000,
      });

      expect(response.accepted).toBe(vector.expected.accepted);
      expect(response.rejectionCode).toBe(
        delegationRejectionCodeByName[vector.expected.rejection_code]
      );
      expect(attempts).toEqual(vector.expected.attempts);

      if (vector.expected.reason_contains) {
        expect(response.rejectionReason?.toLowerCase()).toContain(
          vector.expected.reason_contains.toLowerCase()
        );
      }
      if (vector.expected.redirect_to_agent_id !== undefined) {
        expect(response.redirectToAgentId).toBe(vector.expected.redirect_to_agent_id);
      }
    });
  }
});

describe('Shared SW4-004 cancellation conformance vectors', () => {
  for (const vector of cancellationVectorSuite.vectors) {
    it(`executes vector ${vector.id}`, () => {
      const manager = new CancellationManager({ nowMsFn: () => 1_000 });

      for (const childLink of vector.children) {
        manager.registerChildDelegation(childLink.parent, childLink.child);
      }

      const response = manager.handleCancelDelegation({
        correlationId: vector.request.correlation_id,
        reason: vector.request.reason,
        gracePeriodMs: vector.request.grace_period_ms,
      });

      expect(response.acknowledged).toBe(vector.expected.acknowledged);

      const rootFlag = manager.cancellationFlags.get(vector.request.correlation_id);
      expect(rootFlag).toBeDefined();
      expect(rootFlag?.gracePeriodMs).toBe(vector.expected.effective_grace_period_ms);

      for (const correlationId of vector.expected.cancelled) {
        expect(manager.isCancelled(correlationId)).toBe(true);
      }

      for (const check of vector.expected.grace_expiry_checks) {
        const flag = manager.cancellationFlags.get(check.correlation_id);
        expect(flag).toBeDefined();
        const nowMs = (flag?.cancelTimeMs ?? 0) + (flag?.gracePeriodMs ?? 0) + check.offset_ms;
        expect(manager.isGraceExpired(check.correlation_id, nowMs)).toBe(check.expired);
      }

      for (const check of vector.expected.forced_preemption_checks) {
        const flag = manager.cancellationFlags.get(check.correlation_id);
        expect(flag).toBeDefined();
        const nowMs = (flag?.cancelTimeMs ?? 0) + (flag?.gracePeriodMs ?? 0) + check.offset_ms;
        expect(manager.forcedPreemptionErrorCode(check.correlation_id, nowMs)).toBe(
          cancellationErrorCodeByName[check.error_code]
        );
      }

      if (vector.expected.collect_forced) {
        const nowMs =
          (rootFlag?.cancelTimeMs ?? 0) +
          (rootFlag?.gracePeriodMs ?? 0) +
          vector.expected.collect_forced.offset_ms;
        const forced = manager.collectForcedPreemptions(
          new Set(vector.expected.collect_forced.active_correlations),
          nowMs
        );
        expect([...forced].sort()).toEqual([...vector.expected.collect_forced.expected].sort());
      }
    });
  }
});
