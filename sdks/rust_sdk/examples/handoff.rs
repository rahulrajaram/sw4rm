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

//! Agent Handoff Example for SW4RM Protocol.
//!
//! Demonstrates agent-to-agent task handoff using the real SDK
//! `HandoffClient`:
//! - Requesting a handoff when the current agent lacks capabilities
//! - Accepting or rejecting handoffs based on agent state
//! - Transferring context between agents via `context_snapshot`
//! - Marking handoffs as completed after work finishes
//!
//! Execution mode: Local in-memory demo. The `HandoffClient` stores
//! request/response state in process memory using `Arc<RwLock<...>>`.
//! No external services are required.
//!
//! Run:
//! ```bash
//! cargo run --example handoff
//! ```

use sw4rm_sdk::clients::handoff::{
    BudgetEnvelope, HandoffClient, HandoffRequest, HandoffStatus, RejectHandoffOptions,
    SwarmDelegationPolicy, REJECTION_CODE_OVERLOADED, REJECTION_CODE_REDIRECT,
};

// ============================================================================
// Agent abstraction
// ============================================================================

/// Simulated agent with capabilities and availability.
struct Agent {
    agent_id: String,
    capabilities: Vec<String>,
    busy: bool,
}

impl Agent {
    fn new(agent_id: &str, capabilities: Vec<&str>) -> Self {
        Self {
            agent_id: agent_id.to_string(),
            capabilities: capabilities.into_iter().map(String::from).collect(),
            busy: false,
        }
    }

    fn has_capability(&self, cap: &str) -> bool {
        self.capabilities.iter().any(|c| c == cap)
    }

    fn can_accept_work(&self) -> bool {
        !self.busy
    }

    fn mark_busy(&mut self) {
        self.busy = true;
    }

    fn mark_free(&mut self) {
        self.busy = false;
    }
}

// ============================================================================
// Helper: process pending handoffs for an agent
// ============================================================================

/// Evaluate pending handoffs and accept/reject based on capability and availability.
fn process_pending_handoffs(client: &HandoffClient, agent: &mut Agent) -> Vec<String> {
    let pending = client.get_pending_handoffs(&agent.agent_id).unwrap();
    let mut accepted = Vec::new();

    for request in &pending {
        println!(
            "\n[{}] Evaluating handoff {}",
            agent.agent_id, request.request_id
        );
        println!("  From: {}", request.from_agent);
        println!(
            "  Required: {}",
            request.capabilities_required.join(", ")
        );

        let has_all = request
            .capabilities_required
            .iter()
            .all(|c| agent.has_capability(c));

        if !has_all {
            let missing: Vec<_> = request
                .capabilities_required
                .iter()
                .filter(|c| !agent.has_capability(c))
                .cloned()
                .collect();
            client
                .reject_handoff(
                    &request.request_id,
                    &format!("Missing capabilities: {}", missing.join(", ")),
                )
                .unwrap();
            println!("  -> Rejected (missing capabilities)");
            continue;
        }

        if !agent.can_accept_work() {
            client
                .reject_handoff(&request.request_id, "Agent is busy with another task")
                .unwrap();
            println!("  -> Rejected (busy)");
            continue;
        }

        client.accept_handoff(&request.request_id).unwrap();
        agent.mark_busy();
        accepted.push(request.request_id.clone());
        println!("  -> Accepted");
    }

    accepted
}

// ============================================================================
// Scenario 1: Successful handoff (Code → Security)
// ============================================================================

fn scenario1_successful_handoff() {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 1: Successful Handoff (Code -> Security)");
    println!("{}", "=".repeat(60));

    let client = HandoffClient::new();
    let mut security_agent =
        Agent::new("security-agent", vec!["security-audit", "vulnerability-scan"]);

    println!("\n[code-agent] Found security-sensitive code, requesting security review...");

    let context = serde_json::json!({
        "file_path": "src/auth/login.rs",
        "code_hash": "abc123",
        "concern": "Handling of user credentials",
        "lines_affected": [45, 67, 89],
    });

    let request = HandoffRequest::new(
        "code-agent".to_string(),
        "security-agent".to_string(),
        "Security review needed for authentication module".to_string(),
    )
    .with_context(serde_json::to_vec(&context).unwrap())
    .with_capabilities(vec!["security-audit".to_string()])
    .with_priority(5);

    // request_handoff stores the request and returns immediately (Pending)
    let response = client.request_handoff(request).unwrap();
    println!(
        "\n[Handoff] Request stored: handoff_id={}",
        response.handoff_id
    );
    println!("  Status: {:?}", response.status);

    // Target agent evaluates and accepts
    let accepted = process_pending_handoffs(&client, &mut security_agent);
    assert!(!accepted.is_empty());

    // Verify status after acceptance
    let status = client
        .get_handoff_status(&accepted[0])
        .unwrap()
        .unwrap();
    println!(
        "\n[Handoff] After acceptance: status={:?}, accepted={}",
        status.status, status.accepted
    );

    // Agent completes the work
    println!("\n[security-agent] Performing security audit...");
    client.complete_handoff(&accepted[0]).unwrap();
    security_agent.mark_free();

    let final_status = client
        .get_handoff_status(&accepted[0])
        .unwrap()
        .unwrap();
    println!(
        "[security-agent] Audit complete. Final status: {:?}",
        final_status.status
    );
    assert_eq!(final_status.status, HandoffStatus::Completed);
}

// ============================================================================
// Scenario 2: Rejected handoff (missing capabilities)
// ============================================================================

fn scenario2_rejected_handoff() {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 2: Rejected Handoff (Missing Capabilities)");
    println!("{}", "=".repeat(60));

    let client = HandoffClient::new();
    let mut docs_agent = Agent::new("docs-agent", vec!["documentation", "markdown"]);

    println!("\n[code-agent] Requesting deployment help from docs agent (wrong agent)...");

    let request = HandoffRequest::new(
        "code-agent".to_string(),
        "docs-agent".to_string(),
        "Need help with Kubernetes deployment".to_string(),
    )
    .with_capabilities(vec![
        "kubernetes".to_string(),
        "deployment".to_string(),
    ])
    .with_priority(5);

    let response = client.request_handoff(request).unwrap();
    println!(
        "\n[Handoff] Request stored: handoff_id={}",
        response.handoff_id
    );

    let accepted = process_pending_handoffs(&client, &mut docs_agent);
    assert!(accepted.is_empty());

    let status = client
        .get_handoff_status(&response.handoff_id)
        .unwrap()
        .unwrap();
    println!("\n[Handoff] Result: accepted={}", status.accepted);
    println!("  Reason: {:?}", status.rejection_reason);
    assert_eq!(status.status, HandoffStatus::Rejected);
}

// ============================================================================
// Scenario 3: Busy agent rejects second handoff
// ============================================================================

fn scenario3_busy_agent() {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 3: Rejected Handoff (Busy Agent)");
    println!("{}", "=".repeat(60));

    let client = HandoffClient::new();
    let mut agent2 = Agent::new("agent-2", vec!["task-a", "task-b"]);

    // First handoff — accepted
    println!("\n[agent-1] First handoff request...");
    let req1 = HandoffRequest::new(
        "agent-1".to_string(),
        "agent-2".to_string(),
        "Task A work".to_string(),
    )
    .with_capabilities(vec!["task-a".to_string()])
    .with_priority(5);

    let resp1 = client.request_handoff(req1).unwrap();
    let accepted1 = process_pending_handoffs(&client, &mut agent2);
    assert_eq!(accepted1.len(), 1);

    let status1 = client
        .get_handoff_status(&resp1.handoff_id)
        .unwrap()
        .unwrap();
    println!(
        "\nFirst: accepted={}, status={:?}",
        status1.accepted, status1.status
    );

    // Second handoff — agent2 is now busy
    println!("\n[agent-1] Second handoff request while agent-2 is busy...");
    let req2 = HandoffRequest::new(
        "agent-1".to_string(),
        "agent-2".to_string(),
        "More Task A work".to_string(),
    )
    .with_capabilities(vec!["task-a".to_string()])
    .with_priority(5);

    let resp2 = client.request_handoff(req2).unwrap();
    let accepted2 = process_pending_handoffs(&client, &mut agent2);
    assert!(accepted2.is_empty());

    let status2 = client
        .get_handoff_status(&resp2.handoff_id)
        .unwrap()
        .unwrap();
    println!("\nSecond: accepted={}", status2.accepted);
    println!("  Reason: {:?}", status2.rejection_reason);

    // First task finishes
    client.complete_handoff(&accepted1[0]).unwrap();
    agent2.mark_free();
}

// ============================================================================
// Scenario 4: Context preservation
// ============================================================================

fn scenario4_context_preservation() {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 4: Context Preservation");
    println!("{}", "=".repeat(60));

    let client = HandoffClient::new();
    let mut review_agent = Agent::new("review-agent", vec!["code-review", "quality-check"]);

    let complex_context = serde_json::json!({
        "pull_request": {
            "id": "PR-123",
            "title": "Add user authentication",
            "files_changed": 15,
            "additions": 450,
            "deletions": 120,
        },
        "code_analysis": {
            "complexity_score": 7.5,
            "test_coverage": 85.2,
            "lint_warnings": 3,
        },
        "previous_reviews": [
            { "reviewer": "auto-lint", "status": "passed" },
            { "reviewer": "type-check", "status": "passed" },
        ],
    });

    println!("\n[code-agent] Handing off for code review with rich context...");

    let request = HandoffRequest::new(
        "code-agent".to_string(),
        "review-agent".to_string(),
        "PR ready for human-like code review".to_string(),
    )
    .with_context(serde_json::to_vec(&complex_context).unwrap())
    .with_capabilities(vec!["code-review".to_string()])
    .with_priority(3);

    let response = client.request_handoff(request).unwrap();
    let accepted = process_pending_handoffs(&client, &mut review_agent);
    assert!(!accepted.is_empty());

    println!(
        "\n[Handoff] Result: accepted={}",
        client
            .get_handoff_status(&response.handoff_id)
            .unwrap()
            .unwrap()
            .accepted
    );

    // Show context received (in production, agent reads from the request)
    let context_str = serde_json::to_string_pretty(&complex_context).unwrap();
    println!("\n[review-agent] Received context:");
    for line in context_str.lines().take(10) {
        println!("  {}", line);
    }
    println!("  ...");

    client.complete_handoff(&accepted[0]).unwrap();
    review_agent.mark_free();
}

// ============================================================================
// Scenario 5: Rejection with options (overloaded + redirect)
// ============================================================================

fn scenario5_rejection_with_options() {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 5: Rejection with Options (Overloaded + Redirect)");
    println!("{}", "=".repeat(60));

    let client = HandoffClient::new();

    // Request sent to an overloaded agent
    println!("\n[requester] Sending work to overloaded-agent...");
    let req = HandoffRequest::new(
        "requester".to_string(),
        "overloaded-agent".to_string(),
        "Process data batch".to_string(),
    )
    .with_capabilities(vec!["data-processing".to_string()])
    .with_priority(5);

    let resp = client.request_handoff(req).unwrap();

    // Overloaded agent rejects with OVERLOADED code and retry hint
    client
        .reject_handoff_with_options(
            &resp.handoff_id,
            "Agent at capacity (12/12 slots)",
            RejectHandoffOptions {
                rejection_code: Some(REJECTION_CODE_OVERLOADED),
                retry_after_ms: Some(5000),
                redirect_to_agent_id: None,
            },
        )
        .unwrap();

    let status = client
        .get_handoff_status(&resp.handoff_id)
        .unwrap()
        .unwrap();
    println!("\n  Status: {:?}", status.status);
    println!("  Rejection code: {:?}", status.rejection_code);
    println!("  Retry after ms: {:?}", status.retry_after_ms);

    // Second request — agent redirects to an alternative
    println!("\n[requester] Sending work to redirect-agent...");
    let req2 = HandoffRequest::new(
        "requester".to_string(),
        "redirect-agent".to_string(),
        "Process another batch".to_string(),
    )
    .with_capabilities(vec!["data-processing".to_string()])
    .with_priority(5);

    let resp2 = client.request_handoff(req2).unwrap();

    client
        .reject_handoff_with_options(
            &resp2.handoff_id,
            "Redirecting to backup-agent",
            RejectHandoffOptions {
                rejection_code: Some(REJECTION_CODE_REDIRECT),
                retry_after_ms: None,
                redirect_to_agent_id: Some("backup-agent".to_string()),
            },
        )
        .unwrap();

    let status2 = client
        .get_handoff_status(&resp2.handoff_id)
        .unwrap()
        .unwrap();
    println!("\n  Status: {:?}", status2.status);
    println!("  Rejection code: {:?}", status2.rejection_code);
    println!("  Redirect to: {:?}", status2.redirect_to_agent_id);
}

// ============================================================================
// Scenario 6: Cross-swarm delegation with BudgetEnvelope
// ============================================================================

fn scenario6_budget_delegation() {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 6: Cross-Swarm Delegation with BudgetEnvelope");
    println!("{}", "=".repeat(60));

    let client = HandoffClient::new();
    let mut worker = Agent::new("worker", vec!["data-processing"]);

    println!("\n[orchestrator] Delegating with budget constraints...");

    let deadline = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_millis() as u64
        + 30_000;

    let budget = BudgetEnvelope {
        token_budget_remaining: Some(10_000),
        wall_time_remaining_ms: Some(25_000),
        deadline_epoch_ms: deadline,
        current_depth: Some(1),
        max_delegation_depth: Some(3),
    };

    let policy = SwarmDelegationPolicy {
        max_retries_on_overloaded: 3,
        initial_backoff_ms: 200,
        backoff_multiplier: 2.0,
        max_backoff_ms: 5000,
        allow_spillover_routing: true,
        max_redirects: 2,
    };

    let request = HandoffRequest::new(
        "orchestrator".to_string(),
        "worker".to_string(),
        "Cross-swarm data processing delegation".to_string(),
    )
    .with_context(
        serde_json::to_vec(&serde_json::json!({
            "dataset": "batch-42",
            "rows": 50000,
        }))
        .unwrap(),
    )
    .with_capabilities(vec!["data-processing".to_string()])
    .with_priority(2)
    .with_budget(budget)
    .with_delegation_policy(policy);

    // The budget and policy are attached to the request before sending
    println!("  Budget deadline: {} (epoch ms)", deadline);
    println!("  Token budget: 10000");
    println!("  Delegation depth: 1/3");
    println!("  Max retries on overloaded: 3");
    println!("  Spillover routing: true");

    let resp = client.request_handoff(request).unwrap();
    let accepted = process_pending_handoffs(&client, &mut worker);
    assert!(!accepted.is_empty());

    let status = client
        .get_handoff_status(&resp.handoff_id)
        .unwrap()
        .unwrap();
    println!("\n  Result: accepted={}", status.accepted);

    // Demonstrate validation: budget with invalid deadline
    println!("\n--- Budget Validation Error ---");
    let bad_request = HandoffRequest::new(
        "test".to_string(),
        "test2".to_string(),
        "Bad budget".to_string(),
    )
    .with_budget(BudgetEnvelope::new(0)); // Invalid: zero deadline

    match client.request_handoff(bad_request) {
        Ok(_) => println!("  Unexpected success"),
        Err(e) => println!("  Caught: {}", e),
    }

    client.complete_handoff(&accepted[0]).unwrap();
    worker.mark_free();
}

// ============================================================================
// Main
// ============================================================================

fn main() {
    println!("SW4RM Agent Handoff Example");
    println!("{}", "=".repeat(60));
    println!("\nThis example uses the SDK HandoffClient to demonstrate");
    println!("agent-to-agent task handoff with capability-based routing.\n");

    scenario1_successful_handoff();
    scenario2_rejected_handoff();
    scenario3_busy_agent();
    scenario4_context_preservation();
    scenario5_rejection_with_options();
    scenario6_budget_delegation();

    println!("\n{}", "=".repeat(60));
    println!("SUMMARY");
    println!("{}", "=".repeat(60));
    println!("\nKey takeaways:");
    println!("1. HandoffClient::request_handoff() stores a request and returns immediately");
    println!("2. Target agents call accept_handoff()/reject_handoff() via get_pending_handoffs()");
    println!("3. Context is preserved in context_snapshot (Vec<u8>) during handoff");
    println!("4. complete_handoff() marks the lifecycle as done after work finishes");
    println!("5. Busy or incapable agents reject with a reason");
    println!("6. reject_handoff_with_options() supports OVERLOADED (retry) and REDIRECT (alternative agent) codes");
    println!("7. BudgetEnvelope + SwarmDelegationPolicy enable cross-swarm delegation with constraints");
}
