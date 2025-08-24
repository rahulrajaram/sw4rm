use crate::proto::sw4rm::registry::{
    registry_service_server::{RegistryService, RegistryServiceServer},
    RegisterAgentRequest, RegisterAgentResponse,
    HeartbeatRequest, HeartbeatResponse,
    DeregisterAgentRequest, DeregisterAgentResponse,
};
use crate::proto::sw4rm::common::{AgentState, CommunicationClass};
use dashmap::DashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::time::{interval, Duration};
use tonic::{Request, Response, Status};
use tracing::{info, warn, debug};

#[derive(Debug, Clone)]
pub struct AgentInfo {
    pub agent_id: String,
    pub name: String,
    pub description: String,
    pub capabilities: Vec<String>,
    pub communication_class: CommunicationClass,
    pub modalities_supported: Vec<String>,
    pub reasoning_connectors: Vec<String>,
    pub registered_at: u64,
    pub last_heartbeat: u64,
    pub state: Option<AgentState>,
    pub health: std::collections::HashMap<String, String>,
}

#[derive(Debug)]
pub struct RegistryServiceImpl {
    agents: Arc<DashMap<String, AgentInfo>>,
}

impl RegistryServiceImpl {
    pub fn new() -> Self {
        let service = Self {
            agents: Arc::new(DashMap::new()),
        };

        // Start heartbeat cleanup task
        let agents_clone = Arc::clone(&service.agents);
        tokio::spawn(async move {
            let mut cleanup_interval = interval(Duration::from_secs(60));
            let heartbeat_timeout = Duration::from_secs(300); // 5 minutes

            loop {
                cleanup_interval.tick().await;
                
                let current_time = SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap()
                    .as_secs();

                let mut expired_agents = Vec::new();
                
                for entry in agents_clone.iter() {
                    let agent_info = entry.value();
                    if current_time - agent_info.last_heartbeat > heartbeat_timeout.as_secs() {
                        expired_agents.push(entry.key().clone());
                    }
                }

                for agent_id in expired_agents {
                    agents_clone.remove(&agent_id);
                    info!("Removed expired agent: {}", agent_id);
                }
            }
        });

        service
    }

    pub fn get_registered_agents(&self) -> Vec<AgentInfo> {
        self.agents.iter().map(|entry| entry.value().clone()).collect()
    }
}

#[tonic::async_trait]
impl RegistryService for RegistryServiceImpl {
    async fn register_agent(
        &self,
        request: Request<RegisterAgentRequest>,
    ) -> Result<Response<RegisterAgentResponse>, Status> {
        let req = request.into_inner();
        let agent = req.agent.ok_or_else(|| Status::invalid_argument("Agent descriptor required"))?;
        
        let agent_id = agent.agent_id.clone();
        
        if agent_id.is_empty() {
            return Err(Status::invalid_argument("Agent ID cannot be empty"));
        }

        let current_time = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();

        let agent_info = AgentInfo {
            agent_id: agent_id.clone(),
            name: agent.name.clone(),
            description: agent.description.clone(),
            capabilities: agent.capabilities.clone(),
            communication_class: agent.communication_class(),
            modalities_supported: agent.modalities_supported.clone(),
            reasoning_connectors: agent.reasoning_connectors.clone(),
            registered_at: current_time,
            last_heartbeat: current_time,
            state: None,
            health: std::collections::HashMap::new(),
        };

        if self.agents.contains_key(&agent_id) {
            warn!("Agent {} already registered, updating", agent_id);
        }

        self.agents.insert(agent_id.clone(), agent_info);
        info!("Registered agent: {} ({})", agent_id, agent.name);

        Ok(Response::new(RegisterAgentResponse {
            accepted: true,
            reason: format!("Agent {} registered successfully", agent_id),
        }))
    }

    async fn heartbeat(
        &self,
        request: Request<HeartbeatRequest>,
    ) -> Result<Response<HeartbeatResponse>, Status> {
        let req = request.into_inner();
        let agent_id = req.agent_id.clone();
        let state = req.state();

        if let Some(mut agent_info) = self.agents.get_mut(&agent_id) {
            let current_time = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_secs();

            agent_info.last_heartbeat = current_time;
            agent_info.state = Some(state);
            agent_info.health = req.health;

            debug!("Heartbeat from {}, state: {:?}", agent_id, state);

            Ok(Response::new(HeartbeatResponse { ok: true }))
        } else {
            warn!("Heartbeat from unregistered agent: {}", agent_id);
            Ok(Response::new(HeartbeatResponse { ok: false }))
        }
    }

    async fn deregister_agent(
        &self,
        request: Request<DeregisterAgentRequest>,
    ) -> Result<Response<DeregisterAgentResponse>, Status> {
        let req = request.into_inner();
        let agent_id = req.agent_id;

        if self.agents.remove(&agent_id).is_some() {
            info!("Deregistered agent: {}, reason: {}", agent_id, req.reason);
            Ok(Response::new(DeregisterAgentResponse { ok: true }))
        } else {
            warn!("Attempted to deregister unknown agent: {}", agent_id);
            Ok(Response::new(DeregisterAgentResponse { ok: false }))
        }
    }
}

pub fn create_service() -> RegistryServiceServer<RegistryServiceImpl> {
    RegistryServiceServer::new(RegistryServiceImpl::new())
}