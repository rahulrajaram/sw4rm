use serde_json::json;
use std::time::Duration;
use sw4rm_sdk::prelude::*;
use tokio::time::sleep;

/// Simple echo agent that demonstrates SW4RM protocol usage
struct EchoAgent {
    config: AgentConfig,
    preemption: PreemptionManager,
    message_count: u64,
}

impl EchoAgent {
    fn new(config: AgentConfig) -> Self {
        Self {
            config,
            preemption: PreemptionManager::new(),
            message_count: 0,
        }
    }
}

#[async_trait]
impl Agent for EchoAgent {
    async fn on_startup(&mut self) -> Result<()> {
        tracing::info!("🚀 Echo agent starting: {}", self.config.agent_id);
        tracing::info!("Agent capabilities: {:?}", self.config.capabilities);
        Ok(())
    }

    async fn on_shutdown(&mut self) -> Result<()> {
        tracing::info!(
            "🛑 Echo agent shutting down: {} (processed {} messages)",
            self.config.agent_id,
            self.message_count
        );
        Ok(())
    }

    async fn on_message(&mut self, envelope: EnvelopeData) -> Result<()> {
        self.message_count += 1;

        tracing::info!(
            "📨 Message #{} received: {} (type: {})",
            self.message_count,
            envelope.message_id,
            envelope.message_type
        );

        // Check for preemption at safe points
        if self.preemption.is_preemption_requested() {
            tracing::warn!("⚠️ Preemption requested, stopping message processing");
            return Ok(());
        }

        // Process message based on content type
        match envelope.content_type.as_str() {
            "application/json" => {
                match envelope.json_payload::<serde_json::Value>() {
                    Ok(data) => {
                        tracing::info!("📄 JSON payload: {}", data);

                        // Echo back the data with additional info
                        let echo_data = json!({
                            "echo": data,
                            "processed_by": self.config.agent_id,
                            "message_count": self.message_count,
                            "timestamp": chrono::Utc::now().to_rfc3339()
                        });

                        tracing::info!("🔄 Echoing: {}", echo_data);
                    }
                    Err(e) => {
                        tracing::error!("❌ Failed to parse JSON payload: {}", e);
                    }
                }
            }
            _ => match envelope.string_payload() {
                Ok(text) => {
                    tracing::info!("📝 Text payload: {}", text);
                    tracing::info!("🔄 Echoing: {}", text);
                }
                Err(e) => {
                    tracing::warn!("⚠️ Failed to decode payload as text: {}", e);
                    tracing::info!("🔢 Raw payload ({} bytes)", envelope.payload.len());
                }
            },
        }

        // Simulate processing time
        sleep(Duration::from_millis(100)).await;

        tracing::info!("✅ Message processed successfully");
        Ok(())
    }

    async fn on_control(&mut self, envelope: EnvelopeData) -> Result<()> {
        tracing::info!("🎛️ Control message: {}", envelope.message_id);

        if envelope.content_type == "application/json" {
            if let Ok(body) = envelope.json_payload::<serde_json::Value>() {
                if let Some(msg_type) = body.get("type").and_then(|v| v.as_str()) {
                    match msg_type {
                        "PREEMPT_REQUEST" => {
                            let reason = body
                                .get("reason")
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_string());

                            tracing::warn!("🛑 Preemption requested: {:?}", reason);
                            self.preemption.request_preemption(reason);
                        }
                        "SHUTDOWN" => {
                            tracing::warn!("🔚 Shutdown requested");
                            self.preemption
                                .request_preemption(Some("Shutdown requested".to_string()));
                        }
                        "PING" => {
                            tracing::info!("🏓 Ping received - agent is alive!");
                        }
                        _ => {
                            tracing::info!("❓ Unknown control message type: {}", msg_type);
                        }
                    }
                }
            }
        }

        Ok(())
    }

    async fn on_tool_call(&mut self, envelope: EnvelopeData) -> Result<()> {
        tracing::info!("🔧 Tool call received: {}", envelope.message_id);

        if let Ok(call_data) = envelope.json_payload::<serde_json::Value>() {
            if let Some(tool_name) = call_data.get("tool_name").and_then(|v| v.as_str()) {
                tracing::info!("🛠️ Tool: {}", tool_name);

                match tool_name {
                    "echo" => {
                        let empty = json!({});
                        let params_ref = call_data.get("parameters").unwrap_or(&empty);
                        tracing::info!("🔄 Echo tool called with params: {}", params_ref);
                    }
                    "status" => {
                        let status = json!({
                            "agent_id": self.config.agent_id,
                            "messages_processed": self.message_count,
                            "uptime": "running",
                            "capabilities": self.config.capabilities
                        });
                        tracing::info!("📊 Agent status: {}", status);
                    }
                    _ => {
                        tracing::warn!("❓ Unknown tool: {}", tool_name);
                    }
                }
            }
        }

        Ok(())
    }

    fn config(&self) -> &AgentConfig {
        &self.config
    }

    fn preemption_manager(&self) -> &PreemptionManager {
        &self.preemption
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing with colored output
    tracing_subscriber::fmt()
        .with_target(false)
        .with_thread_ids(true)
        .with_level(true)
        .init();

    tracing::info!("🎯 SW4RM Echo Agent Demo");
    tracing::info!("📦 SDK Version: {}", sw4rm_sdk::VERSION);

    // Create agent configuration
    let agent_id = format!("echo-agent-{}", new_uuid().split('-').next().unwrap());
    let config = AgentConfig::new(agent_id.clone(), "SW4RM Echo Agent".to_string())
        .with_description("A demonstration echo agent for the SW4RM Agentic Protocol".to_string())
        .with_capabilities(vec![
            "echo".to_string(),
            "message_processing".to_string(),
            "tool_execution".to_string(),
            "status_reporting".to_string(),
        ]);

    tracing::info!("🆔 Agent ID: {}", agent_id);
    tracing::info!("🔧 Capabilities: {:?}", config.capabilities);

    // Create agent with activity tracking
    let agent = EchoAgent::new(config.clone());

    // Note: Since we don't have actual gRPC services running, we'll demonstrate
    // the SDK components working together locally
    tracing::info!("🏗️ Demonstrating SDK components...");

    // Test envelope creation
    let test_envelope = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::DATA)
        .with_json_payload(&json!({
            "message": "Hello SW4RM!",
            "timestamp": chrono::Utc::now().to_rfc3339(),
            "from": "test_client"
        }))
        .unwrap()
        .build();

    tracing::info!("📤 Created test envelope: {}", test_envelope.message_id);

    // Test activity buffer
    let _activity_buffer = sw4rm_sdk::activity_buffer::ActivityBuffer::new(100);
    tracing::info!("📊 Activity buffer initialized with capacity 100");

    // Test worktree state
    let mut worktree_state = sw4rm_sdk::worktree_state::WorktreeState::new();
    worktree_state.bind("demo-repo".to_string(), "main-worktree".to_string());
    if let Some((repo, tree)) = worktree_state.current() {
        tracing::info!("🌳 Worktree bound to: {}/{}", repo, tree);
    }

    // Test ACK generation
    let ack_envelope = sw4rm_sdk::acks::build_ack_envelope(
        agent_id.clone(),
        test_envelope.message_id.clone(),
        constants::ack_stage::RECEIVED,
        None,
        Some("Message received successfully".to_string()),
        None,
        None,
    )?;

    tracing::info!("✅ Generated ACK: {}", ack_envelope.message_id);

    // Simulate message processing
    tracing::info!("🔄 Simulating message processing...");
    let mut demo_agent = agent;

    // Process the test message
    demo_agent.on_message(test_envelope).await?;

    // Process a control message
    let control_envelope = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::CONTROL)
        .with_json_payload(&json!({
            "type": "PING",
            "timestamp": chrono::Utc::now().to_rfc3339()
        }))
        .unwrap()
        .build();

    demo_agent.on_control(control_envelope).await?;

    // Process a tool call
    let tool_envelope = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::TOOL_CALL)
        .with_json_payload(&json!({
            "tool_name": "status",
            "call_id": new_uuid(),
            "parameters": {}
        }))
        .unwrap()
        .build();

    demo_agent.on_tool_call(tool_envelope).await?;

    tracing::info!("🎉 Demo completed successfully!");
    tracing::info!("📈 Agent processed {} messages", demo_agent.message_count);

    // Show final status
    demo_agent.on_shutdown().await?;

    tracing::info!("🏁 SW4RM Echo Agent Demo finished");
    Ok(())
}
