"""Token bucket rate limiter for LLM API requests.

Provides proactive rate limiting to avoid 429 errors. All LLM clients
in the process share a global singleton bucket.

Configuration via environment variables:
    LLM_RATE_LIMIT_ENABLED: "1" (default) or "0"
    LLM_RATE_LIMIT_TOKENS_PER_MIN: 250000 (default, matches Groq free tier)
    LLM_RATE_LIMIT_ADAPTIVE: "1" (default) — reduce budget on 429, recover on success
"""

import asyncio
import logging
import os
import time
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)


@dataclass
class RateLimiterConfig:
    """Configuration for the token bucket rate limiter."""

    tokens_per_minute: int = field(
        default_factory=lambda: int(os.getenv("LLM_RATE_LIMIT_TOKENS_PER_MIN", "250000"))
    )
    burst_allowance: float = 1.0
    min_tokens_per_request: int = 100
    max_wait_seconds: float = 120.0
    enabled: bool = field(
        default_factory=lambda: os.getenv("LLM_RATE_LIMIT_ENABLED", "1").lower()
        not in ("0", "false", "no")
    )
    adaptive_enabled: bool = field(
        default_factory=lambda: os.getenv("LLM_RATE_LIMIT_ADAPTIVE", "1").lower()
        not in ("0", "false", "no")
    )
    reduction_factor: float = field(
        default_factory=lambda: float(os.getenv("LLM_RATE_LIMIT_REDUCTION_FACTOR", "0.7"))
    )
    recovery_factor: float = field(
        default_factory=lambda: float(os.getenv("LLM_RATE_LIMIT_RECOVERY_FACTOR", "1.1"))
    )
    cooldown_seconds: float = field(
        default_factory=lambda: float(os.getenv("LLM_RATE_LIMIT_COOLDOWN_SECONDS", "30"))
    )
    successes_for_recovery: int = field(
        default_factory=lambda: int(os.getenv("LLM_RATE_LIMIT_RECOVERY_SUCCESS_THRESHOLD", "20"))
    )


class TokenBucket:
    """Token bucket rate limiter with adaptive throttling.

    Refills tokens at a steady rate. When a 429 is reported via
    record_rate_limit(), the budget is reduced. After enough successes
    and a cooldown period, the budget recovers.
    """

    def __init__(self, config: Optional[RateLimiterConfig] = None):
        self.config = config or RateLimiterConfig()
        self._base_tpm = float(self.config.tokens_per_minute)
        self._current_tpm = float(self.config.tokens_per_minute)
        self._min_tpm = max(1000.0, self._base_tpm * 0.25)
        self._tokens = self._current_tpm  # start full
        self._last_refill = time.monotonic()
        self._lock = asyncio.Lock()
        self._last_rate_limit_time: Optional[float] = None
        self._successes_since_limit = 0

    def _refill(self) -> None:
        now = time.monotonic()
        elapsed = now - self._last_refill
        refill = elapsed * (self._current_tpm / 60.0)
        self._tokens = min(
            self._tokens + refill,
            self._current_tpm * self.config.burst_allowance,
        )
        self._last_refill = now
        self._maybe_recover(now)

    def _maybe_recover(self, now: float) -> None:
        if not self.config.adaptive_enabled:
            return
        if self._current_tpm >= self._base_tpm:
            return
        if self._last_rate_limit_time is None:
            return
        if (now - self._last_rate_limit_time) < self.config.cooldown_seconds:
            return
        if self._successes_since_limit < self.config.successes_for_recovery:
            return
        new_limit = min(self._base_tpm, self._current_tpm * self.config.recovery_factor)
        if new_limit > self._current_tpm:
            self._current_tpm = new_limit
            self._successes_since_limit = 0
            logger.info("Rate limiter recovered to %.0f tokens/min", self._current_tpm)

    async def acquire(self, estimated_tokens: int) -> float:
        """Acquire tokens, waiting if necessary.

        Returns time spent waiting (0.0 if immediate).
        """
        if not self.config.enabled:
            return 0.0

        estimated_tokens = max(estimated_tokens, self.config.min_tokens_per_request)
        wait_start = time.monotonic()

        while True:
            async with self._lock:
                self._refill()
                if self._tokens >= estimated_tokens:
                    self._tokens -= estimated_tokens
                    return time.monotonic() - wait_start

            elapsed = time.monotonic() - wait_start
            if elapsed >= self.config.max_wait_seconds:
                raise asyncio.TimeoutError(
                    f"Rate limiter: waited {elapsed:.1f}s for {estimated_tokens} tokens"
                )
            await asyncio.sleep(0.25)

    async def record_rate_limit(self) -> None:
        """Record a 429 event — adaptively reduce budget."""
        if not (self.config.enabled and self.config.adaptive_enabled):
            return
        async with self._lock:
            self._last_rate_limit_time = time.monotonic()
            self._successes_since_limit = 0
            new_limit = max(self._min_tpm, self._current_tpm * self.config.reduction_factor)
            if new_limit < self._current_tpm:
                self._current_tpm = new_limit
                self._tokens = min(self._tokens, self._current_tpm)
                logger.warning("Rate limiter reduced to %.0f tokens/min", self._current_tpm)

    async def record_success(self) -> None:
        """Record a successful request for adaptive recovery."""
        if not (self.config.enabled and self.config.adaptive_enabled):
            return
        async with self._lock:
            self._successes_since_limit += 1

    @property
    def available_tokens(self) -> float:
        return self._tokens

    @property
    def current_tokens_per_minute(self) -> float:
        return self._current_tpm


# Global singleton
_global_bucket: Optional[TokenBucket] = None


def get_global_rate_limiter(config: Optional[RateLimiterConfig] = None) -> TokenBucket:
    """Get or create the global rate limiter singleton."""
    global _global_bucket
    if _global_bucket is None:
        _global_bucket = TokenBucket(config)
    return _global_bucket


def reset_global_rate_limiter() -> None:
    """Reset the global rate limiter (for testing)."""
    global _global_bucket
    _global_bucket = None
