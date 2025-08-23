use anyhow::Result;
use serde_json::{json, Value};
use std::fs::{self, File};
use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use tokio::time::{sleep, Duration};
use tracing::{info, warn};
use std::os::unix::fs::PermissionsExt;

use sw4rm_sdk::clients::{registry::RegistryClient, router::RouterClient};
use sw4rm_sdk::constants;
use sw4rm_sdk::envelope::EnvelopeBuilder;
use sw4rm_sdk::proto::sw4rm::common::AgentState;
use sw4rm_sdk::types::AgentDescriptor;

const CT_SCHED_CMD: &str = "application/vnd.sw4rm.scheduler.command+json;v=1";
const CT_AGENT_REPORT: &str = "application/vnd.sw4rm.agent.report+json;v=1";

fn root_dir() -> PathBuf { std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")) }
fn demo_root() -> PathBuf { root_dir().join("agents") }
fn gen_root() -> PathBuf { demo_root().join("generated_app").join("frontend") }
fn session_file() -> PathBuf { demo_root().join(".frontend_session_id") }

fn ensure_workspace() { let _ = fs::create_dir_all(gen_root()); }

fn normalize_rel(rel: &str) -> PathBuf {
    let s = rel.replace('\\', "/");
    let mut parts: Vec<&str> = s.split('/')
        .filter(|p| !p.is_empty() && *p != "." && *p != "..")
        .collect();
    if parts.first() == Some(&"generated_app") { parts.remove(0); }
    if parts.first() == Some(&"frontend") { parts.remove(0); }
    if parts.is_empty() { parts.push("unknown.txt"); }
    let mut out = PathBuf::new();
    for p in parts { out.push(p); }
    out
}

fn write_frontend_files(result_obj: &Value, fallback_prompt: &str) -> Vec<String> {
    let mut written = Vec::new();
    if let Some(files) = result_obj.get("files").and_then(|v| v.as_array()) {
        for f in files {
            let rel = f.get("path").and_then(|v| v.as_str()).unwrap_or("unknown.txt");
            let out_path = gen_root().join(normalize_rel(rel));
            if let Some(parent) = out_path.parent() { let _ = fs::create_dir_all(parent); }
            let encoding = f.get("encoding").and_then(|v| v.as_str()).unwrap_or("").to_ascii_lowercase();
            if f.get("content_b64").is_some() || encoding == "base64" {
                let b64 = f.get("content_b64").or_else(|| f.get("content")).and_then(|v| v.as_str()).unwrap_or("");
                let data = base64::decode(b64).unwrap_or_default();
                let _ = fs::write(&out_path, data);
            } else {
                let text = f.get("content").and_then(|v| v.as_str()).unwrap_or("");
                let _ = fs::write(&out_path, text);
            }
            if f.get("executable").and_then(|v| v.as_bool()).unwrap_or(false) {
                let _ = fs::set_permissions(&out_path, fs::Permissions::from_mode(0o755));
            }
            if let Ok(rel) = out_path.strip_prefix(gen_root()) { written.push(rel.to_string_lossy().to_string()); }
        }
        return written;
    }
    // Fallback minimal frontend
    let index_html = r#"<!doctype html>
<html><head><meta charset=\"utf-8\"><title>Frontend</title></head>
<body>
  <h1>Frontend</h1>
  <button id=\"btn\">Call Backend</button>
  <pre id=\"out\"></pre>
  <script src=\"index.js\"></script>
</body></html>
"#;
    let index_js = r#"
const qs = new URLSearchParams(location.search);
const backend = qs.get('backend_url') || 'http://localhost:8000';
document.getElementById('btn').addEventListener('click', async () => {
  const url = backend.replace(/\/$/, '') + '/hello';
  try {
    const res = await fetch(url);
    document.getElementById('out').textContent = await res.text();
  } catch (e) {
    document.getElementById('out').textContent = String(e);
  }
});
"#;
    let _ = fs::write(gen_root().join("index.html"), index_html);
    let _ = fs::write(gen_root().join("index.js"), index_js);
    let _ = fs::write(gen_root().join("PROMPT.txt"), fallback_prompt);
    vec!["index.html".into(), "index.js".into(), "PROMPT.txt".into()]
}

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
    info!("claude prompt (first 400)\n{}", &prompt.chars().take(400).collect::<String>());
    let cli = std::env::var("CLAUDE_CLI").unwrap_or_else(|_| "claude".to_string());
    let mut args = vec!["-p".to_string(), prompt.to_string(), "--output-format".into(), "stream-json".into(), "--verbose".into()];
    static mut SESSION_READY: bool = false;
    if let Some(sid) = read_session_id() {
        unsafe { if SESSION_READY { args.push("--session-id".into()); args.push(sid.clone()); } }
    }
    let mut child = match Command::new(&cli).args(&args).stdout(Stdio::piped()).stderr(Stdio::piped()).spawn() {
        Ok(c) => c,
        Err(_) => { warn!("claude CLI not found on PATH."); return Value::Object(serde_json::Map::new()); }
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
    if (last_result_text.contains("Invalid API key")) || (full_text.contains("Invalid API key")) { warn!("Claude CLI reports Invalid API key. Run `claude login`."); }
    info!("claude session={}, result_excerpt (first 400):\n{}",
        seen_session.clone().unwrap_or_else(|| "-".into()),
        last_result_text.chars().take(400).collect::<String>()
    );
    if seen_session.is_some() { unsafe { SESSION_READY = true; } }
    result_obj.unwrap_or_else(|| Value::Object(serde_json::Map::new()))
}

pub async fn run() -> Result<()> {
    ensure_workspace();

    let router_host = std::env::var("ROUTER_HOST").unwrap_or_else(|_| "localhost".into());
    let router_port = std::env::var("ROUTER_PORT").unwrap_or_else(|_| "50051".into());
    let registry_host = std::env::var("REGISTRY_HOST").unwrap_or_else(|_| "localhost".into());
    let registry_port = std::env::var("REGISTRY_PORT").unwrap_or_else(|_| "50052".into());

    let router_ep = format!("http://{}:{}", router_host, router_port);
    let registry_ep = format!("http://{}:{}", registry_host, registry_port);

    let mut router = RouterClient::new(&router_ep).await?;
    let mut registry = RegistryClient::new(&registry_ep).await?;

    let agent_id = "frontend".to_string();
    let agent = AgentDescriptor::new(agent_id.clone(), "Frontend Agent".into())
        .with_description("Generates frontend client".into())
        .with_capabilities(vec!["frontend".into()]);
    let _ = registry.register(&agent).await;

    // Heartbeats
    let mut hb_registry = RegistryClient::new(&registry_ep).await?;
    let aid = agent_id.clone();
    tokio::spawn(async move {
        loop {
            let _ = hb_registry.heartbeat(&aid, AgentState::AgentStateUnspecified, None).await;
            sleep(Duration::from_secs(30)).await;
        }
    });

    info!("waiting for commands…");
    let mut stream = router.stream_incoming(&agent_id).await?;
    let mut processed: std::collections::HashSet<String> = std::collections::HashSet::new();
    while let Some(item) = tokio_stream::StreamExt::next(&mut stream).await {
        let env = match item { Ok(e) => e, Err(e) => { warn!("stream error: {}", e); continue; } };
        if env.content_type != CT_SCHED_CMD { continue; }
        let payload_s = String::from_utf8(env.payload.clone()).unwrap_or_default();
        let cmd: Value = serde_json::from_str(&payload_s).unwrap_or(Value::Null);
        let to = cmd.get("to").and_then(|v| v.as_str()); if let Some(t) = to { if t != agent_id { continue; } }
        let stage = cmd.get("stage").and_then(|v| v.as_str()).unwrap_or("");
        let params = cmd.get("params").or_else(|| cmd.get("input")).cloned().unwrap_or(Value::Object(serde_json::Map::new()));
        let corr = env.correlation_id.clone();
        let key = format!("{}:{}:{}", corr, stage, params);
        if processed.contains(&key) { info!("duplicate command ignored {}", key); continue; }

        match stage {
            "generate" => {
                let prompt = params.get("prompt").and_then(|v| v.as_str()).unwrap_or("");
                info!("generate: invoking claude…");
                let result_obj = run_claude(prompt);
                let files_written = write_frontend_files(&result_obj, prompt);
                let report = json!({
                    "schema_version": 1,
                    "stage": "generate",
                    "status": "ok",
                    "files": files_written,
                });
                let env_out = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::NOTIFICATION)
                    .with_payload(serde_json::to_vec(&report).unwrap())
                    .with_content_type(CT_AGENT_REPORT.to_string())
                    .with_correlation_id(corr.clone())
                    .build();
                let _ = router.send_message(&env_out).await;
                let preview = if files_written.len() > 5 { format!("{}…", files_written[..5].join(", ")) } else { files_written.join(", ") };
                info!("completed generate: status=ok files={} [{}]", files_written.len(), preview);
                processed.insert(key);
            }
            "run" => {
                let suggested = params.get("cmd").and_then(|v| v.as_str()).unwrap_or("");
                let llm_prompt = format!(
                    "{}{}{}",
                    "You are the frontend run orchestrator. A suggested command was provided. ",
                    "Return JSON ONLY as {\"run_cmd\": string}. Execution cwd is ./generated_app. ",
                    "Use 'cd frontend && python3 -m http.server 5173'. Do NOT include 'generated_app' in paths.\n\n",
                ) + &format!("Suggested: {}", serde_json::to_string(&suggested).unwrap());
                info!("run: invoking claude to confirm command…");
                let result_obj = run_claude(&llm_prompt);
                let cmdline = result_obj.get("run_cmd").and_then(|v| v.as_str()).unwrap_or(suggested);
                let base_dir = demo_root().join("generated_app");
                let log_path = gen_root().join("service.log");
                let mut status = "ok".to_string();
                let mut info_map = json!({"cmd": cmdline});
                match File::options().create(true).append(true).open(&log_path) {
                    Ok(file) => {
                        let _ = fs::write(gen_root().join(".service.pid"), "");
                        match Command::new("sh").arg("-c").arg(cmdline)
                            .current_dir(&base_dir)
                            .stdout(Stdio::from(file.try_clone().unwrap()))
                            .stderr(Stdio::from(file))
                            .spawn()
                        {
                            Ok(child) => {
                                let _ = fs::write(gen_root().join(".service.pid"), child.id().to_string());
                                info_map["pid"] = json!(child.id());
                            }
                            Err(e) => { status = "error".into(); info_map["error"] = json!(e.to_string()); }
                        }
                    }
                    Err(e) => { status = "error".into(); info_map["error"] = json!(e.to_string()); }
                }
                let report = json!({"schema_version":1, "stage":"run", "status":status, "info":info_map});
                let env_out = EnvelopeBuilder::new(agent_id.clone(), constants::message_type::NOTIFICATION)
                    .with_payload(serde_json::to_vec(&report).unwrap())
                    .with_content_type(CT_AGENT_REPORT.to_string())
                    .with_correlation_id(corr.clone())
                    .build();
                let _ = router.send_message(&env_out).await;
                processed.insert(key);
            }
            _ => {}
        }
    }

    Ok(())
}

