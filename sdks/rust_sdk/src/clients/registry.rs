use crate::proto::sw4rm::common::AgentState;
use crate::proto::sw4rm::registry::registry_service_client::RegistryServiceClient;
use crate::proto::sw4rm::registry::{
    AgentDescriptor as ProtoAgentDescriptor, DeregisterAgentRequest, DeregisterAgentResponse,
    HeartbeatRequest, HeartbeatResponse, RegisterAgentRequest, RegisterAgentResponse,
};
use crate::types::AgentDescriptor;
use crate::{Error, Result};
use std::collections::HashMap;
use tonic::transport::{Channel, Endpoint};
use tracing::{debug, error, info};

/// Client for interacting with the SW4RM Registry service
#[derive(Debug, Clone)]
pub struct RegistryClient {
    client: RegistryServiceClient<Channel>,
    endpoint: String,
}

/// Type alias for intercepted registry client
pub type InterceptedRegistryClient = RegistryClient;

impl RegistryClient {
    /// Create a new registry client
    pub async fn new(endpoint: &str) -> Result<Self> {
        debug!("Creating registry client for endpoint: {}", endpoint);

        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid registry endpoint: {}", e)))?
            .connect()
            .await
            .map_err(|e| {
                error!("Failed to connect to registry at {}: {}", endpoint, e);
                Error::Connection(format!("Registry connection failed: {}", e))
            })?;

        info!("Successfully connected to registry at {}", endpoint);

        Ok(Self {
            client: RegistryServiceClient::new(channel),
            endpoint: endpoint.to_string(),
        })
    }

    /// Create a registry client with an existing channel (for testing)
    pub fn with_channel(channel: Channel, endpoint: String) -> Self {
        Self {
            client: RegistryServiceClient::new(channel),
            endpoint,
        }
    }

    /// Register an agent with the registry
    pub async fn register(&mut self, agent: &AgentDescriptor) -> Result<RegisterAgentResponse> {
        debug!("Registering agent: {} ({})", agent.agent_id, agent.name);

        let proto_agent = ProtoAgentDescriptor {
            agent_id: agent.agent_id.clone(),
            name: agent.name.clone(),
            description: agent.description.clone(),
            capabilities: agent.capabilities.clone(),
            communication_class: agent.communication_class,
            modalities_supported: agent.modalities_supported.clone(),
            reasoning_connectors: agent.reasoning_connectors.clone(),
            public_key: agent.public_key.clone(),
        };

        let request = tonic::Request::new(RegisterAgentRequest {
            agent: Some(proto_agent),
        });

        match self.client.register_agent(request).await {
            Ok(response) => {
                let inner = response.into_inner();
                if inner.accepted {
                    info!("Agent {} registered successfully", agent.agent_id);
                } else {
                    error!(
                        "Agent {} registration rejected: {}",
                        agent.agent_id, inner.reason
                    );
                }
                Ok(inner)
            }
            Err(status) => {
                error!("Failed to register agent {}: {}", agent.agent_id, status);
                Err(Error::Status(status))
            }
        }
    }

    /// Send heartbeat for an agent
    pub async fn heartbeat(
        &mut self,
        agent_id: &str,
        state: AgentState,
        health: Option<HashMap<String, String>>,
    ) -> Result<HeartbeatResponse> {
        debug!(
            "Sending heartbeat for agent: {} (state: {:?})",
            agent_id, state
        );

        let request = tonic::Request::new(HeartbeatRequest {
            agent_id: agent_id.to_string(),
            state: state as i32,
            health: health.unwrap_or_default(),
        });

        match self.client.heartbeat(request).await {
            Ok(response) => {
                let inner = response.into_inner();
                debug!("Heartbeat response for {}: ok={}", agent_id, inner.ok);
                Ok(inner)
            }
            Err(status) => {
                error!("Heartbeat failed for agent {}: {}", agent_id, status);
                Err(Error::Status(status))
            }
        }
    }

    /// Deregister an agent
    pub async fn deregister(
        &mut self,
        agent_id: &str,
        reason: Option<&str>,
    ) -> Result<DeregisterAgentResponse> {
        info!("Deregistering agent: {} (reason: {:?})", agent_id, reason);

        let request = tonic::Request::new(DeregisterAgentRequest {
            agent_id: agent_id.to_string(),
            reason: reason.unwrap_or("Normal shutdown").to_string(),
        });

        match self.client.deregister_agent(request).await {
            Ok(response) => {
                let inner = response.into_inner();
                if inner.ok {
                    info!("Agent {} deregistered successfully", agent_id);
                } else {
                    error!("Failed to deregister agent {}", agent_id);
                }
                Ok(inner)
            }
            Err(status) => {
                error!("Failed to deregister agent {}: {}", agent_id, status);
                Err(Error::Status(status))
            }
        }
    }

    /// Get the endpoint this client is connected to
    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }

    /// Check if the client connection is healthy (basic connectivity test)
    pub async fn health_check(&mut self) -> Result<bool> {
        debug!("Performing health check for registry client");

        // Try a simple heartbeat with a test agent to check connectivity
        match self
            .heartbeat("health-check", AgentState::Initializing, None)
            .await
        {
            Ok(_) => Ok(true),
            Err(Error::Status(status)) => {
                // Expect NOT_FOUND or similar for health check agent
                match status.code() {
                    tonic::Code::NotFound | tonic::Code::InvalidArgument => Ok(true),
                    _ => {
                        error!("Registry health check failed: {}", status);
                        Ok(false)
                    }
                }
            }
            Err(e) => {
                error!("Registry health check error: {}", e);
                Err(e)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::proto::sw4rm::common::CommunicationClass;

    #[tokio::test(flavor = "current_thread")]
    async fn test_registry_client_creation() {
        // Test that we can create the client struct
        let endpoint = "http://localhost:50051";
        let channel = Endpoint::from_static("http://localhost:50051").connect_lazy();
        let client = RegistryClient::with_channel(channel, endpoint.to_string());

        assert_eq!(client.endpoint(), endpoint);
    }

    #[test]
    fn test_agent_descriptor_conversion() {
        let agent = AgentDescriptor::new("test-agent".to_string(), "Test Agent".to_string());

        // Test that we can convert to proto format
        let proto_agent = ProtoAgentDescriptor {
            agent_id: agent.agent_id.clone(),
            name: agent.name.clone(),
            description: agent.description.clone(),
            capabilities: agent.capabilities.clone(),
            communication_class: CommunicationClass::Standard as i32,
            modalities_supported: vec!["application/json".to_string()],
            reasoning_connectors: Vec::new(),
            public_key: Vec::new(),
        };

        assert_eq!(proto_agent.agent_id, "test-agent");
        assert_eq!(proto_agent.name, "Test Agent");
    }
}
