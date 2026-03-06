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

//! Groq LLM client for SW4RM agents.
//!
//! Thin wrapper around the Groq REST API (OpenAI-compatible). No vendor SDK
//! crate needed -- just `reqwest` HTTP calls.
//!
//! # Credential resolution (in order)
//!
//! 1. `api_key` constructor parameter
//! 2. `GROQ_API_KEY` environment variable
//! 3. `~/.groq` file (plain text, one line)
//!
//! # Environment variables
//!
//! | Variable | Default | Description |
//! |----------|---------|-------------|
//! | `GROQ_API_KEY` | - | API key |
//! | `GROQ_DEFAULT_MODEL` | `llama-3.3-70b-versatile` | Default model |

use std::collections::HashMap;
use std::pin::Pin;

use async_trait::async_trait;
use reqwest::Client;
use serde_json::json;
use tokio_stream::Stream;

use super::client::{LlmClient, LlmError, LlmResponse, LlmResult};
use super::rate_limiter;

/// Base URL for the Groq chat completions API.
const GROQ_API_URL: &str = "https://api.groq.com/openai/v1/chat/completions";

/// Default model when no override is provided.
const DEFAULT_MODEL: &str = "llama-3.3-70b-versatile";

/// LLM client for the Groq API.
///
/// Uses the OpenAI-compatible chat completions endpoint. Credentials are
/// resolved from the constructor parameter, the `GROQ_API_KEY` environment
/// variable, or the `~/.groq` file (in that order).
///
/// # Examples
///
/// ```rust,no_run
/// use sw4rm_sdk::llm::GroqClient;
/// use sw4rm_sdk::llm::LlmClient;
///
/// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
/// let client = GroqClient::new(None, None, None)?;
/// let response = client.query(
///     "Explain quantum computing",
///     Some("You are a physics teacher."),
///     4096,
///     0.7,
///     None,
/// ).await?;
/// println!("{}", response.content);
/// # Ok(())
/// # }
/// ```
#[derive(Debug, Clone)]
pub struct GroqClient {
    api_key: String,
    default_model: String,
    http_client: Client,
    #[allow(dead_code)]
    timeout_secs: u64,
}

impl GroqClient {
    /// Create a new Groq client.
    ///
    /// # Arguments
    ///
    /// * `api_key` - Explicit API key. Falls back to `GROQ_API_KEY` env var,
    ///   then `~/.groq` file.
    /// * `default_model` - Default model name. Falls back to
    ///   `GROQ_DEFAULT_MODEL` env var, then `"llama-3.3-70b-versatile"`.
    /// * `timeout_secs` - HTTP request timeout in seconds. Defaults to 120.
    ///
    /// # Errors
    ///
    /// Returns [`LlmError::Authentication`] if no API key can be resolved.
    pub fn new(
        api_key: Option<&str>,
        default_model: Option<&str>,
        timeout_secs: Option<u64>,
    ) -> LlmResult<Self> {
        let resolved_model = default_model
            .map(String::from)
            .or_else(|| std::env::var("GROQ_DEFAULT_MODEL").ok())
            .unwrap_or_else(|| DEFAULT_MODEL.to_string());

        let resolved_key = resolve_api_key(api_key, "GROQ_API_KEY", ".groq")?;

        let timeout = timeout_secs.unwrap_or(120);
        let http_client = Client::builder()
            .timeout(std::time::Duration::from_secs(timeout))
            .build()
            .map_err(|e| LlmError::Http(format!("Failed to create HTTP client: {}", e)))?;

        tracing::info!(model = %resolved_model, "Initialized Groq LLM client");

        Ok(Self {
            api_key: resolved_key,
            default_model: resolved_model,
            http_client,
            timeout_secs: timeout,
        })
    }
}

#[async_trait]
impl LlmClient for GroqClient {
    async fn query(
        &self,
        prompt: &str,
        system_prompt: Option<&str>,
        max_tokens: u32,
        temperature: f64,
        model_override: Option<&str>,
    ) -> LlmResult<LlmResponse> {
        let use_model = model_override.unwrap_or(&self.default_model);
        let estimated = estimate_tokens(prompt, system_prompt);
        rate_limiter::acquire(estimated).await?;

        let mut messages = Vec::new();
        if let Some(sys) = system_prompt {
            messages.push(json!({"role": "system", "content": sys}));
        }
        messages.push(json!({"role": "user", "content": prompt}));

        let body = json!({
            "model": use_model,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
        });

        let response = self
            .http_client
            .post(GROQ_API_URL)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| map_reqwest_error(e, "Groq"))?;

        let status = response.status();

        if !status.is_success() {
            let body_text = response.text().await.unwrap_or_default();
            return Err(map_http_status(status.as_u16(), &body_text, "Groq"));
        }

        rate_limiter::record_success();

        let resp_json: serde_json::Value = response
            .json()
            .await
            .map_err(|e| LlmError::Serialization(format!("Failed to parse Groq response: {}", e)))?;

        parse_openai_response(&resp_json, use_model)
    }

    async fn stream_query(
        &self,
        prompt: &str,
        system_prompt: Option<&str>,
        max_tokens: u32,
        temperature: f64,
        model_override: Option<&str>,
    ) -> LlmResult<Pin<Box<dyn Stream<Item = LlmResult<String>> + Send>>> {
        let use_model = model_override.unwrap_or(&self.default_model).to_string();
        let estimated = estimate_tokens(prompt, system_prompt);
        rate_limiter::acquire(estimated).await?;

        let mut messages = Vec::new();
        if let Some(sys) = system_prompt {
            messages.push(json!({"role": "system", "content": sys}));
        }
        messages.push(json!({"role": "user", "content": prompt}));

        let body = json!({
            "model": use_model,
            "messages": messages,
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": true,
        });

        let response = self
            .http_client
            .post(GROQ_API_URL)
            .header("Authorization", format!("Bearer {}", self.api_key))
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| map_reqwest_error(e, "Groq"))?;

        let status = response.status();
        if !status.is_success() {
            let body_text = response.text().await.unwrap_or_default();
            return Err(map_http_status(status.as_u16(), &body_text, "Groq"));
        }

        let byte_stream = response.bytes_stream();
        let stream = sse_text_stream(byte_stream);

        Ok(Box::pin(stream))
    }
}

// ---------------------------------------------------------------------------
// Shared helpers (also used by anthropic.rs via pub(crate))
// ---------------------------------------------------------------------------

/// Resolve an API key from explicit parameter, environment variable, or file.
///
/// # Arguments
///
/// * `explicit` - Explicitly provided API key (highest priority).
/// * `env_var` - Name of the environment variable to check.
/// * `file_name` - Name of the file in the user's home directory (e.g., ".groq").
///
/// # Errors
///
/// Returns [`LlmError::Authentication`] if no key is found from any source.
pub(crate) fn resolve_api_key(
    explicit: Option<&str>,
    env_var: &str,
    file_name: &str,
) -> LlmResult<String> {
    // 1. Explicit parameter
    if let Some(key) = explicit {
        let key = key.trim();
        if !key.is_empty() {
            return Ok(key.to_string());
        }
    }

    // 2. Environment variable
    if let Ok(val) = std::env::var(env_var) {
        let val = val.trim().to_string();
        if !val.is_empty() {
            return Ok(val);
        }
    }

    // 3. Home directory file
    if let Some(home) = dirs_home() {
        let path = home.join(file_name);
        if path.exists() {
            if let Ok(contents) = std::fs::read_to_string(&path) {
                let key = contents.trim().to_string();
                if !key.is_empty() {
                    return Ok(key);
                }
            }
        }
    }

    Err(LlmError::Authentication(format!(
        "No API key found. Set {}, pass api_key, or create ~/{}",
        env_var, file_name
    )))
}

/// Get the user's home directory.
fn dirs_home() -> Option<std::path::PathBuf> {
    directories::BaseDirs::new().map(|d| d.home_dir().to_path_buf())
}

/// Rough token estimate (~4 characters per token, minimum 100).
pub(crate) fn estimate_tokens(prompt: &str, system_prompt: Option<&str>) -> u64 {
    let mut total = prompt.len();
    if let Some(sys) = system_prompt {
        total += sys.len();
    }
    (total as u64 / 4).max(100)
}

/// Map a reqwest error to an [`LlmError`].
pub(crate) fn map_reqwest_error(err: reqwest::Error, provider: &str) -> LlmError {
    if err.is_timeout() {
        LlmError::Timeout(format!("{} request timed out: {}", provider, err))
    } else if err.is_connect() {
        LlmError::Http(format!("{} connection failed: {}", provider, err))
    } else {
        LlmError::Http(format!("{} HTTP error: {}", provider, err))
    }
}

/// Map an HTTP status code to an appropriate [`LlmError`] variant.
pub(crate) fn map_http_status(status: u16, body: &str, provider: &str) -> LlmError {
    match status {
        401 | 403 => {
            LlmError::Authentication(format!("{} auth failed ({}): {}", provider, status, body))
        }
        429 => {
            rate_limiter::record_rate_limit();
            LlmError::RateLimit(format!("{} rate limit exceeded: {}", provider, body))
        }
        400 if body.contains("context_length") || body.contains("too many tokens") => {
            LlmError::ContextLength(format!("{} context length exceeded: {}", provider, body))
        }
        _ => LlmError::Api(format!("{} API error ({}): {}", provider, status, body)),
    }
}

/// Parse an OpenAI-compatible chat completion response JSON.
pub(crate) fn parse_openai_response(
    resp: &serde_json::Value,
    fallback_model: &str,
) -> LlmResult<LlmResponse> {
    let content = resp
        .pointer("/choices/0/message/content")
        .and_then(|v| v.as_str())
        .unwrap_or("")
        .to_string();

    let model = resp
        .get("model")
        .and_then(|v| v.as_str())
        .unwrap_or(fallback_model)
        .to_string();

    let mut usage = HashMap::new();
    if let Some(u) = resp.get("usage") {
        if let Some(pt) = u.get("prompt_tokens").and_then(|v| v.as_u64()) {
            usage.insert("input_tokens".to_string(), pt);
        }
        if let Some(ct) = u.get("completion_tokens").and_then(|v| v.as_u64()) {
            usage.insert("output_tokens".to_string(), ct);
        }
        let total = usage.get("input_tokens").unwrap_or(&0)
            + usage.get("output_tokens").unwrap_or(&0);
        usage.insert("total_tokens".to_string(), total);
    }

    Ok(LlmResponse {
        content,
        model,
        usage,
        metadata: HashMap::new(),
    })
}

/// Create a stream that extracts text deltas from an SSE byte stream.
///
/// Parses Server-Sent Events (SSE) formatted responses from OpenAI-compatible
/// streaming endpoints. Each `data:` line is parsed as JSON and the
/// `choices[0].delta.content` field is extracted.
pub(crate) fn sse_text_stream(
    byte_stream: impl futures::Stream<Item = Result<bytes::Bytes, reqwest::Error>> + Send + 'static,
) -> impl Stream<Item = LlmResult<String>> + Send {
    use futures::StreamExt;

    let buffer = String::new();

    futures::stream::unfold(
        (Box::pin(byte_stream), buffer),
        |(mut stream, mut buf)| async move {
            loop {
                // Try to extract a complete line from the buffer
                if let Some(newline_pos) = buf.find('\n') {
                    let line = buf[..newline_pos].trim().to_string();
                    buf = buf[newline_pos + 1..].to_string();

                    if line.starts_with("data: ") {
                        let data = &line[6..];
                        if data == "[DONE]" {
                            rate_limiter::record_success();
                            return None;
                        }
                        match serde_json::from_str::<serde_json::Value>(data) {
                            Ok(json) => {
                                if let Some(content) = json
                                    .pointer("/choices/0/delta/content")
                                    .and_then(|v| v.as_str())
                                {
                                    if !content.is_empty() {
                                        return Some((
                                            Ok(content.to_string()),
                                            (stream, buf),
                                        ));
                                    }
                                }
                                // No content in this chunk, continue
                                continue;
                            }
                            Err(e) => {
                                tracing::debug!(line = %data, error = %e, "SSE parse skip");
                                continue;
                            }
                        }
                    }
                    // Not a data line, skip
                    continue;
                }

                // Need more data from the byte stream
                match stream.next().await {
                    Some(Ok(bytes)) => {
                        buf.push_str(&String::from_utf8_lossy(&bytes));
                        continue;
                    }
                    Some(Err(e)) => {
                        return Some((
                            Err(LlmError::Http(format!("Stream error: {}", e))),
                            (stream, buf),
                        ));
                    }
                    None => {
                        // Stream ended. Process any remaining buffer content.
                        if !buf.trim().is_empty() {
                            let line = buf.trim().to_string();
                            buf.clear();
                            if line.starts_with("data: ") {
                                let data = &line[6..];
                                if data != "[DONE]" {
                                    if let Ok(json) =
                                        serde_json::from_str::<serde_json::Value>(data)
                                    {
                                        if let Some(content) = json
                                            .pointer("/choices/0/delta/content")
                                            .and_then(|v| v.as_str())
                                        {
                                            if !content.is_empty() {
                                                return Some((
                                                    Ok(content.to_string()),
                                                    (stream, buf),
                                                ));
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        rate_limiter::record_success();
                        return None;
                    }
                }
            }
        },
    )
}
