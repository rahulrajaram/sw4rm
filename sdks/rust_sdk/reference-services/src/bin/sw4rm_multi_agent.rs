//! SW4RM Multi-Agent Collaboration Example with Real gRPC Services.
//!
//! This example demonstrates the COMPLETE SW4RM protocol connecting to real
//! gRPC services (Router, Registry, Scheduler).
//!
//! REQUIREMENTS:
//!   Start the gRPC servers first:
//!     ./start_services.sh
//!
//! USAGE:
//!   cargo run --bin sw4rm-multi-agent              # LLM verify + multi-agent
//!   cargo run --bin sw4rm-multi-agent -- --llm-only   # Just LLM verification
//!   cargo run --bin sw4rm-multi-agent -- --verbose    # With debug logging
//!
//! AGENTS:
//!   - Coordinator: Orchestrates workflow, manages negotiations
//!   - SecurityAnalyst: Security-focused code review
//!   - QualityAnalyst: Code quality review
//!   - Critic: Senior reviewer, aggregates findings

use anyhow::{Context, Result};
use async_trait::async_trait;
use clap::Parser;
use futures::StreamExt;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::{oneshot, Mutex, RwLock};
use tokio_stream::Stream;
use tracing::{debug, error, info, warn};
use uuid::Uuid;

use sw4rm_sdk::clients::negotiation_room::{
    AggregatedScore, ArtifactType, DecisionOutcome, NegotiationDecision, NegotiationProposal,
    NegotiationRoomClient, NegotiationVote,
};
use sw4rm_sdk::clients::{RegistryClient, RouterClient, SchedulerClient};
use sw4rm_sdk::constants::message_type;
use sw4rm_sdk::envelope::{EnvelopeBuilder, EnvelopeData};
use sw4rm_sdk::proto::sw4rm::common::AgentState;
use sw4rm_sdk::types::AgentDescriptor;

// =============================================================================
// LLM CLIENT
// =============================================================================

/// Response from the LLM API.
#[derive(Debug, Clone)]
pub struct LLMResponse {
    pub content: String,
    pub usage: Option<LLMUsage>,
}

/// Token usage statistics from the LLM API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LLMUsage {
    pub input_tokens: u32,
    pub output_tokens: u32,
}

/// Client for interacting with the Anthropic Claude API.
#[derive(Clone)]
pub struct AnthropicClient {
    client: reqwest::Client,
    api_key: String,
    model: String,
}

impl AnthropicClient {
    /// Create a new Anthropic client.
    ///
    /// # Arguments
    ///
    /// * `api_key` - The Anthropic API key
    /// * `model` - The model to use (e.g., "claude-sonnet-4-20250514")
    pub fn new(api_key: String, model: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            api_key,
            model,
        }
    }

    /// Create a client from environment variables.
    ///
    /// Uses ANTHROPIC_API_KEY environment variable.
    pub fn from_env() -> Result<Self> {
        let api_key =
            std::env::var("ANTHROPIC_API_KEY").context("ANTHROPIC_API_KEY not set")?;
        let model = std::env::var("ANTHROPIC_MODEL")
            .unwrap_or_else(|_| "claude-sonnet-4-20250514".to_string());
        Ok(Self::new(api_key, model))
    }

    /// Send a query to the LLM and return the response.
    ///
    /// # Arguments
    ///
    /// * `prompt` - The user prompt
    /// * `system_prompt` - Optional system prompt
    /// * `max_tokens` - Maximum tokens to generate
    pub async fn query(
        &self,
        prompt: &str,
        system_prompt: Option<&str>,
        max_tokens: u32,
    ) -> Result<LLMResponse> {
        let mut body = json!({
            "model": self.model,
            "max_tokens": max_tokens,
            "messages": [
                {"role": "user", "content": prompt}
            ]
        });

        if let Some(sys) = system_prompt {
            body["system"] = json!(sys);
        }

        let response = self
            .client
            .post("https://api.anthropic.com/v1/messages")
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", "2023-06-01")
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .context("Failed to send request to Anthropic API")?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            anyhow::bail!("Anthropic API error {}: {}", status, text);
        }

        let json_response: Value = response
            .json()
            .await
            .context("Failed to parse Anthropic API response")?;

        let content = json_response["content"][0]["text"]
            .as_str()
            .unwrap_or("")
            .to_string();

        let usage = json_response.get("usage").map(|u| LLMUsage {
            input_tokens: u["input_tokens"].as_u64().unwrap_or(0) as u32,
            output_tokens: u["output_tokens"].as_u64().unwrap_or(0) as u32,
        });

        Ok(LLMResponse { content, usage })
    }

    /// Stream a query response from the LLM.
    ///
    /// # Arguments
    ///
    /// * `prompt` - The user prompt
    /// * `system_prompt` - Optional system prompt
    /// * `max_tokens` - Maximum tokens to generate
    pub async fn stream_query(
        &self,
        prompt: &str,
        system_prompt: Option<&str>,
        max_tokens: u32,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<String>> + Send>>> {
        let mut body = json!({
            "model": self.model,
            "max_tokens": max_tokens,
            "stream": true,
            "messages": [
                {"role": "user", "content": prompt}
            ]
        });

        if let Some(sys) = system_prompt {
            body["system"] = json!(sys);
        }

        let response = self
            .client
            .post("https://api.anthropic.com/v1/messages")
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", "2023-06-01")
            .header("content-type", "application/json")
            .json(&body)
            .send()
            .await
            .context("Failed to send streaming request to Anthropic API")?;

        if !response.status().is_success() {
            let status = response.status();
            let text = response.text().await.unwrap_or_default();
            anyhow::bail!("Anthropic API error {}: {}", status, text);
        }

        let byte_stream = response.bytes_stream();

        let stream = async_stream::stream! {
            let mut byte_stream = byte_stream;
            let mut buf = String::new();

            while let Some(chunk_result) = byte_stream.next().await {
                match chunk_result {
                    Ok(bytes) => {
                        buf.push_str(&String::from_utf8_lossy(&bytes));

                        while let Some(newline_pos) = buf.find('\n') {
                            let line = buf[..newline_pos].to_string();
                            buf = buf[newline_pos + 1..].to_string();

                            if let Some(data) = line.strip_prefix("data: ") {
                                if data.trim() == "[DONE]" {
                                    continue;
                                }
                                if let Ok(json_val) = serde_json::from_str::<Value>(data) {
                                    let event_type = json_val.get("type").and_then(|t| t.as_str());
                                    if event_type == Some("content_block_delta") {
                                        if let Some(text) = json_val
                                            .get("delta")
                                            .and_then(|d| d.get("text"))
                                            .and_then(|t| t.as_str())
                                        {
                                            yield Ok(text.to_string());
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Err(e) => {
                        yield Err(anyhow::anyhow!("Stream error: {}", e));
                    }
                }
            }
        };

        Ok(Box::pin(stream))
    }
}

// =============================================================================
// NEGOTIATION TYPES (local extensions)
// =============================================================================

/// Confidence-weighted vote aggregation strategy.
pub struct ConfidenceWeightedVoteAggregator;

impl ConfidenceWeightedVoteAggregator {
    /// Aggregate votes using confidence-weighted averaging.
    pub fn aggregate(votes: &[NegotiationVote]) -> Result<AggregatedScore> {
        if votes.is_empty() {
            anyhow::bail!("Cannot aggregate empty votes");
        }

        let n = votes.len() as f64;
        let scores: Vec<f64> = votes.iter().map(|v| v.score).collect();
        let confidences: Vec<f64> = votes.iter().map(|v| v.confidence).collect();

        let mean = scores.iter().sum::<f64>() / n;
        let min_score = scores.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_score = scores.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

        let variance = scores.iter().map(|s| (s - mean).powi(2)).sum::<f64>() / n;
        let std_dev = variance.sqrt();

        let total_confidence: f64 = confidences.iter().sum();
        let weighted_mean = if total_confidence > 0.0 {
            scores
                .iter()
                .zip(confidences.iter())
                .map(|(s, c)| s * c)
                .sum::<f64>()
                / total_confidence
        } else {
            mean
        };

        Ok(AggregatedScore {
            mean,
            min_score,
            max_score,
            std_dev,
            weighted_mean,
            vote_count: votes.len(),
        })
    }
}

// =============================================================================
// ASYNC gRPC CLIENT WRAPPERS
// =============================================================================

/// Async wrapper for RouterService gRPC client.
#[derive(Clone)]
pub struct AsyncRouterClient {
    inner: Arc<Mutex<RouterClient>>,
}

impl AsyncRouterClient {
    /// Create a new async router client from an existing RouterClient.
    pub fn new(client: RouterClient) -> Self {
        Self {
            inner: Arc::new(Mutex::new(client)),
        }
    }

    /// Send an envelope via gRPC.
    pub async fn send_message(&self, envelope: &EnvelopeData) -> Result<bool> {
        let mut client = self.inner.lock().await;
        let result = client.send_message(envelope).await?;
        Ok(result.accepted)
    }

    /// Stream incoming messages for an agent.
    pub async fn stream_incoming(
        &self,
        agent_id: &str,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<EnvelopeData>> + Send>>> {
        let mut client = self.inner.lock().await;
        let stream = client.stream_incoming(agent_id).await?;

        // Wrap the stream to convert errors
        let mapped_stream = stream.map(|result| result.map_err(|e| anyhow::anyhow!("{}", e)));

        Ok(Box::pin(mapped_stream))
    }
}

/// Async wrapper for RegistryService gRPC client.
#[derive(Clone)]
pub struct AsyncRegistryClient {
    inner: Arc<Mutex<RegistryClient>>,
}

impl AsyncRegistryClient {
    /// Create a new async registry client from an existing RegistryClient.
    pub fn new(client: RegistryClient) -> Self {
        Self {
            inner: Arc::new(Mutex::new(client)),
        }
    }

    /// Register an agent with the registry.
    pub async fn register(&self, agent_id: &str, name: &str, capabilities: Vec<String>) -> Result<bool> {
        let agent = AgentDescriptor::new(agent_id.to_string(), name.to_string())
            .with_capabilities(capabilities);
        let mut client = self.inner.lock().await;
        let response = client.register(&agent).await?;
        Ok(response.accepted)
    }

    /// Deregister an agent from the registry.
    pub async fn deregister(&self, agent_id: &str, reason: &str) -> Result<bool> {
        let mut client = self.inner.lock().await;
        let response = client.deregister(agent_id, Some(reason)).await?;
        Ok(response.ok)
    }

    /// Send a heartbeat for an agent.
    pub async fn heartbeat(&self, agent_id: &str, state: AgentState) -> Result<bool> {
        let mut client = self.inner.lock().await;
        let response = client.heartbeat(agent_id, state, None).await?;
        Ok(response.ok)
    }
}

/// Async wrapper for SchedulerService gRPC client.
#[derive(Clone)]
pub struct AsyncSchedulerClient {
    inner: Arc<Mutex<SchedulerClient>>,
}

impl AsyncSchedulerClient {
    /// Create a new async scheduler client from an existing SchedulerClient.
    pub fn new(client: SchedulerClient) -> Self {
        Self {
            inner: Arc::new(Mutex::new(client)),
        }
    }

    /// Submit a task to the scheduler.
    pub async fn submit_task(
        &self,
        agent_id: &str,
        task_id: &str,
        priority: i32,
    ) -> Result<String> {
        let mut client = self.inner.lock().await;
        client
            .submit_task(task_id, agent_id, priority, vec![], "", "")
            .await?;
        info!("Scheduled task {} for {}", task_id, agent_id);
        Ok(task_id.to_string())
    }

    /// Mark a task as completed (logging only - scheduler manages lifecycle).
    pub async fn complete_task(&self, task_id: &str, status: &str) {
        debug!("Task {} {}", task_id, status);
    }
}

// =============================================================================
// BASE AGENT TRAIT
// =============================================================================

/// Shared context for all agents in the system.
#[derive(Clone)]
pub struct AgentContext {
    pub router: AsyncRouterClient,
    pub registry: AsyncRegistryClient,
    pub scheduler: AsyncSchedulerClient,
    pub negotiation_room: NegotiationRoomClient,
    pub llm: AnthropicClient,
}

/// Trait defining the interface for SW4RM agents.
#[async_trait]
pub trait SW4RMAgent: Send + Sync {
    /// Get the agent's unique identifier.
    fn agent_id(&self) -> &str;

    /// Get the agent's human-readable name.
    fn name(&self) -> &str;

    /// Get the agent's capabilities.
    fn capabilities(&self) -> &[String];

    /// Handle an incoming message.
    async fn handle_message(&self, envelope: &EnvelopeData) -> Result<()>;

    /// Get the agent context.
    fn context(&self) -> &AgentContext;

    /// Get the next sequence number for outgoing messages.
    fn next_sequence(&self) -> u64;

    /// Build an envelope for sending.
    fn build_envelope(
        &self,
        message_type: i32,
        payload: Value,
        target: &str,
        correlation_id: &str,
    ) -> EnvelopeData {
        let mut payload_with_target = payload.clone();
        if let Some(obj) = payload_with_target.as_object_mut() {
            obj.insert("_target".to_string(), json!(target));
        }

        let payload_bytes = serde_json::to_vec(&payload_with_target).unwrap_or_default();

        EnvelopeBuilder::new(self.agent_id().to_string(), message_type)
            .with_payload(payload_bytes)
            .with_content_type("application/json".to_string())
            .with_correlation_id(correlation_id.to_string())
            .with_sequence_number(self.next_sequence())
            .build()
    }

    /// Send a message to another agent.
    async fn send_to(
        &self,
        recipient: &str,
        message_type: i32,
        payload: Value,
        correlation_id: &str,
    ) -> Result<()> {
        let envelope = self.build_envelope(message_type, payload, recipient, correlation_id);
        self.context().router.send_message(&envelope).await?;
        Ok(())
    }
}

// =============================================================================
// CONCRETE AGENTS
// =============================================================================

/// Coordinator agent that orchestrates the review workflow.
pub struct CoordinatorAgent {
    agent_id: String,
    name: String,
    capabilities: Vec<String>,
    context: AgentContext,
    sequence: AtomicU64,
    worker_ids: Vec<String>,
    critic_id: String,
    pending_reviews: Arc<RwLock<HashMap<String, PendingReview>>>,
    collected_findings: Arc<RwLock<HashMap<String, Vec<Value>>>>,
    final_report: Arc<RwLock<Option<Value>>>,
    completion_tx: Arc<Mutex<Option<oneshot::Sender<()>>>>,
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
struct PendingReview {
    workers: HashSet<String>,
    code: String,
}

impl CoordinatorAgent {
    /// Create a new coordinator agent.
    pub fn new(
        context: AgentContext,
        worker_ids: Vec<String>,
        critic_id: String,
    ) -> (Self, oneshot::Receiver<()>) {
        let (tx, rx) = oneshot::channel();
        (
            Self {
                agent_id: "coordinator".to_string(),
                name: "Coordinator".to_string(),
                capabilities: vec!["coordination".to_string(), "scheduling".to_string()],
                context,
                sequence: AtomicU64::new(0),
                worker_ids,
                critic_id,
                pending_reviews: Arc::new(RwLock::new(HashMap::new())),
                collected_findings: Arc::new(RwLock::new(HashMap::new())),
                final_report: Arc::new(RwLock::new(None)),
                completion_tx: Arc::new(Mutex::new(Some(tx))),
            },
            rx,
        )
    }

    /// Get the final report if available.
    pub async fn get_final_report(&self) -> Option<Value> {
        self.final_report.read().await.clone()
    }

    /// Start the code review workflow.
    async fn start_review(&self, payload: &Value, correlation_id: &str) -> Result<()> {
        info!("Starting code review workflow...");
        let code = payload
            .get("code")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();

        // Use LLM to plan the review
        let plan_prompt = format!(
            "Plan a code review for this code. List 2 reviewers needed (security, quality):\n{}",
            &code[..code.len().min(500)]
        );
        let plan = self
            .context
            .llm
            .query(&plan_prompt, Some("You are a code review coordinator. Be brief."), 200)
            .await?;
        debug!("Review plan: {}...", &plan.content[..plan.content.len().min(100)]);

        // Set up pending review
        {
            let mut pending = self.pending_reviews.write().await;
            pending.insert(
                correlation_id.to_string(),
                PendingReview {
                    workers: self.worker_ids.iter().cloned().collect(),
                    code: code.clone(),
                },
            );

            let mut findings = self.collected_findings.write().await;
            findings.insert(correlation_id.to_string(), Vec::new());
        }

        // Assign tasks to workers
        for worker_id in &self.worker_ids {
            let task_id = format!("review-{}-{}", worker_id, correlation_id);
            self.context
                .scheduler
                .submit_task(worker_id, &task_id, 0)
                .await?;

            self.send_to(
                worker_id,
                message_type::DATA,
                json!({
                    "type": "review_task",
                    "code": code
                }),
                correlation_id,
            )
            .await?;

            info!("Assigned task to {}", worker_id);
        }

        Ok(())
    }

    /// Collect findings from a worker.
    async fn collect_findings(&self, payload: &Value, correlation_id: &str) -> Result<()> {
        let worker_id = payload
            .get("worker_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");
        let findings = payload
            .get("findings")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        info!("Received {} findings from {}", findings.len(), worker_id);

        {
            let mut collected = self.collected_findings.write().await;
            if let Some(f) = collected.get_mut(correlation_id) {
                f.extend(findings);
            }
        }

        // Check if all workers are done
        let all_done = {
            let mut pending = self.pending_reviews.write().await;
            if let Some(review) = pending.get_mut(correlation_id) {
                review.workers.remove(worker_id);
                review.workers.is_empty()
            } else {
                false
            }
        };

        if all_done {
            let all_findings = {
                let collected = self.collected_findings.read().await;
                collected.get(correlation_id).cloned().unwrap_or_default()
            };

            info!("Sending {} findings to critic...", all_findings.len());
            self.send_to(
                &self.critic_id,
                message_type::DATA,
                json!({
                    "type": "review_findings",
                    "findings": all_findings
                }),
                correlation_id,
            )
            .await?;
        }

        Ok(())
    }

    /// Handle the critic's review.
    async fn handle_critic_review(&self, payload: &Value, correlation_id: &str) -> Result<()> {
        info!("Critic review complete, submitting proposal...");

        // Submit to negotiation room
        let artifact_id = format!("review-{}", correlation_id);
        let proposal = NegotiationProposal::new(
            ArtifactType::Code,
            artifact_id.clone(),
            self.agent_id.clone(),
            serde_json::to_vec(payload)?,
            "application/json".to_string(),
            [vec![self.critic_id.clone()], self.worker_ids.clone()].concat(),
            correlation_id.to_string(),
        );
        self.context.negotiation_room.submit_proposal(proposal)?;
        info!("Proposal submitted: {}", artifact_id);

        // Request votes from all critics
        let voter_ids: Vec<String> = [vec![self.critic_id.clone()], self.worker_ids.clone()].concat();
        for voter_id in voter_ids {
            self.send_to(
                &voter_id,
                message_type::NEGOTIATION,
                json!({
                    "type": "vote_request",
                    "artifact_id": artifact_id,
                    "content": payload
                }),
                correlation_id,
            )
            .await?;
        }

        Ok(())
    }

    /// Handle a vote result notification.
    async fn handle_vote_result(&self, payload: &Value, correlation_id: &str) -> Result<()> {
        let artifact_id = payload
            .get("artifact_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        // Get votes and make decision
        let votes = self.context.negotiation_room.get_votes(artifact_id)?;

        if votes.len() >= 3 {
            // All voted
            let score = ConfidenceWeightedVoteAggregator::aggregate(&votes)?;
            let outcome = if score.weighted_mean >= 7.0 {
                DecisionOutcome::Approved
            } else {
                DecisionOutcome::RevisionRequested
            };

            let decision = NegotiationDecision::new(
                artifact_id.to_string(),
                outcome,
                votes.clone(),
                score.clone(),
                "1.0".to_string(),
                format!("Score: {:.1} (std: {:.2})", score.weighted_mean, score.std_dev),
                correlation_id.to_string(),
            );
            self.context.negotiation_room.store_decision(decision)?;

            let outcome_name = match outcome {
                DecisionOutcome::Approved => "APPROVED",
                DecisionOutcome::RevisionRequested => "REVISION_REQUESTED",
                DecisionOutcome::EscalatedToHitl => "ESCALATED_TO_HITL",
                DecisionOutcome::Unspecified => "UNSPECIFIED",
            };

            let report = json!({
                "artifact_id": artifact_id,
                "outcome": outcome_name,
                "score": score.weighted_mean,
                "reason": format!("Score: {:.1} (std: {:.2})", score.weighted_mean, score.std_dev),
                "vote_count": votes.len(),
                "votes": votes.iter().map(|v| json!({
                    "critic": v.critic_id,
                    "score": v.score,
                    "confidence": v.confidence,
                    "passed": v.passed
                })).collect::<Vec<_>>()
            });

            {
                let mut final_report = self.final_report.write().await;
                *final_report = Some(report);
            }

            info!("Decision: {}", outcome_name);

            // Signal completion
            let tx = self.completion_tx.lock().await.take();
            if let Some(tx) = tx {
                let _ = tx.send(());
            }
        }

        Ok(())
    }
}

#[async_trait]
impl SW4RMAgent for CoordinatorAgent {
    fn agent_id(&self) -> &str {
        &self.agent_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn capabilities(&self) -> &[String] {
        &self.capabilities
    }

    fn context(&self) -> &AgentContext {
        &self.context
    }

    fn next_sequence(&self) -> u64 {
        self.sequence.fetch_add(1, Ordering::SeqCst)
    }

    async fn handle_message(&self, envelope: &EnvelopeData) -> Result<()> {
        let payload: Value = serde_json::from_slice(&envelope.payload)?;
        let correlation_id = if envelope.correlation_id.is_empty() {
            &envelope.message_id
        } else {
            &envelope.correlation_id
        };
        let msg_type = payload.get("type").and_then(|v| v.as_str()).unwrap_or("");

        match msg_type {
            "start_review" => self.start_review(&payload, correlation_id).await,
            "findings" => self.collect_findings(&payload, correlation_id).await,
            "critic_review" => self.handle_critic_review(&payload, correlation_id).await,
            "vote_result" => self.handle_vote_result(&payload, correlation_id).await,
            _ => Ok(()),
        }
    }
}

/// Analyst agent that performs code analysis.
pub struct AnalystAgent {
    agent_id: String,
    name: String,
    capabilities: Vec<String>,
    specialty: String,
    context: AgentContext,
    sequence: AtomicU64,
}

impl AnalystAgent {
    /// Create a new analyst agent.
    pub fn new(agent_id: &str, name: &str, specialty: &str, context: AgentContext) -> Self {
        Self {
            agent_id: agent_id.to_string(),
            name: name.to_string(),
            capabilities: vec![specialty.to_string(), "analysis".to_string()],
            specialty: specialty.to_string(),
            context,
            sequence: AtomicU64::new(0),
        }
    }

    /// Perform the code review.
    async fn do_review(&self, payload: &Value, correlation_id: &str) -> Result<()> {
        let code = payload.get("code").and_then(|v| v.as_str()).unwrap_or("");
        info!("Analyzing code ({})...", self.specialty);

        // Use LLM to analyze
        let prompt = format!(
            "Review this code for {} issues. List findings as JSON array:\n{}",
            self.specialty, code
        );
        let system = format!(
            "You are a {} analyst. Return JSON array of findings.",
            self.specialty
        );
        let response = self
            .context
            .llm
            .query(&prompt, Some(&system), 500)
            .await?;

        // Parse findings
        let findings: Vec<Value> = {
            let content = response.content.trim();
            let cleaned = if content.starts_with("```") {
                let lines: Vec<&str> = content.lines().collect();
                let start = if lines.first().map_or(false, |l| l.starts_with("```")) {
                    1
                } else {
                    0
                };
                let end = if lines.last().map_or(false, |l| l.trim().starts_with("```")) {
                    lines.len() - 1
                } else {
                    lines.len()
                };
                lines[start..end].join("\n")
            } else {
                content.to_string()
            };

            serde_json::from_str(&cleaned).unwrap_or_else(|_| {
                vec![json!({
                    "issue": &response.content[..response.content.len().min(200)],
                    "severity": "medium"
                })]
            })
        };

        info!("Found {} issues", findings.len());

        // Mark task complete
        let task_id = format!("review-{}-{}", self.agent_id, correlation_id);
        self.context.scheduler.complete_task(&task_id, "completed").await;

        // Send findings to coordinator
        self.send_to(
            "coordinator",
            message_type::DATA,
            json!({
                "type": "findings",
                "worker_id": self.agent_id,
                "findings": findings
            }),
            correlation_id,
        )
        .await
    }

    /// Cast a vote on an artifact.
    async fn cast_vote(&self, payload: &Value, correlation_id: &str) -> Result<()> {
        let artifact_id = payload
            .get("artifact_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let vote = NegotiationVote::new(
            artifact_id.to_string(),
            self.agent_id.clone(),
            9.7, // High score from analyst
            0.8,
            true,
            vec![format!("{} review passed", self.specialty)],
            vec![],
            vec![],
            correlation_id.to_string(),
        )?;

        self.context.negotiation_room.submit_vote(vote)?;
        info!("Voted on {}: score=9.7", artifact_id);

        self.send_to(
            "coordinator",
            message_type::NEGOTIATION,
            json!({
                "type": "vote_result",
                "artifact_id": artifact_id
            }),
            correlation_id,
        )
        .await
    }
}

#[async_trait]
impl SW4RMAgent for AnalystAgent {
    fn agent_id(&self) -> &str {
        &self.agent_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn capabilities(&self) -> &[String] {
        &self.capabilities
    }

    fn context(&self) -> &AgentContext {
        &self.context
    }

    fn next_sequence(&self) -> u64 {
        self.sequence.fetch_add(1, Ordering::SeqCst)
    }

    async fn handle_message(&self, envelope: &EnvelopeData) -> Result<()> {
        let payload: Value = serde_json::from_slice(&envelope.payload)?;
        let correlation_id = if envelope.correlation_id.is_empty() {
            &envelope.message_id
        } else {
            &envelope.correlation_id
        };
        let msg_type = payload.get("type").and_then(|v| v.as_str()).unwrap_or("");

        match msg_type {
            "review_task" => self.do_review(&payload, correlation_id).await,
            "vote_request" => self.cast_vote(&payload, correlation_id).await,
            _ => Ok(()),
        }
    }
}

/// Critic agent that synthesizes findings.
pub struct CriticAgent {
    agent_id: String,
    name: String,
    capabilities: Vec<String>,
    context: AgentContext,
    sequence: AtomicU64,
}

impl CriticAgent {
    /// Create a new critic agent.
    pub fn new(context: AgentContext) -> Self {
        Self {
            agent_id: "critic".to_string(),
            name: "Senior Critic".to_string(),
            capabilities: vec!["review".to_string(), "synthesis".to_string()],
            context,
            sequence: AtomicU64::new(0),
        }
    }

    /// Review the collected findings.
    async fn review_findings(&self, payload: &Value, correlation_id: &str) -> Result<()> {
        let findings = payload
            .get("findings")
            .and_then(|v| v.as_array())
            .cloned()
            .unwrap_or_default();

        info!("Reviewing {} findings...", findings.len());

        // Use LLM to synthesize
        let findings_str = serde_json::to_string(&findings)?;
        let prompt = format!(
            "Synthesize these code review findings: {}. Is the code acceptable? Reply: acceptable or needs_work",
            &findings_str[..findings_str.len().min(1000)]
        );
        let response = self
            .context
            .llm
            .query(&prompt, Some("You are a senior code critic. Be decisive."), 200)
            .await?;

        let assessment = if response.content.to_lowercase().contains("acceptable") {
            "acceptable"
        } else {
            "needs_work"
        };

        info!("Assessment: {}", assessment);

        self.send_to(
            "coordinator",
            message_type::DATA,
            json!({
                "type": "critic_review",
                "assessment": assessment,
                "summary": response.content
            }),
            correlation_id,
        )
        .await
    }

    /// Cast a vote on an artifact.
    async fn cast_vote(&self, payload: &Value, correlation_id: &str) -> Result<()> {
        let artifact_id = payload
            .get("artifact_id")
            .and_then(|v| v.as_str())
            .unwrap_or("");

        let vote = NegotiationVote::new(
            artifact_id.to_string(),
            self.agent_id.clone(),
            7.0, // Critic is more conservative
            0.9,
            true,
            vec!["Senior critic approval".to_string()],
            vec![],
            vec![],
            correlation_id.to_string(),
        )?;

        self.context.negotiation_room.submit_vote(vote)?;
        info!("Voted on {}: score=7.0", artifact_id);

        self.send_to(
            "coordinator",
            message_type::NEGOTIATION,
            json!({
                "type": "vote_result",
                "artifact_id": artifact_id
            }),
            correlation_id,
        )
        .await
    }
}

#[async_trait]
impl SW4RMAgent for CriticAgent {
    fn agent_id(&self) -> &str {
        &self.agent_id
    }

    fn name(&self) -> &str {
        &self.name
    }

    fn capabilities(&self) -> &[String] {
        &self.capabilities
    }

    fn context(&self) -> &AgentContext {
        &self.context
    }

    fn next_sequence(&self) -> u64 {
        self.sequence.fetch_add(1, Ordering::SeqCst)
    }

    async fn handle_message(&self, envelope: &EnvelopeData) -> Result<()> {
        let payload: Value = serde_json::from_slice(&envelope.payload)?;
        let correlation_id = if envelope.correlation_id.is_empty() {
            &envelope.message_id
        } else {
            &envelope.correlation_id
        };
        let msg_type = payload.get("type").and_then(|v| v.as_str()).unwrap_or("");

        match msg_type {
            "review_findings" => self.review_findings(&payload, correlation_id).await,
            "vote_request" => self.cast_vote(&payload, correlation_id).await,
            _ => Ok(()),
        }
    }
}

// =============================================================================
// AGENT RUNNER
// =============================================================================

/// Runs an agent, handling registration and message processing.
pub struct AgentRunner<A: SW4RMAgent + 'static> {
    agent: Arc<A>,
    running: Arc<std::sync::atomic::AtomicBool>,
}

impl<A: SW4RMAgent + 'static> AgentRunner<A> {
    /// Create a new agent runner.
    pub fn new(agent: A) -> Self {
        Self {
            agent: Arc::new(agent),
            running: Arc::new(std::sync::atomic::AtomicBool::new(false)),
        }
    }

    /// Start the agent.
    pub async fn start(&self) -> Result<()> {
        // Register with registry
        self.agent
            .context()
            .registry
            .register(
                self.agent.agent_id(),
                self.agent.name(),
                self.agent.capabilities().to_vec(),
            )
            .await?;

        self.running.store(true, Ordering::SeqCst);
        info!(
            "{} started with capabilities: {:?}",
            self.agent.name(),
            self.agent.capabilities()
        );

        Ok(())
    }

    /// Stop the agent.
    pub async fn stop(&self) -> Result<()> {
        self.running.store(false, Ordering::SeqCst);
        self.agent
            .context()
            .registry
            .deregister(self.agent.agent_id(), "graceful_shutdown")
            .await?;
        info!("{} stopped", self.agent.name());
        Ok(())
    }

    /// Run the message loop.
    pub async fn run_message_loop(&self) -> Result<()> {
        let mut stream = self
            .agent
            .context()
            .router
            .stream_incoming(self.agent.agent_id())
            .await?;

        while self.running.load(Ordering::SeqCst) {
            tokio::select! {
                Some(result) = stream.next() => {
                    match result {
                        Ok(envelope) => {
                            // Parse payload to check target
                            if let Ok(payload) = serde_json::from_slice::<Value>(&envelope.payload) {
                                // Check for shutdown
                                if payload.get("command").and_then(|v| v.as_str()) == Some("shutdown") {
                                    break;
                                }

                                // Check target
                                if let Some(target) = payload.get("_target").and_then(|v| v.as_str()) {
                                    if !target.is_empty() && target != self.agent.agent_id() {
                                        continue; // Not for us
                                    }
                                }
                            }

                            // Process message
                            if let Err(e) = self.agent.handle_message(&envelope).await {
                                error!("Failed to process message: {}", e);
                            }
                        }
                        Err(e) => {
                            warn!("Stream error: {}", e);
                        }
                    }
                }
                _ = tokio::time::sleep(Duration::from_millis(100)) => {
                    // Periodic check
                    if !self.running.load(Ordering::SeqCst) {
                        break;
                    }
                }
            }
        }

        Ok(())
    }

    /// Get a reference to the agent.
    pub fn agent(&self) -> &A {
        &self.agent
    }
}

// =============================================================================
// ORCHESTRATOR
// =============================================================================

/// Orchestrates the multi-agent system with real gRPC services.
#[allow(dead_code)]
pub struct SW4RMOrchestrator {
    code_to_review: String,
    router_addr: String,
    registry_addr: String,
    scheduler_addr: String,
    verbose: bool,
}

impl SW4RMOrchestrator {
    /// Create a new orchestrator.
    pub fn new(
        code_to_review: String,
        router_addr: String,
        registry_addr: String,
        scheduler_addr: String,
        verbose: bool,
    ) -> Self {
        Self {
            code_to_review,
            router_addr,
            registry_addr,
            scheduler_addr,
            verbose,
        }
    }

    /// Run the complete workflow.
    pub async fn run(&self) -> Result<Value> {
        // Create gRPC clients
        let router_client = RouterClient::new(&format!("http://{}", self.router_addr)).await?;
        let registry_client = RegistryClient::new(&format!("http://{}", self.registry_addr)).await?;
        let scheduler_client = SchedulerClient::new(&format!("http://{}", self.scheduler_addr)).await?;

        let router = AsyncRouterClient::new(router_client);
        let registry = AsyncRegistryClient::new(registry_client);
        let scheduler = AsyncSchedulerClient::new(scheduler_client);
        let negotiation_room = NegotiationRoomClient::new();
        let llm = AnthropicClient::from_env()?;

        info!(
            "Connected to Router({}), Registry({}), Scheduler({})",
            self.router_addr, self.registry_addr, self.scheduler_addr
        );

        let context = AgentContext {
            router: router.clone(),
            registry: registry.clone(),
            scheduler: scheduler.clone(),
            negotiation_room: negotiation_room.clone(),
            llm: llm.clone(),
        };

        // Create agents
        let (coordinator, completion_rx) = CoordinatorAgent::new(
            context.clone(),
            vec!["security_analyst".to_string(), "quality_analyst".to_string()],
            "critic".to_string(),
        );
        let security_analyst =
            AnalystAgent::new("security_analyst", "Security Analyst", "security", context.clone());
        let quality_analyst =
            AnalystAgent::new("quality_analyst", "Quality Analyst", "code quality", context.clone());
        let critic = CriticAgent::new(context.clone());

        let coordinator_runner = AgentRunner::new(coordinator);
        let security_runner = AgentRunner::new(security_analyst);
        let quality_runner = AgentRunner::new(quality_analyst);
        let critic_runner = AgentRunner::new(critic);

        info!("======================================================================");
        info!("SW4RM MULTI-AGENT CODE REVIEW (Real gRPC)");
        info!("======================================================================");
        info!(
            "Services: Router({}), Registry({})",
            self.router_addr, self.registry_addr
        );
        info!(
            "Agents: [Coordinator, Security Analyst, Quality Analyst, Senior Critic]"
        );
        info!("======================================================================");

        let start_time = Instant::now();

        // Start all agents
        coordinator_runner.start().await?;
        security_runner.start().await?;
        quality_runner.start().await?;
        critic_runner.start().await?;

        // Spawn message loops
        let coordinator_runner_clone = coordinator_runner.agent.clone();
        let security_runner_clone = security_runner.clone();
        let quality_runner_clone = quality_runner.clone();
        let critic_runner_clone = critic_runner.clone();

        let security_handle = tokio::spawn(async move {
            if let Err(e) = security_runner_clone.run_message_loop().await {
                error!("Security analyst error: {}", e);
            }
        });

        let quality_handle = tokio::spawn(async move {
            if let Err(e) = quality_runner_clone.run_message_loop().await {
                error!("Quality analyst error: {}", e);
            }
        });

        let critic_handle = tokio::spawn(async move {
            if let Err(e) = critic_runner_clone.run_message_loop().await {
                error!("Critic error: {}", e);
            }
        });

        // Trigger initial review directly
        let correlation_id = Uuid::new_v4().to_string();
        let initial_envelope = EnvelopeBuilder::new("orchestrator".to_string(), message_type::DATA)
            .with_json_payload(&json!({
                "type": "start_review",
                "code": self.code_to_review
            }))?
            .with_correlation_id(correlation_id.clone())
            .build();

        coordinator_runner_clone.handle_message(&initial_envelope).await?;

        // Run coordinator message loop with timeout
        let coordinator_runner_for_loop = coordinator_runner.clone();
        let coordinator_handle = tokio::spawn(async move {
            if let Err(e) = coordinator_runner_for_loop.run_message_loop().await {
                error!("Coordinator error: {}", e);
            }
        });

        // Wait for completion or timeout
        let timeout = Duration::from_secs(300);
        match tokio::time::timeout(timeout, completion_rx).await {
            Ok(_) => {
                info!("Workflow completed successfully");
            }
            Err(_) => {
                warn!("Workflow timed out after {:?}", timeout);
            }
        }

        // Stop all agents
        coordinator_runner.stop().await?;
        security_runner.stop().await?;
        quality_runner.stop().await?;
        critic_runner.stop().await?;

        // Cancel handles
        coordinator_handle.abort();
        security_handle.abort();
        quality_handle.abort();
        critic_handle.abort();

        let elapsed = start_time.elapsed();
        info!("======================================================================");
        info!("Workflow completed in {:.1}s", elapsed.as_secs_f64());
        info!("======================================================================");

        let report = coordinator_runner
            .agent()
            .get_final_report()
            .await
            .unwrap_or(json!({}));

        Ok(report)
    }
}

impl<A: SW4RMAgent + 'static> Clone for AgentRunner<A> {
    fn clone(&self) -> Self {
        Self {
            agent: self.agent.clone(),
            running: self.running.clone(),
        }
    }
}

// =============================================================================
// LLM VERIFICATION
// =============================================================================

/// Run LLM verification tests.
async fn run_llm_verification() -> Result<bool> {
    println!("======================================================================");
    println!("LLM LIVE VERIFICATION (No mocks)");
    println!("======================================================================");

    let client = AnthropicClient::from_env()?;
    let mut tests_passed = 0;

    // Test 1: Basic
    println!("\n[LLM Test 1] Basic Query...");
    match client
        .query("What is 2 + 2? Reply with just the number.", None, 50)
        .await
    {
        Ok(response) => {
            if response.content.contains("4") {
                println!("  Response: {} PASSED", response.content.trim());
                tests_passed += 1;
            } else {
                println!("  FAILED: {}", response.content);
            }
        }
        Err(e) => {
            println!("  ERROR: {}", e);
        }
    }

    // Test 2: Security
    println!("[LLM Test 2] Security Analysis...");
    match client
        .query(
            "What's wrong with: password = 'admin123'",
            Some("Security analyst. Be brief."),
            100,
        )
        .await
    {
        Ok(response) => {
            let content_lower = response.content.to_lowercase();
            if content_lower.contains("password")
                || content_lower.contains("hardcoded")
                || content_lower.contains("security")
            {
                println!("  Found security issue PASSED");
                tests_passed += 1;
            } else {
                println!("  FAILED: {}", response.content);
            }
        }
        Err(e) => {
            println!("  ERROR: {}", e);
        }
    }

    // Test 3: Streaming
    println!("[LLM Test 3] Streaming...");
    print!("  Stream: ");
    match client.stream_query("Count 1 to 3", None, 30).await {
        Ok(mut stream) => {
            let mut chunks = String::new();
            while let Some(result) = stream.next().await {
                match result {
                    Ok(chunk) => {
                        print!("{}", chunk);
                        chunks.push_str(&chunk);
                    }
                    Err(e) => {
                        print!(" [ERROR: {}]", e);
                    }
                }
            }
            if chunks.contains('1') || chunks.contains('2') || chunks.contains('3') {
                println!(" PASSED");
                tests_passed += 1;
            } else {
                println!(" FAILED");
            }
        }
        Err(e) => {
            println!("  ERROR: {}", e);
        }
    }

    println!("\nLLM Verification: {}/3 passed", tests_passed);
    println!("======================================================================");

    Ok(tests_passed == 3)
}

// =============================================================================
// CLI
// =============================================================================

const DEFAULT_CODE: &str = r#"
def process_user_data(user_input, db_connection):
    query = f"SELECT * FROM users WHERE name = '{user_input}'"
    result = db_connection.execute(query)
    return result

def authenticate(username, password):
    if username == "admin" and password == "admin123":
        return True
    return check_database(username, password)
"#;

#[derive(Parser, Debug)]
#[command(name = "sw4rm-multi-agent")]
#[command(about = "SW4RM Multi-Agent Code Review")]
struct Args {
    /// Code to review (default: example code with vulnerabilities)
    #[arg(long, default_value = DEFAULT_CODE)]
    code: String,

    /// Enable verbose/debug logging
    #[arg(short, long)]
    verbose: bool,

    /// Run only LLM verification tests
    #[arg(long)]
    llm_only: bool,

    /// Router service address
    #[arg(long, default_value = "localhost:50051")]
    router: String,

    /// Registry service address
    #[arg(long, default_value = "localhost:50052")]
    registry: String,

    /// Scheduler service address
    #[arg(long, default_value = "localhost:50053")]
    scheduler: String,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    // Configure logging
    let filter = if args.verbose {
        "debug"
    } else {
        "info"
    };
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .init();

    if args.llm_only {
        let success = run_llm_verification().await?;
        std::process::exit(if success { 0 } else { 1 });
    }

    // Run LLM verification first
    let llm_ok = run_llm_verification().await?;
    if !llm_ok {
        println!("\nLLM verification failed.");
        std::process::exit(1);
    }
    println!("\nProceeding to multi-agent workflow...\n");

    let orchestrator = SW4RMOrchestrator::new(
        args.code,
        args.router,
        args.registry,
        args.scheduler,
        args.verbose,
    );

    let report = orchestrator.run().await?;

    if !report.is_null() && report.as_object().map_or(false, |o| !o.is_empty()) {
        println!("\n======================================================================");
        println!("FINAL REPORT");
        println!("======================================================================");
        println!(
            "Artifact ID:    {}",
            report.get("artifact_id").and_then(|v| v.as_str()).unwrap_or("N/A")
        );
        println!(
            "Outcome:        {}",
            report.get("outcome").and_then(|v| v.as_str()).unwrap_or("N/A")
        );
        println!(
            "Weighted Score: {:.2}/10",
            report.get("score").and_then(|v| v.as_f64()).unwrap_or(0.0)
        );
        println!(
            "Vote Count:     {}",
            report.get("vote_count").and_then(|v| v.as_u64()).unwrap_or(0)
        );
        println!("\nVotes:");
        if let Some(votes) = report.get("votes").and_then(|v| v.as_array()) {
            for v in votes {
                println!(
                    "  - {}: score={:.1}, confidence={:.1}",
                    v.get("critic").and_then(|c| c.as_str()).unwrap_or("?"),
                    v.get("score").and_then(|s| s.as_f64()).unwrap_or(0.0),
                    v.get("confidence").and_then(|c| c.as_f64()).unwrap_or(0.0)
                );
            }
        }
        println!("======================================================================");
    }

    Ok(())
}
