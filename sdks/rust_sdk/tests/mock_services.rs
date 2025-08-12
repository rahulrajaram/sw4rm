//! Mock SW4RM services for integration testing

use sw4rm_sdk::proto::sw4rm;
use tonic::{transport::Server, Request, Response, Status};
use tokio::sync::mpsc;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::net::SocketAddr;

/// Mock registry service that tracks registered agents
#[derive(Debug, Default)]
pub struct MockRegistryService {
    agents: Arc<Mutex<HashMap<String, sw4rm::registry::AgentDescriptor>>>,
    heartbeats: Arc<Mutex<HashMap<String, Vec<sw4rm::registry::HeartbeatRequest>>>>,
}

impl MockRegistryService {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn get_registered_agents(&self) -> HashMap<String, sw4rm::registry::AgentDescriptor> {
        self.agents.lock().unwrap().clone()
    }

    pub fn get_heartbeats(&self, agent_id: &str) -> Vec<sw4rm::registry::HeartbeatRequest> {
        self.heartbeats
            .lock()
            .unwrap()
            .get(agent_id)
            .cloned()
            .unwrap_or_default()
    }
}

#[tonic::async_trait]
impl sw4rm::registry::registry_service_server::RegistryService for MockRegistryService {
    async fn register_agent(
        &self,
        request: Request<sw4rm::registry::RegisterAgentRequest>,
    ) -> Result<Response<sw4rm::registry::RegisterAgentResponse>, Status> {
        let req = request.into_inner();
        
        if let Some(agent) = req.agent {
            println!("Mock Registry: Registering agent {} ({})", agent.agent_id, agent.name);
            
            // Simulate validation
            if agent.agent_id.is_empty() || agent.name.is_empty() {
                return Ok(Response::new(sw4rm::registry::RegisterAgentResponse {
                    accepted: false,
                    reason: "Agent ID and name are required".to_string(),
                }));
            }

            // Store agent
            self.agents.lock().unwrap().insert(agent.agent_id.clone(), agent);

            Ok(Response::new(sw4rm::registry::RegisterAgentResponse {
                accepted: true,
                reason: "Agent registered successfully".to_string(),
            }))
        } else {
            Ok(Response::new(sw4rm::registry::RegisterAgentResponse {
                accepted: false,
                reason: "No agent descriptor provided".to_string(),
            }))
        }
    }

    async fn heartbeat(
        &self,
        request: Request<sw4rm::registry::HeartbeatRequest>,
    ) -> Result<Response<sw4rm::registry::HeartbeatResponse>, Status> {
        let req = request.into_inner();
        
        println!("Mock Registry: Heartbeat from agent {} (state: {})", req.agent_id, req.state);
        
        // Check if agent is registered
        let agents = self.agents.lock().unwrap();
        if !agents.contains_key(&req.agent_id) {
            return Ok(Response::new(sw4rm::registry::HeartbeatResponse { ok: false }));
        }

        // Store heartbeat
        let mut heartbeats = self.heartbeats.lock().unwrap();
        heartbeats.entry(req.agent_id.clone()).or_insert_with(Vec::new).push(req);

        Ok(Response::new(sw4rm::registry::HeartbeatResponse { ok: true }))
    }

    async fn deregister_agent(
        &self,
        request: Request<sw4rm::registry::DeregisterAgentRequest>,
    ) -> Result<Response<sw4rm::registry::DeregisterAgentResponse>, Status> {
        let req = request.into_inner();
        
        println!("Mock Registry: Deregistering agent {} (reason: {})", req.agent_id, req.reason);
        
        let was_registered = self.agents.lock().unwrap().remove(&req.agent_id).is_some();
        
        Ok(Response::new(sw4rm::registry::DeregisterAgentResponse {
            ok: was_registered,
        }))
    }
}

/// Mock router service that handles message routing
#[derive(Debug)]
pub struct MockRouterService {
    messages: Arc<Mutex<Vec<sw4rm::common::Envelope>>>,
    streams: Arc<Mutex<HashMap<String, mpsc::UnboundedSender<sw4rm::router::StreamItem>>>>,
}

impl MockRouterService {
    pub fn new() -> Self {
        Self {
            messages: Arc::new(Mutex::new(Vec::new())),
            streams: Arc::new(Mutex::new(HashMap::new())),
        }
    }

    pub fn get_messages(&self) -> Vec<sw4rm::common::Envelope> {
        self.messages.lock().unwrap().clone()
    }

    pub fn send_test_message_to_agent(&self, agent_id: &str, envelope: sw4rm::common::Envelope) {
        let streams = self.streams.lock().unwrap();
        if let Some(sender) = streams.get(agent_id) {
            let stream_item = sw4rm::router::StreamItem { msg: Some(envelope) };
            let _ = sender.send(stream_item);
        }
    }
}

#[tonic::async_trait]
impl sw4rm::router::router_service_server::RouterService for MockRouterService {
    async fn send_message(
        &self,
        request: Request<sw4rm::router::SendMessageRequest>,
    ) -> Result<Response<sw4rm::router::SendMessageResponse>, Status> {
        let req = request.into_inner();
        
        if let Some(envelope) = req.msg {
            println!("Mock Router: Received message {} from {}", 
                    envelope.message_id, envelope.producer_id);
            
            // Store message
            self.messages.lock().unwrap().push(envelope.clone());

            // Simulate message routing - echo back to sender for testing
            self.send_test_message_to_agent(&envelope.producer_id, envelope);

            Ok(Response::new(sw4rm::router::SendMessageResponse {
                accepted: true,
                reason: "Message accepted for routing".to_string(),
            }))
        } else {
            Ok(Response::new(sw4rm::router::SendMessageResponse {
                accepted: false,
                reason: "No message provided".to_string(),
            }))
        }
    }

    type StreamIncomingStream = mpsc::UnboundedReceiver<Result<sw4rm::router::StreamItem, Status>>;

    async fn stream_incoming(
        &self,
        request: Request<sw4rm::router::StreamRequest>,
    ) -> Result<Response<Self::StreamIncomingStream>, Status> {
        let req = request.into_inner();
        let agent_id = req.agent_id;
        
        println!("Mock Router: Starting stream for agent {}", agent_id);
        
        let (tx, rx) = mpsc::unbounded_channel();
        
        // Convert sender to handle Result<StreamItem, Status>
        let (result_tx, result_rx) = mpsc::unbounded_channel();
        
        tokio::spawn(async move {
            let mut receiver = rx;
            while let Some(item) = receiver.recv().await {
                if result_tx.send(Ok(item)).is_err() {
                    break;
                }
            }
        });

        // Store the sender for this agent
        self.streams.lock().unwrap().insert(agent_id, tx);

        Ok(Response::new(result_rx))
    }
}

/// Integration test server that hosts mock services
pub struct MockServer {
    addr: SocketAddr,
    shutdown_tx: Option<tokio::sync::oneshot::Sender<()>>,
}

impl MockServer {
    pub async fn start() -> Result<Self, Box<dyn std::error::Error + Send + Sync>> {
        let registry_service = MockRegistryService::new();
        let router_service = MockRouterService::new();

        let addr = "127.0.0.1:0".parse()?;
        let listener = tokio::net::TcpListener::bind(addr).await?;
        let addr = listener.local_addr()?;

        let (shutdown_tx, shutdown_rx) = tokio::sync::oneshot::channel();

        let server = Server::builder()
            .add_service(sw4rm::registry::registry_service_server::RegistryServiceServer::new(registry_service))
            .add_service(sw4rm::router::router_service_server::RouterServiceServer::new(router_service))
            .serve_with_incoming_shutdown(
                tokio_stream::wrappers::TcpListenerStream::new(listener),
                async {
                    shutdown_rx.await.ok();
                    println!("Mock server shutting down");
                }
            );

        tokio::spawn(server);

        // Wait a bit for server to start
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;

        println!("Mock SW4RM server started on {}", addr);

        Ok(Self {
            addr,
            shutdown_tx: Some(shutdown_tx),
        })
    }

    pub fn endpoint(&self) -> String {
        format!("http://{}", self.addr)
    }

    pub fn registry_endpoint(&self) -> String {
        self.endpoint()
    }

    pub fn router_endpoint(&self) -> String {
        self.endpoint()
    }

    pub async fn shutdown(mut self) {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(());
        }
        // Give server time to shutdown gracefully
        tokio::time::sleep(tokio::time::Duration::from_millis(100)).await;
    }
}

impl Drop for MockServer {
    fn drop(&mut self) {
        if let Some(tx) = self.shutdown_tx.take() {
            let _ = tx.send(());
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sw4rm_sdk::clients::{RegistryClient, RouterClient};
    use sw4rm_sdk::types::AgentDescriptor;
    use sw4rm_sdk::envelope::EnvelopeBuilder;
    use sw4rm_sdk::constants;

    #[tokio::test]
    async fn test_mock_registry_service() {
        let mock_server = MockServer::start().await.unwrap();
        
        let mut client = RegistryClient::new(&mock_server.registry_endpoint())
            .await
            .unwrap();

        // Test agent registration
        let agent = AgentDescriptor::new(
            "test-agent-mock".to_string(),
            "Mock Test Agent".to_string()
        );

        let response = client.register(&agent).await.unwrap();
        assert!(response.accepted);
        assert_eq!(response.reason, "Agent registered successfully");

        // Test heartbeat
        let heartbeat_response = client.heartbeat(
            "test-agent-mock",
            sw4rm_sdk::proto::sw4rm::common::AgentState::Running,
            None
        ).await.unwrap();
        assert!(heartbeat_response.ok);

        // Test deregistration
        let dereg_response = client.deregister("test-agent-mock", Some("Test complete")).await.unwrap();
        assert!(dereg_response.ok);

        mock_server.shutdown().await;
    }

    #[tokio::test]
    async fn test_mock_router_service() {
        let mock_server = MockServer::start().await.unwrap();
        
        let mut client = RouterClient::new(&mock_server.router_endpoint())
            .await
            .unwrap();

        // Test message sending
        let envelope = EnvelopeBuilder::new(
            "test-producer".to_string(),
            constants::message_type::DATA
        )
        .with_json_payload(&serde_json::json!({"test": "router message"}))
        .unwrap()
        .build();

        let send_result = client.send_message(&envelope).await.unwrap();
        assert!(send_result.accepted);
        assert_eq!(send_result.reason, "Message accepted for routing");

        mock_server.shutdown().await;
    }

    #[tokio::test] 
    async fn test_end_to_end_with_mock_services() {
        let mock_server = MockServer::start().await.unwrap();
        
        // Create clients
        let mut registry_client = RegistryClient::new(&mock_server.registry_endpoint()).await.unwrap();
        let mut router_client = RouterClient::new(&mock_server.router_endpoint()).await.unwrap();

        // Register agent
        let agent = AgentDescriptor::new(
            "e2e-test-agent".to_string(),
            "End-to-End Test Agent".to_string()
        );

        let reg_response = registry_client.register(&agent).await.unwrap();
        assert!(reg_response.accepted);

        // Send heartbeat
        let hb_response = registry_client.heartbeat(
            "e2e-test-agent",
            sw4rm_sdk::proto::sw4rm::common::AgentState::Running,
            Some(std::collections::HashMap::from([
                ("status".to_string(), "healthy".to_string())
            ]))
        ).await.unwrap();
        assert!(hb_response.ok);

        // Send test message
        let test_message = EnvelopeBuilder::new(
            "e2e-test-agent".to_string(),
            constants::message_type::DATA
        )
        .with_json_payload(&serde_json::json!({
            "message": "End-to-end test message",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }))
        .unwrap()
        .build();

        let send_result = router_client.send_message(&test_message).await.unwrap();
        assert!(send_result.accepted);

        // Clean up
        let dereg_response = registry_client.deregister("e2e-test-agent", Some("Test complete")).await.unwrap();
        assert!(dereg_response.ok);

        mock_server.shutdown().await;
    }
}