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

//! Agent Handoff Example
//!
//! Demonstrates agent-to-agent task handoff:
//!
//! 1. Requesting handoff from one agent to another
//! 2. Accept/reject flows for handoff requests
//! 3. Context transfer between agents
//!
//! This example uses stub implementations since HandoffClient
//! is not yet implemented in the Rust SDK. See Phase 3.2 of the
//! IMPLEMENTATION_PLAN.md for the full client implementation.

use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::HashMap;
use sw4rm_sdk::prelude::*;

// ============================================================================
// Stub Types (will be replaced by proto-generated types in Phase 3.2)
// ============================================================================

/// Status of a handoff request
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum HandoffStatus {
    Unspecified = 0,
    Pending = 1,
    Accepted = 2,
    Rejected = 3,
    Completed = 4,
    Expired = 5,
}

impl std::fmt::Display for HandoffStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            HandoffStatus::Unspecified => write!(f, "UNSPECIFIED"),
            HandoffStatus::Pending => write!(f, "PENDING"),
            HandoffStatus::Accepted => write!(f, "ACCEPTED"),
            HandoffStatus::Rejected => write!(f, "REJECTED"),
            HandoffStatus::Completed => write!(f, "COMPLETED"),
            HandoffStatus::Expired => write!(f, "EXPIRED"),
        }
    }
}

/// A request to hand off a task to another agent
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HandoffRequest {
    pub request_id: String,
    pub from_agent: String,
    pub to_agent: String,
    pub reason: String,
    pub context_snapshot: Vec<u8>,
    pub capabilities_required: Vec<String>,
    pub priority: i32,
    pub timeout_seconds: u32,
}

/// Response to a handoff request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HandoffResponse {
    pub request_id: String,
    pub accepted: bool,
    pub accepting_agent: String,
    pub rejection_reason: Option<String>,
}

/// Context that can be transferred during handoff
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HandoffContext {
    pub conversation_history: Vec<ConversationMessage>,
    pub tool_state: HashMap<String, serde_json::Value>,
    pub metadata: HashMap<String, String>,
}

/// A message in the conversation history
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConversationMessage {
    pub role: String,
    pub content: String,
    pub timestamp: String,
}

// ============================================================================
// Stub Client (will be replaced by actual gRPC client in Phase 3.2)
// ============================================================================

/// Stub client for Handoff service
#[derive(Debug, Clone)]
pub struct HandoffClientStub {
    requests: HashMap<String, HandoffRequest>,
    responses: HashMap<String, HandoffResponse>,
    statuses: HashMap<String, HandoffStatus>,
}

impl HandoffClientStub {
    pub fn new() -> Self {
        Self {
            requests: HashMap::new(),
            responses: HashMap::new(),
            statuses: HashMap::new(),
        }
    }

    /// Request a handoff to another agent
    pub fn request_handoff(&mut self, request: HandoffRequest) -> Result<String> {
        let request_id = request.request_id.clone();
        tracing::info!(
            "Handoff request: {} -> {} (reason: {})",
            request.from_agent,
            request.to_agent,
            request.reason
        );

        self.requests.insert(request_id.clone(), request);
        self.statuses.insert(request_id.clone(), HandoffStatus::Pending);

        Ok(request_id)
    }

    /// Get pending handoff requests for an agent
    pub fn get_pending_handoffs(&self, agent_id: &str) -> Vec<&HandoffRequest> {
        self.requests
            .values()
            .filter(|r| r.to_agent == agent_id)
            .filter(|r| {
                self.statuses
                    .get(&r.request_id)
                    .map(|s| *s == HandoffStatus::Pending)
                    .unwrap_or(false)
            })
            .collect()
    }

    /// Accept a handoff request
    pub fn accept_handoff(&mut self, request_id: &str, agent_id: &str) -> Result<HandoffResponse> {
        let request = self
            .requests
            .get(request_id)
            .ok_or_else(|| Error::NotFound(format!("Handoff request not found: {}", request_id)))?;

        if request.to_agent != agent_id {
            return Err(Error::Validation(format!(
                "Agent {} is not the target of handoff {}",
                agent_id, request_id
            )));
        }

        let response = HandoffResponse {
            request_id: request_id.to_string(),
            accepted: true,
            accepting_agent: agent_id.to_string(),
            rejection_reason: None,
        };

        tracing::info!("Handoff {} accepted by {}", request_id, agent_id);

        self.responses.insert(request_id.to_string(), response.clone());
        self.statuses.insert(request_id.to_string(), HandoffStatus::Accepted);

        Ok(response)
    }

    /// Reject a handoff request
    pub fn reject_handoff(
        &mut self,
        request_id: &str,
        agent_id: &str,
        reason: &str,
    ) -> Result<HandoffResponse> {
        let request = self
            .requests
            .get(request_id)
            .ok_or_else(|| Error::NotFound(format!("Handoff request not found: {}", request_id)))?;

        if request.to_agent != agent_id {
            return Err(Error::Validation(format!(
                "Agent {} is not the target of handoff {}",
                agent_id, request_id
            )));
        }

        let response = HandoffResponse {
            request_id: request_id.to_string(),
            accepted: false,
            accepting_agent: agent_id.to_string(),
            rejection_reason: Some(reason.to_string()),
        };

        tracing::info!("Handoff {} rejected by {}: {}", request_id, agent_id, reason);

        self.responses.insert(request_id.to_string(), response.clone());
        self.statuses.insert(request_id.to_string(), HandoffStatus::Rejected);

        Ok(response)
    }

    /// Complete a handoff
    pub fn complete_handoff(&mut self, request_id: &str) -> Result<()> {
        let status = self
            .statuses
            .get(request_id)
            .ok_or_else(|| Error::NotFound(format!("Handoff request not found: {}", request_id)))?;

        if *status != HandoffStatus::Accepted {
            return Err(Error::Validation(format!(
                "Cannot complete handoff {} with status {}",
                request_id, status
            )));
        }

        tracing::info!("Handoff {} completed", request_id);
        self.statuses.insert(request_id.to_string(), HandoffStatus::Completed);

        Ok(())
    }

    /// Get handoff status
    pub fn get_status(&self, request_id: &str) -> Option<HandoffStatus> {
        self.statuses.get(request_id).copied()
    }

    /// Get handoff request
    pub fn get_request(&self, request_id: &str) -> Option<&HandoffRequest> {
        self.requests.get(request_id)
    }
}

// ============================================================================
// Context Serialization
// ============================================================================

/// Serialize handoff context to bytes
pub fn serialize_context(context: &HandoffContext) -> Result<Vec<u8>> {
    Ok(serde_json::to_vec(context)?)
}

/// Deserialize handoff context from bytes
pub fn deserialize_context(data: &[u8]) -> Result<HandoffContext> {
    Ok(serde_json::from_slice(data)?)
}

// ============================================================================
// Demo Agents
// ============================================================================

/// Generalist agent that can delegate to specialists
struct GeneralistAgent {
    agent_id: String,
    name: String,
    conversation_history: Vec<ConversationMessage>,
    client: HandoffClientStub,
}

impl GeneralistAgent {
    fn new(agent_id: &str, name: &str, client: HandoffClientStub) -> Self {
        Self {
            agent_id: agent_id.to_string(),
            name: name.to_string(),
            conversation_history: Vec::new(),
            client,
        }
    }

    /// Build context for handoff
    fn build_context(&self) -> HandoffContext {
        HandoffContext {
            conversation_history: self.conversation_history.clone(),
            tool_state: HashMap::from([
                ("mode".to_string(), json!("generalist")),
                ("session_start".to_string(), json!(chrono::Utc::now().to_rfc3339())),
            ]),
            metadata: HashMap::from([
                ("agent_id".to_string(), self.agent_id.clone()),
                ("agent_name".to_string(), self.name.clone()),
            ]),
        }
    }

    /// Handle a user query, potentially handing off to a specialist
    fn handle_query(&mut self, query: &str) -> Result<Option<String>> {
        // Record the user message
        self.conversation_history.push(ConversationMessage {
            role: "user".to_string(),
            content: query.to_string(),
            timestamp: chrono::Utc::now().to_rfc3339(),
        });

        tracing::info!("[{}] Received query: {}", self.name, query);

        // Check if we need to hand off to a specialist
        let query_lower = query.to_lowercase();

        if query_lower.contains("database") || query_lower.contains("sql") {
            tracing::info!("[{}] Query requires database expertise, initiating handoff", self.name);
            let request_id = self.initiate_handoff(
                "specialist-db",
                "Query requires database expertise",
                vec!["database".to_string(), "sql".to_string()],
            )?;
            return Ok(Some(request_id));
        }

        if query_lower.contains("security") || query_lower.contains("auth") {
            tracing::info!("[{}] Query requires security expertise, initiating handoff", self.name);
            let request_id = self.initiate_handoff(
                "specialist-security",
                "Query requires security expertise",
                vec!["security".to_string(), "authentication".to_string()],
            )?;
            return Ok(Some(request_id));
        }

        // Handle locally
        let response = format!("I can help with that: {}", query);
        self.conversation_history.push(ConversationMessage {
            role: "assistant".to_string(),
            content: response.clone(),
            timestamp: chrono::Utc::now().to_rfc3339(),
        });

        tracing::info!("[{}] Handled locally: {}", self.name, response);
        Ok(None)
    }

    /// Initiate a handoff to another agent
    fn initiate_handoff(
        &mut self,
        to_agent: &str,
        reason: &str,
        capabilities: Vec<String>,
    ) -> Result<String> {
        let context = self.build_context();
        let context_bytes = serialize_context(&context)?;

        let request = HandoffRequest {
            request_id: format!("handoff-{}", new_uuid().split('-').next().unwrap()),
            from_agent: self.agent_id.clone(),
            to_agent: to_agent.to_string(),
            reason: reason.to_string(),
            context_snapshot: context_bytes,
            capabilities_required: capabilities,
            priority: 5,
            timeout_seconds: 300,
        };

        let request_id = self.client.request_handoff(request)?;
        tracing::info!(
            "[{}] Initiated handoff {} to {}",
            self.name,
            request_id,
            to_agent
        );

        Ok(request_id)
    }
}

/// Specialist agent that handles specific domains
struct SpecialistAgent {
    agent_id: String,
    name: String,
    specialty: String,
    capabilities: Vec<String>,
    conversation_history: Vec<ConversationMessage>,
}

impl SpecialistAgent {
    fn new(agent_id: &str, name: &str, specialty: &str, capabilities: Vec<String>) -> Self {
        Self {
            agent_id: agent_id.to_string(),
            name: name.to_string(),
            specialty: specialty.to_string(),
            capabilities,
            conversation_history: Vec::new(),
        }
    }

    /// Check if this agent can handle the required capabilities
    fn can_handle(&self, required: &[String]) -> bool {
        required.iter().all(|cap| self.capabilities.contains(cap))
    }

    /// Evaluate a handoff request
    fn evaluate_request(&self, request: &HandoffRequest) -> (bool, Option<String>) {
        tracing::info!(
            "[{}] Evaluating handoff from {}: {}",
            self.name,
            request.from_agent,
            request.reason
        );

        if self.can_handle(&request.capabilities_required) {
            tracing::info!("[{}] Can handle required capabilities", self.name);
            (true, None)
        } else {
            let missing: Vec<_> = request
                .capabilities_required
                .iter()
                .filter(|cap| !self.capabilities.contains(cap))
                .cloned()
                .collect();
            let reason = format!("Missing capabilities: {:?}", missing);
            tracing::warn!("[{}] Cannot handle: {}", self.name, reason);
            (false, Some(reason))
        }
    }

    /// Receive handoff context and continue the conversation
    fn receive_handoff(&mut self, context: HandoffContext) -> Result<String> {
        tracing::info!(
            "[{}] Receiving handoff with {} messages in history",
            self.name,
            context.conversation_history.len()
        );

        // Restore conversation history
        self.conversation_history = context.conversation_history;

        // Get the last user message to continue from
        let last_query = self
            .conversation_history
            .iter()
            .rev()
            .find(|m| m.role == "user")
            .map(|m| m.content.clone())
            .unwrap_or_else(|| "No previous query".to_string());

        tracing::info!("[{}] Continuing from query: {}", self.name, last_query);

        // Provide specialist response
        let response = format!(
            "As a {} specialist, I can help with that. {}",
            self.specialty,
            self.get_specialist_response(&last_query)
        );

        self.conversation_history.push(ConversationMessage {
            role: "assistant".to_string(),
            content: response.clone(),
            timestamp: chrono::Utc::now().to_rfc3339(),
        });

        Ok(response)
    }

    /// Generate a specialist response based on the query
    fn get_specialist_response(&self, query: &str) -> String {
        match self.specialty.as_str() {
            "database" => {
                if query.to_lowercase().contains("optimize") {
                    "For query optimization, consider: 1) Adding appropriate indexes, 2) Analyzing query execution plans, 3) Using connection pooling.".to_string()
                } else {
                    "I can help with database design, query optimization, and data modeling.".to_string()
                }
            }
            "security" => {
                if query.to_lowercase().contains("auth") {
                    "For authentication, I recommend: 1) Use OAuth 2.0 or OpenID Connect, 2) Implement proper session management, 3) Add MFA support.".to_string()
                } else {
                    "I can help with security audits, vulnerability assessments, and secure architecture design.".to_string()
                }
            }
            _ => format!("I specialize in {} and can assist with your question.", self.specialty),
        }
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

fn print_separator(title: &str) {
    println!("\n{}", "=".repeat(70));
    println!("{}", title);
    println!("{}\n", "=".repeat(70));
}

fn print_conversation(history: &[ConversationMessage]) {
    println!("\nConversation History:");
    println!("{:-<70}", "");
    for (i, msg) in history.iter().enumerate() {
        let role_icon = match msg.role.as_str() {
            "user" => "[User]",
            "assistant" => "[Agent]",
            _ => "[?]",
        };
        println!("{}. {} {}", i + 1, role_icon, msg.content);
    }
    println!("{:-<70}", "");
}

// ============================================================================
// Main Demo
// ============================================================================

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize tracing
    tracing_subscriber::fmt()
        .with_target(false)
        .with_level(true)
        .init();

    print_separator("SW4RM Agent Handoff Demo");
    println!("SDK Version: {}", sw4rm_sdk::VERSION);
    println!("\nThis example demonstrates agent-to-agent task handoff with context transfer.\n");

    // Create shared client
    let mut client = HandoffClientStub::new();

    // Create agents
    let mut generalist = GeneralistAgent::new("agent-generalist", "Generalist Agent", client.clone());
    let mut db_specialist = SpecialistAgent::new(
        "specialist-db",
        "Database Specialist",
        "database",
        vec!["database".to_string(), "sql".to_string(), "data-modeling".to_string()],
    );
    let mut security_specialist = SpecialistAgent::new(
        "specialist-security",
        "Security Specialist",
        "security",
        vec!["security".to_string(), "authentication".to_string(), "encryption".to_string()],
    );

    // =========================================================================
    // Scenario 1: Successful handoff to database specialist
    // =========================================================================
    print_separator("Scenario 1: Database Query Handoff");

    println!("User asks a database-related question...\n");

    let query = "How can I optimize my database queries for better performance?";
    println!("User: {}\n", query);

    match generalist.handle_query(query)? {
        Some(handoff_request_id) => {
            println!("Handoff initiated: {}\n", handoff_request_id);

            // Sync client state
            client = generalist.client.clone();

            // DB specialist checks pending handoffs
            let pending = client.get_pending_handoffs(&db_specialist.agent_id);
            println!("Pending handoffs for DB specialist: {}", pending.len());

            if let Some(request) = pending.first() {
                // Clone the data we need before mutating client
                let request_id = request.request_id.clone();
                let context_snapshot = request.context_snapshot.clone();

                // Evaluate and accept
                let (can_accept, _) = db_specialist.evaluate_request(request);
                if can_accept {
                    let response = client.accept_handoff(&request_id, &db_specialist.agent_id)?;
                    println!("Handoff accepted: {}\n", response.request_id);

                    // Transfer context
                    let context = deserialize_context(&context_snapshot)?;
                    let specialist_response = db_specialist.receive_handoff(context)?;
                    println!("Specialist response: {}\n", specialist_response);

                    // Complete handoff
                    client.complete_handoff(&request_id)?;
                    println!("Handoff completed successfully!");
                }
            }

            print_conversation(&db_specialist.conversation_history);
        }
        None => {
            println!("Query handled locally (no handoff needed)");
        }
    }

    // =========================================================================
    // Scenario 2: Rejected handoff (missing capabilities)
    // =========================================================================
    print_separator("Scenario 2: Rejected Handoff (Missing Capabilities)");

    // Reset agents
    let mut client = HandoffClientStub::new();
    let generalist = GeneralistAgent::new("agent-generalist", "Generalist Agent", client.clone());
    let limited_specialist = SpecialistAgent::new(
        "specialist-limited",
        "Limited Specialist",
        "general",
        vec!["general".to_string()], // Missing database capabilities
    );

    println!("User asks about databases, but target specialist lacks capabilities...\n");

    let query = "How do I write efficient SQL joins?";
    println!("User: {}\n", query);

    // Generalist initiates handoff to limited specialist (wrong target)
    let context = generalist.build_context();
    let context_bytes = serialize_context(&context)?;
    let request = HandoffRequest {
        request_id: format!("handoff-{}", new_uuid().split('-').next().unwrap()),
        from_agent: generalist.agent_id.clone(),
        to_agent: limited_specialist.agent_id.clone(),
        reason: "Database expertise needed".to_string(),
        context_snapshot: context_bytes,
        capabilities_required: vec!["database".to_string(), "sql".to_string()],
        priority: 5,
        timeout_seconds: 300,
    };

    let request_id = client.request_handoff(request.clone())?;
    println!("Handoff initiated: {}\n", request_id);

    // Limited specialist evaluates and rejects
    let (can_accept, rejection_reason) = limited_specialist.evaluate_request(&request);
    if !can_accept {
        let response = client.reject_handoff(
            &request_id,
            &limited_specialist.agent_id,
            rejection_reason.as_deref().unwrap_or("Cannot handle request"),
        )?;
        println!("Handoff rejected: {}", response.rejection_reason.unwrap_or_default());
    }

    let status = client.get_status(&request_id);
    println!("Final status: {:?}", status);

    // =========================================================================
    // Scenario 3: Security handoff with context preservation
    // =========================================================================
    print_separator("Scenario 3: Security Handoff with Context");

    let mut client = HandoffClientStub::new();
    let mut generalist = GeneralistAgent::new("agent-generalist", "Generalist Agent", client.clone());

    // Build up some conversation history first
    let _ = generalist.handle_query("I need help with my application")?;
    let _ = generalist.handle_query("It's a web app with user accounts")?;

    // Now ask about security
    let query = "How should I implement authentication for my users?";
    println!("User: {}\n", query);

    match generalist.handle_query(query)? {
        Some(_handoff_request_id) => {
            client = generalist.client.clone();

            let pending = client.get_pending_handoffs(&security_specialist.agent_id);
            if let Some(request) = pending.first() {
                // Clone the data we need before mutating client
                let request_id = request.request_id.clone();
                let context_snapshot = request.context_snapshot.clone();

                // Accept and receive context
                client.accept_handoff(&request_id, &security_specialist.agent_id)?;

                let context = deserialize_context(&context_snapshot)?;
                println!("Context transferred with {} previous messages\n", context.conversation_history.len());

                let response = security_specialist.receive_handoff(context)?;
                println!("Security specialist response: {}\n", response);

                client.complete_handoff(&request_id)?;
            }

            print_conversation(&security_specialist.conversation_history);
        }
        None => {
            println!("Handled locally");
        }
    }

    // =========================================================================
    // Summary
    // =========================================================================
    print_separator("Demo Complete");
    println!("The Agent Handoff pattern enables:");
    println!();
    println!("1. Task delegation from generalist to specialist agents");
    println!("2. Context preservation across agent boundaries");
    println!("3. Capability matching for appropriate routing");
    println!("4. Accept/reject flows for handoff negotiation");
    println!("5. Conversation history continuity");
    println!();
    println!("Key features demonstrated:");
    println!("  - HandoffRequest with context snapshot");
    println!("  - Capability-based acceptance/rejection");
    println!("  - Context deserialization and restoration");
    println!("  - Handoff lifecycle (PENDING -> ACCEPTED -> COMPLETED)");
    println!();

    Ok(())
}
