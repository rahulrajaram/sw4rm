import { randomUUID } from 'node:crypto';
import {
  DEFAULT_BACKOFF_MULTIPLIER,
  DEFAULT_INITIAL_BACKOFF_MS,
  DEFAULT_MAX_BACKOFF_MS,
  DEFAULT_MAX_REDIRECTS,
  DEFAULT_MAX_RETRIES_ON_OVERLOADED,
  HandoffValidationError,
  type BudgetEnvelope,
  type HandoffRequest,
  type HandoffResponse,
  type SwarmDelegationPolicy,
} from '../clients/handoff.js';
import { ErrorCode } from '../internal/errorMapping.js';

export const RETRY_AFTER_JITTER_RATIO = 0.2;
export const DEFAULT_EFFECTIVE_MAX_REDIRECTS = 2;

export interface DelegateToSwarmOptions {
  sendHandoffFn: (request: HandoffRequest) => Promise<HandoffResponse> | HandoffResponse;
  fromAgent: string;
  toAgent: string;
  reason: string;
  budget: BudgetEnvelope;
  delegationPolicy?: SwarmDelegationPolicy;
  requestId?: string;
  contextSnapshot?: Uint8Array;
  capabilitiesRequired?: string[];
  priority?: number;
  timeoutMs?: number;
  nowMsFn?: () => number;
  sleepMsFn?: (milliseconds: number) => Promise<void> | void;
  randUniformFn?: (low: number, high: number) => number;
}

function defaultNowMs(): number {
  return Date.now();
}

function defaultSleepMs(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function defaultRandUniform(low: number, high: number): number {
  if (high <= low) {
    return low;
  }
  return low + Math.random() * (high - low);
}

function normalizePolicy(policy?: SwarmDelegationPolicy): SwarmDelegationPolicy {
  return {
    maxRetriesOnOverloaded:
      policy?.maxRetriesOnOverloaded ?? DEFAULT_MAX_RETRIES_ON_OVERLOADED,
    initialBackoffMs:
      policy?.initialBackoffMs !== undefined && policy.initialBackoffMs > 0
        ? policy.initialBackoffMs
        : DEFAULT_INITIAL_BACKOFF_MS,
    backoffMultiplier:
      policy?.backoffMultiplier !== undefined && policy.backoffMultiplier > 0
        ? policy.backoffMultiplier
        : DEFAULT_BACKOFF_MULTIPLIER,
    maxBackoffMs:
      policy?.maxBackoffMs !== undefined && policy.maxBackoffMs > 0
        ? policy.maxBackoffMs
        : DEFAULT_MAX_BACKOFF_MS,
    allowSpilloverRouting: policy?.allowSpilloverRouting ?? false,
    maxRedirects: policy?.maxRedirects ?? DEFAULT_MAX_REDIRECTS,
  };
}

function deadlineExhaustedResponse(requestId: string): HandoffResponse {
  return {
    requestId,
    accepted: false,
    rejectionReason: 'Delegation deadline exhausted before handoff acceptance',
    rejectionCode: ErrorCode.ACK_TIMEOUT,
  };
}

function invalidRedirectResponse(requestId: string, reason: string): HandoffResponse {
  return {
    requestId,
    accepted: false,
    rejectionReason: reason,
    rejectionCode: ErrorCode.VALIDATION_ERROR,
  };
}

function effectiveMaxRedirects(policy: SwarmDelegationPolicy): number {
  const configured = policy.maxRedirects ?? DEFAULT_MAX_REDIRECTS;
  return configured > 0 ? configured : DEFAULT_EFFECTIVE_MAX_REDIRECTS;
}

function nextRetryWaitMs(
  response: HandoffResponse,
  retryIndex: number,
  policy: SwarmDelegationPolicy,
  randUniformFn: (low: number, high: number) => number
): number {
  if (response.retryAfterMs !== undefined && response.retryAfterMs > 0) {
    const retryAfter = response.retryAfterMs;
    const jitter = randUniformFn(0, retryAfter * RETRY_AFTER_JITTER_RATIO);
    return Math.floor(retryAfter + jitter);
  }

  const initialBackoffMs = policy.initialBackoffMs ?? DEFAULT_INITIAL_BACKOFF_MS;
  const backoffMultiplier = policy.backoffMultiplier ?? DEFAULT_BACKOFF_MULTIPLIER;
  const maxBackoffMs = policy.maxBackoffMs ?? DEFAULT_MAX_BACKOFF_MS;
  const exponential = initialBackoffMs * backoffMultiplier ** retryIndex;
  const bounded = Math.min(exponential, maxBackoffMs);
  return Math.floor(randUniformFn(0, bounded));
}

function deductWallTime(request: HandoffRequest, elapsedMs: number): void {
  if (request.budget?.wallTimeRemainingMs !== undefined) {
    request.budget.wallTimeRemainingMs = Math.max(
      request.budget.wallTimeRemainingMs - elapsedMs,
      0
    );
  }
}

function budgetExhausted(budget: BudgetEnvelope, nowMs: number): boolean {
  return (
    (budget.wallTimeRemainingMs !== undefined && budget.wallTimeRemainingMs <= 0) ||
    nowMs > budget.deadlineEpochMs
  );
}

export async function delegateToSwarm(
  options: DelegateToSwarmOptions
): Promise<HandoffResponse> {
  if (!options.budget.deadlineEpochMs || options.budget.deadlineEpochMs <= 0) {
    throw new HandoffValidationError(
      'budget.deadlineEpochMs is required for cross-swarm delegation'
    );
  }
  if (options.timeoutMs !== undefined && options.timeoutMs < 0) {
    throw new HandoffValidationError('timeoutMs must be >= 0');
  }

  const nowMs = options.nowMsFn ?? defaultNowMs;
  const sleepMs = options.sleepMsFn ?? defaultSleepMs;
  const randUniform = options.randUniformFn ?? defaultRandUniform;
  const policy = normalizePolicy(options.delegationPolicy);

  const requestBudget: BudgetEnvelope = { ...options.budget };
  const request: HandoffRequest = {
    requestId: options.requestId ?? randomUUID(),
    fromAgent: options.fromAgent,
    toAgent: options.toAgent,
    reason: options.reason,
    contextSnapshot: options.contextSnapshot ?? new Uint8Array(),
    capabilitiesRequired: [...(options.capabilitiesRequired ?? [])],
    priority: options.priority ?? 0,
    timeoutMs: options.timeoutMs,
    budget: requestBudget,
    delegationPolicy: policy,
  };

  const maxRetriesOnOverloaded =
    policy.maxRetriesOnOverloaded ?? DEFAULT_MAX_RETRIES_ON_OVERLOADED;
  let retryIndex = 0;
  let redirectHops = 0;
  const redirectBound = effectiveMaxRedirects(policy);
  const visitedAgents = new Set<string>([request.toAgent]);

  while (true) {
    const startMs = nowMs();
    if (budgetExhausted(request.budget!, startMs)) {
      return deadlineExhaustedResponse(request.requestId);
    }

    const response = await options.sendHandoffFn(request);

    const endMs = nowMs();
    const elapsedMs = Math.max(endMs - startMs, 0);
    deductWallTime(request, elapsedMs);

    if (response.accepted) {
      return response;
    }
    if (budgetExhausted(request.budget!, endMs)) {
      return deadlineExhaustedResponse(request.requestId);
    }

    if (response.rejectionCode !== ErrorCode.OVERLOADED) {
      if (response.rejectionCode !== ErrorCode.REDIRECT) {
        return response;
      }
      if (!policy.allowSpilloverRouting) {
        return response;
      }

      const targetAgent = response.redirectToAgentId?.trim();
      if (!targetAgent) {
        return invalidRedirectResponse(
          request.requestId,
          'Redirect response missing non-empty redirectToAgentId'
        );
      }
      if (visitedAgents.has(targetAgent)) {
        return invalidRedirectResponse(
          request.requestId,
          `Redirect loop detected for agent '${targetAgent}'`
        );
      }
      if (redirectHops >= redirectBound) {
        return response;
      }

      request.toAgent = targetAgent;
      visitedAgents.add(targetAgent);
      redirectHops += 1;
      continue;
    }

    if (retryIndex >= maxRetriesOnOverloaded) {
      return response;
    }

    const waitMs = nextRetryWaitMs(response, retryIndex, policy, randUniform);
    retryIndex += 1;

    const remainingDeadlineMs = request.budget!.deadlineEpochMs - endMs;
    const remainingWallTimeMs = request.budget?.wallTimeRemainingMs;
    if (
      waitMs <= 0 ||
      (remainingWallTimeMs !== undefined && waitMs > remainingWallTimeMs) ||
      waitMs > remainingDeadlineMs
    ) {
      return response;
    }

    const beforeSleepMs = nowMs();
    await sleepMs(waitMs);
    const afterSleepMs = nowMs();
    deductWallTime(request, Math.max(afterSleepMs - beforeSleepMs, 0));
  }
}
