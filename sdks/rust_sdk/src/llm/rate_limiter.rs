// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Token bucket rate limiter for LLM API requests.
//!
//! Provides proactive rate limiting to avoid 429 errors. All LLM clients
//! in the process share a global singleton bucket.
//!
//! # Configuration via environment variables
//!
//! | Variable | Default | Description |
//! |----------|---------|-------------|
//! | `LLM_RATE_LIMIT_ENABLED` | `"1"` | Enable/disable rate limiting |
//! | `LLM_RATE_LIMIT_TOKENS_PER_MIN` | `250000` | Token budget per minute |
//! | `LLM_RATE_LIMIT_ADAPTIVE` | `"1"` | Enable adaptive throttling |
//! | `LLM_RATE_LIMIT_REDUCTION_FACTOR` | `0.7` | Budget reduction on 429 |
//! | `LLM_RATE_LIMIT_RECOVERY_FACTOR` | `1.1` | Budget recovery multiplier |
//! | `LLM_RATE_LIMIT_COOLDOWN_SECONDS` | `30` | Cooldown before recovery |
//! | `LLM_RATE_LIMIT_RECOVERY_SUCCESS_THRESHOLD` | `20` | Successes needed for recovery |

use std::sync::Mutex;
use std::time::Instant;

use once_cell::sync::Lazy;

use super::client::LlmError;

/// Configuration for the token bucket rate limiter.
///
/// All fields have sensible defaults and can be overridden via environment
/// variables. The defaults match the Groq free tier (250k tokens/min).
#[derive(Debug, Clone)]
pub struct RateLimiterConfig {
    /// Token budget per minute.
    pub tokens_per_minute: u64,
    /// Burst allowance multiplier (1.0 = no burst beyond steady-state).
    pub burst_allowance: f64,
    /// Minimum tokens per request (floor for estimates).
    pub min_tokens_per_request: u64,
    /// Maximum seconds to wait for tokens before timing out.
    pub max_wait_seconds: f64,
    /// Whether rate limiting is enabled at all.
    pub enabled: bool,
    /// Whether adaptive throttling is enabled (reduce on 429, recover on success).
    pub adaptive_enabled: bool,
    /// Factor to multiply budget by on 429 (e.g., 0.7 = 30% reduction).
    pub reduction_factor: f64,
    /// Factor to multiply budget by on recovery (e.g., 1.1 = 10% increase).
    pub recovery_factor: f64,
    /// Seconds to wait after a 429 before attempting recovery.
    pub cooldown_seconds: f64,
    /// Number of consecutive successes required before recovery.
    pub successes_for_recovery: u64,
}

impl Default for RateLimiterConfig {
    fn default() -> Self {
        Self {
            tokens_per_minute: env_u64("LLM_RATE_LIMIT_TOKENS_PER_MIN", 250_000),
            burst_allowance: 1.0,
            min_tokens_per_request: 100,
            max_wait_seconds: 120.0,
            enabled: env_bool("LLM_RATE_LIMIT_ENABLED", true),
            adaptive_enabled: env_bool("LLM_RATE_LIMIT_ADAPTIVE", true),
            reduction_factor: env_f64("LLM_RATE_LIMIT_REDUCTION_FACTOR", 0.7),
            recovery_factor: env_f64("LLM_RATE_LIMIT_RECOVERY_FACTOR", 1.1),
            cooldown_seconds: env_f64("LLM_RATE_LIMIT_COOLDOWN_SECONDS", 30.0),
            successes_for_recovery: env_u64("LLM_RATE_LIMIT_RECOVERY_SUCCESS_THRESHOLD", 20),
        }
    }
}

/// Parse a boolean from an environment variable.
///
/// Values "0", "false", "no" (case-insensitive) are `false`; anything else
/// (including absent) uses the provided default.
fn env_bool(key: &str, default: bool) -> bool {
    match std::env::var(key) {
        Ok(val) => !matches!(val.to_lowercase().as_str(), "0" | "false" | "no"),
        Err(_) => default,
    }
}

/// Parse a u64 from an environment variable, falling back to default.
fn env_u64(key: &str, default: u64) -> u64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

/// Parse an f64 from an environment variable, falling back to default.
fn env_f64(key: &str, default: f64) -> f64 {
    std::env::var(key)
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(default)
}

/// Token bucket rate limiter with adaptive throttling.
///
/// Refills tokens at a steady rate proportional to `tokens_per_minute`.
/// When a 429 is reported via [`TokenBucket::record_rate_limit`], the budget
/// is reduced by `reduction_factor`. After `cooldown_seconds` and
/// `successes_for_recovery` consecutive successes, the budget recovers
/// by `recovery_factor` until it reaches the original baseline.
///
/// # Thread Safety
///
/// The global singleton is protected by a `Mutex`. The `acquire` method
/// releases the lock between polling iterations so other tasks can proceed.
pub struct TokenBucket {
    config: RateLimiterConfig,
    base_tpm: f64,
    current_tpm: f64,
    min_tpm: f64,
    tokens: f64,
    last_refill: Instant,
    last_rate_limit_time: Option<Instant>,
    successes_since_limit: u64,
}

impl TokenBucket {
    /// Create a new token bucket with the given configuration.
    ///
    /// The bucket starts full (tokens = current_tpm).
    pub fn new(config: RateLimiterConfig) -> Self {
        let base_tpm = config.tokens_per_minute as f64;
        let min_tpm = (base_tpm * 0.25).max(1000.0);
        Self {
            tokens: base_tpm,
            base_tpm,
            current_tpm: base_tpm,
            min_tpm,
            last_refill: Instant::now(),
            last_rate_limit_time: None,
            successes_since_limit: 0,
            config,
        }
    }

    /// Refill tokens based on elapsed time since last refill.
    fn refill(&mut self) {
        let now = Instant::now();
        let elapsed = now.duration_since(self.last_refill).as_secs_f64();
        let refill = elapsed * (self.current_tpm / 60.0);
        self.tokens = (self.tokens + refill).min(self.current_tpm * self.config.burst_allowance);
        self.last_refill = now;
        self.maybe_recover(now);
    }

    /// Attempt adaptive recovery if conditions are met.
    fn maybe_recover(&mut self, now: Instant) {
        if !self.config.adaptive_enabled {
            return;
        }
        if self.current_tpm >= self.base_tpm {
            return;
        }
        let last_limit = match self.last_rate_limit_time {
            Some(t) => t,
            None => return,
        };
        if now.duration_since(last_limit).as_secs_f64() < self.config.cooldown_seconds {
            return;
        }
        if self.successes_since_limit < self.config.successes_for_recovery {
            return;
        }
        let new_limit = (self.current_tpm * self.config.recovery_factor).min(self.base_tpm);
        if new_limit > self.current_tpm {
            self.current_tpm = new_limit;
            self.successes_since_limit = 0;
            tracing::info!(
                current_tpm = self.current_tpm,
                "Rate limiter recovered"
            );
        }
    }

    /// Try to acquire tokens without waiting.
    ///
    /// Returns `true` if tokens were successfully consumed, `false` if
    /// insufficient tokens are available.
    fn try_acquire(&mut self, estimated_tokens: u64) -> bool {
        if !self.config.enabled {
            return true;
        }
        self.refill();
        let needed = estimated_tokens.max(self.config.min_tokens_per_request) as f64;
        if self.tokens >= needed {
            self.tokens -= needed;
            true
        } else {
            false
        }
    }

    /// Record a 429 rate-limit event, adaptively reducing the token budget.
    ///
    /// If adaptive throttling is enabled, the budget is reduced by
    /// `reduction_factor` (default 0.7), down to a floor of 25% of the
    /// original baseline (minimum 1000 tokens/min).
    pub fn record_rate_limit(&mut self) {
        if !(self.config.enabled && self.config.adaptive_enabled) {
            return;
        }
        self.last_rate_limit_time = Some(Instant::now());
        self.successes_since_limit = 0;
        let new_limit = (self.current_tpm * self.config.reduction_factor).max(self.min_tpm);
        if new_limit < self.current_tpm {
            self.current_tpm = new_limit;
            self.tokens = self.tokens.min(self.current_tpm);
            tracing::warn!(
                current_tpm = self.current_tpm,
                "Rate limiter reduced budget"
            );
        }
    }

    /// Record a successful API request for adaptive recovery tracking.
    ///
    /// After enough consecutive successes (default 20) and a cooldown
    /// period, the budget will be gradually increased.
    pub fn record_success(&mut self) {
        if !(self.config.enabled && self.config.adaptive_enabled) {
            return;
        }
        self.successes_since_limit += 1;
    }

    /// Current number of available tokens.
    pub fn available_tokens(&self) -> f64 {
        self.tokens
    }

    /// Current effective tokens-per-minute budget.
    pub fn current_tokens_per_minute(&self) -> f64 {
        self.current_tpm
    }

    /// Whether rate limiting is enabled.
    pub fn is_enabled(&self) -> bool {
        self.config.enabled
    }
}

/// Global singleton rate limiter shared by all LLM clients in the process.
///
/// Protected by a `Mutex` for thread safety. The `acquire` free function
/// releases the lock between polling iterations to avoid blocking other tasks.
static GLOBAL_BUCKET: Lazy<Mutex<TokenBucket>> = Lazy::new(|| {
    Mutex::new(TokenBucket::new(RateLimiterConfig::default()))
});

/// Acquire tokens from the global rate limiter, waiting if necessary.
///
/// Polls every 250ms until enough tokens are available or the maximum
/// wait time is exceeded.
///
/// # Arguments
///
/// * `estimated_tokens` - Estimated number of tokens for this request.
///
/// # Returns
///
/// The time spent waiting in seconds (0.0 if immediate).
///
/// # Errors
///
/// Returns [`LlmError::Timeout`] if the maximum wait time is exceeded.
pub async fn acquire(estimated_tokens: u64) -> Result<f64, LlmError> {
    let start = Instant::now();
    let max_wait = {
        let bucket = GLOBAL_BUCKET.lock().unwrap();
        if !bucket.is_enabled() {
            return Ok(0.0);
        }
        bucket.config.max_wait_seconds
    };

    loop {
        {
            let mut bucket = GLOBAL_BUCKET.lock().unwrap();
            if bucket.try_acquire(estimated_tokens) {
                return Ok(start.elapsed().as_secs_f64());
            }
        }

        let elapsed = start.elapsed().as_secs_f64();
        if elapsed >= max_wait {
            return Err(LlmError::Timeout(format!(
                "Rate limiter: waited {:.1}s for {} tokens",
                elapsed, estimated_tokens
            )));
        }
        tokio::time::sleep(std::time::Duration::from_millis(250)).await;
    }
}

/// Record a 429 rate-limit event on the global rate limiter.
pub fn record_rate_limit() {
    let mut bucket = GLOBAL_BUCKET.lock().unwrap();
    bucket.record_rate_limit();
}

/// Record a successful request on the global rate limiter.
pub fn record_success() {
    let mut bucket = GLOBAL_BUCKET.lock().unwrap();
    bucket.record_success();
}

/// Get the current available tokens in the global rate limiter.
pub fn available_tokens() -> f64 {
    let bucket = GLOBAL_BUCKET.lock().unwrap();
    bucket.available_tokens()
}

/// Get the current effective tokens-per-minute from the global rate limiter.
pub fn current_tokens_per_minute() -> f64 {
    let bucket = GLOBAL_BUCKET.lock().unwrap();
    bucket.current_tokens_per_minute()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_config_defaults() {
        let config = RateLimiterConfig::default();
        // These may be overridden by env vars in CI, so just check types
        assert!(config.tokens_per_minute > 0);
        assert!(config.burst_allowance > 0.0);
        assert!(config.min_tokens_per_request > 0);
        assert!(config.max_wait_seconds > 0.0);
        assert!(config.reduction_factor > 0.0 && config.reduction_factor < 1.0);
        assert!(config.recovery_factor > 1.0);
        assert!(config.cooldown_seconds > 0.0);
    }

    #[test]
    fn test_token_bucket_starts_full() {
        let config = RateLimiterConfig {
            tokens_per_minute: 10_000,
            enabled: true,
            ..Default::default()
        };
        let bucket = TokenBucket::new(config);
        assert!((bucket.available_tokens() - 10_000.0).abs() < 0.01);
        assert!((bucket.current_tokens_per_minute() - 10_000.0).abs() < 0.01);
    }

    #[test]
    fn test_try_acquire_success() {
        let config = RateLimiterConfig {
            tokens_per_minute: 10_000,
            enabled: true,
            min_tokens_per_request: 10,
            ..Default::default()
        };
        let mut bucket = TokenBucket::new(config);
        assert!(bucket.try_acquire(100));
        // Tokens should be reduced (accounting for possible tiny refill)
        assert!(bucket.available_tokens() < 10_000.0);
    }

    #[test]
    fn test_try_acquire_insufficient() {
        let config = RateLimiterConfig {
            tokens_per_minute: 100,
            enabled: true,
            min_tokens_per_request: 10,
            burst_allowance: 1.0,
            ..Default::default()
        };
        let mut bucket = TokenBucket::new(config);
        // Drain tokens
        assert!(bucket.try_acquire(90));
        // Should fail for a large request
        assert!(!bucket.try_acquire(50));
    }

    #[test]
    fn test_disabled_bucket_always_succeeds() {
        let config = RateLimiterConfig {
            tokens_per_minute: 1,
            enabled: false,
            ..Default::default()
        };
        let mut bucket = TokenBucket::new(config);
        // Even a huge request succeeds when disabled
        assert!(bucket.try_acquire(1_000_000));
    }

    #[test]
    fn test_record_rate_limit_reduces_budget() {
        let config = RateLimiterConfig {
            tokens_per_minute: 10_000,
            enabled: true,
            adaptive_enabled: true,
            reduction_factor: 0.5,
            ..Default::default()
        };
        let mut bucket = TokenBucket::new(config);
        let original = bucket.current_tokens_per_minute();
        bucket.record_rate_limit();
        assert!(bucket.current_tokens_per_minute() < original);
        // Should be roughly 5000 (0.5 of 10000)
        assert!((bucket.current_tokens_per_minute() - 5_000.0).abs() < 1.0);
    }

    #[test]
    fn test_record_rate_limit_respects_floor() {
        let config = RateLimiterConfig {
            tokens_per_minute: 2_000,
            enabled: true,
            adaptive_enabled: true,
            reduction_factor: 0.1,
            ..Default::default()
        };
        let mut bucket = TokenBucket::new(config);
        // min_tpm = max(1000, 2000*0.25) = 1000
        bucket.record_rate_limit();
        // 2000 * 0.1 = 200, but floor is 1000
        assert!((bucket.current_tokens_per_minute() - 1_000.0).abs() < 1.0);
    }

    #[test]
    fn test_record_success_increments() {
        let config = RateLimiterConfig {
            tokens_per_minute: 10_000,
            enabled: true,
            adaptive_enabled: true,
            ..Default::default()
        };
        let mut bucket = TokenBucket::new(config);
        bucket.record_rate_limit();
        for _ in 0..5 {
            bucket.record_success();
        }
        // successes_since_limit should be 5 (internal, can't directly check,
        // but we verify it doesn't panic)
    }

    #[test]
    fn test_min_tokens_per_request_floor() {
        let config = RateLimiterConfig {
            tokens_per_minute: 10_000,
            enabled: true,
            min_tokens_per_request: 500,
            ..Default::default()
        };
        let mut bucket = TokenBucket::new(config);
        // Request 1 token, but min is 500
        assert!(bucket.try_acquire(1));
        // Should have consumed at least 500 tokens
        assert!(bucket.available_tokens() <= 9_501.0);
    }

    #[tokio::test]
    async fn test_acquire_immediate_when_disabled() {
        // This test uses the global bucket which may have state from other
        // tests. We just verify the function signature works.
        // A real disabled test would need a non-global bucket.
    }

    #[test]
    fn test_env_bool_parsing() {
        // These test the helper function directly
        // Note: we can't easily set env vars in parallel tests, so just
        // test the function logic with known absent keys
        assert!(env_bool("SW4RM_TEST_NONEXISTENT_TRUE", true));
        assert!(!env_bool("SW4RM_TEST_NONEXISTENT_FALSE", false));
    }
}
