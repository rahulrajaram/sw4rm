/**
 * Token bucket rate limiter for LLM API requests.
 *
 * Provides proactive rate limiting to avoid 429 errors. All LLM clients
 * in the process share a global singleton bucket.
 *
 * Configuration via environment variables:
 *   LLM_RATE_LIMIT_ENABLED:          "1" (default) or "0"
 *   LLM_RATE_LIMIT_TOKENS_PER_MIN:   250000 (default, matches Groq free tier)
 *   LLM_RATE_LIMIT_ADAPTIVE:         "1" (default) -- reduce budget on 429, recover on success
 *   LLM_RATE_LIMIT_REDUCTION_FACTOR: 0.7
 *   LLM_RATE_LIMIT_RECOVERY_FACTOR:  1.1
 *   LLM_RATE_LIMIT_COOLDOWN_SECONDS: 30
 *   LLM_RATE_LIMIT_RECOVERY_SUCCESS_THRESHOLD: 20
 *
 * @module llm/rateLimiter
 */

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/** Configuration for the token bucket rate limiter. */
export interface RateLimiterConfig {
  /** Token budget per minute. */
  tokensPerMinute: number;
  /** Burst allowance multiplier (1.0 = no burst above budget). */
  burstAllowance: number;
  /** Minimum tokens assumed per request. */
  minTokensPerRequest: number;
  /** Maximum seconds to wait before throwing a timeout. */
  maxWaitSeconds: number;
  /** Whether the rate limiter is enabled at all. */
  enabled: boolean;
  /** Whether adaptive throttling is enabled. */
  adaptiveEnabled: boolean;
  /** Factor to multiply budget by after a 429 event. */
  reductionFactor: number;
  /** Factor to multiply budget by during recovery. */
  recoveryFactor: number;
  /** Seconds to wait after last 429 before allowing recovery. */
  cooldownSeconds: number;
  /** Number of consecutive successes required before recovery. */
  successesForRecovery: number;
}

/** Parse an env var as a boolean, treating "0", "false", "no" as false. */
function envBool(name: string, defaultVal: string): boolean {
  const raw = (process.env[name] ?? defaultVal).toLowerCase();
  return !['0', 'false', 'no'].includes(raw);
}

/** Build a RateLimiterConfig from environment variables and optional overrides. */
export function buildRateLimiterConfig(
  overrides?: Partial<RateLimiterConfig>,
): RateLimiterConfig {
  return {
    tokensPerMinute:
      overrides?.tokensPerMinute ??
      parseInt(process.env['LLM_RATE_LIMIT_TOKENS_PER_MIN'] ?? '250000', 10),
    burstAllowance: overrides?.burstAllowance ?? 1.0,
    minTokensPerRequest: overrides?.minTokensPerRequest ?? 100,
    maxWaitSeconds: overrides?.maxWaitSeconds ?? 120.0,
    enabled: overrides?.enabled ?? envBool('LLM_RATE_LIMIT_ENABLED', '1'),
    adaptiveEnabled:
      overrides?.adaptiveEnabled ??
      envBool('LLM_RATE_LIMIT_ADAPTIVE', '1'),
    reductionFactor:
      overrides?.reductionFactor ??
      parseFloat(process.env['LLM_RATE_LIMIT_REDUCTION_FACTOR'] ?? '0.7'),
    recoveryFactor:
      overrides?.recoveryFactor ??
      parseFloat(process.env['LLM_RATE_LIMIT_RECOVERY_FACTOR'] ?? '1.1'),
    cooldownSeconds:
      overrides?.cooldownSeconds ??
      parseFloat(process.env['LLM_RATE_LIMIT_COOLDOWN_SECONDS'] ?? '30'),
    successesForRecovery:
      overrides?.successesForRecovery ??
      parseInt(
        process.env['LLM_RATE_LIMIT_RECOVERY_SUCCESS_THRESHOLD'] ?? '20',
        10,
      ),
  };
}

// ---------------------------------------------------------------------------
// TokenBucket
// ---------------------------------------------------------------------------

/**
 * Token bucket rate limiter with adaptive throttling.
 *
 * Refills tokens at a steady rate. When a 429 is reported via
 * {@link recordRateLimit}, the budget is reduced. After enough successes
 * and a cooldown period, the budget recovers.
 */
export class TokenBucket {
  private readonly config: RateLimiterConfig;
  private readonly baseTpm: number;
  private currentTpm: number;
  private readonly minTpm: number;
  private tokens: number;
  private lastRefill: number;
  private lastRateLimitTime: number | null = null;
  private successesSinceLimit = 0;

  constructor(config?: Partial<RateLimiterConfig>) {
    this.config = buildRateLimiterConfig(config);
    this.baseTpm = this.config.tokensPerMinute;
    this.currentTpm = this.config.tokensPerMinute;
    this.minTpm = Math.max(1000, this.baseTpm * 0.25);
    this.tokens = this.currentTpm; // start full
    this.lastRefill = performance.now();
  }

  // -- Internal helpers ----------------------------------------------------

  private refill(): void {
    const now = performance.now();
    const elapsedSeconds = (now - this.lastRefill) / 1000;
    const refill = elapsedSeconds * (this.currentTpm / 60);
    this.tokens = Math.min(
      this.tokens + refill,
      this.currentTpm * this.config.burstAllowance,
    );
    this.lastRefill = now;
    this.maybeRecover(now);
  }

  private maybeRecover(now: number): void {
    if (!this.config.adaptiveEnabled) return;
    if (this.currentTpm >= this.baseTpm) return;
    if (this.lastRateLimitTime === null) return;
    if ((now - this.lastRateLimitTime) / 1000 < this.config.cooldownSeconds) return;
    if (this.successesSinceLimit < this.config.successesForRecovery) return;

    const newLimit = Math.min(
      this.baseTpm,
      this.currentTpm * this.config.recoveryFactor,
    );
    if (newLimit > this.currentTpm) {
      this.currentTpm = newLimit;
      this.successesSinceLimit = 0;
    }
  }

  // -- Public API ----------------------------------------------------------

  /**
   * Acquire tokens, waiting if necessary.
   *
   * @param estimatedTokens - Estimated token count for the request.
   * @returns Time spent waiting in milliseconds (0 if immediate).
   * @throws Error if waiting exceeds {@link RateLimiterConfig.maxWaitSeconds}.
   */
  async acquire(estimatedTokens: number): Promise<number> {
    if (!this.config.enabled) return 0;

    estimatedTokens = Math.max(estimatedTokens, this.config.minTokensPerRequest);
    const waitStart = performance.now();

    for (;;) {
      this.refill();
      if (this.tokens >= estimatedTokens) {
        this.tokens -= estimatedTokens;
        return performance.now() - waitStart;
      }

      const elapsed = (performance.now() - waitStart) / 1000;
      if (elapsed >= this.config.maxWaitSeconds) {
        throw new Error(
          `Rate limiter: waited ${elapsed.toFixed(1)}s for ${estimatedTokens} tokens`,
        );
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  }

  /**
   * Record a 429 event -- adaptively reduce budget.
   *
   * Call this when the upstream API returns HTTP 429 or an equivalent
   * rate-limit error.
   */
  recordRateLimit(): void {
    if (!(this.config.enabled && this.config.adaptiveEnabled)) return;

    this.lastRateLimitTime = performance.now();
    this.successesSinceLimit = 0;
    const newLimit = Math.max(
      this.minTpm,
      this.currentTpm * this.config.reductionFactor,
    );
    if (newLimit < this.currentTpm) {
      this.currentTpm = newLimit;
      this.tokens = Math.min(this.tokens, this.currentTpm);
    }
  }

  /**
   * Record a successful request for adaptive recovery.
   *
   * Call this after each successful API response.
   */
  recordSuccess(): void {
    if (!(this.config.enabled && this.config.adaptiveEnabled)) return;
    this.successesSinceLimit += 1;
  }

  /** Current available token count. */
  get availableTokens(): number {
    return this.tokens;
  }

  /** Current tokens-per-minute budget (may be reduced after 429). */
  get currentTokensPerMinute(): number {
    return this.currentTpm;
  }
}

// ---------------------------------------------------------------------------
// Global singleton
// ---------------------------------------------------------------------------

let globalBucket: TokenBucket | null = null;

/**
 * Get or create the global rate limiter singleton.
 *
 * @param config - Optional configuration overrides (only used on first call).
 * @returns The shared TokenBucket instance.
 */
export function getGlobalRateLimiter(
  config?: Partial<RateLimiterConfig>,
): TokenBucket {
  if (globalBucket === null) {
    globalBucket = new TokenBucket(config);
  }
  return globalBucket;
}

/**
 * Reset the global rate limiter (for testing).
 *
 * Clears the singleton so the next call to {@link getGlobalRateLimiter}
 * creates a fresh instance.
 */
export function resetGlobalRateLimiter(): void {
  globalBucket = null;
}
