use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use sw4rm_sdk::clients::{
    BudgetEnvelope, GatewayPeerDescriptor, GatewayRedirectEmitter, GatewayRedirectEmitterOptions,
    HandoffRequest, SwarmDelegationPolicy, REJECTION_CODE_OVERLOADED, REJECTION_CODE_REDIRECT,
    REGISTRATION_TYPE_STANDARD_AGENT, REGISTRATION_TYPE_SWARM_GATEWAY,
};
use sw4rm_sdk::constants::agent_state;

fn peer_descriptor(
    agent_id: &str,
    registration_type: i32,
    capabilities: &[&str],
) -> GatewayPeerDescriptor {
    GatewayPeerDescriptor::new(agent_id.to_string())
        .with_registration_type(registration_type)
        .with_capabilities(capabilities.iter().map(|cap| (*cap).to_string()).collect())
}

fn make_request(request_id: &str, allow_spillover: bool) -> HandoffRequest {
    let mut request = HandoffRequest::new(
        "parent".to_string(),
        "gateway-1".to_string(),
        "delegate".to_string(),
    );
    request.request_id = request_id.to_string();
    request.budget = Some(BudgetEnvelope {
        token_budget_remaining: Some(10_000),
        wall_time_remaining_ms: Some(60_000),
        deadline_epoch_ms: 2_000_000,
        current_depth: Some(0),
        max_delegation_depth: Some(3),
    });
    request.delegation_policy = Some(SwarmDelegationPolicy {
        allow_spillover_routing: allow_spillover,
        ..SwarmDelegationPolicy::default()
    });
    request
}

#[test]
fn emits_redirect_when_spillover_enabled_and_healthy_peer_available() {
    let mut gateway = GatewayRedirectEmitter::new({
        let mut options = GatewayRedirectEmitterOptions::new(
            "gateway-1".to_string(),
            vec!["plan".to_string(), "execute".to_string()],
        );
        options.peer_descriptors = vec![
            peer_descriptor(
                "worker-1",
                REGISTRATION_TYPE_STANDARD_AGENT,
                &["plan", "execute"],
            ),
            peer_descriptor(
                "gateway-2",
                REGISTRATION_TYPE_SWARM_GATEWAY,
                &["plan", "execute"],
            ),
        ];
        options
    });

    let response = gateway.emit_overloaded_response(&make_request("req-redirect", true));

    assert!(!response.accepted);
    assert_eq!(response.rejection_code, Some(REJECTION_CODE_REDIRECT));
    assert_eq!(response.redirect_to_agent_id, Some("gateway-2".to_string()));
    assert_eq!(response.retry_after_ms, Some(0));
}

#[test]
fn falls_back_to_overloaded_when_spillover_disabled() {
    let mut gateway = GatewayRedirectEmitter::new({
        let mut options = GatewayRedirectEmitterOptions::new(
            "gateway-1".to_string(),
            vec!["plan".to_string(), "execute".to_string()],
        );
        options.retry_after_ms = 222;
        options.peer_descriptors = vec![peer_descriptor(
            "gateway-2",
            REGISTRATION_TYPE_SWARM_GATEWAY,
            &["plan", "execute"],
        )];
        options
    });

    let response = gateway.emit_overloaded_response(&make_request("req-no-spillover", false));

    assert!(!response.accepted);
    assert_eq!(response.rejection_code, Some(REJECTION_CODE_OVERLOADED));
    assert_eq!(response.redirect_to_agent_id, None);
    assert_eq!(response.retry_after_ms, Some(222));
}

#[test]
fn filters_stale_non_serving_and_cooldown_peers() {
    let now = Arc::new(AtomicU64::new(200_000));
    let clock = Arc::clone(&now);

    let mut gateway = GatewayRedirectEmitter::new({
        let mut options = GatewayRedirectEmitterOptions::new(
            "gateway-1".to_string(),
            vec!["plan".to_string(), "execute".to_string()],
        );
        options.now_ms_fn = Some(Arc::new(move || clock.load(Ordering::Relaxed)));
        options.peer_descriptors = vec![
            peer_descriptor(
                "peer-stale",
                REGISTRATION_TYPE_SWARM_GATEWAY,
                &["plan", "execute"],
            ),
            peer_descriptor(
                "peer-initializing",
                REGISTRATION_TYPE_SWARM_GATEWAY,
                &["plan", "execute"],
            ),
            peer_descriptor(
                "peer-cooldown",
                REGISTRATION_TYPE_SWARM_GATEWAY,
                &["plan", "execute"],
            ),
            peer_descriptor(
                "peer-shutting-down",
                REGISTRATION_TYPE_SWARM_GATEWAY,
                &["plan", "execute"],
            ),
            peer_descriptor(
                "peer-healthy",
                REGISTRATION_TYPE_SWARM_GATEWAY,
                &["plan", "execute"],
            ),
        ];
        options
    });

    gateway.update_peer_runtime_state(
        "peer-stale",
        Some(agent_state::RUNNING),
        Some(now.load(Ordering::Relaxed).saturating_sub(120_000)),
        None,
    );
    gateway.touch_peer_heartbeat("peer-initializing", Some(agent_state::INITIALIZING), None);
    gateway.touch_peer_heartbeat("peer-cooldown", Some(agent_state::RUNNING), None);
    gateway.record_peer_overloaded("peer-cooldown", Some(15_000), None);
    gateway.touch_peer_heartbeat("peer-shutting-down", Some(agent_state::SHUTTING_DOWN), None);
    gateway.touch_peer_heartbeat("peer-healthy", Some(agent_state::RUNNING), None);

    let response = gateway.emit_overloaded_response(&make_request("req-health-filter", true));

    assert!(!response.accepted);
    assert_eq!(response.rejection_code, Some(REJECTION_CODE_REDIRECT));
    assert_eq!(response.redirect_to_agent_id, Some("peer-healthy".to_string()));
}

#[test]
fn uses_round_robin_across_healthy_peers() {
    let now = Arc::new(AtomicU64::new(10_000));
    let clock = Arc::clone(&now);
    let mut gateway = GatewayRedirectEmitter::new({
        let mut options = GatewayRedirectEmitterOptions::new(
            "gateway-1".to_string(),
            vec!["plan".to_string(), "execute".to_string()],
        );
        options.now_ms_fn = Some(Arc::new(move || clock.load(Ordering::Relaxed)));
        options.peer_descriptors = vec![
            peer_descriptor(
                "peer-1",
                REGISTRATION_TYPE_SWARM_GATEWAY,
                &["plan", "execute"],
            ),
            peer_descriptor(
                "peer-2",
                REGISTRATION_TYPE_SWARM_GATEWAY,
                &["plan", "execute"],
            ),
            peer_descriptor(
                "peer-3",
                REGISTRATION_TYPE_SWARM_GATEWAY,
                &["plan", "execute"],
            ),
        ];
        options
    });

    gateway.touch_peer_heartbeat("peer-1", Some(agent_state::RUNNING), None);
    gateway.touch_peer_heartbeat("peer-2", Some(agent_state::RUNNING), None);
    gateway.touch_peer_heartbeat("peer-3", Some(agent_state::RUNNING), None);

    let mut seen = Vec::new();
    for idx in 0..6 {
        let request_id = format!("req-rr-{}", idx);
        let response = gateway.emit_overloaded_response(&make_request(&request_id, true));
        seen.push(response.redirect_to_agent_id.unwrap_or_default());
    }

    assert_eq!(
        seen,
        vec![
            "peer-1".to_string(),
            "peer-2".to_string(),
            "peer-3".to_string(),
            "peer-1".to_string(),
            "peer-2".to_string(),
            "peer-3".to_string(),
        ]
    );
}
