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

//! Workflow orchestration for SW4RM.
//!
//! This module provides the `WorkflowClient` for managing multi-agent workflows
//! as directed acyclic graphs (DAGs). Inspired by CrewAI Flows, it enables
//! sophisticated coordination patterns with dependencies, triggers, and state
//! management.
//!
//! Core components:
//! - `WorkflowDefinition`: Immutable workflow structure
//! - `WorkflowInstance`: Runtime state of executing workflow
//! - `WorkflowNode`: Individual node in the workflow DAG
//! - `WorkflowClient`: Client for managing workflows

use crate::{Error, Result};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::sync::{Arc, RwLock};
use uuid::Uuid;

/// Execution status of a workflow node.
///
/// Tracks the lifecycle state of individual nodes during workflow execution.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum NodeStatus {
    /// Node waiting for dependencies
    Pending = 1,
    /// Node ready to execute
    Ready = 2,
    /// Node currently executing
    Running = 3,
    /// Node finished successfully
    Completed = 4,
    /// Node encountered an error
    Failed = 5,
    /// Node skipped due to conditional logic
    Skipped = 6,
}

impl Default for NodeStatus {
    fn default() -> Self {
        Self::Pending
    }
}

impl NodeStatus {
    /// Check if the node is in a terminal state.
    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Completed | Self::Failed | Self::Skipped)
    }
}

/// Trigger mechanism for node execution.
///
/// Defines how and when a node should be activated within the workflow.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[repr(i32)]
pub enum TriggerType {
    /// Triggered by specific events
    Event = 1,
    /// Triggered on a schedule (cron-like)
    Schedule = 2,
    /// Triggered by explicit user action
    Manual = 3,
    /// Triggered by dependency completion
    Dependency = 4,
}

impl Default for TriggerType {
    fn default() -> Self {
        Self::Dependency
    }
}

/// A single node in a workflow DAG.
///
/// Represents an agent or operation with dependencies, triggers, and I/O mappings.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowNode {
    /// Unique identifier for this node within the workflow
    pub node_id: String,
    /// Identifier of the agent that executes this node
    pub agent_id: String,
    /// Set of node_ids that must complete before this node runs
    pub dependencies: HashSet<String>,
    /// How this node is triggered
    pub trigger_type: TriggerType,
    /// Maps workflow state keys to node input parameters
    pub input_mapping: HashMap<String, String>,
    /// Maps node output keys to workflow state keys
    pub output_mapping: HashMap<String, String>,
    /// Additional node configuration and context
    pub metadata: HashMap<String, String>,
}

impl WorkflowNode {
    /// Create a new workflow node.
    ///
    /// # Arguments
    ///
    /// * `node_id` - Unique identifier for the node
    /// * `agent_id` - Identifier of the agent that executes this node
    ///
    /// # Errors
    ///
    /// Returns an error if node_id or agent_id is empty.
    pub fn new(node_id: String, agent_id: String) -> Result<Self> {
        if node_id.trim().is_empty() {
            return Err(Error::Config("node_id must be a non-empty string".to_string()));
        }
        if agent_id.trim().is_empty() {
            return Err(Error::Config("agent_id must be a non-empty string".to_string()));
        }
        Ok(Self {
            node_id,
            agent_id,
            dependencies: HashSet::new(),
            trigger_type: TriggerType::default(),
            input_mapping: HashMap::new(),
            output_mapping: HashMap::new(),
            metadata: HashMap::new(),
        })
    }

    /// Add a dependency to this node.
    pub fn with_dependency(mut self, dep: String) -> Self {
        self.dependencies.insert(dep);
        self
    }

    /// Set the trigger type.
    pub fn with_trigger(mut self, trigger: TriggerType) -> Self {
        self.trigger_type = trigger;
        self
    }

    /// Add an input mapping.
    pub fn with_input(mut self, param_name: String, state_key: String) -> Self {
        self.input_mapping.insert(param_name, state_key);
        self
    }

    /// Add an output mapping.
    pub fn with_output(mut self, output_key: String, state_key: String) -> Self {
        self.output_mapping.insert(output_key, state_key);
        self
    }

    /// Add metadata.
    pub fn with_metadata(mut self, key: String, value: String) -> Self {
        self.metadata.insert(key, value);
        self
    }
}

/// Immutable workflow definition as a DAG of nodes.
///
/// Defines the complete structure of a multi-agent workflow including all nodes,
/// their dependencies, and metadata.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowDefinition {
    /// Unique identifier for this workflow
    pub workflow_id: String,
    /// Map of node_id to WorkflowNode
    pub nodes: HashMap<String, WorkflowNode>,
    /// When the workflow was created
    pub created_at: DateTime<Utc>,
    /// Additional workflow-level configuration
    pub metadata: HashMap<String, String>,
}

impl WorkflowDefinition {
    /// Create a new workflow definition.
    ///
    /// # Arguments
    ///
    /// * `workflow_id` - Unique identifier for the workflow
    /// * `nodes` - Map of node_id to WorkflowNode
    ///
    /// # Errors
    ///
    /// Returns an error if workflow_id is empty, no nodes are provided,
    /// or dependencies reference non-existent nodes.
    pub fn new(workflow_id: String, nodes: HashMap<String, WorkflowNode>) -> Result<Self> {
        if workflow_id.trim().is_empty() {
            return Err(Error::Config("workflow_id must be a non-empty string".to_string()));
        }
        if nodes.is_empty() {
            return Err(Error::Config("workflow must contain at least one node".to_string()));
        }

        // Validate all dependency references exist
        let all_node_ids: HashSet<_> = nodes.keys().cloned().collect();
        for node in nodes.values() {
            let invalid_deps: HashSet<_> = node
                .dependencies
                .difference(&all_node_ids)
                .cloned()
                .collect();
            if !invalid_deps.is_empty() {
                return Err(Error::Config(format!(
                    "node {} has invalid dependencies: {:?}",
                    node.node_id, invalid_deps
                )));
            }
        }

        Ok(Self {
            workflow_id,
            nodes,
            created_at: Utc::now(),
            metadata: HashMap::new(),
        })
    }

    /// Get a node by ID.
    pub fn get_node(&self, node_id: &str) -> Option<&WorkflowNode> {
        self.nodes.get(node_id)
    }

    /// Get all nodes with no dependencies (entry points).
    pub fn get_root_nodes(&self) -> HashSet<String> {
        self.nodes
            .iter()
            .filter(|(_, node)| node.dependencies.is_empty())
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// Get all nodes that no other nodes depend on (exit points).
    pub fn get_leaf_nodes(&self) -> HashSet<String> {
        let all_deps: HashSet<String> = self
            .nodes
            .values()
            .flat_map(|n| n.dependencies.iter().cloned())
            .collect();

        self.nodes
            .keys()
            .filter(|id| !all_deps.contains(*id))
            .cloned()
            .collect()
    }
}

/// Runtime state of a single workflow node.
///
/// Tracks the execution state, results, and errors for a node during workflow
/// execution.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NodeState {
    /// The node this state belongs to
    pub node_id: String,
    /// Current execution status
    pub status: NodeStatus,
    /// Output data from node execution (JSON string)
    pub output: Option<String>,
    /// Error information if node failed
    pub error: Option<String>,
    /// When node execution started
    pub started_at: Option<DateTime<Utc>>,
    /// When node execution completed
    pub completed_at: Option<DateTime<Utc>>,
}

impl NodeState {
    /// Create a new node state in pending status.
    pub fn new(node_id: String) -> Self {
        Self {
            node_id,
            status: NodeStatus::Pending,
            output: None,
            error: None,
            started_at: None,
            completed_at: None,
        }
    }

    /// Check if node is in a terminal state.
    pub fn is_terminal(&self) -> bool {
        self.status.is_terminal()
    }

    /// Calculate execution duration in milliseconds.
    pub fn duration_ms(&self) -> Option<i64> {
        match (self.started_at, self.completed_at) {
            (Some(start), Some(end)) => Some((end - start).num_milliseconds()),
            _ => None,
        }
    }
}

/// Runtime state for an executing workflow.
///
/// Maintains the execution state for all nodes and shared workflow data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WorkflowInstance {
    /// Identifier of the workflow being executed
    pub workflow_id: String,
    /// Unique instance identifier
    pub instance_id: String,
    /// Map of node_id to NodeState for tracking execution
    pub node_states: HashMap<String, NodeState>,
    /// Shared workflow data (JSON string)
    pub workflow_data: String,
    /// When the workflow execution started
    pub started_at: Option<DateTime<Utc>>,
    /// When the workflow execution completed
    pub completed_at: Option<DateTime<Utc>>,
    /// Additional runtime metadata
    pub metadata: HashMap<String, String>,
}

impl WorkflowInstance {
    /// Create a new workflow instance.
    pub fn new(workflow_id: String) -> Self {
        Self {
            workflow_id,
            instance_id: Uuid::new_v4().to_string(),
            node_states: HashMap::new(),
            workflow_data: "{}".to_string(),
            started_at: None,
            completed_at: None,
            metadata: HashMap::new(),
        }
    }

    /// Get the state of a specific node.
    pub fn get_node_state(&self, node_id: &str) -> Option<&NodeState> {
        self.node_states.get(node_id)
    }

    /// Check if all nodes are in terminal states.
    pub fn is_completed(&self) -> bool {
        self.node_states.values().all(|s| s.is_terminal())
    }

    /// Check if any nodes failed.
    pub fn has_failures(&self) -> bool {
        self.node_states
            .values()
            .any(|s| s.status == NodeStatus::Failed)
    }

    /// Get all successfully completed node IDs.
    pub fn get_completed_nodes(&self) -> HashSet<String> {
        self.node_states
            .iter()
            .filter(|(_, s)| s.status == NodeStatus::Completed)
            .map(|(id, _)| id.clone())
            .collect()
    }

    /// Get all failed node IDs.
    pub fn get_failed_nodes(&self) -> HashSet<String> {
        self.node_states
            .iter()
            .filter(|(_, s)| s.status == NodeStatus::Failed)
            .map(|(id, _)| id.clone())
            .collect()
    }
}

/// Internal storage for workflows.
struct WorkflowStorage {
    definitions: HashMap<String, WorkflowDefinition>,
    instances: HashMap<String, WorkflowInstance>,
}

impl WorkflowStorage {
    fn new() -> Self {
        Self {
            definitions: HashMap::new(),
            instances: HashMap::new(),
        }
    }
}

/// Client for managing workflow operations.
///
/// This client provides methods for creating workflows, starting execution,
/// querying status, and canceling workflows. It maintains an in-memory store
/// of workflow definitions and instances.
///
/// In a production system, this would interface with a distributed workflow
/// service via gRPC. For now, it provides a local implementation suitable
/// for development and testing.
///
/// # Example
///
/// ```rust
/// use sw4rm_sdk::clients::workflow::{WorkflowClient, WorkflowDefinition, WorkflowNode};
/// use std::collections::HashMap;
///
/// let client = WorkflowClient::new();
///
/// // Create nodes
/// let mut nodes = HashMap::new();
/// let node1 = WorkflowNode::new("fetch".to_string(), "fetcher_agent".to_string()).unwrap();
/// let node2 = WorkflowNode::new("process".to_string(), "processor_agent".to_string())
///     .unwrap()
///     .with_dependency("fetch".to_string());
/// nodes.insert("fetch".to_string(), node1);
/// nodes.insert("process".to_string(), node2);
///
/// // Create workflow definition
/// let definition = WorkflowDefinition::new("data_pipeline".to_string(), nodes).unwrap();
///
/// // Register and start
/// let workflow_id = client.create_workflow(definition).unwrap();
/// let instance = client.start_workflow(&workflow_id).unwrap();
/// ```
#[derive(Clone)]
pub struct WorkflowClient {
    storage: Arc<RwLock<WorkflowStorage>>,
}

impl Default for WorkflowClient {
    fn default() -> Self {
        Self::new()
    }
}

impl WorkflowClient {
    /// Create a new workflow client with in-memory storage.
    pub fn new() -> Self {
        Self {
            storage: Arc::new(RwLock::new(WorkflowStorage::new())),
        }
    }

    /// Create a new workflow definition.
    ///
    /// Validates the DAG structure and stores the workflow definition.
    ///
    /// # Arguments
    ///
    /// * `definition` - The workflow definition containing nodes and metadata
    ///
    /// # Returns
    ///
    /// The workflow_id of the created workflow.
    ///
    /// # Errors
    ///
    /// Returns an error if the workflow already exists or has a cycle.
    pub fn create_workflow(&self, definition: WorkflowDefinition) -> Result<String> {
        // Validate DAG - check for cycles
        self.validate_dag(&definition)?;

        let workflow_id = definition.workflow_id.clone();

        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        if storage.definitions.contains_key(&workflow_id) {
            return Err(Error::Config(format!(
                "Workflow with id '{}' already exists",
                workflow_id
            )));
        }

        storage.definitions.insert(workflow_id.clone(), definition);

        Ok(workflow_id)
    }

    /// Start a workflow execution.
    ///
    /// Creates a new instance of the workflow and initializes all node states.
    ///
    /// # Arguments
    ///
    /// * `workflow_id` - ID of the workflow to start
    ///
    /// # Returns
    ///
    /// The `WorkflowInstance` representing the executing workflow.
    ///
    /// # Errors
    ///
    /// Returns an error if the workflow doesn't exist.
    pub fn start_workflow(&self, workflow_id: &str) -> Result<WorkflowInstance> {
        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        let definition = storage
            .definitions
            .get(workflow_id)
            .ok_or_else(|| Error::Config(format!("Workflow '{}' not found", workflow_id)))?;

        let mut instance = WorkflowInstance::new(workflow_id.to_string());
        instance.started_at = Some(Utc::now());

        // Initialize node states
        for node_id in definition.nodes.keys() {
            instance
                .node_states
                .insert(node_id.clone(), NodeState::new(node_id.clone()));
        }

        let instance_id = instance.instance_id.clone();
        storage.instances.insert(instance_id.clone(), instance.clone());

        Ok(instance)
    }

    /// Get the status of a workflow instance.
    ///
    /// # Arguments
    ///
    /// * `instance_id` - ID of the workflow instance
    ///
    /// # Returns
    ///
    /// The `WorkflowInstance` with current state.
    ///
    /// # Errors
    ///
    /// Returns an error if the instance doesn't exist.
    pub fn get_workflow_status(&self, instance_id: &str) -> Result<WorkflowInstance> {
        let storage = self
            .storage
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        storage
            .instances
            .get(instance_id)
            .cloned()
            .ok_or_else(|| Error::Config(format!("Instance '{}' not found", instance_id)))
    }

    /// Cancel a workflow execution.
    ///
    /// Marks all non-completed nodes as failed and sets a cancellation timestamp.
    ///
    /// # Arguments
    ///
    /// * `instance_id` - ID of the workflow instance to cancel
    ///
    /// # Errors
    ///
    /// Returns an error if the instance doesn't exist.
    pub fn cancel_workflow(&self, instance_id: &str) -> Result<()> {
        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        let instance = storage
            .instances
            .get_mut(instance_id)
            .ok_or_else(|| Error::Config(format!("Instance '{}' not found", instance_id)))?;

        // Mark all non-terminal nodes as failed with cancellation
        for node_state in instance.node_states.values_mut() {
            if !node_state.is_terminal() {
                node_state.status = NodeStatus::Failed;
                node_state.error = Some("Workflow cancelled".to_string());
                node_state.completed_at = Some(Utc::now());
            }
        }

        instance.completed_at = Some(Utc::now());
        instance
            .metadata
            .insert("cancelled".to_string(), "true".to_string());

        Ok(())
    }

    /// Update node state in a workflow instance.
    ///
    /// # Arguments
    ///
    /// * `instance_id` - ID of the workflow instance
    /// * `node_id` - ID of the node to update
    /// * `status` - New status for the node
    /// * `output` - Optional output data
    /// * `error` - Optional error message
    pub fn update_node_state(
        &self,
        instance_id: &str,
        node_id: &str,
        status: NodeStatus,
        output: Option<String>,
        error: Option<String>,
    ) -> Result<()> {
        let mut storage = self
            .storage
            .write()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        let instance = storage
            .instances
            .get_mut(instance_id)
            .ok_or_else(|| Error::Config(format!("Instance '{}' not found", instance_id)))?;

        let node_state = instance
            .node_states
            .get_mut(node_id)
            .ok_or_else(|| Error::Config(format!("Node '{}' not found in instance", node_id)))?;

        if status == NodeStatus::Running && node_state.started_at.is_none() {
            node_state.started_at = Some(Utc::now());
        }

        if status.is_terminal() && node_state.completed_at.is_none() {
            node_state.completed_at = Some(Utc::now());
        }

        node_state.status = status;
        node_state.output = output;
        node_state.error = error;

        // Check if all nodes are complete
        if instance.node_states.values().all(|s| s.is_terminal()) {
            instance.completed_at = Some(Utc::now());
        }

        Ok(())
    }

    /// Resume a workflow by marking a node as completed and advancing dependents.
    ///
    /// This implements the ResumeWorkflow RPC (spec §17.7 MUST). It marks the
    /// specified node as COMPLETED with optional output, then transitions any
    /// dependent nodes from Pending to Ready if all their dependencies are met.
    ///
    /// # Arguments
    ///
    /// * `instance_id` - ID of the workflow instance
    /// * `node_id` - ID of the node to mark as completed
    /// * `output` - Optional output data from the node
    /// * `workflow_data` - Optional updated workflow data (JSON string)
    pub fn resume_workflow(
        &self,
        instance_id: &str,
        node_id: &str,
        output: Option<String>,
        workflow_data: Option<String>,
    ) -> Result<WorkflowInstance> {
        // Mark the node as completed
        self.update_node_state(instance_id, node_id, NodeStatus::Completed, output, None)?;

        // Update workflow data if provided
        if let Some(data) = workflow_data {
            let mut storage = self
                .storage
                .write()
                .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;
            let instance = storage
                .instances
                .get_mut(instance_id)
                .ok_or_else(|| Error::Config(format!("Instance '{}' not found", instance_id)))?;
            instance.workflow_data = data;
        }

        // Advance dependent nodes: look up definition, check deps
        {
            let mut storage = self
                .storage
                .write()
                .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

            let instance = storage
                .instances
                .get(instance_id)
                .ok_or_else(|| Error::Config(format!("Instance '{}' not found", instance_id)))?;
            let workflow_id = instance.workflow_id.clone();

            let definition = storage
                .definitions
                .get(&workflow_id)
                .ok_or_else(|| Error::Config(format!("Workflow '{}' not found", workflow_id)))?
                .clone();

            let instance = storage.instances.get_mut(instance_id).unwrap();
            let completed: HashSet<String> = instance.get_completed_nodes();

            for (nid, node) in &definition.nodes {
                if let Some(state) = instance.node_states.get_mut(nid) {
                    if state.status == NodeStatus::Pending
                        && node.dependencies.iter().all(|d| completed.contains(d))
                    {
                        state.status = NodeStatus::Ready;
                    }
                }
            }
        }

        self.get_workflow_status(instance_id)
    }

    /// Get workflow definition by ID.
    pub fn get_workflow_definition(&self, workflow_id: &str) -> Result<Option<WorkflowDefinition>> {
        let storage = self
            .storage
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        Ok(storage.definitions.get(workflow_id).cloned())
    }

    /// List all workflow definitions.
    pub fn list_workflows(&self) -> Result<Vec<String>> {
        let storage = self
            .storage
            .read()
            .map_err(|_| Error::Internal("Lock poisoned".to_string()))?;

        Ok(storage.definitions.keys().cloned().collect())
    }

    /// Validate that the workflow DAG has no cycles.
    fn validate_dag(&self, definition: &WorkflowDefinition) -> Result<()> {
        let mut visited = HashSet::new();
        let mut rec_stack = HashSet::new();

        for node_id in definition.nodes.keys() {
            if !visited.contains(node_id)
                && self.has_cycle(definition, node_id, &mut visited, &mut rec_stack)?
            {
                return Err(Error::Config(format!(
                    "Cycle detected in workflow starting from node '{}'",
                    node_id
                )));
            }
        }

        Ok(())
    }

    /// DFS-based cycle detection.
    #[allow(clippy::only_used_in_recursion)]
    fn has_cycle(
        &self,
        definition: &WorkflowDefinition,
        node_id: &str,
        visited: &mut HashSet<String>,
        rec_stack: &mut HashSet<String>,
    ) -> Result<bool> {
        visited.insert(node_id.to_string());
        rec_stack.insert(node_id.to_string());

        if let Some(node) = definition.nodes.get(node_id) {
            for dep in &node.dependencies {
                if !visited.contains(dep) {
                    if self.has_cycle(definition, dep, visited, rec_stack)? {
                        return Ok(true);
                    }
                } else if rec_stack.contains(dep) {
                    return Ok(true);
                }
            }
        }

        rec_stack.remove(node_id);
        Ok(false)
    }
}

impl std::fmt::Debug for WorkflowClient {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("WorkflowClient").finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn create_test_workflow() -> WorkflowDefinition {
        let mut nodes = HashMap::new();
        let node1 = WorkflowNode::new("fetch".to_string(), "fetcher".to_string()).unwrap();
        let node2 = WorkflowNode::new("process".to_string(), "processor".to_string())
            .unwrap()
            .with_dependency("fetch".to_string());
        let node3 = WorkflowNode::new("store".to_string(), "storer".to_string())
            .unwrap()
            .with_dependency("process".to_string());

        nodes.insert("fetch".to_string(), node1);
        nodes.insert("process".to_string(), node2);
        nodes.insert("store".to_string(), node3);

        WorkflowDefinition::new("test-workflow".to_string(), nodes).unwrap()
    }

    #[test]
    fn test_create_workflow() {
        let client = WorkflowClient::new();
        let definition = create_test_workflow();

        let result = client.create_workflow(definition);
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "test-workflow");
    }

    #[test]
    fn test_duplicate_workflow_fails() {
        let client = WorkflowClient::new();
        let definition = create_test_workflow();

        client.create_workflow(definition.clone()).unwrap();
        let result = client.create_workflow(definition);
        assert!(result.is_err());
    }

    #[test]
    fn test_start_workflow() {
        let client = WorkflowClient::new();
        let definition = create_test_workflow();

        client.create_workflow(definition).unwrap();
        let instance = client.start_workflow("test-workflow").unwrap();

        assert_eq!(instance.workflow_id, "test-workflow");
        assert_eq!(instance.node_states.len(), 3);
        assert!(instance.started_at.is_some());
    }

    #[test]
    fn test_get_workflow_status() {
        let client = WorkflowClient::new();
        let definition = create_test_workflow();

        client.create_workflow(definition).unwrap();
        let instance = client.start_workflow("test-workflow").unwrap();
        let instance_id = instance.instance_id.clone();

        let status = client.get_workflow_status(&instance_id).unwrap();
        assert_eq!(status.workflow_id, "test-workflow");
    }

    #[test]
    fn test_cancel_workflow() {
        let client = WorkflowClient::new();
        let definition = create_test_workflow();

        client.create_workflow(definition).unwrap();
        let instance = client.start_workflow("test-workflow").unwrap();
        let instance_id = instance.instance_id.clone();

        client.cancel_workflow(&instance_id).unwrap();

        let status = client.get_workflow_status(&instance_id).unwrap();
        assert!(status.is_completed());
        assert!(status.has_failures());
    }

    #[test]
    fn test_cycle_detection() {
        let client = WorkflowClient::new();

        let mut nodes = HashMap::new();
        let node1 = WorkflowNode::new("a".to_string(), "agent".to_string())
            .unwrap()
            .with_dependency("c".to_string());
        let node2 = WorkflowNode::new("b".to_string(), "agent".to_string())
            .unwrap()
            .with_dependency("a".to_string());
        let node3 = WorkflowNode::new("c".to_string(), "agent".to_string())
            .unwrap()
            .with_dependency("b".to_string());

        nodes.insert("a".to_string(), node1);
        nodes.insert("b".to_string(), node2);
        nodes.insert("c".to_string(), node3);

        let definition = WorkflowDefinition::new("cyclic-workflow".to_string(), nodes).unwrap();
        let result = client.create_workflow(definition);
        assert!(result.is_err());
    }

    #[test]
    fn test_workflow_node_builder() {
        let node = WorkflowNode::new("test".to_string(), "agent".to_string())
            .unwrap()
            .with_dependency("dep1".to_string())
            .with_trigger(TriggerType::Manual)
            .with_input("param".to_string(), "state_key".to_string())
            .with_output("result".to_string(), "output_key".to_string())
            .with_metadata("key".to_string(), "value".to_string());

        assert!(node.dependencies.contains("dep1"));
        assert_eq!(node.trigger_type, TriggerType::Manual);
        assert_eq!(node.input_mapping.get("param"), Some(&"state_key".to_string()));
        assert_eq!(node.output_mapping.get("result"), Some(&"output_key".to_string()));
        assert_eq!(node.metadata.get("key"), Some(&"value".to_string()));
    }

    #[test]
    fn test_workflow_instance_helpers() {
        let mut instance = WorkflowInstance::new("test".to_string());
        instance.node_states.insert(
            "node1".to_string(),
            NodeState {
                node_id: "node1".to_string(),
                status: NodeStatus::Completed,
                output: Some("result".to_string()),
                error: None,
                started_at: Some(Utc::now()),
                completed_at: Some(Utc::now()),
            },
        );
        instance.node_states.insert(
            "node2".to_string(),
            NodeState {
                node_id: "node2".to_string(),
                status: NodeStatus::Failed,
                output: None,
                error: Some("error".to_string()),
                started_at: Some(Utc::now()),
                completed_at: Some(Utc::now()),
            },
        );

        assert!(instance.is_completed());
        assert!(instance.has_failures());
        assert_eq!(instance.get_completed_nodes().len(), 1);
        assert_eq!(instance.get_failed_nodes().len(), 1);
    }

    #[test]
    fn test_resume_workflow() {
        let client = WorkflowClient::new();
        let definition = create_test_workflow(); // fetch -> process -> store

        client.create_workflow(definition).unwrap();
        let instance = client.start_workflow("test-workflow").unwrap();
        let instance_id = instance.instance_id.clone();

        // Resume by completing "fetch" — should advance "process" to Ready
        let updated = client
            .resume_workflow(&instance_id, "fetch", Some("fetched data".into()), None)
            .unwrap();

        assert_eq!(
            updated.get_node_state("fetch").unwrap().status,
            NodeStatus::Completed
        );
        assert_eq!(
            updated.get_node_state("process").unwrap().status,
            NodeStatus::Ready
        );
        // "store" still pending (depends on "process")
        assert_eq!(
            updated.get_node_state("store").unwrap().status,
            NodeStatus::Pending
        );
    }

    #[test]
    fn test_invalid_dependency_fails() {
        let mut nodes = HashMap::new();
        let node = WorkflowNode::new("test".to_string(), "agent".to_string())
            .unwrap()
            .with_dependency("nonexistent".to_string());
        nodes.insert("test".to_string(), node);

        let result = WorkflowDefinition::new("invalid".to_string(), nodes);
        assert!(result.is_err());
    }
}
