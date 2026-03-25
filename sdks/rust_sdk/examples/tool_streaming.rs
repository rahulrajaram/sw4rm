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

//! Tool Streaming Example for SW4RM Protocol.
//!
//! This example demonstrates:
//! - Streaming tool calls using `MockToolClient::call_stream()`
//! - How to handle streaming frames progressively via `tokio::sync::mpsc`
//! - Cancellation handling with `Arc<AtomicBool>`
//! - Frame types: `PROGRESS`, `OUTPUT`, `RESULT`, `ERROR`, `CANCELLED`
//!
//! Execution mode: Mock/stub — no gRPC service required.
//! The `MockToolProvider` simulates the behaviour of a real `ToolClient`
//! that would connect to a running Tool service on `localhost:50054`.
//!
//! Run:
//! ```bash
//! cargo run --example tool_streaming
//! ```

use anyhow::Result;
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::mpsc;
use tokio::time::{sleep, Duration};
use uuid::Uuid;

// ============================================================================
// Frame Types and Data Structures
// ============================================================================

/// Types of frames in a streaming tool response.
#[derive(Debug, Clone, PartialEq)]
pub enum FrameType {
    /// Progress update (percentage, status message).
    Progress,
    /// Partial output data.
    Output,
    /// Final result frame — stream ends after this.
    Result,
    /// Error occurred — stream ends after this.
    Error,
    /// Tool call was cancelled — stream ends after this.
    Cancelled,
}

/// A single frame in a streaming tool response.
#[derive(Debug, Clone)]
pub struct ToolFrame {
    /// Unique identifier for the tool call this frame belongs to.
    pub call_id: String,
    /// Type of this frame.
    pub frame_type: FrameType,
    /// Sequence number for ordering frames within a call.
    pub sequence: u32,
    /// Frame payload; content varies by `frame_type`.
    pub data: Value,
    /// Unix millisecond timestamp of frame generation.
    pub timestamp_ms: u64,
}

impl ToolFrame {
    fn new(call_id: &str, frame_type: FrameType, sequence: u32, data: Value) -> Self {
        let timestamp_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_millis() as u64;

        Self {
            call_id: call_id.to_string(),
            frame_type,
            sequence,
            data,
            timestamp_ms,
        }
    }
}

/// Request to execute a tool.
#[derive(Debug, Clone)]
pub struct ToolCall {
    /// Unique identifier for this call.
    pub call_id: String,
    /// Name of the tool to execute.
    pub tool_name: String,
    /// ID of the provider offering this tool.
    pub provider_id: String,
    /// Arguments to pass to the tool.
    pub args: HashMap<String, Value>,
    /// Optional worktree context.
    pub worktree_id: Option<String>,
    /// Maximum execution time in milliseconds.
    pub timeout_ms: u64,
}

/// Result of a cancellation request.
#[derive(Debug, Clone)]
pub struct CancelResult {
    /// The call_id that was targeted for cancellation.
    pub call_id: String,
    /// Whether the cancellation was acknowledged.
    pub success: bool,
    /// Human-readable status message.
    pub message: String,
}

// ============================================================================
// Mock Tool Provider
// ============================================================================

/// Mock tool provider simulating a gRPC-backed Tool service.
///
/// In production this logic lives inside the real `ToolClient`, which
/// speaks to `localhost:50054`.  Here every tool is executed in a
/// `tokio::spawn` background task and frames are delivered through an
/// `mpsc` channel so callers receive an async `Receiver<ToolFrame>`.
pub struct MockToolProvider {
    /// Per-call cancellation flags: call_id -> AtomicBool.
    cancel_flags: Arc<tokio::sync::Mutex<HashMap<String, Arc<AtomicBool>>>>,
}

impl MockToolProvider {
    pub fn new() -> Self {
        Self {
            cancel_flags: Arc::new(tokio::sync::Mutex::new(HashMap::new())),
        }
    }

    /// Execute a tool with a streaming response.
    ///
    /// Spawns a background task and returns an `mpsc::Receiver<ToolFrame>`.
    /// The caller drains the receiver to observe frames as they arrive.
    pub async fn call_stream(&self, call: ToolCall) -> mpsc::Receiver<ToolFrame> {
        let (tx, rx) = mpsc::channel::<ToolFrame>(64);
        let cancel_flag = Arc::new(AtomicBool::new(false));

        // Register the cancel flag so `cancel()` can find it.
        {
            let mut flags = self.cancel_flags.lock().await;
            flags.insert(call.call_id.clone(), cancel_flag.clone());
        }

        let flags_ref = self.cancel_flags.clone();

        tokio::spawn(async move {
            match call.tool_name.as_str() {
                "file_search" => {
                    file_search_stream(&call, &tx, &cancel_flag).await;
                }
                "code_analysis" => {
                    code_analysis_stream(&call, &tx, &cancel_flag).await;
                }
                "long_computation" => {
                    long_computation_stream(&call, &tx, &cancel_flag).await;
                }
                unknown => {
                    let _ = tx
                        .send(ToolFrame::new(
                            &call.call_id,
                            FrameType::Error,
                            0,
                            json!({ "error": format!("Unknown tool: {}", unknown) }),
                        ))
                        .await;
                }
            }

            // Remove the cancel flag when the task finishes.
            let mut flags = flags_ref.lock().await;
            flags.remove(&call.call_id);
        });

        rx
    }

    /// Cancel an active tool call.
    ///
    /// Sets the shared `AtomicBool` for the call.  The background task
    /// polls this flag at every iteration and emits a `CANCELLED` frame
    /// when it detects it.
    pub async fn cancel(&self, call_id: &str) -> CancelResult {
        let flags = self.cancel_flags.lock().await;
        match flags.get(call_id) {
            Some(flag) => {
                flag.store(true, Ordering::SeqCst);
                CancelResult {
                    call_id: call_id.to_string(),
                    success: true,
                    message: "Cancellation requested".to_string(),
                }
            }
            None => CancelResult {
                call_id: call_id.to_string(),
                success: false,
                message: "Call not found or already completed".to_string(),
            },
        }
    }
}

// ============================================================================
// Streaming Implementations (free async functions)
// ============================================================================

/// Simulate a file-search tool emitting PROGRESS + OUTPUT frames per file.
async fn file_search_stream(
    call: &ToolCall,
    tx: &mpsc::Sender<ToolFrame>,
    cancelled: &Arc<AtomicBool>,
) {
    let pattern = call
        .args
        .get("pattern")
        .and_then(|v| v.as_str())
        .unwrap_or("*")
        .to_string();
    let directory = call
        .args
        .get("directory")
        .and_then(|v| v.as_str())
        .unwrap_or("/")
        .to_string();

    let files = vec![
        format!("{}/file1.rs", directory),
        format!("{}/file2.rs", directory),
        format!("{}/subdir/file3.rs", directory),
        format!("{}/subdir/file4.rs", directory),
        format!("{}/subdir/deep/file5.rs", directory),
    ];

    let total = files.len();

    for (i, file_path) in files.iter().enumerate() {
        if cancelled.load(Ordering::SeqCst) {
            let _ = tx
                .send(ToolFrame::new(
                    &call.call_id,
                    FrameType::Cancelled,
                    i as u32 * 2,
                    json!({
                        "message": "Search cancelled by user",
                        "files_found": i,
                    }),
                ))
                .await;
            return;
        }

        // PROGRESS frame.
        let _ = tx
            .send(ToolFrame::new(
                &call.call_id,
                FrameType::Progress,
                i as u32 * 2,
                json!({
                    "percentage": ((i + 1) * 100 / total) as u64,
                    "status": format!("Searching... found {} files", i + 1),
                }),
            ))
            .await;

        // OUTPUT frame with the discovered file.
        let matches = pattern == "*" || file_path.contains(&pattern);
        let _ = tx
            .send(ToolFrame::new(
                &call.call_id,
                FrameType::Output,
                i as u32 * 2 + 1,
                json!({
                    "file": file_path,
                    "matches_pattern": matches,
                }),
            ))
            .await;

        sleep(Duration::from_millis(80)).await;
    }

    // RESULT frame — final summary.
    let _ = tx
        .send(ToolFrame::new(
            &call.call_id,
            FrameType::Result,
            total as u32 * 2,
            json!({
                "total_files": total,
                "pattern": pattern,
                "directory": directory,
            }),
        ))
        .await;
}

/// Simulate a code-analysis tool with per-step OUTPUT frames.
async fn code_analysis_stream(
    call: &ToolCall,
    tx: &mpsc::Sender<ToolFrame>,
    cancelled: &Arc<AtomicBool>,
) {
    let _code = call
        .args
        .get("code")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let analysis_steps: &[(&str, &str)] = &[
        ("syntax", "Checking syntax..."),
        ("imports", "Analyzing imports..."),
        ("types", "Checking type hints..."),
        ("complexity", "Computing complexity..."),
        ("security", "Scanning for vulnerabilities..."),
    ];

    let step_results: HashMap<&str, Value> = [
        (
            "syntax",
            json!({ "valid": true, "errors": [] }),
        ),
        (
            "imports",
            json!({ "count": 3, "external": ["serde", "tokio"] }),
        ),
        (
            "types",
            json!({ "coverage": 0.85, "missing": ["return type on line 5"] }),
        ),
        (
            "complexity",
            json!({ "cyclomatic": 4, "cognitive": 3 }),
        ),
        (
            "security",
            json!({ "issues": 0, "warnings": 1 }),
        ),
    ]
    .into_iter()
    .collect();

    let total = analysis_steps.len();

    for (i, (step_name, status_msg)) in analysis_steps.iter().enumerate() {
        if cancelled.load(Ordering::SeqCst) {
            let completed: Vec<_> = analysis_steps[..i].iter().map(|(n, _)| n).collect();
            let _ = tx
                .send(ToolFrame::new(
                    &call.call_id,
                    FrameType::Cancelled,
                    i as u32 * 2,
                    json!({
                        "message": "Analysis cancelled",
                        "completed_steps": completed,
                    }),
                ))
                .await;
            return;
        }

        // PROGRESS frame.
        let _ = tx
            .send(ToolFrame::new(
                &call.call_id,
                FrameType::Progress,
                i as u32 * 2,
                json!({
                    "percentage": ((i + 1) * 100 / total) as u64,
                    "status": status_msg,
                    "current_step": step_name,
                }),
            ))
            .await;

        sleep(Duration::from_millis(120)).await;

        // OUTPUT frame with this step's findings.
        let result = step_results.get(step_name).cloned().unwrap_or(json!({}));
        let _ = tx
            .send(ToolFrame::new(
                &call.call_id,
                FrameType::Output,
                i as u32 * 2 + 1,
                json!({
                    "step": step_name,
                    "result": result,
                }),
            ))
            .await;
    }

    // RESULT frame — aggregate summary.
    let _ = tx
        .send(ToolFrame::new(
            &call.call_id,
            FrameType::Result,
            total as u32 * 2,
            json!({
                "summary": "Analysis complete",
                "overall_score": 8.5,
            }),
        ))
        .await;
}

/// Simulate a long-running computation that can be cancelled mid-flight.
async fn long_computation_stream(
    call: &ToolCall,
    tx: &mpsc::Sender<ToolFrame>,
    cancelled: &Arc<AtomicBool>,
) {
    let iterations = call
        .args
        .get("iterations")
        .and_then(|v| v.as_u64())
        .unwrap_or(10) as u32;

    let mut accumulated: u64 = 0;

    for i in 0..iterations {
        if cancelled.load(Ordering::SeqCst) {
            let _ = tx
                .send(ToolFrame::new(
                    &call.call_id,
                    FrameType::Cancelled,
                    i,
                    json!({
                        "message": "Computation cancelled",
                        "completed_iterations": i,
                        "partial_result": accumulated,
                    }),
                ))
                .await;
            return;
        }

        sleep(Duration::from_millis(150)).await;
        accumulated += (i as u64) * (i as u64);

        let _ = tx
            .send(ToolFrame::new(
                &call.call_id,
                FrameType::Progress,
                i,
                json!({
                    "percentage": ((i + 1) * 100 / iterations) as u64,
                    "status": format!("Computing iteration {}/{}", i + 1, iterations),
                    "intermediate_result": accumulated,
                }),
            ))
            .await;
    }

    let _ = tx
        .send(ToolFrame::new(
            &call.call_id,
            FrameType::Result,
            iterations,
            json!({
                "final_result": accumulated,
                "iterations_completed": iterations,
            }),
        ))
        .await;
}

// ============================================================================
// Mock Tool Client (mirrors real ToolClient API shape)
// ============================================================================

/// Mock `ToolClient` wrapping a `MockToolProvider`.
///
/// This mirrors the public API of the real `sw4rm_sdk::clients::tool::ToolClient`.
/// Replace `MockToolProvider` with a real gRPC channel to talk to the Tool service.
pub struct MockToolClient {
    provider: Arc<MockToolProvider>,
}

impl MockToolClient {
    pub fn new() -> Self {
        Self {
            provider: Arc::new(MockToolProvider::new()),
        }
    }

    /// Execute a streaming tool call.
    ///
    /// Returns an `mpsc::Receiver<ToolFrame>` the caller drains to observe frames.
    pub async fn call_stream(
        &self,
        call_id: &str,
        tool_name: &str,
        provider_id: &str,
        args: HashMap<String, Value>,
    ) -> mpsc::Receiver<ToolFrame> {
        let call = ToolCall {
            call_id: call_id.to_string(),
            tool_name: tool_name.to_string(),
            provider_id: provider_id.to_string(),
            args,
            worktree_id: None,
            timeout_ms: 30_000,
        };
        self.provider.call_stream(call).await
    }

    /// Cancel an active tool call.
    pub async fn cancel(&self, call_id: &str) -> CancelResult {
        self.provider.cancel(call_id).await
    }
}

// ============================================================================
// Demo Scenarios
// ============================================================================

/// Demonstrate streaming file search with per-file progress updates.
async fn demo_file_search() -> Result<()> {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 1: Streaming File Search");
    println!("{}", "=".repeat(60));

    let client = MockToolClient::new();
    let call_id = Uuid::new_v4().to_string();

    let mut args = HashMap::new();
    args.insert("pattern".to_string(), json!("*.rs"));
    args.insert("directory".to_string(), json!("/project/src"));

    println!("\nExecuting file search for *.rs in /project/src ...");

    let mut rx = client
        .call_stream(&call_id, "file_search", "filesystem-provider", args)
        .await;

    let mut total_files = 0u64;
    let mut pattern = String::new();

    while let Some(frame) = rx.recv().await {
        match frame.frame_type {
            FrameType::Progress => {
                let pct = frame.data["percentage"].as_u64().unwrap_or(0);
                let status = frame.data["status"].as_str().unwrap_or("");
                println!("  Progress: {:3}%  {}", pct, status);
            }
            FrameType::Output => {
                let file = frame.data["file"].as_str().unwrap_or("");
                let matches = frame.data["matches_pattern"].as_bool().unwrap_or(false);
                if matches {
                    println!("  Found:    {}", file);
                }
            }
            FrameType::Result => {
                total_files = frame.data["total_files"].as_u64().unwrap_or(0);
                pattern = frame.data["pattern"]
                    .as_str()
                    .unwrap_or("")
                    .to_string();
                break;
            }
            FrameType::Error | FrameType::Cancelled => break,
        }
    }

    println!("\nSearch complete.");
    println!("  Total files found : {}", total_files);
    println!("  Pattern           : {}", pattern);

    Ok(())
}

/// Demonstrate streaming code analysis with per-step output.
async fn demo_code_analysis() -> Result<()> {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 2: Streaming Code Analysis");
    println!("{}", "=".repeat(60));

    let client = MockToolClient::new();

    let code_sample = r#"
fn calculate_total(items: &[Item]) -> f64 {
    let mut total = 0.0;
    for item in items {
        total += item.price * item.quantity as f64;
    }
    total
}
"#;

    println!("\nAnalyzing code:\n{}", code_sample);

    let mut args = HashMap::new();
    args.insert("code".to_string(), json!(code_sample));

    let mut rx = client
        .call_stream(
            &Uuid::new_v4().to_string(),
            "code_analysis",
            "analyzer-provider",
            args,
        )
        .await;

    let mut overall_score = 0.0f64;

    while let Some(frame) = rx.recv().await {
        match frame.frame_type {
            FrameType::Progress => {
                let pct = frame.data["percentage"].as_u64().unwrap_or(0);
                let status = frame.data["status"].as_str().unwrap_or("");
                println!("  [{:3}%] {}", pct, status);
            }
            FrameType::Output => {
                let step = frame.data["step"].as_str().unwrap_or("");
                let result = &frame.data["result"];
                println!("         {}: {}", step, result);
            }
            FrameType::Result => {
                overall_score = frame.data["overall_score"].as_f64().unwrap_or(0.0);
                break;
            }
            FrameType::Error | FrameType::Cancelled => break,
        }
    }

    println!("\nAnalysis complete.");
    println!("  Overall score: {}/10", overall_score);

    Ok(())
}

/// Demonstrate cancelling a long-running computation after 3 frames.
async fn demo_cancellation() -> Result<()> {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 3: Cancellation Handling");
    println!("{}", "=".repeat(60));

    let client = Arc::new(MockToolClient::new());
    let call_id = Uuid::new_v4().to_string();

    let mut args = HashMap::new();
    args.insert("iterations".to_string(), json!(20u64));

    println!("\nStarting long computation (will cancel after 3 PROGRESS frames) ...");

    let mut rx = client
        .call_stream(&call_id, "long_computation", "compute-provider", args)
        .await;

    let mut frames_received: u32 = 0;
    let mut cancelled = false;
    let mut completed_iterations = 0u64;
    let mut partial_result = 0u64;

    while let Some(frame) = rx.recv().await {
        match &frame.frame_type {
            FrameType::Progress => {
                let pct = frame.data["percentage"].as_u64().unwrap_or(0);
                let status = frame.data["status"].as_str().unwrap_or("");
                println!("  Progress: {:3}%  {}", pct, status);
                frames_received += 1;

                // Trigger cancellation after 3 progress frames.
                if frames_received == 3 {
                    println!("\n  Requesting cancellation...");
                    let cancel_result = client.cancel(&call_id).await;
                    println!("  Cancel result: {}", cancel_result.message);
                }
            }
            FrameType::Cancelled => {
                cancelled = true;
                completed_iterations =
                    frame.data["completed_iterations"].as_u64().unwrap_or(0);
                partial_result = frame.data["partial_result"].as_u64().unwrap_or(0);
                break;
            }
            FrameType::Result => {
                break;
            }
            FrameType::Error => break,
            _ => {}
        }
    }

    if cancelled {
        println!("\nComputation was cancelled.");
        println!("  Completed iterations : {}", completed_iterations);
        println!("  Partial result       : {}", partial_result);
    }

    Ok(())
}

/// Demonstrate error handling when an unknown tool name is requested.
async fn demo_error_handling() -> Result<()> {
    println!("\n{}", "=".repeat(60));
    println!("SCENARIO 4: Error Handling");
    println!("{}", "=".repeat(60));

    let client = MockToolClient::new();

    println!("\nCalling unknown tool 'nonexistent_tool' ...");

    let mut rx = client
        .call_stream(
            &Uuid::new_v4().to_string(),
            "nonexistent_tool",
            "unknown-provider",
            HashMap::new(),
        )
        .await;

    while let Some(frame) = rx.recv().await {
        match frame.frame_type {
            FrameType::Error => {
                let error_msg = frame.data["error"].as_str().unwrap_or("unknown error");
                println!("  ERROR: {}", error_msg);
                break;
            }
            FrameType::Result | FrameType::Cancelled => break,
            _ => {}
        }
    }

    Ok(())
}

/// Print a reference snippet showing how to use the real `ToolClient`.
///
/// This scenario requires no execution — it prints the code pattern a
/// caller would use once a live Tool gRPC service is available.
async fn demo_real_api_usage() {
    println!("\n{}", "=".repeat(60));
    println!("REAL API USAGE (Reference Only)");
    println!("{}", "=".repeat(60));

    println!(
        r#"
To use the real ToolClient with a running Tool service:

    use sw4rm_sdk::clients::tool::ToolClient;
    use tonic::transport::Channel;

    // Connect to the Tool service.
    let channel = Channel::from_static("http://localhost:50054")
        .connect()
        .await?;
    let mut client = ToolClient::new(channel);

    // Execute a streaming tool call.
    let call_id = uuid::Uuid::new_v4().to_string();
    let request = sw4rm_sdk::proto::CallToolStreamRequest {{
        call_id: call_id.clone(),
        tool_name: "file_search".to_string(),
        provider_id: "fs-provider".to_string(),
        args_json: serde_json::to_string(&serde_json::json!({{
            "pattern": "*.rs",
            "directory": "/src",
        }}))?,
        ..Default::default()
    }};

    let mut stream = client.call_tool_stream(request).await?.into_inner();

    while let Some(frame) = stream.message().await? {{
        match frame.frame_type {{
            1 => println!("Progress: {{}}%", frame.progress_pct),  // PROGRESS
            2 => println!("Output: {{}}",  frame.output_chunk),     // OUTPUT
            3 => {{ println!("Done: {{}}", frame.result); break; }} // RESULT
            4 => {{ println!("Error: {{}}", frame.error); break; }} // ERROR
            5 => {{ println!("Cancelled");  break; }}               // CANCELLED
            _ => {{}}
        }}
    }}

    // Cancel if needed.
    client.cancel_tool_call(sw4rm_sdk::proto::CancelToolCallRequest {{
        call_id,
        ..Default::default()
    }}).await?;
"#
    );
}

// ============================================================================
// Main
// ============================================================================

#[tokio::main]
async fn main() -> Result<()> {
    println!("SW4RM Tool Streaming Example");
    println!("{}", "=".repeat(60));
    println!(
        "Demonstrates streaming tool calls with progress updates and cancellation.\n"
    );

    demo_file_search().await?;
    demo_code_analysis().await?;
    demo_cancellation().await?;
    demo_error_handling().await?;
    demo_real_api_usage().await;

    println!("\n{}", "=".repeat(60));
    println!("ALL STREAMING SCENARIOS COMPLETED");
    println!("{}", "=".repeat(60));

    println!("\nKey takeaways:");
    println!("1. call_stream() spawns a background task; frames arrive via mpsc::Receiver");
    println!("2. Frame types: PROGRESS, OUTPUT, RESULT, ERROR, CANCELLED");
    println!("3. Process frames in a while-let loop; break on terminal frame types");
    println!("4. Cancellation uses Arc<AtomicBool> shared between caller and background task");
    println!("5. Check for Cancelled variant to retrieve partial results on early exit");

    Ok(())
}
