use crate::constants::error_code;
use crate::{Error, Result};
use std::collections::{HashMap, HashSet};
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use super::handoff::{
    BudgetEnvelope, HandoffRequest, HandoffResponse, HandoffStatus, SwarmDelegationPolicy,
    DEFAULT_BACKOFF_MULTIPLIER, DEFAULT_INITIAL_BACKOFF_MS, DEFAULT_MAX_BACKOFF_MS,
    REJECTION_CODE_OVERLOADED, REJECTION_CODE_REDIRECT,
};

pub const RETRY_AFTER_JITTER_RATIO: f64 = 0.2;
pub const DEFAULT_EFFECTIVE_MAX_REDIRECTS: u32 = 2;

/// Parameters for caller-side SW4-005 delegation processing.
#[derive(Debug, Clone)]
pub struct DelegateToSwarmOptions {
    pub from_agent: String,
    pub to_agent: String,
    pub reason: String,
    pub budget: BudgetEnvelope,
    pub delegation_policy: Option<SwarmDelegationPolicy>,
    pub request_id: Option<String>,
    pub context_snapshot: Option<Vec<u8>>,
    pub capabilities_required: Vec<String>,
    pub priority: i32,
    pub timeout: Option<Duration>,
}

impl DelegateToSwarmOptions {
    pub fn new(
        from_agent: String,
        to_agent: String,
        reason: String,
        budget: BudgetEnvelope,
    ) -> Self {
        Self {
            from_agent,
            to_agent,
            reason,
            budget,
            delegation_policy: None,
            request_id: None,
            context_snapshot: None,
            capabilities_required: Vec::new(),
            priority: 0,
            timeout: None,
        }
    }

    pub fn with_delegation_policy(mut self, policy: SwarmDelegationPolicy) -> Self {
        self.delegation_policy = Some(policy);
        self
    }

    pub fn with_request_id(mut self, request_id: String) -> Self {
        self.request_id = Some(request_id);
        self
    }

    pub fn with_context_snapshot(mut self, context_snapshot: Vec<u8>) -> Self {
        self.context_snapshot = Some(context_snapshot);
        self
    }

    pub fn with_capabilities_required(mut self, capabilities_required: Vec<String>) -> Self {
        self.capabilities_required = capabilities_required;
        self
    }

    pub fn with_priority(mut self, priority: i32) -> Self {
        self.priority = priority;
        self
    }

    pub fn with_timeout(mut self, timeout: Duration) -> Self {
        self.timeout = Some(timeout);
        self
    }
}

pub fn delegate_to_swarm<SendFn>(
    options: DelegateToSwarmOptions,
    send_handoff_fn: SendFn,
) -> Result<HandoffResponse>
where
    SendFn: FnMut(&HandoffRequest) -> Result<HandoffResponse>,
{
    delegate_to_swarm_with_runtime(
        options,
        send_handoff_fn,
        default_now_ms,
        default_sleep_ms,
        default_rand_uniform,
    )
}

pub fn delegate_to_swarm_with_runtime<SendFn, NowFn, SleepFn, RandFn>(
    options: DelegateToSwarmOptions,
    mut send_handoff_fn: SendFn,
    mut now_ms_fn: NowFn,
    mut sleep_ms_fn: SleepFn,
    mut rand_uniform_fn: RandFn,
) -> Result<HandoffResponse>
where
    SendFn: FnMut(&HandoffRequest) -> Result<HandoffResponse>,
    NowFn: FnMut() -> u64,
    SleepFn: FnMut(u64) -> Result<()>,
    RandFn: FnMut(f64, f64) -> f64,
{
    if options.budget.deadline_epoch_ms == 0 {
        return Err(Error::Validation(
            "budget.deadline_epoch_ms is required for cross-swarm delegation".to_string(),
        ));
    }

    let policy = normalize_policy(options.delegation_policy.clone());
    let mut request = build_request(options, policy.clone());
    let max_retries_on_overloaded = policy.max_retries_on_overloaded;
    let redirect_bound = effective_max_redirects(&policy);
    let mut redirect_hops = 0_u32;
    let mut retry_index = 0_u32;
    let mut visited_agents = HashSet::new();
    visited_agents.insert(request.to_agent.clone());

    loop {
        let start_ms = now_ms_fn();
        let budget_ref = request
            .budget
            .as_ref()
            .expect("delegate_to_swarm always assigns request budget");
        let deadline_exceeded = start_ms > budget_ref.deadline_epoch_ms;
        let wall_time_exhausted = budget_ref
            .wall_time_remaining_ms
            .is_some_and(|remaining| remaining == 0);
        if deadline_exceeded || wall_time_exhausted {
            return Ok(deadline_exhausted_response(request.request_id.clone()));
        }

        let response = send_handoff_fn(&request)?;

        let end_ms = now_ms_fn();
        let elapsed_ms = end_ms.saturating_sub(start_ms);
        if let Some(budget) = request.budget.as_mut() {
            deduct_wall_time(budget, elapsed_ms);
        }

        if response.accepted {
            return Ok(response);
        }

        let budget_ref = request
            .budget
            .as_ref()
            .expect("delegate_to_swarm always assigns request budget");
        let deadline_exceeded = end_ms > budget_ref.deadline_epoch_ms;
        let wall_time_exhausted = budget_ref
            .wall_time_remaining_ms
            .is_some_and(|remaining| remaining == 0);
        if deadline_exceeded || wall_time_exhausted {
            return Ok(deadline_exhausted_response(request.request_id.clone()));
        }

        if response.rejection_code != Some(REJECTION_CODE_OVERLOADED) {
            if response.rejection_code != Some(REJECTION_CODE_REDIRECT) {
                return Ok(response);
            }

            if !policy.allow_spillover_routing {
                return Ok(response);
            }

            let Some(target_agent) = response
                .redirect_to_agent_id
                .as_ref()
                .map(|value| value.trim())
                .filter(|value| !value.is_empty())
            else {
                return Ok(invalid_redirect_response(
                    request.request_id.clone(),
                    "Redirect response missing non-empty redirect_to_agent_id".to_string(),
                ));
            };

            if visited_agents.contains(target_agent) {
                return Ok(invalid_redirect_response(
                    request.request_id.clone(),
                    format!("Redirect loop detected for agent '{}'", target_agent),
                ));
            }

            if redirect_hops >= redirect_bound {
                return Ok(response);
            }

            request.to_agent = target_agent.to_string();
            visited_agents.insert(target_agent.to_string());
            redirect_hops = redirect_hops.saturating_add(1);
            continue;
        }

        if retry_index >= max_retries_on_overloaded {
            return Ok(response);
        }

        let wait_ms = next_retry_wait_ms(&response, retry_index, &policy, &mut rand_uniform_fn);
        retry_index = retry_index.saturating_add(1);

        let budget_ref = request
            .budget
            .as_ref()
            .expect("delegate_to_swarm always assigns request budget");
        let remaining_deadline_ms = budget_ref.deadline_epoch_ms.saturating_sub(end_ms);
        let remaining_wall_time_ms = budget_ref.wall_time_remaining_ms;
        if wait_ms == 0
            || wait_ms > remaining_deadline_ms
            || remaining_wall_time_ms.is_some_and(|remaining| wait_ms > remaining)
        {
            return Ok(response);
        }

        let before_sleep_ms = now_ms_fn();
        sleep_ms_fn(wait_ms)?;
        let after_sleep_ms = now_ms_fn();
        if let Some(budget) = request.budget.as_mut() {
            deduct_wall_time(budget, after_sleep_ms.saturating_sub(before_sleep_ms));
        }
    }
}

fn build_request(options: DelegateToSwarmOptions, policy: SwarmDelegationPolicy) -> HandoffRequest {
    let mut request = HandoffRequest::new(options.from_agent, options.to_agent, options.reason);
    request.request_id = options
        .request_id
        .unwrap_or_else(|| Uuid::new_v4().to_string());
    request.context_snapshot = options.context_snapshot;
    request.capabilities_required = options.capabilities_required;
    request.priority = options.priority;
    request.timeout = options.timeout;
    request.budget = Some(options.budget);
    request.delegation_policy = Some(policy);
    request
}

fn normalize_policy(policy: Option<SwarmDelegationPolicy>) -> SwarmDelegationPolicy {
    let defaults = SwarmDelegationPolicy::default();
    match policy {
        Some(policy) => SwarmDelegationPolicy {
            max_retries_on_overloaded: policy.max_retries_on_overloaded,
            initial_backoff_ms: if policy.initial_backoff_ms > 0 {
                policy.initial_backoff_ms
            } else {
                defaults.initial_backoff_ms
            },
            backoff_multiplier: if policy.backoff_multiplier > 0.0 {
                policy.backoff_multiplier
            } else {
                defaults.backoff_multiplier
            },
            max_backoff_ms: if policy.max_backoff_ms > 0 {
                policy.max_backoff_ms
            } else {
                defaults.max_backoff_ms
            },
            allow_spillover_routing: policy.allow_spillover_routing,
            max_redirects: policy.max_redirects,
        },
        None => defaults,
    }
}

fn effective_max_redirects(policy: &SwarmDelegationPolicy) -> u32 {
    if policy.max_redirects > 0 {
        policy.max_redirects
    } else {
        DEFAULT_EFFECTIVE_MAX_REDIRECTS
    }
}

fn next_retry_wait_ms<RandFn>(
    response: &HandoffResponse,
    retry_index: u32,
    policy: &SwarmDelegationPolicy,
    rand_uniform_fn: &mut RandFn,
) -> u64
where
    RandFn: FnMut(f64, f64) -> f64,
{
    if let Some(retry_after_ms) = response.retry_after_ms.filter(|value| *value > 0) {
        let retry_after = retry_after_ms as f64;
        let jitter = rand_uniform_fn(0.0, retry_after * RETRY_AFTER_JITTER_RATIO).max(0.0);
        return (retry_after + jitter).floor() as u64;
    }

    let initial_backoff_ms = if policy.initial_backoff_ms > 0 {
        policy.initial_backoff_ms
    } else {
        DEFAULT_INITIAL_BACKOFF_MS
    } as f64;
    let backoff_multiplier = if policy.backoff_multiplier > 0.0 {
        policy.backoff_multiplier
    } else {
        DEFAULT_BACKOFF_MULTIPLIER
    };
    let max_backoff_ms = if policy.max_backoff_ms > 0 {
        policy.max_backoff_ms
    } else {
        DEFAULT_MAX_BACKOFF_MS
    } as f64;
    let exponential = initial_backoff_ms * backoff_multiplier.powi(retry_index as i32);
    let bounded = exponential.min(max_backoff_ms).max(0.0);
    rand_uniform_fn(0.0, bounded).max(0.0).floor() as u64
}

fn deduct_wall_time(budget: &mut BudgetEnvelope, elapsed_ms: u64) {
    if let Some(remaining) = budget.wall_time_remaining_ms {
        budget.wall_time_remaining_ms = Some(remaining.saturating_sub(elapsed_ms));
    }
}

fn deadline_exhausted_response(request_id: String) -> HandoffResponse {
    HandoffResponse {
        accepted: false,
        handoff_id: request_id,
        rejection_reason: Some(
            "Delegation deadline exhausted before handoff acceptance".to_string(),
        ),
        accepting_agent: None,
        rejection_code: Some(error_code::ACK_TIMEOUT),
        retry_after_ms: None,
        redirect_to_agent_id: None,
        status: HandoffStatus::Rejected,
        metadata: HashMap::new(),
    }
}

fn invalid_redirect_response(request_id: String, reason: String) -> HandoffResponse {
    HandoffResponse {
        accepted: false,
        handoff_id: request_id,
        rejection_reason: Some(reason),
        accepting_agent: None,
        rejection_code: Some(error_code::VALIDATION_ERROR),
        retry_after_ms: None,
        redirect_to_agent_id: None,
        status: HandoffStatus::Rejected,
        metadata: HashMap::new(),
    }
}

fn default_now_ms() -> u64 {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_millis(0));
    now.as_millis().min(u128::from(u64::MAX)) as u64
}

fn default_sleep_ms(milliseconds: u64) -> Result<()> {
    std::thread::sleep(Duration::from_millis(milliseconds));
    Ok(())
}

fn default_rand_uniform(low: f64, high: f64) -> f64 {
    if high <= low {
        return low;
    }
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0));
    let unit = (now.subsec_nanos() as f64) / 1_000_000_000.0;
    low + unit * (high - low)
}
