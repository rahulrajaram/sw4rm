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

//! Workflow Orchestration Example
//!
//! Demonstrates DAG-based workflow execution:
//!
//! 1. Creating workflow definitions with nodes and dependencies
//! 2. Starting workflow instances
//! 3. Monitoring workflow execution progress
//! 4. Handling node completion events
//!
//! This example uses stub implementations since WorkflowClient
//! is not yet implemented in the Rust SDK. See Phase 3.3 of the
//! IMPLEMENTATION_PLAN.md for the full client implementation.

use serde::{Deserialize, Serialize};
use serde_json::json;
use std::collections::{HashMap, HashSet};
use std::time::Duration;
use sw4rm_sdk::prelude::*;
use tokio::time::sleep;

// ============================================================================
// Stub Types (will be replaced by proto-generated types in Phase 3.3)
// ============================================================================

/// Status of a workflow node
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum NodeStatus {
    Unspecified = 0,
    Pending = 1,
    Ready = 2,
    Running = 3,
    Completed = 4,
    Failed = 5,
    Skipped = 6,
}

impl std::fmt::Display for NodeStatus {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            NodeStatus::Unspecified => write!(f, "UNSPECIFIED"),
            NodeStatus::Pending => write!(f, "PENDING"),
            NodeStatus::Ready => write!(f, "READY"),
            NodeStatus::Running => write!(f, "RUNNING"),
            NodeStatus::Completed => write!(f, "COMPLETED"),
            NodeStatus::Failed => write!(f, "FAILED"),
            NodeStatus::Skipped => write!(f, "SKIPPED"),
        }
    }
}

/// Type of trigger for a workflow node
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum TriggerType {
    Unspecified = 0,
    Event = 1,
    Schedule = 2,
    Manual = 3,
    Dependency = 4,
}

/// A node in the workflow DAG
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowNode {
    pub node_id: String,
    pub agent_id: String,
    pub dependencies: Vec<String>,
    pub trigger_type: TriggerType,
    pub input_mapping: HashMap<String, String>,
    pub output_mapping: HashMap<String, String>,
    pub metadata: HashMap<String, String>,
}

/// Definition of a workflow
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowDefinition {
    pub workflow_id: String,
    pub nodes: HashMap<String, WorkflowNode>,
    pub metadata: HashMap<String, String>,
}

/// State of a node during execution
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeState {
    pub node_id: String,
    pub status: NodeStatus,
    pub started_at: Option<String>,
    pub completed_at: Option<String>,
    pub output: Option<String>,
    pub error: Option<String>,
}

/// State of a workflow instance
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowState {
    pub workflow_id: String,
    pub instance_id: String,
    pub node_states: HashMap<String, NodeState>,
    pub workflow_data: String,
    pub started_at: String,
    pub completed_at: Option<String>,
}

// ============================================================================
// Stub Client (will be replaced by actual gRPC client in Phase 3.3)
// ============================================================================

/// Stub client for Workflow service
#[derive(Debug, Clone)]
pub struct WorkflowClientStub {
    definitions: HashMap<String, WorkflowDefinition>,
    instances: HashMap<String, WorkflowState>,
}

impl WorkflowClientStub {
    pub fn new() -> Self {
        Self {
            definitions: HashMap::new(),
            instances: HashMap::new(),
        }
    }

    /// Create a new workflow definition
    pub fn create_workflow(&mut self, definition: WorkflowDefinition) -> Result<String> {
        let workflow_id = definition.workflow_id.clone();

        // Validate DAG (check for cycles)
        self.validate_dag(&definition)?;

        tracing::info!("Creating workflow: {}", workflow_id);
        self.definitions.insert(workflow_id.clone(), definition);
        Ok(workflow_id)
    }

    /// Validate that the workflow is a valid DAG (no cycles)
    fn validate_dag(&self, definition: &WorkflowDefinition) -> Result<()> {
        let mut visited = HashSet::new();
        let mut rec_stack = HashSet::new();

        fn has_cycle(
            node_id: &str,
            nodes: &HashMap<String, WorkflowNode>,
            visited: &mut HashSet<String>,
            rec_stack: &mut HashSet<String>,
        ) -> bool {
            visited.insert(node_id.to_string());
            rec_stack.insert(node_id.to_string());

            if let Some(node) = nodes.get(node_id) {
                for dep in &node.dependencies {
                    if !visited.contains(dep) {
                        if has_cycle(dep, nodes, visited, rec_stack) {
                            return true;
                        }
                    } else if rec_stack.contains(dep) {
                        return true;
                    }
                }
            }

            rec_stack.remove(node_id);
            false
        }

        for node_id in definition.nodes.keys() {
            if !visited.contains(node_id) {
                if has_cycle(node_id, &definition.nodes, &mut visited, &mut rec_stack) {
                    return Err(Error::Validation(format!(
                        "Workflow {} contains a cycle",
                        definition.workflow_id
                    )));
                }
            }
        }

        Ok(())
    }

    /// Start a workflow instance
    pub fn start_workflow(
        &mut self,
        workflow_id: &str,
        initial_data: serde_json::Value,
    ) -> Result<WorkflowState> {
        let definition = self
            .definitions
            .get(workflow_id)
            .ok_or_else(|| Error::NotFound(format!("Workflow not found: {}", workflow_id)))?
            .clone();

        let instance_id = format!("instance-{}", new_uuid().split('-').next().unwrap());

        // Initialize node states
        let mut node_states = HashMap::new();
        for (node_id, _) in &definition.nodes {
            node_states.insert(
                node_id.clone(),
                NodeState {
                    node_id: node_id.clone(),
                    status: NodeStatus::Pending,
                    started_at: None,
                    completed_at: None,
                    output: None,
                    error: None,
                },
            );
        }

        let state = WorkflowState {
            workflow_id: workflow_id.to_string(),
            instance_id: instance_id.clone(),
            node_states,
            workflow_data: initial_data.to_string(),
            started_at: chrono::Utc::now().to_rfc3339(),
            completed_at: None,
        };

        tracing::info!(
            "Started workflow instance: {} for workflow: {}",
            instance_id,
            workflow_id
        );
        self.instances.insert(instance_id.clone(), state.clone());
        Ok(state)
    }

    /// Get workflow state
    pub fn get_workflow_state(&self, instance_id: &str) -> Result<WorkflowState> {
        self.instances
            .get(instance_id)
            .cloned()
            .ok_or_else(|| Error::NotFound(format!("Instance not found: {}", instance_id)))
    }

    /// Get ready nodes (nodes whose dependencies are all completed)
    pub fn get_ready_nodes(&self, instance_id: &str) -> Result<Vec<String>> {
        let state = self.get_workflow_state(instance_id)?;
        let definition = self
            .definitions
            .get(&state.workflow_id)
            .ok_or_else(|| Error::NotFound(format!("Workflow not found: {}", state.workflow_id)))?;

        let mut ready = Vec::new();

        for (node_id, node) in &definition.nodes {
            let node_state = state.node_states.get(node_id);
            if let Some(ns) = node_state {
                if ns.status != NodeStatus::Pending {
                    continue;
                }
            }

            // Check if all dependencies are completed
            let deps_complete = node.dependencies.iter().all(|dep| {
                state
                    .node_states
                    .get(dep)
                    .map(|s| s.status == NodeStatus::Completed)
                    .unwrap_or(false)
            });

            if deps_complete {
                ready.push(node_id.clone());
            }
        }

        Ok(ready)
    }

    /// Mark a node as running
    pub fn start_node(&mut self, instance_id: &str, node_id: &str) -> Result<()> {
        let state = self
            .instances
            .get_mut(instance_id)
            .ok_or_else(|| Error::NotFound(format!("Instance not found: {}", instance_id)))?;

        if let Some(node_state) = state.node_states.get_mut(node_id) {
            node_state.status = NodeStatus::Running;
            node_state.started_at = Some(chrono::Utc::now().to_rfc3339());
            tracing::info!("Node {} started in instance {}", node_id, instance_id);
        }

        Ok(())
    }

    /// Complete a node
    pub fn complete_node(
        &mut self,
        instance_id: &str,
        node_id: &str,
        output: serde_json::Value,
    ) -> Result<()> {
        let state = self
            .instances
            .get_mut(instance_id)
            .ok_or_else(|| Error::NotFound(format!("Instance not found: {}", instance_id)))?;

        if let Some(node_state) = state.node_states.get_mut(node_id) {
            node_state.status = NodeStatus::Completed;
            node_state.completed_at = Some(chrono::Utc::now().to_rfc3339());
            node_state.output = Some(output.to_string());
            tracing::info!("Node {} completed in instance {}", node_id, instance_id);
        }

        // Check if workflow is complete
        let all_complete = state
            .node_states
            .values()
            .all(|s| s.status == NodeStatus::Completed || s.status == NodeStatus::Skipped);

        if all_complete {
            state.completed_at = Some(chrono::Utc::now().to_rfc3339());
            tracing::info!("Workflow instance {} completed", instance_id);
        }

        Ok(())
    }

    /// Fail a node
    pub fn fail_node(&mut self, instance_id: &str, node_id: &str, error: &str) -> Result<()> {
        let state = self
            .instances
            .get_mut(instance_id)
            .ok_or_else(|| Error::NotFound(format!("Instance not found: {}", instance_id)))?;

        if let Some(node_state) = state.node_states.get_mut(node_id) {
            node_state.status = NodeStatus::Failed;
            node_state.completed_at = Some(chrono::Utc::now().to_rfc3339());
            node_state.error = Some(error.to_string());
            tracing::warn!("Node {} failed in instance {}: {}", node_id, instance_id, error);
        }

        Ok(())
    }

    /// Get workflow definition
    pub fn get_definition(&self, workflow_id: &str) -> Result<WorkflowDefinition> {
        self.definitions
            .get(workflow_id)
            .cloned()
            .ok_or_else(|| Error::NotFound(format!("Workflow not found: {}", workflow_id)))
    }

    /// Check if workflow is complete
    pub fn is_complete(&self, instance_id: &str) -> Result<bool> {
        let state = self.get_workflow_state(instance_id)?;
        Ok(state.completed_at.is_some())
    }
}

// ============================================================================
// Workflow Executor
// ============================================================================

/// Executes workflow nodes
struct WorkflowExecutor {
    client: WorkflowClientStub,
}

impl WorkflowExecutor {
    fn new(client: WorkflowClientStub) -> Self {
        Self { client }
    }

    /// Execute a workflow to completion
    async fn execute(&mut self, instance_id: &str) -> Result<()> {
        tracing::info!("Starting workflow execution: {}", instance_id);

        loop {
            // Check if workflow is complete
            if self.client.is_complete(instance_id)? {
                tracing::info!("Workflow {} completed", instance_id);
                break;
            }

            // Get ready nodes
            let ready_nodes = self.client.get_ready_nodes(instance_id)?;

            if ready_nodes.is_empty() {
                // No ready nodes and not complete - check for failures
                let state = self.client.get_workflow_state(instance_id)?;
                let has_failed = state.node_states.values().any(|s| s.status == NodeStatus::Failed);
                if has_failed {
                    tracing::warn!("Workflow {} has failed nodes, stopping", instance_id);
                    break;
                }
                // Otherwise wait and retry
                sleep(Duration::from_millis(100)).await;
                continue;
            }

            // Execute ready nodes (in parallel in a real implementation)
            for node_id in ready_nodes {
                self.execute_node(instance_id, &node_id).await?;
            }
        }

        Ok(())
    }

    /// Execute a single node
    async fn execute_node(&mut self, instance_id: &str, node_id: &str) -> Result<()> {
        let state = self.client.get_workflow_state(instance_id)?;
        let definition = self.client.get_definition(&state.workflow_id)?;

        let node = definition
            .nodes
            .get(node_id)
            .ok_or_else(|| Error::NotFound(format!("Node not found: {}", node_id)))?;

        tracing::info!(
            "Executing node: {} (agent: {})",
            node_id,
            node.agent_id
        );

        // Mark node as running
        self.client.start_node(instance_id, node_id)?;

        // Simulate node execution based on agent type
        let result = self.simulate_agent_execution(&node.agent_id, &state.workflow_data).await;

        match result {
            Ok(output) => {
                self.client.complete_node(instance_id, node_id, output)?;
            }
            Err(e) => {
                self.client.fail_node(instance_id, node_id, &e.to_string())?;
            }
        }

        Ok(())
    }

    /// Simulate agent execution (in real impl, this would call the actual agent)
    async fn simulate_agent_execution(
        &self,
        agent_id: &str,
        _workflow_data: &str,
    ) -> Result<serde_json::Value> {
        // Simulate processing time
        sleep(Duration::from_millis(100)).await;

        // Simulate different agent behaviors
        match agent_id {
            "requirements-agent" => Ok(json!({
                "stage": "requirements",
                "status": "analyzed",
                "requirements": ["REQ-001", "REQ-002", "REQ-003"],
            })),
            "planning-agent" => Ok(json!({
                "stage": "planning",
                "status": "planned",
                "tasks": ["task-1", "task-2", "task-3"],
            })),
            "coding-agent" => Ok(json!({
                "stage": "coding",
                "status": "implemented",
                "files_changed": ["src/main.rs", "src/lib.rs"],
            })),
            "review-agent" => Ok(json!({
                "stage": "review",
                "status": "approved",
                "score": 8.5,
            })),
            "testing-agent" => Ok(json!({
                "stage": "testing",
                "status": "passed",
                "tests_run": 42,
                "tests_passed": 42,
            })),
            "deployment-agent" => Ok(json!({
                "stage": "deployment",
                "status": "deployed",
                "environment": "staging",
            })),
            _ => Ok(json!({
                "stage": "unknown",
                "status": "completed",
                "agent_id": agent_id,
            })),
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

fn print_workflow_graph(definition: &WorkflowDefinition) {
    println!("Workflow DAG: {}", definition.workflow_id);
    println!("{:-<70}", "");

    // Find nodes with no dependencies (entry points)
    let entry_nodes: Vec<_> = definition
        .nodes
        .iter()
        .filter(|(_, n)| n.dependencies.is_empty())
        .map(|(id, _)| id.clone())
        .collect();

    println!("Entry nodes: {:?}", entry_nodes);
    println!();

    // Print each node and its dependencies
    for (node_id, node) in &definition.nodes {
        let deps = if node.dependencies.is_empty() {
            "(none)".to_string()
        } else {
            node.dependencies.join(", ")
        };
        println!("  {} -> agent: {} (deps: {})", node_id, node.agent_id, deps);
    }
    println!("{:-<70}", "");
}

fn print_workflow_state(state: &WorkflowState) {
    println!("\nWorkflow State: {}", state.instance_id);
    println!("{:-<70}", "");
    println!("  Workflow ID: {}", state.workflow_id);
    println!("  Started: {}", state.started_at);
    if let Some(completed) = &state.completed_at {
        println!("  Completed: {}", completed);
    }
    println!("\n  Node States:");
    for (node_id, node_state) in &state.node_states {
        let output_preview = node_state
            .output
            .as_ref()
            .map(|o| {
                if o.len() > 50 {
                    format!("{}...", &o[..50])
                } else {
                    o.clone()
                }
            })
            .unwrap_or_else(|| "(no output)".to_string());

        println!(
            "    {} [{}] {}",
            node_id, node_state.status, output_preview
        );
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

    print_separator("SW4RM Workflow Orchestration Demo");
    println!("SDK Version: {}", sw4rm_sdk::VERSION);
    println!("\nThis example demonstrates DAG-based workflow execution.");
    println!("A typical software development workflow is modeled:\n");
    println!("  Requirements -> Planning -> Coding -> Review -> Testing -> Deployment\n");

    let mut client = WorkflowClientStub::new();

    // =========================================================================
    // Create a software development workflow
    // =========================================================================
    print_separator("Step 1: Define Workflow");

    let workflow_id = format!("dev-workflow-{}", new_uuid().split('-').next().unwrap());

    let definition = WorkflowDefinition {
        workflow_id: workflow_id.clone(),
        nodes: HashMap::from([
            (
                "requirements".to_string(),
                WorkflowNode {
                    node_id: "requirements".to_string(),
                    agent_id: "requirements-agent".to_string(),
                    dependencies: vec![],
                    trigger_type: TriggerType::Manual,
                    input_mapping: HashMap::from([("task".to_string(), "$.task_description".to_string())]),
                    output_mapping: HashMap::from([("reqs".to_string(), "$.requirements".to_string())]),
                    metadata: HashMap::new(),
                },
            ),
            (
                "planning".to_string(),
                WorkflowNode {
                    node_id: "planning".to_string(),
                    agent_id: "planning-agent".to_string(),
                    dependencies: vec!["requirements".to_string()],
                    trigger_type: TriggerType::Dependency,
                    input_mapping: HashMap::from([("reqs".to_string(), "$.requirements".to_string())]),
                    output_mapping: HashMap::from([("plan".to_string(), "$.tasks".to_string())]),
                    metadata: HashMap::new(),
                },
            ),
            (
                "coding".to_string(),
                WorkflowNode {
                    node_id: "coding".to_string(),
                    agent_id: "coding-agent".to_string(),
                    dependencies: vec!["planning".to_string()],
                    trigger_type: TriggerType::Dependency,
                    input_mapping: HashMap::from([("plan".to_string(), "$.tasks".to_string())]),
                    output_mapping: HashMap::from([("code".to_string(), "$.files_changed".to_string())]),
                    metadata: HashMap::new(),
                },
            ),
            (
                "review".to_string(),
                WorkflowNode {
                    node_id: "review".to_string(),
                    agent_id: "review-agent".to_string(),
                    dependencies: vec!["coding".to_string()],
                    trigger_type: TriggerType::Dependency,
                    input_mapping: HashMap::from([("code".to_string(), "$.files_changed".to_string())]),
                    output_mapping: HashMap::from([("review_score".to_string(), "$.score".to_string())]),
                    metadata: HashMap::new(),
                },
            ),
            (
                "testing".to_string(),
                WorkflowNode {
                    node_id: "testing".to_string(),
                    agent_id: "testing-agent".to_string(),
                    dependencies: vec!["coding".to_string()],
                    trigger_type: TriggerType::Dependency,
                    input_mapping: HashMap::from([("code".to_string(), "$.files_changed".to_string())]),
                    output_mapping: HashMap::from([("test_results".to_string(), "$.tests_passed".to_string())]),
                    metadata: HashMap::new(),
                },
            ),
            (
                "deployment".to_string(),
                WorkflowNode {
                    node_id: "deployment".to_string(),
                    agent_id: "deployment-agent".to_string(),
                    dependencies: vec!["review".to_string(), "testing".to_string()],
                    trigger_type: TriggerType::Dependency,
                    input_mapping: HashMap::new(),
                    output_mapping: HashMap::from([("deploy_status".to_string(), "$.status".to_string())]),
                    metadata: HashMap::new(),
                },
            ),
        ]),
        metadata: HashMap::from([
            ("version".to_string(), "1.0.0".to_string()),
            ("description".to_string(), "Software development workflow".to_string()),
        ]),
    };

    client.create_workflow(definition.clone())?;
    print_workflow_graph(&definition);

    // =========================================================================
    // Start workflow instance
    // =========================================================================
    print_separator("Step 2: Start Workflow Instance");

    let initial_data = json!({
        "task_description": "Implement user authentication feature",
        "priority": "high",
        "deadline": "2025-01-15",
    });

    let state = client.start_workflow(&workflow_id, initial_data)?;
    println!("Started workflow instance: {}", state.instance_id);
    print_workflow_state(&state);

    // =========================================================================
    // Execute workflow
    // =========================================================================
    print_separator("Step 3: Execute Workflow");

    let mut executor = WorkflowExecutor::new(client.clone());
    executor.execute(&state.instance_id).await?;

    // =========================================================================
    // Show final state
    // =========================================================================
    print_separator("Step 4: Final Workflow State");

    let final_state = executor.client.get_workflow_state(&state.instance_id)?;
    print_workflow_state(&final_state);

    // =========================================================================
    // Summary
    // =========================================================================
    print_separator("Demo Complete");
    println!("The Workflow Orchestration pattern enables:");
    println!();
    println!("1. DAG-based workflow definitions with dependency management");
    println!("2. Automatic scheduling of ready nodes");
    println!("3. Parallel execution of independent nodes");
    println!("4. Input/output mapping between nodes via workflow state");
    println!("5. Node status tracking (PENDING, RUNNING, COMPLETED, FAILED)");
    println!();
    println!("In this demo, the development workflow executed:");
    println!("  - Requirements analysis");
    println!("  - Planning (depends on requirements)");
    println!("  - Coding (depends on planning)");
    println!("  - Review and Testing (both depend on coding, run in parallel)");
    println!("  - Deployment (depends on both review and testing)");
    println!();

    Ok(())
}
