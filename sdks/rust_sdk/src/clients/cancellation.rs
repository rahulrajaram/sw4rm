use crate::constants::error_code;
use serde::{Deserialize, Serialize};
use serde_json::{Number, Value};
use std::collections::{HashMap, HashSet};
use std::fmt::{Display, Formatter};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const MIN_GRACE_PERIOD_MS: u64 = 5000;

pub type CancellationMetadata = HashMap<String, Value>;

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CancelDelegationRequest {
    pub correlation_id: String,
    pub reason: Option<String>,
    pub grace_period_ms: Option<u64>,
    pub metadata: Option<HashMap<String, Value>>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CancelDelegationResponse {
    pub acknowledged: bool,
    pub correlation_id: String,
    pub grace_period_ms: u64,
    pub message: String,
    pub metadata: CancellationMetadata,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct CancellationFlag {
    pub cancelled: bool,
    pub grace_period_ms: u64,
    pub cancel_time_ms: u64,
    pub metadata: CancellationMetadata,
}

#[derive(Clone, Default)]
pub struct CancellationManagerOptions {
    pub now_ms_fn: Option<Arc<dyn Fn() -> u64 + Send + Sync>>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CancellationValidationError {
    message: String,
}

impl CancellationValidationError {
    fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl Display for CancellationValidationError {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for CancellationValidationError {}

pub struct CancellationManager {
    pub child_delegations: HashMap<String, HashSet<String>>,
    pub cancellation_flags: HashMap<String, CancellationFlag>,
    now_ms_fn: Arc<dyn Fn() -> u64 + Send + Sync>,
}

impl Default for CancellationManager {
    fn default() -> Self {
        Self::new(CancellationManagerOptions::default())
    }
}

impl CancellationManager {
    pub fn new(options: CancellationManagerOptions) -> Self {
        Self {
            child_delegations: HashMap::new(),
            cancellation_flags: HashMap::new(),
            now_ms_fn: options
                .now_ms_fn
                .unwrap_or_else(|| Arc::new(default_now_ms as fn() -> u64)),
        }
    }

    pub fn register_child_delegation(
        &mut self,
        parent_correlation_id: &str,
        child_correlation_id: &str,
    ) -> Result<(), CancellationValidationError> {
        let parent = normalize_correlation_id(parent_correlation_id)?;
        let child = normalize_correlation_id(child_correlation_id)?;
        self.child_delegations
            .entry(parent)
            .or_default()
            .insert(child);
        Ok(())
    }

    pub fn handle_cancel_delegation(
        &mut self,
        cancel: CancelDelegationRequest,
    ) -> Result<CancelDelegationResponse, CancellationValidationError> {
        let correlation_id = normalize_correlation_id(&cancel.correlation_id)?;
        let grace_period_ms = normalize_grace_period_ms(cancel.grace_period_ms);
        let reason = normalize_reason(cancel.reason.as_deref());
        let cancel_time_ms = self.now_ms();
        let metadata = normalize_metadata(cancel.metadata.as_ref(), &reason, grace_period_ms);

        let flag = CancellationFlag {
            cancelled: true,
            grace_period_ms,
            cancel_time_ms,
            metadata: metadata.clone(),
        };

        self.cancellation_flags
            .insert(correlation_id.clone(), flag.clone());
        if let Some(children) = self.child_delegations.get(&correlation_id) {
            for child_correlation_id in children {
                self.cancellation_flags
                    .insert(child_correlation_id.clone(), flag.clone());
            }
        }

        Ok(CancelDelegationResponse {
            acknowledged: true,
            correlation_id,
            grace_period_ms,
            message: "Cancellation recorded".to_string(),
            metadata,
        })
    }

    pub fn is_cancelled(&self, correlation_id: &str) -> bool {
        let normalized = correlation_id.trim();
        if normalized.is_empty() {
            return false;
        }
        self.cancellation_flags
            .get(normalized)
            .is_some_and(|entry| entry.cancelled)
    }

    pub fn is_grace_expired(&self, correlation_id: &str, now_ms: Option<u64>) -> bool {
        let normalized = correlation_id.trim();
        if normalized.is_empty() {
            return false;
        }

        let Some(entry) = self.cancellation_flags.get(normalized) else {
            return false;
        };
        if !entry.cancelled {
            return false;
        }

        let current_ms = now_ms.unwrap_or_else(|| self.now_ms());
        current_ms.saturating_sub(entry.cancel_time_ms) >= entry.grace_period_ms
    }

    pub fn forced_preemption_error_code(&self, correlation_id: &str, now_ms: Option<u64>) -> i32 {
        if self.is_grace_expired(correlation_id, now_ms) {
            return error_code::FORCED_PREEMPTION;
        }
        error_code::ERROR_CODE_UNSPECIFIED
    }

    pub fn collect_forced_preemptions<I, S>(
        &self,
        correlation_ids: I,
        now_ms: Option<u64>,
    ) -> HashSet<String>
    where
        I: IntoIterator<Item = S>,
        S: AsRef<str>,
    {
        let current_ms = now_ms.unwrap_or_else(|| self.now_ms());
        let mut forced = HashSet::new();

        for correlation_id in correlation_ids {
            let normalized = correlation_id.as_ref().trim();
            if normalized.is_empty() {
                continue;
            }
            if self.is_grace_expired(normalized, Some(current_ms)) {
                forced.insert(normalized.to_string());
            }
        }

        forced
    }

    fn now_ms(&self) -> u64 {
        (self.now_ms_fn)()
    }
}

fn normalize_correlation_id(correlation_id: &str) -> Result<String, CancellationValidationError> {
    let normalized = correlation_id.trim();
    if normalized.is_empty() {
        return Err(CancellationValidationError::new(
            "cancel.correlation_id is required and must be a non-empty string",
        ));
    }
    Ok(normalized.to_string())
}

fn normalize_reason(reason: Option<&str>) -> String {
    reason.unwrap_or_default().trim().to_string()
}

fn normalize_grace_period_ms(grace_period_ms: Option<u64>) -> u64 {
    grace_period_ms.unwrap_or(0).max(MIN_GRACE_PERIOD_MS)
}

fn normalize_metadata_value(value: &Value) -> Option<Value> {
    match value {
        Value::Null => Some(Value::Null),
        Value::String(v) => Some(Value::String(v.trim().to_string())),
        Value::Number(v) => Some(Value::Number(v.clone())),
        Value::Bool(v) => Some(Value::Bool(*v)),
        Value::Array(_) | Value::Object(_) => serde_json::to_string(value).ok().map(Value::String),
    }
}

fn normalize_metadata(
    metadata: Option<&HashMap<String, Value>>,
    reason: &str,
    grace_period_ms: u64,
) -> CancellationMetadata {
    let mut normalized = HashMap::new();

    if let Some(metadata) = metadata {
        for (raw_key, raw_value) in metadata {
            let key = raw_key.trim();
            if key.is_empty() {
                continue;
            }
            if let Some(value) = normalize_metadata_value(raw_value) {
                normalized.insert(key.to_string(), value);
            }
        }
    }

    normalized.insert("reason".to_string(), Value::String(reason.to_string()));
    normalized.insert(
        "grace_period_ms".to_string(),
        Value::Number(Number::from(grace_period_ms)),
    );
    normalized
}

fn default_now_ms() -> u64 {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_millis(0));
    now.as_millis().min(u128::from(u64::MAX)) as u64
}
