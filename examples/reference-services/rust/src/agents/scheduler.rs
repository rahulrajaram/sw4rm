use anyhow::Result;
use serde_json::Value;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use tokio::time::{sleep, Duration};
use tracing::{info, warn};

use sw4rm_sdk::clients::{registry::RegistryClient, router::RouterClient};
use sw4rm_sdk::constants;
use sw4rm_sdk::envelope::EnvelopeBuilder;
use sw4rm_sdk::proto::sw4rm::common::AgentState;
use sw4rm_sdk::types::AgentDescriptor;

const CT_SCHED_CMD: &str = "application/vnd.sw4rm.scheduler.command+json;v=1";

fn demo_root() -> PathBuf { std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")) .join("agents") }
fn session_file() -> PathBuf { demo_root().join(".scheduler_session_id") }
fn read_session_id() -> Option<String> { fs::read_to_string(session_file()).ok().map(|s| s.trim().to_string()).filter(|s| !s.is_empty()) }
fn write_session_id(sid: &str) { let _ = fs::write(session_file(), sid.as_bytes()); }

fn extract_first_json_object(s: &str) -> Option<Value> {
    if let Ok(v) = serde_json::from_str::<Value>(s) { if v.is_object() { return Some(v); } }
    if s.starts_with("```") {
        let mut lines: Vec<&str> = s.lines().collect();
        if !lines.is_empty() { lines.remove(0); }
        if let Some(last) = lines.last().cloned() { if last.trim().starts_with("```") { lines.pop(); } }
        let inner = lines.join("\n");
        if let Ok(v) = serde_json::from_str::<Value>(&inner) { if v.is_object() { return Some(v); } }
    }
    if let Some(start) = s.find('{') {
        let mut depth = 0;
        for (i, ch) in s[start..].char_indices() {
            let idx = start + i;
            match ch { '{' => depth += 1, '}' => { depth -= 1; if depth == 0 { if let Ok(v) = serde_json::from_str::<Value>(&s[start..=idx]) { return Some(v); } break; } }, _ => {} }
        }
    }
    None
}

fn run_claude(prompt: &str) -> Value {
    info!("[scheduler] claude prompt (first 400)\n{}", &prompt.chars().take(400).collect::<String>());
    let cli = std::env::var("CLAUDE_CLI").unwrap_or_else(|_| "claude".to_string());
    let mut args = vec!["-p".to_string(), prompt.to_string(), "--output-format".into(), "stream-json".into(), "--verbose".into()];
    static mut SESSION_READY: bool = false;
    if let Some(sid) = read_session_id() { unsafe { if SESSION_READY { args.push("--session-id".into()); args.push(sid.clone()); } } }
    let mut child = match Command::new(&cli).args(&args).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn() {
        Ok(c) => c, Err(_) => { warn!("[scheduler] claude CLI not found"); return Value::Object(serde_json::Map::new()); }
    };
    let stdout = child.stdout.take().unwrap();
    let reader = BufReader::new(stdout);
    let mut text_buf = String::new();
    let mut result_obj: Option<Value> = None;
    let mut seen_session: Option<String> = None;
    let mut last_result_text = String::new();
    for line in reader.lines().flatten() {
        let l = line.trim().to_string(); if l.is_empty() { continue; }
        if let Ok(obj) = serde_json::from_str::<Value>(&l) {
            let typ = obj.get("type").and_then(|v| v.as_str()).unwrap_or("");
            if typ == "content_block_delta" {
                if obj.get("delta").and_then(|d| d.get("type")).and_then(|v| v.as_str()) == Some("text_delta") {
                    if let Some(txt) = obj.get("delta").and_then(|d| d.get("text")).and_then(|v| v.as_str()) { text_buf.push_str(txt); }
                }
            } else if typ == "content_block_start" {
                if obj.get("content_block").and_then(|cb| cb.get("type")).and_then(|v| v.as_str()) == Some("text") {
                    if let Some(initial) = obj.get("content_block").and_then(|cb| cb.get("text")).and_then(|v| v.as_str()) { if !initial.is_empty() { text_buf.push_str(initial); } }
                }
            } else if typ == "message_delta" {
                if let Some(pj) = obj.get("delta").and_then(|d| d.get("partial_json")).and_then(|v| v.as_str()) { text_buf.push_str(pj); }
            }
            if typ == "result" {
                if let Some(sid) = obj.get("session_id").and_then(|v| v.as_str()) { write_session_id(sid); seen_session = Some(sid.to_string()); }
                if let Some(res) = obj.get("result") {
                    if let Some(s) = res.as_str() {
                        let mut t = s.trim().to_string();
                        if t.starts_with("```") {
                            let mut lines: Vec<&str> = t.lines().collect(); if !lines.is_empty() { lines.remove(0); }
                            if let Some(last) = lines.last().cloned() { if last.trim().ends_with("```") { lines.pop(); } }
                            t = lines.join("\n");
                        }
                        last_result_text = t.clone();
                        if let Some(parsed) = extract_first_json_object(&t) { result_obj = Some(parsed); }
                    } else if res.is_object() { result_obj = Some(res.clone()); last_result_text = res.to_string(); }
                }
            }
        }
    }
    let _ = child.wait();
    let full_text = text_buf.trim().to_string();
    if result_obj.is_none() && !full_text.is_empty() { result_obj = extract_first_json_object(&full_text); }
    if last_result_text.contains("Invalid API key") || full_text.contains("Invalid API key") { warn!("[scheduler] Claude CLI: Invalid API key. Run `claude login`."); }
    if seen_session.is_some() { unsafe { SESSION_READY = true; } }
    result_obj.unwrap_or_else(|| Value::Object(serde_json::Map::new()))
}

pub async fn run_control() -> Result<()> {
    let router_host = std::env::var("ROUTER_HOST").unwrap_or_else(|_| "localhost".into());
    let router_port = std::env::var("ROUTER_PORT").unwrap_or_else(|_| "50051".into());
    let registry_host = std::env::var("REGISTRY_HOST").unwrap_or_else(|_| "localhost".into());
    let registry_port = std::env::var("REGISTRY_PORT").unwrap_or_else(|_| "50052".into());
    let router_ep = format!("http://{}:{}", router_host, router_port);
    let registry_ep = format!("http://{}:{}", registry_host, registry_port);

    let mut router = RouterClient::new(&router_ep).await?;
    let mut registry = RegistryClient::new(&registry_ep).await?;
    let agent_id = "scheduler".to_string();
    let agent = AgentDescriptor::new(agent_id.clone(), "Scheduler".into())
        .with_description("CONTROL orchestrator".into())
        .with_capabilities(vec!["scheduler".into()]);
    let _ = registry.register(&agent).await;

    // Heartbeats
    let mut hb_registry = RegistryClient::new(&registry_ep).await?;
    tokio::spawn(async move { loop { let _ = hb_registry.heartbeat(&"scheduler", AgentState::AgentStateUnspecified, None).await; sleep(Duration::from_secs(30)).await; } });

    info!("[scheduler] waiting for CONTROL…");
    let mut stream = router.stream_incoming(&agent_id).await?;
    while let Some(item) = tokio_stream::StreamExt::next(&mut stream).await {
        let env = match item { Ok(e) => e, Err(e) => { warn!("[scheduler] stream error: {}", e); continue; } };
        if env.content_type != CT_SCHED_CMD { continue; }
        let payload_s = String::from_utf8(env.payload.clone()).unwrap_or_default();
        let cmd: Value = serde_json::from_str(&payload_s).unwrap_or(Value::Null);
        let stage = cmd.get("stage").and_then(|v| v.as_str()).unwrap_or("");
        let params = cmd.get("params").or_else(|| cmd.get("input")).cloned().unwrap_or(Value::Object(serde_json::Map::new()));
        let corr = env.correlation_id.clone();

        if stage == "prompt" || stage == "plan" {
            let user_text = params.get("prompt").and_then(|v| v.as_str()).unwrap_or("");
            let plan = run_claude(user_text);
            let backend_prompt = plan.get("backend").and_then(|v| v.as_str()).unwrap_or("");
            let frontend_prompt = plan.get("frontend").and_then(|v| v.as_str()).unwrap_or("");
            let mk = |to: &str, prompt: &str| serde_json::json!({"schema_version":1, "to": to, "stage":"generate", "params": {"prompt": prompt}});
            for (to, prompt) in [("backend", backend_prompt), ("frontend", frontend_prompt)] {
                if prompt.is_empty() { continue; }
                let env_out = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::CONTROL)
                    .with_payload(serde_json::to_vec(&mk(to, prompt)).unwrap())
                    .with_content_type(CT_SCHED_CMD.to_string())
                    .with_correlation_id(corr.clone())
                    .build();
                let _ = router.send_message(&env_out).await;
            }
        } else if stage == "run" {
            let mut commands = params.get("commands").cloned();
            if commands.is_none() {
                let guidance = params.get("prompt").cloned().unwrap_or(serde_json::json!(""));
                let run_prompt = format!(
                    "{}{}{}\n\nGuidance: {}",
                    "Return JSON ONLY as {\\\"commands\\\": { backend: { run_cmd }, frontend: { run_cmd } } }.",
                    " Execution cwd for agents is ./generated_app.",
                    " Backend: 'cd backend && python3 server.py'; Frontend: 'cd frontend && python3 -m http.server 5173'.",
                    guidance
                );
                let run_obj = run_claude(&run_prompt);
                commands = run_obj.get("commands").cloned();
            }
            let backend_cmd = commands.as_ref().and_then(|c| c.get("backend").and_then(|b| b.get("run_cmd")).and_then(|v| v.as_str())).unwrap_or("cd backend && python3 server.py");
            let frontend_cmd = commands.as_ref().and_then(|c| c.get("frontend").and_then(|b| b.get("run_cmd")).and_then(|v| v.as_str())).unwrap_or("cd frontend && python3 -m http.server 5173");
            let mk_run = |to: &str, cmdline: &str| serde_json::json!({"schema_version":1, "to": to, "stage":"run", "params": {"cmd": cmdline}});
            for (to, cmdline) in [("backend", backend_cmd), ("frontend", frontend_cmd)] {
                let env_out = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::CONTROL)
                    .with_payload(serde_json::to_vec(&mk_run(to, cmdline)).unwrap())
                    .with_content_type(CT_SCHED_CMD.to_string())
                    .with_correlation_id(corr.clone())
                    .build();
                let _ = router.send_message(&env_out).await;
            }
        }
    }
    Ok(())
}

