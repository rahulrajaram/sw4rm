use crate::constants::agent_state;
use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use super::handoff::{
    HandoffRequest, HandoffResponse, HandoffStatus, REJECTION_CODE_OVERLOADED,
    REJECTION_CODE_REDIRECT,
};

pub const REGISTRATION_TYPE_STANDARD_AGENT: i32 = 1;
pub const REGISTRATION_TYPE_SWARM_GATEWAY: i32 = 2;
pub const DEFAULT_PEER_LIVENESS_THRESHOLD_MS: u64 = 30_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GatewayPeerDescriptor {
    pub agent_id: String,
    pub registration_type: i32,
    pub capabilities: Vec<String>,
}

impl GatewayPeerDescriptor {
    pub fn new(agent_id: String) -> Self {
        Self {
            agent_id,
            registration_type: REGISTRATION_TYPE_SWARM_GATEWAY,
            capabilities: Vec::new(),
        }
    }

    pub fn with_registration_type(mut self, registration_type: i32) -> Self {
        self.registration_type = registration_type;
        self
    }

    pub fn with_capabilities(mut self, capabilities: Vec<String>) -> Self {
        self.capabilities = capabilities;
        self
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerRuntimeState {
    pub state: i32,
    pub last_heartbeat_ms: u64,
    pub cooldown_until_ms: u64,
}

impl PeerRuntimeState {
    fn new(last_heartbeat_ms: u64) -> Self {
        Self {
            state: agent_state::RUNNING,
            last_heartbeat_ms,
            cooldown_until_ms: 0,
        }
    }
}

pub type PeerHealthFn = Arc<dyn Fn(&GatewayPeerDescriptor) -> bool + Send + Sync>;
pub type NowMsFn = Arc<dyn Fn() -> u64 + Send + Sync>;

#[derive(Clone)]
pub struct PeerSelectorOptions {
    pub local_agent_id: String,
    pub local_capabilities: Vec<String>,
    pub now_ms_fn: Option<NowMsFn>,
    pub peer_health_fn: Option<PeerHealthFn>,
    pub liveness_threshold_ms: u64,
}

impl PeerSelectorOptions {
    pub fn new(local_agent_id: String, local_capabilities: Vec<String>) -> Self {
        Self {
            local_agent_id,
            local_capabilities,
            now_ms_fn: None,
            peer_health_fn: None,
            liveness_threshold_ms: DEFAULT_PEER_LIVENESS_THRESHOLD_MS,
        }
    }
}

pub struct PeerSelector {
    local_agent_id: String,
    local_capabilities: HashSet<String>,
    now_ms_fn: NowMsFn,
    peer_health_fn: PeerHealthFn,
    liveness_threshold_ms: u64,
    peers: Vec<GatewayPeerDescriptor>,
    runtime: HashMap<String, PeerRuntimeState>,
    rr_cursor: usize,
}

impl PeerSelector {
    pub fn new(options: PeerSelectorOptions) -> Self {
        Self {
            local_agent_id: options.local_agent_id,
            local_capabilities: options.local_capabilities.into_iter().collect(),
            now_ms_fn: options
                .now_ms_fn
                .unwrap_or_else(|| Arc::new(default_now_ms as fn() -> u64)),
            peer_health_fn: options.peer_health_fn.unwrap_or_else(|| Arc::new(|_| true)),
            liveness_threshold_ms: options.liveness_threshold_ms,
            peers: Vec::new(),
            runtime: HashMap::new(),
            rr_cursor: 0,
        }
    }

    pub fn set_peers<I>(&mut self, peers: I)
    where
        I: IntoIterator<Item = GatewayPeerDescriptor>,
    {
        self.peers = peers.into_iter().collect();
        let active_ids: HashSet<&str> = self.peers.iter().map(|peer| peer.agent_id.as_str()).collect();
        self.runtime.retain(|agent_id, _| active_ids.contains(agent_id.as_str()));

        let now_ms = self.now_ms();
        for peer in &self.peers {
            self.runtime
                .entry(peer.agent_id.clone())
                .or_insert_with(|| PeerRuntimeState::new(now_ms));
        }
    }

    pub fn update_peer_runtime_state(
        &mut self,
        agent_id: &str,
        state: Option<i32>,
        last_heartbeat_ms: Option<u64>,
        cooldown_until_ms: Option<u64>,
    ) {
        let now_ms = self.now_ms();
        let runtime = self
            .runtime
            .entry(agent_id.to_string())
            .or_insert_with(|| PeerRuntimeState::new(now_ms));

        if let Some(state) = state {
            runtime.state = state;
        }
        if let Some(last_heartbeat_ms) = last_heartbeat_ms {
            runtime.last_heartbeat_ms = last_heartbeat_ms;
        }
        if let Some(cooldown_until_ms) = cooldown_until_ms {
            runtime.cooldown_until_ms = cooldown_until_ms;
        }
    }

    pub fn touch_peer_heartbeat(&mut self, agent_id: &str, state: Option<i32>, now_ms: Option<u64>) {
        self.update_peer_runtime_state(
            agent_id,
            state,
            Some(now_ms.unwrap_or_else(|| self.now_ms())),
            None,
        );
    }

    pub fn record_peer_overloaded(
        &mut self,
        agent_id: &str,
        retry_after_ms: Option<u64>,
        local_cooldown_ms: Option<u64>,
    ) {
        let now_ms = self.now_ms();
        let runtime = self
            .runtime
            .entry(agent_id.to_string())
            .or_insert_with(|| PeerRuntimeState::new(now_ms));
        let cooldown_ms = retry_after_ms
            .unwrap_or(0)
            .max(local_cooldown_ms.unwrap_or(0));
        runtime.cooldown_until_ms = runtime.cooldown_until_ms.max(now_ms.saturating_add(cooldown_ms));
    }

    pub fn is_eligible(&self, peer: &GatewayPeerDescriptor) -> bool {
        if peer.registration_type != REGISTRATION_TYPE_SWARM_GATEWAY {
            return false;
        }
        if peer.agent_id == self.local_agent_id {
            return false;
        }
        same_capabilities(&peer.capabilities, &self.local_capabilities)
    }

    pub fn select_peer(&mut self) -> Option<String> {
        let healthy: Vec<&GatewayPeerDescriptor> =
            self.peers.iter().filter(|peer| self.is_healthy(peer)).collect();
        if healthy.is_empty() {
            return None;
        }

        let idx = self.rr_cursor % healthy.len();
        self.rr_cursor = self.rr_cursor.saturating_add(1);
        Some(healthy[idx].agent_id.clone())
    }

    fn is_healthy(&self, peer: &GatewayPeerDescriptor) -> bool {
        if !self.is_eligible(peer) {
            return false;
        }
        if !(self.peer_health_fn)(peer) {
            return false;
        }

        let Some(runtime) = self.runtime.get(&peer.agent_id) else {
            return false;
        };
        let now_ms = self.now_ms();
        if runtime.cooldown_until_ms > now_ms {
            return false;
        }
        if now_ms.saturating_sub(runtime.last_heartbeat_ms) > self.liveness_threshold_ms {
            return false;
        }
        if matches!(
            runtime.state,
            agent_state::INITIALIZING | agent_state::FAILED | agent_state::SHUTTING_DOWN
        ) {
            return false;
        }
        true
    }

    fn now_ms(&self) -> u64 {
        (self.now_ms_fn)()
    }
}

#[derive(Clone)]
pub struct GatewayRedirectEmitterOptions {
    pub agent_id: String,
    pub capabilities: Vec<String>,
    pub retry_after_ms: u64,
    pub peer_descriptors: Vec<GatewayPeerDescriptor>,
    pub now_ms_fn: Option<NowMsFn>,
    pub peer_health_fn: Option<PeerHealthFn>,
    pub peer_liveness_threshold_ms: u64,
}

impl GatewayRedirectEmitterOptions {
    pub fn new(agent_id: String, capabilities: Vec<String>) -> Self {
        Self {
            agent_id,
            capabilities,
            retry_after_ms: 1000,
            peer_descriptors: Vec::new(),
            now_ms_fn: None,
            peer_health_fn: None,
            peer_liveness_threshold_ms: DEFAULT_PEER_LIVENESS_THRESHOLD_MS,
        }
    }
}

pub struct GatewayRedirectEmitter {
    retry_after_ms: u64,
    peer_selector: PeerSelector,
}

impl GatewayRedirectEmitter {
    pub fn new(options: GatewayRedirectEmitterOptions) -> Self {
        let mut peer_selector = PeerSelector::new(PeerSelectorOptions {
            local_agent_id: options.agent_id,
            local_capabilities: options.capabilities,
            now_ms_fn: options.now_ms_fn,
            peer_health_fn: options.peer_health_fn,
            liveness_threshold_ms: options.peer_liveness_threshold_ms,
        });
        peer_selector.set_peers(options.peer_descriptors);

        Self {
            retry_after_ms: options.retry_after_ms,
            peer_selector,
        }
    }

    pub fn set_peer_descriptors<I>(&mut self, peers: I)
    where
        I: IntoIterator<Item = GatewayPeerDescriptor>,
    {
        self.peer_selector.set_peers(peers);
    }

    pub fn update_peer_runtime_state(
        &mut self,
        agent_id: &str,
        state: Option<i32>,
        last_heartbeat_ms: Option<u64>,
        cooldown_until_ms: Option<u64>,
    ) {
        self.peer_selector
            .update_peer_runtime_state(agent_id, state, last_heartbeat_ms, cooldown_until_ms);
    }

    pub fn touch_peer_heartbeat(&mut self, agent_id: &str, state: Option<i32>, now_ms: Option<u64>) {
        self.peer_selector.touch_peer_heartbeat(agent_id, state, now_ms);
    }

    pub fn record_peer_overloaded(
        &mut self,
        agent_id: &str,
        retry_after_ms: Option<u64>,
        local_cooldown_ms: Option<u64>,
    ) {
        self.peer_selector
            .record_peer_overloaded(agent_id, retry_after_ms, local_cooldown_ms);
    }

    pub fn emit_overloaded_response(&mut self, request: &HandoffRequest) -> HandoffResponse {
        let allow_spillover = request
            .delegation_policy
            .as_ref()
            .is_some_and(|policy| policy.allow_spillover_routing);

        if allow_spillover {
            if let Some(target) = self.peer_selector.select_peer() {
                return HandoffResponse {
                    accepted: false,
                    handoff_id: request.request_id.clone(),
                    rejection_reason: Some(
                        "Gateway at capacity; redirect to peer gateway".to_string(),
                    ),
                    accepting_agent: None,
                    rejection_code: Some(REJECTION_CODE_REDIRECT),
                    retry_after_ms: Some(0),
                    redirect_to_agent_id: Some(target),
                    status: HandoffStatus::Rejected,
                    metadata: HashMap::new(),
                };
            }
        }

        HandoffResponse {
            accepted: false,
            handoff_id: request.request_id.clone(),
            rejection_reason: Some("Gateway at capacity".to_string()),
            accepting_agent: None,
            rejection_code: Some(REJECTION_CODE_OVERLOADED),
            retry_after_ms: Some(self.retry_after_ms),
            redirect_to_agent_id: None,
            status: HandoffStatus::Rejected,
            metadata: HashMap::new(),
        }
    }
}

fn same_capabilities(peer_capabilities: &[String], local_capabilities: &HashSet<String>) -> bool {
    let peer_set: HashSet<&str> = peer_capabilities.iter().map(String::as_str).collect();
    if peer_set.len() != local_capabilities.len() {
        return false;
    }
    local_capabilities
        .iter()
        .all(|capability| peer_set.contains(capability.as_str()))
}

fn default_now_ms() -> u64 {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_millis(0));
    now.as_millis().min(u128::from(u64::MAX)) as u64
}
