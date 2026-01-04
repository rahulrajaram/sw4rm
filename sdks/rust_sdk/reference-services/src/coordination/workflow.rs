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

//! Workflow Service gRPC Server Implementation.
//!
//! This module provides the gRPC server implementation for the WorkflowService,
//! enabling distributed DAG-based workflow orchestration with centralized state.

use crate::proto::sw4rm::workflow::{
    workflow_service_server::{WorkflowService, WorkflowServiceServer},
    CreateWorkflowRequest, CreateWorkflowResponse, GetWorkflowStateRequest,
    GetWorkflowStateResponse, NodeState, NodeStatus, ResumeWorkflowRequest,
    ResumeWorkflowResponse, StartWorkflowRequest, StartWorkflowResponse,
    WorkflowDefinition, WorkflowState,
};
use dashmap::DashMap;
use prost_types::Timestamp;
use std::collections::HashSet;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tonic::{Request, Response, Status};
use tracing::{debug, info, warn};

fn current_timestamp() -> Timestamp {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap();
    Timestamp {
        seconds: now.as_secs() as i64,
        nanos: now.subsec_nanos() as i32,
    }
}

/// gRPC server implementation for WorkflowService.
///
/// Provides centralized workflow orchestration for distributed agent deployments.
/// Thread-safe implementation using DashMap for concurrent access.
#[derive(Debug)]
pub struct WorkflowServiceImpl {
    /// Workflow definitions indexed by workflow_id
    definitions: Arc<DashMap<String, WorkflowDefinition>>,
    /// Running workflow instances indexed by workflow_id
    instances: Arc<DashMap<String, WorkflowState>>,
}

impl Default for WorkflowServiceImpl {
    fn default() -> Self {
        Self::new()
    }
}

impl WorkflowServiceImpl {
    /// Create a new WorkflowServiceImpl with empty state.
    pub fn new() -> Self {
        info!("WorkflowService initialized");
        Self {
            definitions: Arc::new(DashMap::new()),
            instances: Arc::new(DashMap::new()),
        }
    }

    /// Convert this service into a tonic service.
    pub fn into_service(self) -> WorkflowServiceServer<Self> {
        WorkflowServiceServer::new(self)
    }

    /// Validate that the workflow DAG has no cycles.
    fn validate_dag(&self, definition: &WorkflowDefinition) -> Result<(), String> {
        let mut visited = HashSet::new();
        let mut rec_stack = HashSet::new();

        fn has_cycle(
            node_id: &str,
            nodes: &std::collections::HashMap<String, crate::proto::sw4rm::workflow::WorkflowNode>,
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
                    return Err(format!(
                        "Cycle detected in workflow starting from node '{}'",
                        node_id
                    ));
                }
            }
        }

        Ok(())
    }

    /// Validate that all dependencies reference existing nodes.
    fn validate_dependencies(&self, definition: &WorkflowDefinition) -> Result<(), String> {
        let node_ids: HashSet<_> = definition.nodes.keys().collect();

        for (node_id, node) in &definition.nodes {
            for dep in &node.dependencies {
                if !node_ids.contains(&dep) {
                    return Err(format!(
                        "Node '{}' has dependency '{}' which does not exist",
                        node_id, dep
                    ));
                }
            }
        }

        Ok(())
    }

    /// Get a workflow definition.
    pub fn get_definition(&self, workflow_id: &str) -> Option<WorkflowDefinition> {
        self.definitions.get(workflow_id).map(|v| v.clone())
    }

    /// Clear all workflow data (for testing).
    pub fn clear_all(&self) {
        self.definitions.clear();
        self.instances.clear();
        info!("WorkflowService state cleared");
    }
}

#[tonic::async_trait]
impl WorkflowService for WorkflowServiceImpl {
    /// Create a new workflow from a definition.
    async fn create_workflow(
        &self,
        request: Request<CreateWorkflowRequest>,
    ) -> Result<Response<CreateWorkflowResponse>, Status> {
        let req = request.into_inner();
        let definition = match req.definition {
            Some(d) => d,
            None => {
                return Ok(Response::new(CreateWorkflowResponse {
                    workflow_id: String::new(),
                    success: false,
                    error: "WorkflowDefinition is required".to_string(),
                }));
            }
        };

        let workflow_id = definition.workflow_id.clone();

        // Validate required fields
        if workflow_id.is_empty() {
            return Ok(Response::new(CreateWorkflowResponse {
                workflow_id: String::new(),
                success: false,
                error: "workflow_id is required".to_string(),
            }));
        }

        if definition.nodes.is_empty() {
            return Ok(Response::new(CreateWorkflowResponse {
                workflow_id,
                success: false,
                error: "workflow must contain at least one node".to_string(),
            }));
        }

        // Validate dependencies
        if let Err(e) = self.validate_dependencies(&definition) {
            return Ok(Response::new(CreateWorkflowResponse {
                workflow_id,
                success: false,
                error: e,
            }));
        }

        // Validate DAG (no cycles)
        if let Err(e) = self.validate_dag(&definition) {
            return Ok(Response::new(CreateWorkflowResponse {
                workflow_id,
                success: false,
                error: e,
            }));
        }

        // Check for duplicates
        if self.definitions.contains_key(&workflow_id) {
            return Ok(Response::new(CreateWorkflowResponse {
                workflow_id: workflow_id.clone(),
                success: false,
                error: format!("Workflow with id '{}' already exists", workflow_id),
            }));
        }

        // Store the definition
        let mut def = definition;
        if def.created_at.is_none() {
            def.created_at = Some(current_timestamp());
        }

        let node_count = def.nodes.len();
        self.definitions.insert(workflow_id.clone(), def);

        info!("Workflow created: {} with {} nodes", workflow_id, node_count);

        Ok(Response::new(CreateWorkflowResponse {
            workflow_id,
            success: true,
            error: String::new(),
        }))
    }

    /// Start a new instance of a workflow.
    async fn start_workflow(
        &self,
        request: Request<StartWorkflowRequest>,
    ) -> Result<Response<StartWorkflowResponse>, Status> {
        let req = request.into_inner();
        let workflow_id = req.workflow_id.clone();

        // Check if definition exists
        let definition = match self.definitions.get(&workflow_id) {
            Some(d) => d.clone(),
            None => {
                return Ok(Response::new(StartWorkflowResponse {
                    workflow_id,
                    state: None,
                    success: false,
                    error: format!("Workflow '{}' not found", req.workflow_id),
                }));
            }
        };

        // Check if already running
        if self.instances.contains_key(&workflow_id) {
            return Ok(Response::new(StartWorkflowResponse {
                workflow_id,
                state: None,
                success: false,
                error: format!("Workflow '{}' is already running", req.workflow_id),
            }));
        }

        // Initialize node states
        let mut node_states = std::collections::HashMap::new();
        for (node_id, node) in &definition.nodes {
            // Nodes with no dependencies start as READY, others as PENDING
            let status = if node.dependencies.is_empty() {
                NodeStatus::Ready as i32
            } else {
                NodeStatus::Pending as i32
            };

            node_states.insert(
                node_id.clone(),
                NodeState {
                    node_id: node_id.clone(),
                    status,
                    started_at: None,
                    completed_at: None,
                    output: String::new(),
                    error: String::new(),
                },
            );
        }

        // Create workflow state
        let state = WorkflowState {
            workflow_id: workflow_id.clone(),
            node_states,
            workflow_data: req.workflow_data,
            started_at: Some(current_timestamp()),
            completed_at: None,
            metadata: req.metadata,
        };

        self.instances.insert(workflow_id.clone(), state.clone());

        info!("Workflow started: {}", workflow_id);

        Ok(Response::new(StartWorkflowResponse {
            workflow_id,
            state: Some(state),
            success: true,
            error: String::new(),
        }))
    }

    /// Get the current state of a workflow instance.
    async fn get_workflow_state(
        &self,
        request: Request<GetWorkflowStateRequest>,
    ) -> Result<Response<GetWorkflowStateResponse>, Status> {
        let workflow_id = request.into_inner().workflow_id;

        match self.instances.get(&workflow_id) {
            Some(state) => {
                debug!("GetWorkflowState: {}", workflow_id);
                Ok(Response::new(GetWorkflowStateResponse {
                    state: Some(state.clone()),
                    success: true,
                    error: String::new(),
                }))
            }
            None => {
                // Check if definition exists but not started
                if self.definitions.contains_key(&workflow_id) {
                    Ok(Response::new(GetWorkflowStateResponse {
                        state: None,
                        success: false,
                        error: format!("Workflow '{}' exists but is not started", workflow_id),
                    }))
                } else {
                    Ok(Response::new(GetWorkflowStateResponse {
                        state: None,
                        success: false,
                        error: format!("Workflow '{}' not found", workflow_id),
                    }))
                }
            }
        }
    }

    /// Resume a workflow by completing a node.
    async fn resume_workflow(
        &self,
        request: Request<ResumeWorkflowRequest>,
    ) -> Result<Response<ResumeWorkflowResponse>, Status> {
        let req = request.into_inner();
        let workflow_id = req.workflow_id.clone();
        let node_id = req.node_id.clone();

        // Get the instance
        let mut state = match self.instances.get_mut(&workflow_id) {
            Some(s) => s,
            None => {
                return Ok(Response::new(ResumeWorkflowResponse {
                    workflow_id,
                    state: None,
                    success: false,
                    error: format!("Workflow '{}' not found or not started", req.workflow_id),
                }));
            }
        };

        // Get the definition
        let definition = match self.definitions.get(&workflow_id) {
            Some(d) => d.clone(),
            None => {
                return Ok(Response::new(ResumeWorkflowResponse {
                    workflow_id,
                    state: None,
                    success: false,
                    error: format!("Workflow definition '{}' not found", req.workflow_id),
                }));
            }
        };

        // Check if node exists
        if !state.node_states.contains_key(&node_id) {
            return Ok(Response::new(ResumeWorkflowResponse {
                workflow_id,
                state: Some(state.clone()),
                success: false,
                error: format!("Node '{}' not found in workflow", node_id),
            }));
        }

        // Update the node to COMPLETED
        if let Some(node_state) = state.node_states.get_mut(&node_id) {
            node_state.status = NodeStatus::Completed as i32;
            node_state.completed_at = Some(current_timestamp());
        }

        // Update workflow data if provided
        if !req.workflow_data.is_empty() {
            state.workflow_data = req.workflow_data;
        }

        // Update metadata
        for (k, v) in req.metadata {
            state.metadata.insert(k, v);
        }

        // Update dependent nodes
        for (dep_node_id, node) in &definition.nodes {
            if node.dependencies.contains(&node_id) {
                if let Some(dep_state) = state.node_states.get_mut(dep_node_id) {
                    if dep_state.status == NodeStatus::Pending as i32 {
                        // Check if all dependencies are complete
                        let all_deps_complete = node.dependencies.iter().all(|dep| {
                            state
                                .node_states
                                .get(dep)
                                .map(|s| s.status == NodeStatus::Completed as i32)
                                .unwrap_or(false)
                        });

                        if all_deps_complete {
                            dep_state.status = NodeStatus::Ready as i32;
                        }
                    }
                }
            }
        }

        // Check if workflow is complete
        let terminal_statuses = [
            NodeStatus::Completed as i32,
            NodeStatus::Failed as i32,
            NodeStatus::Skipped as i32,
        ];
        let all_terminal = state
            .node_states
            .values()
            .all(|s| terminal_statuses.contains(&s.status));

        if all_terminal && state.completed_at.is_none() {
            state.completed_at = Some(current_timestamp());
        }

        info!("Workflow resumed: {}, node {} completed", workflow_id, node_id);

        Ok(Response::new(ResumeWorkflowResponse {
            workflow_id,
            state: Some(state.clone()),
            success: true,
            error: String::new(),
        }))
    }
}
