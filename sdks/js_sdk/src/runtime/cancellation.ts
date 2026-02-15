import { ErrorCode } from '../internal/errorMapping.js';

export const MIN_GRACE_PERIOD_MS = 5000;

export type CancellationMetadataValue = string | number | boolean | null;
export type CancellationMetadata = Record<string, CancellationMetadataValue>;

export interface CancelDelegationRequest {
  correlationId: string;
  reason?: string;
  gracePeriodMs?: number;
  metadata?: Record<string, unknown>;
}

export interface CancelDelegationResponse {
  acknowledged: boolean;
  correlationId: string;
  gracePeriodMs: number;
  message: string;
  metadata: CancellationMetadata;
}

export interface CancellationFlag {
  cancelled: boolean;
  gracePeriodMs: number;
  cancelTimeMs: number;
  metadata: CancellationMetadata;
}

export interface CancellationManagerOptions {
  nowMsFn?: () => number;
}

export class CancellationValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'CancellationValidationError';
  }
}

function defaultNowMs(): number {
  return Date.now();
}

function normalizeCorrelationId(correlationId: string): string {
  const normalized = correlationId.trim();
  if (!normalized) {
    throw new CancellationValidationError(
      'cancel.correlationId is required and must be a non-empty string'
    );
  }
  return normalized;
}

function normalizeReason(reason?: string): string {
  if (reason === undefined) {
    return '';
  }
  return reason.trim();
}

function normalizeGracePeriodMs(gracePeriodMs?: number): number {
  const requested =
    gracePeriodMs !== undefined && Number.isFinite(gracePeriodMs) && gracePeriodMs > 0
      ? Math.floor(gracePeriodMs)
      : 0;
  return Math.max(requested, MIN_GRACE_PERIOD_MS);
}

function normalizeMetadataValue(
  value: unknown
): CancellationMetadataValue | undefined {
  if (value === null) {
    return null;
  }
  if (typeof value === 'string') {
    return value.trim();
  }
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : undefined;
  }
  if (typeof value === 'boolean') {
    return value;
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (typeof value === 'bigint') {
    return value.toString();
  }
  if (typeof value === 'object') {
    try {
      return JSON.stringify(value);
    } catch {
      return undefined;
    }
  }
  return undefined;
}

function normalizeMetadata(
  metadata: Record<string, unknown> | undefined,
  options: { reason: string; gracePeriodMs: number }
): CancellationMetadata {
  const { reason, gracePeriodMs } = options;
  const normalized: CancellationMetadata = {};
  if (metadata !== undefined) {
    for (const [rawKey, rawValue] of Object.entries(metadata)) {
      const key = rawKey.trim();
      if (!key) {
        continue;
      }
      const value = normalizeMetadataValue(rawValue);
      if (value !== undefined) {
        normalized[key] = value;
      }
    }
  }
  normalized.reason = reason;
  normalized.grace_period_ms = gracePeriodMs;
  return normalized;
}

function cloneMetadata(metadata: CancellationMetadata): CancellationMetadata {
  return { ...metadata };
}

function cloneFlag(flag: CancellationFlag): CancellationFlag {
  return {
    cancelled: flag.cancelled,
    gracePeriodMs: flag.gracePeriodMs,
    cancelTimeMs: flag.cancelTimeMs,
    metadata: cloneMetadata(flag.metadata),
  };
}

export class CancellationManager {
  readonly childDelegations: Map<string, Set<string>> = new Map();
  readonly cancellationFlags: Map<string, CancellationFlag> = new Map();
  private readonly nowMs: () => number;

  constructor(options: CancellationManagerOptions = {}) {
    this.nowMs = options.nowMsFn ?? defaultNowMs;
  }

  registerChildDelegation(
    parentCorrelationId: string,
    childCorrelationId: string
  ): void {
    const parent = normalizeCorrelationId(parentCorrelationId);
    const child = normalizeCorrelationId(childCorrelationId);

    if (!this.childDelegations.has(parent)) {
      this.childDelegations.set(parent, new Set());
    }
    this.childDelegations.get(parent)!.add(child);
  }

  handleCancelDelegation(
    cancel: CancelDelegationRequest
  ): CancelDelegationResponse {
    const correlationId = normalizeCorrelationId(cancel.correlationId);
    const gracePeriodMs = normalizeGracePeriodMs(cancel.gracePeriodMs);
    const reason = normalizeReason(cancel.reason);
    const cancelTimeMs = this.nowMs();
    const metadata = normalizeMetadata(cancel.metadata, {
      reason,
      gracePeriodMs,
    });

    const flag: CancellationFlag = {
      cancelled: true,
      gracePeriodMs,
      cancelTimeMs,
      metadata,
    };

    this.cancellationFlags.set(correlationId, cloneFlag(flag));
    for (const childCorrelationId of this.childDelegations.get(correlationId) ?? []) {
      this.cancellationFlags.set(childCorrelationId, cloneFlag(flag));
    }

    return {
      acknowledged: true,
      correlationId,
      gracePeriodMs,
      message: 'Cancellation recorded',
      metadata: cloneMetadata(metadata),
    };
  }

  isCancelled(correlationId: string): boolean {
    const normalized = correlationId.trim();
    if (!normalized) {
      return false;
    }
    const entry = this.cancellationFlags.get(normalized);
    return Boolean(entry?.cancelled);
  }

  isGraceExpired(correlationId: string, nowMs?: number): boolean {
    const normalized = correlationId.trim();
    if (!normalized) {
      return false;
    }
    const entry = this.cancellationFlags.get(normalized);
    if (entry === undefined || !entry.cancelled) {
      return false;
    }
    const currentMs = nowMs ?? this.nowMs();
    return currentMs - entry.cancelTimeMs >= entry.gracePeriodMs;
  }

  forcedPreemptionErrorCode(correlationId: string, nowMs?: number): ErrorCode {
    if (this.isGraceExpired(correlationId, nowMs)) {
      return ErrorCode.FORCED_PREEMPTION;
    }
    return ErrorCode.ERROR_CODE_UNSPECIFIED;
  }

  collectForcedPreemptions(
    correlationIds: Iterable<string>,
    nowMs?: number
  ): Set<string> {
    const currentMs = nowMs ?? this.nowMs();
    const forced = new Set<string>();
    for (const correlationId of correlationIds) {
      if (this.isGraceExpired(correlationId, currentMs)) {
        forced.add(correlationId);
      }
    }
    return forced;
  }
}
