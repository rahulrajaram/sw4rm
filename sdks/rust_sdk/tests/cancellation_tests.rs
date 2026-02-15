use serde::Deserialize;
use serde_json::json;
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use sw4rm_sdk::clients::{
    CancelDelegationRequest, CancellationManager, CancellationManagerOptions, MIN_GRACE_PERIOD_MS,
};
use sw4rm_sdk::constants::error_code;

#[derive(Debug, Deserialize)]
struct CancellationVectorSuite {
    vectors: Vec<CancellationVector>,
}

#[derive(Debug, Deserialize)]
struct CancellationVector {
    id: String,
    children: Vec<CancellationChildLink>,
    request: CancellationRequest,
    expected: CancellationExpected,
}

#[derive(Debug, Deserialize)]
struct CancellationChildLink {
    parent: String,
    child: String,
}

#[derive(Debug, Deserialize)]
struct CancellationRequest {
    correlation_id: String,
    reason: String,
    grace_period_ms: u64,
}

#[derive(Debug, Deserialize)]
struct CancellationExpected {
    acknowledged: bool,
    effective_grace_period_ms: u64,
    cancelled: Vec<String>,
    grace_expiry_checks: Vec<CancellationExpiryCheck>,
    forced_preemption_checks: Vec<CancellationForcedCheck>,
    collect_forced: Option<CancellationCollectForced>,
}

#[derive(Debug, Deserialize)]
struct CancellationExpiryCheck {
    correlation_id: String,
    offset_ms: i64,
    expired: bool,
}

#[derive(Debug, Deserialize)]
struct CancellationForcedCheck {
    correlation_id: String,
    offset_ms: i64,
    error_code: String,
}

#[derive(Debug, Deserialize)]
struct CancellationCollectForced {
    active_correlations: Vec<String>,
    offset_ms: i64,
    expected: Vec<String>,
}

fn load_shared_cancellation_vectors() -> CancellationVectorSuite {
    serde_json::from_str(include_str!(
        "../../../tests/conformance_vectors/sw4_004_cancellation_vectors.json"
    ))
    .expect("shared cancellation vectors should parse")
}

fn cancellation_error_code_from_name(name: &str) -> i32 {
    match name {
        "ERROR_CODE_UNSPECIFIED" => error_code::ERROR_CODE_UNSPECIFIED,
        "FORCED_PREEMPTION" => error_code::FORCED_PREEMPTION,
        other => panic!("unsupported cancellation error_code in vector: {other}"),
    }
}

fn eval_now_ms(cancel_time_ms: u64, grace_period_ms: u64, offset_ms: i64) -> u64 {
    let base = (cancel_time_ms + grace_period_ms) as i64;
    if base + offset_ms < 0 {
        0
    } else {
        (base + offset_ms) as u64
    }
}

#[test]
fn shared_cancellation_conformance_vectors() {
    let suite = load_shared_cancellation_vectors();

    for vector in suite.vectors {
        let now = Arc::new(AtomicU64::new(1_000));
        let manager_now = Arc::clone(&now);
        let mut manager = CancellationManager::new(CancellationManagerOptions {
            now_ms_fn: Some(Arc::new(move || manager_now.load(Ordering::Relaxed))),
        });

        for link in &vector.children {
            manager
                .register_child_delegation(&link.parent, &link.child)
                .unwrap_or_else(|err| panic!("vector '{}' child registration failed: {err}", vector.id));
        }

        let response = manager
            .handle_cancel_delegation(CancelDelegationRequest {
                correlation_id: vector.request.correlation_id.clone(),
                reason: Some(vector.request.reason.clone()),
                grace_period_ms: Some(vector.request.grace_period_ms),
                metadata: None,
            })
            .unwrap_or_else(|err| panic!("vector '{}' cancellation request failed: {err}", vector.id));

        assert_eq!(
            response.acknowledged, vector.expected.acknowledged,
            "vector '{}' acknowledged mismatch",
            vector.id
        );

        let root_flag = manager
            .cancellation_flags
            .get(&vector.request.correlation_id)
            .unwrap_or_else(|| panic!("vector '{}' missing root flag", vector.id));
        assert_eq!(
            root_flag.grace_period_ms, vector.expected.effective_grace_period_ms,
            "vector '{}' effective grace period mismatch",
            vector.id
        );

        for correlation_id in &vector.expected.cancelled {
            assert!(
                manager.is_cancelled(correlation_id),
                "vector '{}' expected '{}' to be cancelled",
                vector.id,
                correlation_id
            );
        }

        for check in &vector.expected.grace_expiry_checks {
            let flag = manager
                .cancellation_flags
                .get(&check.correlation_id)
                .unwrap_or_else(|| panic!("vector '{}' missing flag for '{}'", vector.id, check.correlation_id));
            let now_ms = eval_now_ms(flag.cancel_time_ms, flag.grace_period_ms, check.offset_ms);
            assert_eq!(
                manager.is_grace_expired(&check.correlation_id, Some(now_ms)),
                check.expired,
                "vector '{}' grace expiry mismatch for '{}'",
                vector.id,
                check.correlation_id
            );
        }

        for check in &vector.expected.forced_preemption_checks {
            let flag = manager
                .cancellation_flags
                .get(&check.correlation_id)
                .unwrap_or_else(|| panic!("vector '{}' missing flag for '{}'", vector.id, check.correlation_id));
            let now_ms = eval_now_ms(flag.cancel_time_ms, flag.grace_period_ms, check.offset_ms);
            assert_eq!(
                manager.forced_preemption_error_code(&check.correlation_id, Some(now_ms)),
                cancellation_error_code_from_name(&check.error_code),
                "vector '{}' forced preemption code mismatch for '{}'",
                vector.id,
                check.correlation_id
            );
        }

        if let Some(collect) = &vector.expected.collect_forced {
            let collect_now = eval_now_ms(
                root_flag.cancel_time_ms,
                root_flag.grace_period_ms,
                collect.offset_ms,
            );
            let forced = manager.collect_forced_preemptions(
                collect
                    .active_correlations
                    .iter()
                    .map(std::string::String::as_str)
                    .collect::<HashSet<_>>(),
                Some(collect_now),
            );
            let expected = collect.expected.iter().cloned().collect::<HashSet<_>>();
            assert_eq!(
                forced, expected,
                "vector '{}' collect forced mismatch",
                vector.id
            );
        }
    }
}

#[test]
fn acknowledges_cancellation_with_minimum_grace_and_normalized_metadata() {
    let now = Arc::new(AtomicU64::new(1_000));
    let manager_now = Arc::clone(&now);
    let mut manager = CancellationManager::new(CancellationManagerOptions {
        now_ms_fn: Some(Arc::new(move || manager_now.load(Ordering::Relaxed))),
    });

    let mut metadata = HashMap::new();
    metadata.insert(" trace_id ".to_string(), json!(" abc "));
    metadata.insert("retries".to_string(), json!(2));
    metadata.insert("cancellable".to_string(), json!(true));
    metadata.insert("nested".to_string(), json!({ "stage": "handoff" }));

    let response = manager
        .handle_cancel_delegation(CancelDelegationRequest {
            correlation_id: " corr-1 ".to_string(),
            reason: Some(" stop ".to_string()),
            grace_period_ms: Some(0),
            metadata: Some(metadata),
        })
        .expect("request should be valid");

    assert!(response.acknowledged);
    assert_eq!(response.correlation_id, "corr-1");
    assert_eq!(response.grace_period_ms, MIN_GRACE_PERIOD_MS);
    assert_eq!(response.metadata.get("trace_id"), Some(&json!("abc")));
    assert_eq!(response.metadata.get("retries"), Some(&json!(2)));
    assert_eq!(response.metadata.get("cancellable"), Some(&json!(true)));
    assert_eq!(
        response.metadata.get("nested"),
        Some(&json!("{\"stage\":\"handoff\"}"))
    );
    assert_eq!(response.metadata.get("reason"), Some(&json!("stop")));
    assert_eq!(
        response.metadata.get("grace_period_ms"),
        Some(&json!(MIN_GRACE_PERIOD_MS))
    );

    assert!(manager.is_cancelled("corr-1"));
    let flag = manager
        .cancellation_flags
        .get("corr-1")
        .expect("parent flag should exist");
    assert_eq!(flag.cancel_time_ms, 1_000);
    assert_eq!(flag.grace_period_ms, MIN_GRACE_PERIOD_MS);
}

#[test]
fn cascades_cancellation_to_registered_children() {
    let now = Arc::new(AtomicU64::new(42_000));
    let manager_now = Arc::clone(&now);
    let mut manager = CancellationManager::new(CancellationManagerOptions {
        now_ms_fn: Some(Arc::new(move || manager_now.load(Ordering::Relaxed))),
    });
    manager
        .register_child_delegation("parent-corr", "child-a")
        .unwrap();
    manager
        .register_child_delegation("parent-corr", "child-b")
        .unwrap();

    manager
        .handle_cancel_delegation(CancelDelegationRequest {
            correlation_id: "parent-corr".to_string(),
            reason: Some("abort".to_string()),
            grace_period_ms: Some(10_000),
            metadata: None,
        })
        .unwrap();

    assert!(manager.is_cancelled("parent-corr"));
    assert!(manager.is_cancelled("child-a"));
    assert!(manager.is_cancelled("child-b"));
    assert_eq!(
        manager
            .cancellation_flags
            .get("child-a")
            .unwrap()
            .grace_period_ms,
        10_000
    );
    assert_eq!(
        manager
            .cancellation_flags
            .get("child-b")
            .unwrap()
            .cancel_time_ms,
        42_000
    );
}

#[test]
fn evaluates_grace_expiry_using_optional_now_override() {
    let mut manager = CancellationManager::new(CancellationManagerOptions {
        now_ms_fn: Some(Arc::new(|| 5_000)),
    });
    manager
        .handle_cancel_delegation(CancelDelegationRequest {
            correlation_id: "corr-grace".to_string(),
            reason: Some("stop".to_string()),
            grace_period_ms: Some(6_000),
            metadata: None,
        })
        .unwrap();

    assert!(!manager.is_grace_expired("corr-grace", Some(10_999)));
    assert!(manager.is_grace_expired("corr-grace", Some(11_000)));
}

#[test]
fn returns_forced_preemption_only_after_grace_expiry() {
    let mut manager = CancellationManager::new(CancellationManagerOptions {
        now_ms_fn: Some(Arc::new(|| 1_000)),
    });
    manager
        .handle_cancel_delegation(CancelDelegationRequest {
            correlation_id: "corr-preempt".to_string(),
            reason: Some("stop".to_string()),
            grace_period_ms: Some(5_000),
            metadata: None,
        })
        .unwrap();

    assert_eq!(
        manager.forced_preemption_error_code("corr-preempt", Some(5_999)),
        error_code::ERROR_CODE_UNSPECIFIED
    );
    assert_eq!(
        manager.forced_preemption_error_code("corr-preempt", Some(6_000)),
        error_code::FORCED_PREEMPTION
    );
}

#[test]
fn collects_only_correlations_whose_grace_period_has_expired() {
    let now = Arc::new(AtomicU64::new(10_000));
    let manager_now = Arc::clone(&now);
    let mut manager = CancellationManager::new(CancellationManagerOptions {
        now_ms_fn: Some(Arc::new(move || manager_now.load(Ordering::Relaxed))),
    });

    manager
        .handle_cancel_delegation(CancelDelegationRequest {
            correlation_id: "expired-corr".to_string(),
            reason: Some("stop".to_string()),
            grace_period_ms: Some(5_000),
            metadata: None,
        })
        .unwrap();

    now.store(13_000, Ordering::Relaxed);
    manager
        .handle_cancel_delegation(CancelDelegationRequest {
            correlation_id: "within-grace".to_string(),
            reason: Some("stop".to_string()),
            grace_period_ms: Some(8_000),
            metadata: None,
        })
        .unwrap();

    let forced = manager.collect_forced_preemptions(
        HashSet::from(["expired-corr", "within-grace", "not-cancelled"]),
        Some(16_000),
    );

    assert_eq!(forced, HashSet::from(["expired-corr".to_string()]));
}
