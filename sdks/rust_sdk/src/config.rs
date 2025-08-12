use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Configuration for SW4RM service endpoints
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Endpoints {
    pub registry: String,
    pub router: String,
    pub scheduler: String,
    pub hitl: String,
    pub worktree: String,
    pub tool: String,
    pub connector: String,
    pub negotiation: String,
    pub reasoning: String,
    pub logging: String,
}

impl Default for Endpoints {
    fn default() -> Self {
        Self {
            registry: "http://localhost:50051".to_string(),
            router: "http://localhost:50052".to_string(),
            scheduler: "http://localhost:50053".to_string(),
            hitl: "http://localhost:50054".to_string(),
            worktree: "http://localhost:50055".to_string(),
            tool: "http://localhost:50056".to_string(),
            connector: "http://localhost:50057".to_string(),
            negotiation: "http://localhost:50058".to_string(),
            reasoning: "http://localhost:50059".to_string(),
            logging: "http://localhost:50060".to_string(),
        }
    }
}

/// Agent configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AgentConfig {
    pub agent_id: String,
    pub name: String,
    pub description: Option<String>,
    pub version: String,
    pub capabilities: Vec<String>,
    pub endpoints: Endpoints,
    pub metadata: HashMap<String, String>,
    pub timeout_ms: u64,
    pub retry_attempts: u32,
    pub heartbeat_interval_ms: u64,
}

impl AgentConfig {
    pub fn new(agent_id: String, name: String) -> Self {
        Self {
            agent_id,
            name,
            description: None,
            version: "0.1.0".to_string(),
            capabilities: Vec::new(),
            endpoints: Endpoints::default(),
            metadata: HashMap::new(),
            timeout_ms: 30000,
            retry_attempts: 3,
            heartbeat_interval_ms: 30000,
        }
    }

    pub fn with_description(mut self, description: String) -> Self {
        self.description = Some(description);
        self
    }

    pub fn with_capabilities(mut self, capabilities: Vec<String>) -> Self {
        self.capabilities = capabilities;
        self
    }

    pub fn with_endpoints(mut self, endpoints: Endpoints) -> Self {
        self.endpoints = endpoints;
        self
    }

    pub fn with_metadata(mut self, metadata: HashMap<String, String>) -> Self {
        self.metadata = metadata;
        self
    }
}