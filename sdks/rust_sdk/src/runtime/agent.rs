use crate::envelope::EnvelopeData;
use crate::runtime::preemption::PreemptionManager;
use crate::config::AgentConfig;
use crate::clients::*;
use crate::{Error, Result};
use crate::proto::sw4rm::common::AgentState;
use async_trait::async_trait;
use std::collections::HashMap;
use tokio::sync::mpsc;
use tokio_stream::StreamExt;

/// Base trait for SW4RM agents
#[async_trait]
pub trait Agent: Send + Sync {
    /// Called when the agent starts up
    async fn on_startup(&mut self) -> Result<()> {
        Ok(())
    }

    /// Called when the agent shuts down
    async fn on_shutdown(&mut self) -> Result<()> {
        Ok(())
    }

    /// Handle incoming messages
    async fn on_message(&mut self, envelope: EnvelopeData) -> Result<()>;

    /// Handle control messages (preemption, shutdown, etc.)
    async fn on_control(&mut self, envelope: EnvelopeData) -> Result<()> {
        // Default implementation handles preemption requests
        if envelope.content_type == "application/json" {
            if let Ok(body) = envelope.json_payload::<HashMap<String, serde_json::Value>>() {
                if let Some(msg_type) = body.get("type").and_then(|v| v.as_str()) {
                    if msg_type == "PREEMPT_REQUEST" {
                        let reason = body.get("reason").and_then(|v| v.as_str());
                        tracing::info!("Preemption requested: {:?}", reason);
                        return Ok(());
                    }
                }
            }
        }
        Ok(())
    }

    /// Handle tool call messages
    async fn on_tool_call(&mut self, envelope: EnvelopeData) -> Result<()> {
        let _ = envelope; // Default: ignore tool calls
        Ok(())
    }

    /// Handle HITL messages
    async fn on_hitl(&mut self, envelope: EnvelopeData) -> Result<()> {
        let _ = envelope; // Default: ignore HITL
        Ok(())
    }

    /// Handle negotiation messages
    async fn on_negotiation(&mut self, envelope: EnvelopeData) -> Result<()> {
        let _ = envelope; // Default: ignore negotiation
        Ok(())
    }

    /// Get the agent's configuration
    fn config(&self) -> &AgentConfig;

    /// Get the preemption manager
    fn preemption_manager(&self) -> &PreemptionManager;
}

/// Runtime for executing SW4RM agents
pub struct AgentRuntime {
    config: AgentConfig,
    preemption: PreemptionManager,
    registry_client: Option<RegistryClient>,
    router_client: Option<RouterClient>,
    scheduler_client: Option<SchedulerClient>,
}

impl AgentRuntime {
    /// Create a new agent runtime
    pub fn new(config: AgentConfig) -> Self {
        Self {
            config,
            preemption: PreemptionManager::new(),
            registry_client: None,
            router_client: None,
            scheduler_client: None,
        }
    }

    /// Initialize the runtime by connecting to services
    pub async fn init(&mut self) -> Result<()> {
        // Connect to registry service
        self.registry_client = Some(
            RegistryClient::new(&self.config.endpoints.registry).await?
        );

        // Connect to router service
        self.router_client = Some(
            RouterClient::new(&self.config.endpoints.router).await?
        );

        // Connect to scheduler service
        self.scheduler_client = Some(
            SchedulerClient::new(&self.config.endpoints.scheduler).await?
        );

        tracing::info!("Agent runtime initialized for agent: {}", self.config.agent_id);
        Ok(())
    }

    /// Register the agent with the registry
    pub async fn register(&mut self) -> Result<()> {
        if let Some(client) = &mut self.registry_client {
            let descriptor = crate::types::AgentDescriptor {
                agent_id: self.config.agent_id.clone(),
                name: self.config.name.clone(),
                description: self.config.description.clone().unwrap_or_default(),
                version: self.config.version.clone(),
                capabilities: self.config.capabilities.clone(),
                metadata: self.config.metadata.clone(),
            };
            client.register(&descriptor).await?;
            tracing::info!("Agent registered: {}", self.config.agent_id);
        }
        Ok(())
    }

    /// Start the agent with message processing
    pub async fn run<A>(&mut self, mut agent: A) -> Result<()>
    where
        A: Agent + 'static,
    {
        // Initialize runtime
        self.init().await?;
        
        // Register agent
        self.register().await?;

        // Call startup hook
        agent.on_startup().await?;

        // Start message processing
        let (shutdown_tx, mut shutdown_rx) = mpsc::channel::<()>(1);

        // Start heartbeat task
        let heartbeat_handle = self.start_heartbeat_task();

        // Start message streaming
        let message_handle = self.start_message_processing(agent, shutdown_tx).await?;

        // Wait for shutdown signal
        tokio::select! {
            _ = shutdown_rx.recv() => {
                tracing::info!("Shutdown signal received");
            }
            _ = tokio::signal::ctrl_c() => {
                tracing::info!("Ctrl+C received, shutting down");
            }
        }

        // Cleanup
        heartbeat_handle.abort();
        message_handle.abort();

        // Deregister agent
        if let Some(client) = &mut self.registry_client {
            client.deregister(&self.config.agent_id, Some("Normal shutdown")).await?;
        }

        tracing::info!("Agent runtime stopped");
        Ok(())
    }

    /// Start heartbeat task
    fn start_heartbeat_task(&self) -> tokio::task::JoinHandle<()> {
        let agent_id = self.config.agent_id.clone();
        let interval_ms = self.config.heartbeat_interval_ms;
        let registry_endpoint = self.config.endpoints.registry.clone();

        tokio::spawn(async move {
            let mut interval = tokio::time::interval(
                std::time::Duration::from_millis(interval_ms)
            );

            loop {
                interval.tick().await;
                
                if let Ok(mut client) = RegistryClient::new(&registry_endpoint).await {
                    let health = HashMap::from([
                        ("status".to_string(), "healthy".to_string()),
                        ("timestamp".to_string(), crate::types::now_hlc_stub()),
                    ]);
                    
                    if let Err(e) = client.heartbeat(&agent_id, AgentState::Running, Some(health)).await {
                        tracing::warn!("Heartbeat failed: {}", e);
                    }
                }
            }
        })
    }

    /// Start message processing task
    async fn start_message_processing<A>(
        &mut self,
        mut agent: A,
        shutdown_tx: mpsc::Sender<()>,
    ) -> Result<tokio::task::JoinHandle<()>>
    where
        A: Agent + Send + 'static,
    {
        if let Some(router_client) = &mut self.router_client {
            let mut stream = router_client.stream_incoming(&self.config.agent_id).await?;
            
            let handle = tokio::spawn(async move {
                while let Some(envelope_result) = stream.next().await {
                    match envelope_result {
                        Ok(envelope) => {
                            if let Err(e) = Self::dispatch_message(&mut agent, envelope).await {
                                tracing::error!("Error processing message: {}", e);
                            }

                            // Check for preemption
                            if agent.preemption_manager().is_preemption_requested() {
                                tracing::info!("Preemption requested, shutting down");
                                let _ = shutdown_tx.send(()).await;
                                break;
                            }
                        }
                        Err(e) => {
                            tracing::error!("Stream error: {}", e);
                            break;
                        }
                    }
                }
                
                // Shutdown hook
                let _ = agent.on_shutdown().await;
            });

            Ok(handle)
        } else {
            Err(Error::Internal("Router client not initialized".to_string()))
        }
    }

    /// Dispatch message to appropriate handler
    async fn dispatch_message<A>(agent: &mut A, envelope: EnvelopeData) -> Result<()>
    where
        A: Agent,
    {
        use crate::proto::sw4rm::common::MessageType;
        
        match envelope.message_type {
            x if x == MessageType::Control as i32 => {
                agent.on_control(envelope).await
            }
            x if x == MessageType::Data as i32 => {
                agent.on_message(envelope).await
            }
            x if x == MessageType::ToolCall as i32 => {
                agent.on_tool_call(envelope).await
            }
            x if x == MessageType::HitlInvocation as i32 => {
                agent.on_hitl(envelope).await
            }
            x if x == MessageType::Negotiation as i32 => {
                agent.on_negotiation(envelope).await
            }
            _ => {
                tracing::warn!("Unknown message type: {}", envelope.message_type);
                agent.on_message(envelope).await
            }
        }
    }

    /// Get preemption manager
    pub fn preemption_manager(&self) -> &PreemptionManager {
        &self.preemption
    }

    /// Safe point for cooperative preemption
    pub fn safe_point(&self) -> bool {
        self.preemption.is_preemption_requested()
    }
}

/// Base implementation for simple agents
pub struct BaseAgent {
    config: AgentConfig,
    preemption: PreemptionManager,
}

impl BaseAgent {
    pub fn new(config: AgentConfig) -> Self {
        Self {
            config,
            preemption: PreemptionManager::new(),
        }
    }
}

#[async_trait]
impl Agent for BaseAgent {
    async fn on_message(&mut self, envelope: EnvelopeData) -> Result<()> {
        tracing::info!("Received message: {}", envelope.message_id);
        Ok(())
    }

    fn config(&self) -> &AgentConfig {
        &self.config
    }

    fn preemption_manager(&self) -> &PreemptionManager {
        &self.preemption
    }
}