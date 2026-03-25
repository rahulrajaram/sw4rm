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

//! Workflow Orchestration Example for SW4RM Protocol.
//!
//! Demonstrates DAG-based workflow execution using the real SDK
//! `WorkflowClient`:
//! - Creating workflow definitions with nodes and dependencies
//! - Starting workflow instances and tracking node states
//! - Advancing nodes through Ready → Running → Completed transitions
//! - Using `resume_workflow` for automatic dependency advancement
//!
//! Execution mode: Local in-memory demo. The `WorkflowClient` validates
//! the DAG, manages node state transitions, and detects completion
//! automatically. No external services are required.
//!
//! Run:
//! ```bash
//! cargo run --example workflow
//! ```

use std::collections::HashMap;
use sw4rm_sdk::clients::workflow::{
    NodeStatus, TriggerType, WorkflowClient, WorkflowDefinition, WorkflowNode,
};

// ============================================================================
// Pipeline Definition
// ============================================================================

/// Create a sample CI/CD pipeline workflow.
///
/// Pipeline structure:
///   build → test → (security_scan, quality_check) → deploy
///
/// security_scan and quality_check run in parallel after test completes.
/// deploy only runs after both complete.
fn create_cicd_pipeline() -> WorkflowDefinition {
    let mut nodes = HashMap::new();

    nodes.insert(
        "build".to_string(),
        WorkflowNode::new("build".to_string(), "build-agent".to_string())
            .unwrap()
            .with_trigger(TriggerType::Manual)
            .with_input("source_repo".to_string(), "source_repo".to_string())
            .with_output("artifact_path".to_string(), "build_artifact".to_string())
            .with_metadata("timeout_ms".to_string(), "300000".to_string()),
    );

    nodes.insert(
        "test".to_string(),
        WorkflowNode::new("test".to_string(), "test-agent".to_string())
            .unwrap()
            .with_dependency("build".to_string())
            .with_trigger(TriggerType::Dependency)
            .with_input("artifact".to_string(), "build_artifact".to_string())
            .with_output("test_results".to_string(), "test_results".to_string())
            .with_output("coverage".to_string(), "coverage".to_string())
            .with_metadata("test_type".to_string(), "unit,integration".to_string()),
    );

    nodes.insert(
        "security_scan".to_string(),
        WorkflowNode::new("security_scan".to_string(), "security-agent".to_string())
            .unwrap()
            .with_dependency("test".to_string())
            .with_trigger(TriggerType::Dependency)
            .with_input("artifact".to_string(), "build_artifact".to_string())
            .with_output(
                "vulnerabilities".to_string(),
                "security_report".to_string(),
            )
            .with_metadata("scan_type".to_string(), "SAST,DAST".to_string()),
    );

    nodes.insert(
        "quality_check".to_string(),
        WorkflowNode::new("quality_check".to_string(), "quality-agent".to_string())
            .unwrap()
            .with_dependency("test".to_string())
            .with_trigger(TriggerType::Dependency)
            .with_input("coverage".to_string(), "coverage".to_string())
            .with_output("quality_score".to_string(), "quality_score".to_string())
            .with_metadata("min_coverage".to_string(), "80".to_string()),
    );

    nodes.insert(
        "deploy".to_string(),
        WorkflowNode::new("deploy".to_string(), "deploy-agent".to_string())
            .unwrap()
            .with_dependency("security_scan".to_string())
            .with_dependency("quality_check".to_string())
            .with_trigger(TriggerType::Dependency)
            .with_input("artifact".to_string(), "build_artifact".to_string())
            .with_input("security".to_string(), "security_report".to_string())
            .with_input("quality".to_string(), "quality_score".to_string())
            .with_output("deployment_url".to_string(), "deployment_url".to_string())
            .with_metadata("environment".to_string(), "staging".to_string()),
    );

    WorkflowDefinition::new("cicd-pipeline-1".to_string(), nodes).unwrap()
}

// ============================================================================
// Node simulation
// ============================================================================

/// Simulate node execution with realistic output.
fn simulate_node_output(node_id: &str) -> String {
    match node_id {
        "build" => serde_json::json!({
            "artifact_path": "/artifacts/build-123.tar.gz",
            "commit_sha": "abc123",
            "build_time_ms": 45000,
        })
        .to_string(),
        "test" => serde_json::json!({
            "test_results": { "passed": 142, "failed": 0, "skipped": 3 },
            "coverage": 87.5,
            "execution_time_ms": 120000,
        })
        .to_string(),
        "security_scan" => serde_json::json!({
            "vulnerabilities": { "critical": 0, "high": 1, "medium": 3, "low": 8 },
            "scan_time_ms": 60000,
        })
        .to_string(),
        "quality_check" => serde_json::json!({
            "quality_score": 92,
            "coverage_met": true,
            "code_smells": 5,
        })
        .to_string(),
        "deploy" => serde_json::json!({
            "deployment_url": "https://staging.example.com",
            "deployment_id": "deploy-456",
            "health_check": "passed",
        })
        .to_string(),
        _ => r#"{"status":"completed"}"#.to_string(),
    }
}

// ============================================================================
// Workflow execution loop
// ============================================================================

/// Run a workflow instance to completion using the SDK client's
/// `resume_workflow` method, which handles dependency advancement.
fn run_workflow(client: &WorkflowClient, instance_id: &str) {
    let node_order = ["build", "test", "security_scan", "quality_check", "deploy"];

    for iteration in 1..=10 {
        let instance = client.get_workflow_status(instance_id).unwrap();
        if instance.is_completed() {
            break;
        }

        // Find ready nodes
        let ready_nodes: Vec<String> = instance
            .node_states
            .iter()
            .filter(|(_, s)| s.status == NodeStatus::Ready)
            .map(|(id, _)| id.clone())
            .collect();

        // Also include Pending root nodes on the first iteration
        let actionable_nodes: Vec<String> = if iteration == 1 {
            instance
                .node_states
                .iter()
                .filter(|(_, s)| s.status == NodeStatus::Pending || s.status == NodeStatus::Ready)
                .map(|(id, _)| id.clone())
                .collect()
        } else {
            ready_nodes.clone()
        };

        if actionable_nodes.is_empty() {
            break;
        }

        println!("\n{}", "=".repeat(60));
        println!("Workflow Iteration {}", iteration);
        println!("{}", "=".repeat(60));

        // Sort by the expected pipeline order for deterministic output
        let mut sorted_nodes = actionable_nodes;
        sorted_nodes.sort_by_key(|n| {
            node_order
                .iter()
                .position(|&x| x == n.as_str())
                .unwrap_or(99)
        });

        println!("Actionable nodes: {}", sorted_nodes.join(", "));

        for node_id in &sorted_nodes {
            // Mark as RUNNING
            client
                .update_node_state(instance_id, node_id, NodeStatus::Running, None, None)
                .unwrap();
            println!("\n[Node] Executing: {}", node_id);

            // Simulate work
            let output = simulate_node_output(node_id);

            // Mark as COMPLETED and advance dependents
            let updated = client
                .resume_workflow(instance_id, node_id, Some(output.clone()), None)
                .unwrap();

            let truncated = if output.len() > 80 {
                format!("{}...", &output[..80])
            } else {
                output
            };
            println!("[Node] Completed: {}", node_id);
            println!("  Output: {}", truncated);

            // Print current state after each node
            println!("\n  Current states:");
            let mut states: Vec<_> = updated.node_states.iter().collect();
            states.sort_by_key(|(id, _)| {
                node_order
                    .iter()
                    .position(|&x| x == id.as_str())
                    .unwrap_or(99)
            });
            for (id, state) in &states {
                println!("    {}: {:?}", id, state.status);
            }
        }
    }
}

// ============================================================================
// Main
// ============================================================================

fn main() {
    println!("SW4RM Workflow Orchestration Example");
    println!("{}", "=".repeat(60));
    println!("\nThis example uses the SDK WorkflowClient to demonstrate");
    println!("DAG-based workflow execution for multi-agent orchestration.\n");

    let client = WorkflowClient::new();

    // Create the CI/CD pipeline workflow
    let definition = create_cicd_pipeline();

    println!("Workflow Structure:");
    println!("  build -> test -> (security_scan, quality_check) -> deploy");
    println!("  * security_scan and quality_check run in parallel");
    println!("  * deploy waits for both to complete\n");

    let workflow_id = client.create_workflow(definition).unwrap();
    println!("Created workflow: {}", workflow_id);

    // Start the workflow
    let instance = client.start_workflow(&workflow_id).unwrap();
    println!("Started instance: {}", instance.instance_id);

    // Run to completion
    run_workflow(&client, &instance.instance_id);

    // Final state
    let final_state = client
        .get_workflow_status(&instance.instance_id)
        .unwrap();

    println!("\n{}", "=".repeat(60));
    println!("WORKFLOW COMPLETE");
    println!("{}", "=".repeat(60));
    println!("\nAll nodes completed: {}", final_state.is_completed());
    println!("Has failures: {}", final_state.has_failures());

    if let (Some(start), Some(end)) = (final_state.started_at, final_state.completed_at) {
        let duration = (end - start).num_milliseconds();
        println!("Duration: {}ms", duration);
    }

    // --------------------------------------------------------------------------
    // Failure Path: Node failure cascades to workflow failure
    // --------------------------------------------------------------------------
    println!("\n{}", "=".repeat(60));
    println!("FAILURE PATH: Node failure cascade");
    println!("{}", "=".repeat(60));

    let fail_def = create_cicd_pipeline();
    let fail_wf_id = client.create_workflow(fail_def).unwrap();
    let fail_instance = client.start_workflow(&fail_wf_id).unwrap();
    println!(
        "\nStarted failure-demo instance: {}",
        fail_instance.instance_id
    );

    // Advance build → Completed
    client
        .update_node_state(&fail_instance.instance_id, "build", NodeStatus::Running, None, None)
        .unwrap();
    client
        .resume_workflow(&fail_instance.instance_id, "build", None, None)
        .unwrap();
    println!("  build: Completed");

    // Mark test as Failed with an error
    client
        .update_node_state(&fail_instance.instance_id, "test", NodeStatus::Running, None, None)
        .unwrap();
    client
        .update_node_state(
            &fail_instance.instance_id,
            "test",
            NodeStatus::Failed,
            None,
            Some("Integration tests timed out".to_string()),
        )
        .unwrap();
    println!("  test: Failed (Integration tests timed out)");

    let fail_final = client
        .get_workflow_status(&fail_instance.instance_id)
        .unwrap();
    println!("\n  has_failures: {}", fail_final.has_failures());
    println!("  Downstream nodes remain Pending:");
    let mut states: Vec<_> = fail_final.node_states.iter().collect();
    states.sort_by_key(|(id, _)| {
        ["build", "test", "security_scan", "quality_check", "deploy"]
            .iter()
            .position(|&x| x == id.as_str())
            .unwrap_or(99)
    });
    for (id, state) in &states {
        println!("    {}: {:?}", id, state.status);
    }

    // Demonstrate cancel_workflow on a fresh instance
    println!("\n--- cancel_workflow ---");
    let cancel_def = create_cicd_pipeline();
    let cancel_wf_id = client.create_workflow(cancel_def).unwrap();
    let cancel_inst = client.start_workflow(&cancel_wf_id).unwrap();
    client.cancel_workflow(&cancel_inst.instance_id).unwrap();
    let cancelled = client
        .get_workflow_status(&cancel_inst.instance_id)
        .unwrap();
    println!(
        "  Cancelled instance: is_completed={}, has_failures={}",
        cancelled.is_completed(),
        cancelled.has_failures()
    );

    println!("\nKey takeaways:");
    println!("1. WorkflowDefinition::new() validates the DAG (cycle detection, dep resolution)");
    println!("2. start_workflow() initializes all nodes as Pending");
    println!("3. resume_workflow() marks a node Complete and auto-promotes dependents to Ready");
    println!("4. The client detects workflow completion when all nodes are terminal");
    println!("5. Parallel execution is possible for independent branches");
    println!("6. A single Failed node marks the workflow as failed; cancel_workflow() fails all non-terminal nodes");
}
