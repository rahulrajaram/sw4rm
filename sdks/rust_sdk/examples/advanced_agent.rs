// Copyright 2025 Rahul Rajaram
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Advanced Agent Example
//!
//! Demonstrates advanced SW4RM protocol features:
//! - ActivityBuffer for message tracking
//! - Worktree state management
//! - ACK lifecycle handling
//! - Tool call processing
//! - HITL message handling
//! - Negotiation participation

use serde_json::json;
use std::collections::HashMap;
use std::time::Duration;
use sw4rm_sdk::activity_buffer::PersistentActivityBuffer;
use sw4rm_sdk::prelude::*;
use sw4rm_sdk::worktree_state::WorktreeState;
use tokio::time::sleep;

/// Advanced agent with full protocol feature support
struct AdvancedAgent {
    config: AgentConfig,
    preemption: PreemptionManager,
    activity_buffer: PersistentActivityBuffer,
    worktree_state: WorktreeState,
    message_count: u64,
    tool_calls_processed: u64,
    active_negotiations: HashMap<String, NegotiationState>,
}

/// Track negotiation state for this agent
#[derive(Debug, Clone)]
#[allow(dead_code)]
struct NegotiationState {
    negotiation_id: String,
    role: NegotiationRole,
    topic: String,
    proposals_made: u32,
    evaluations_received: u32,
}

#[derive(Debug, Clone, PartialEq)]
#[allow(dead_code)]
enum NegotiationRole {
    Proposer,
    Evaluator,
    Coordinator,
}

impl AdvancedAgent {
    fn new(config: AgentConfig) -> Result<Self> {
        // Create activity buffer with 500 message capacity
        let activity_buffer = PersistentActivityBuffer::new(500, None)?;

        Ok(Self {
            config,
            preemption: PreemptionManager::new(),
            activity_buffer,
            worktree_state: WorktreeState::new(),
            message_count: 0,
            tool_calls_processed: 0,
            active_negotiations: HashMap::new(),
        })
    }

    /// Record a message in the activity buffer
    fn record_message(&self, envelope: &EnvelopeData, direction: &str) {
        let record = json!({
            "message_id": envelope.message_id,
            "producer_id": envelope.producer_id,
            "message_type": envelope.message_type,
            "content_type": envelope.content_type,
            "timestamp": chrono::Utc::now().to_rfc3339(),
        });

        let result = if direction == "incoming" {
            self.activity_buffer.record_incoming(record)
        } else {
            self.activity_buffer.record_outgoing(record)
        };

        if let Err(e) = result {
            tracing::warn!("Failed to record message: {}", e);
        }
    }

    /// Process tool execution request
    async fn execute_tool(&mut self, tool_name: &str, params: &serde_json::Value) -> Result<serde_json::Value> {
        tracing::info!("Executing tool: {} with params: {}", tool_name, params);

        // Simulate tool execution based on tool name
        match tool_name {
            "get_status" => {
                Ok(json!({
                    "status": "running",
                    "agent_id": self.config.agent_id,
                    "messages_processed": self.message_count,
                    "tool_calls": self.tool_calls_processed,
                    "active_negotiations": self.active_negotiations.len(),
                }))
            }
            "analyze_code" => {
                // Simulate code analysis
                sleep(Duration::from_millis(200)).await;
                Ok(json!({
                    "result": "analysis_complete",
                    "issues_found": 0,
                    "suggestions": ["Consider adding more tests"],
                }))
            }
            "search_files" => {
                let pattern = params.get("pattern").and_then(|v| v.as_str()).unwrap_or("*");
                Ok(json!({
                    "pattern": pattern,
                    "matches": ["file1.rs", "file2.rs"],
                    "count": 2,
                }))
            }
            _ => {
                tracing::warn!("Unknown tool: {}", tool_name);
                Ok(json!({
                    "error": "unknown_tool",
                    "tool_name": tool_name,
                }))
            }
        }
    }

    /// Handle HITL decision request
    async fn process_hitl_request(&mut self, envelope: &EnvelopeData) -> Result<()> {
        if let Ok(request) = envelope.json_payload::<serde_json::Value>() {
            let decision_id = request.get("decision_id").and_then(|v| v.as_str()).unwrap_or("unknown");
            let question = request.get("question").and_then(|v| v.as_str()).unwrap_or("");

            tracing::info!("HITL decision requested: {} - {}", decision_id, question);

            // In a real scenario, this would wait for human input
            // Here we simulate by logging and returning
            tracing::info!("HITL request logged for human review: {}", decision_id);
        }
        Ok(())
    }

    /// Join a negotiation session
    fn join_negotiation(&mut self, negotiation_id: &str, role: NegotiationRole, topic: &str) {
        let state = NegotiationState {
            negotiation_id: negotiation_id.to_string(),
            role: role.clone(),
            topic: topic.to_string(),
            proposals_made: 0,
            evaluations_received: 0,
        };

        tracing::info!(
            "Joining negotiation {} as {:?} for topic: {}",
            negotiation_id,
            role,
            topic
        );

        self.active_negotiations.insert(negotiation_id.to_string(), state);
    }

    /// Process negotiation message
    async fn process_negotiation(&mut self, envelope: &EnvelopeData) -> Result<()> {
        if let Ok(msg) = envelope.json_payload::<serde_json::Value>() {
            let negotiation_id = msg.get("negotiation_id").and_then(|v| v.as_str()).unwrap_or("");
            let msg_type = msg.get("type").and_then(|v| v.as_str()).unwrap_or("");

            tracing::info!("Negotiation message: {} - type: {}", negotiation_id, msg_type);

            match msg_type {
                "OPEN" => {
                    let topic = msg.get("topic").and_then(|v| v.as_str()).unwrap_or("");
                    self.join_negotiation(negotiation_id, NegotiationRole::Evaluator, topic);
                }
                "PROPOSAL" => {
                    if let Some(state) = self.active_negotiations.get_mut(negotiation_id) {
                        if state.role == NegotiationRole::Evaluator {
                            // Evaluate the proposal
                            let confidence = 0.85;
                            tracing::info!(
                                "Evaluating proposal in {} with confidence: {}",
                                negotiation_id,
                                confidence
                            );
                            state.evaluations_received += 1;
                        }
                    }
                }
                "DECISION" => {
                    if let Some(state) = self.active_negotiations.remove(negotiation_id) {
                        tracing::info!(
                            "Negotiation {} concluded. Made {} proposals, received {} evaluations",
                            negotiation_id,
                            state.proposals_made,
                            state.evaluations_received
                        );
                    }
                }
                _ => {
                    tracing::debug!("Unhandled negotiation message type: {}", msg_type);
                }
            }
        }
        Ok(())
    }

    /// Print agent status summary
    fn print_status(&self) {
        tracing::info!("=== Agent Status ===");
        tracing::info!("Agent ID: {}", self.config.agent_id);
        tracing::info!("Messages processed: {}", self.message_count);
        tracing::info!("Tool calls: {}", self.tool_calls_processed);
        tracing::info!("Active negotiations: {}", self.active_negotiations.len());

        if let Some((repo, tree)) = self.worktree_state.current() {
            tracing::info!("Worktree: {}/{}", repo, tree);
        } else {
            tracing::info!("Worktree: unbound");
        }

        if let Ok(unacked) = self.activity_buffer.unacked() {
            tracing::info!("Unacked messages: {}", unacked.len());
        }
    }
}

#[async_trait]
impl Agent for AdvancedAgent {
    async fn on_startup(&mut self) -> Result<()> {
        tracing::info!("Advanced agent starting: {}", self.config.agent_id);

        // Bind to a demo worktree
        self.worktree_state.bind("demo-repo".to_string(), "main".to_string());

        if let Some((repo, tree)) = self.worktree_state.current() {
            tracing::info!("Bound to worktree: {}/{}", repo, tree);
        }

        Ok(())
    }

    async fn on_shutdown(&mut self) -> Result<()> {
        tracing::info!("Advanced agent shutting down: {}", self.config.agent_id);
        self.print_status();

        // Flush activity buffer
        if let Err(e) = self.activity_buffer.flush() {
            tracing::warn!("Failed to flush activity buffer: {}", e);
        }

        // Unbind worktree
        self.worktree_state.unbind();

        Ok(())
    }

    async fn on_message(&mut self, envelope: EnvelopeData) -> Result<()> {
        self.message_count += 1;
        self.record_message(&envelope, "incoming");

        tracing::info!(
            "Message #{}: {} (type: {})",
            self.message_count,
            envelope.message_id,
            envelope.message_type
        );

        // Check for preemption
        if self.preemption.is_preemption_requested() {
            tracing::warn!("Preemption requested, deferring message processing");
            return Ok(());
        }

        // Process based on content
        if envelope.content_type == "application/json" {
            if let Ok(data) = envelope.json_payload::<serde_json::Value>() {
                tracing::info!("Payload: {}", data);
            }
        }

        Ok(())
    }

    async fn on_control(&mut self, envelope: EnvelopeData) -> Result<()> {
        tracing::info!("Control message: {}", envelope.message_id);

        if envelope.content_type == "application/json" {
            if let Ok(body) = envelope.json_payload::<serde_json::Value>() {
                if let Some(msg_type) = body.get("type").and_then(|v| v.as_str()) {
                    match msg_type {
                        "PREEMPT_REQUEST" => {
                            let reason = body
                                .get("reason")
                                .and_then(|v| v.as_str())
                                .map(|s| s.to_string());
                            tracing::warn!("Preemption requested: {:?}", reason);
                            self.preemption.request_preemption(reason);
                        }
                        "STATUS_REQUEST" => {
                            self.print_status();
                        }
                        "BIND_WORKTREE" => {
                            if let (Some(repo), Some(tree)) = (
                                body.get("repo").and_then(|v| v.as_str()),
                                body.get("tree").and_then(|v| v.as_str()),
                            ) {
                                self.worktree_state.bind(repo.to_string(), tree.to_string());
                                tracing::info!("Bound to worktree: {}/{}", repo, tree);
                            }
                        }
                        _ => {
                            tracing::debug!("Unhandled control type: {}", msg_type);
                        }
                    }
                }
            }
        }

        Ok(())
    }

    async fn on_tool_call(&mut self, envelope: EnvelopeData) -> Result<()> {
        self.tool_calls_processed += 1;
        tracing::info!("Tool call #{}: {}", self.tool_calls_processed, envelope.message_id);

        if let Ok(call_data) = envelope.json_payload::<serde_json::Value>() {
            if let Some(tool_name) = call_data.get("tool_name").and_then(|v| v.as_str()) {
                let params = call_data.get("parameters").cloned().unwrap_or(json!({}));
                let result = self.execute_tool(tool_name, &params).await?;
                tracing::info!("Tool result: {}", result);
            }
        }

        Ok(())
    }

    async fn on_hitl(&mut self, envelope: EnvelopeData) -> Result<()> {
        tracing::info!("HITL message: {}", envelope.message_id);
        self.process_hitl_request(&envelope).await
    }

    async fn on_negotiation(&mut self, envelope: EnvelopeData) -> Result<()> {
        tracing::info!("Negotiation message: {}", envelope.message_id);
        self.process_negotiation(&envelope).await
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
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_target(false)
        .with_thread_ids(true)
        .with_level(true)
        .init();

    tracing::info!("SW4RM Advanced Agent Demo");
    tracing::info!("SDK Version: {}", sw4rm_sdk::VERSION);

    // Create agent configuration
    let agent_id = format!("advanced-agent-{}", new_uuid().split('-').next().unwrap());
    let config = AgentConfig::new(agent_id.clone(), "SW4RM Advanced Agent".to_string())
        .with_description("An advanced demonstration agent with full protocol support".to_string())
        .with_capabilities(vec![
            "message_processing".to_string(),
            "tool_execution".to_string(),
            "negotiation".to_string(),
            "hitl_handling".to_string(),
            "worktree_management".to_string(),
        ]);

    tracing::info!("Agent ID: {}", agent_id);
    tracing::info!("Capabilities: {:?}", config.capabilities);

    // Create agent
    let mut agent = AdvancedAgent::new(config.clone())?;

    // Simulate agent lifecycle
    agent.on_startup().await?;

    // Create and process test messages
    tracing::info!("Processing test messages...");

    // Test DATA message
    let data_envelope = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::DATA)
        .with_json_payload(&json!({
            "task": "analyze_code",
            "target": "src/main.rs",
        }))
        .unwrap()
        .build();
    agent.on_message(data_envelope).await?;

    // Test TOOL_CALL message
    let tool_envelope = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::TOOL_CALL)
        .with_json_payload(&json!({
            "tool_name": "get_status",
            "call_id": new_uuid(),
            "parameters": {},
        }))
        .unwrap()
        .build();
    agent.on_tool_call(tool_envelope).await?;

    // Test NEGOTIATION message
    let negotiation_envelope = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::NEGOTIATION)
        .with_json_payload(&json!({
            "negotiation_id": new_uuid(),
            "type": "OPEN",
            "topic": "code_review",
            "participants": ["agent-1", "agent-2"],
        }))
        .unwrap()
        .build();
    agent.on_negotiation(negotiation_envelope).await?;

    // Test CONTROL message
    let control_envelope = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::CONTROL)
        .with_json_payload(&json!({
            "type": "STATUS_REQUEST",
        }))
        .unwrap()
        .build();
    agent.on_control(control_envelope).await?;

    // Shutdown
    agent.on_shutdown().await?;

    tracing::info!("Advanced agent demo completed!");
    Ok(())
}
