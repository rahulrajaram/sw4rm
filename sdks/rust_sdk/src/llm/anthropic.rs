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

//! Anthropic LLM client for SW4RM agents.
//!
//! Thin wrapper around the Anthropic Messages API. Uses `reqwest` directly
//! instead of a vendor SDK crate. Handles the system-message normalization
//! (Anthropic uses a top-level `system` param, not an in-band system message).
//!
//! # Credential resolution (in order)
//!
//! 1. `api_key` constructor parameter
//! 2. `ANTHROPIC_API_KEY` environment variable
//! 3. `~/.anthropic` file (plain text, one line)
//!
//! # Environment variables
//!
//! | Variable | Default | Description |
//! |----------|---------|-------------|
//! | `ANTHROPIC_API_KEY` | - | API key |
//! | `ANTHROPIC_DEFAULT_MODEL` | `claude-sonnet-4-20250514` | Default model |

use std::collections::HashMap;
use std::pin::Pin;

use async_trait::async_trait;
use reqwest::Client;
use serde_json::json;
use tokio_stream::Stream;

use super::client::{LlmClient, LlmError, LlmResponse, LlmResult};
use super::groq::{estimate_tokens, map_http_status, map_reqwest_error, resolve_api_key};
use super::rate_limiter;

/// Base URL for the Anthropic Messages API.
const ANTHROPIC_API_URL: &str = "https://api.anthropic.com/v1/messages";

/// Required API version header value.
const ANTHROPIC_VERSION: &str = "2023-06-01";

/// Default model when no override is provided.
const DEFAULT_MODEL: &str = "claude-sonnet-4-20250514";

/// LLM client for the Anthropic Claude API.
///
/// Uses the Messages API directly via `reqwest`. Credentials are resolved
/// from the constructor parameter, the `ANTHROPIC_API_KEY` environment
/// variable, or the `~/.anthropic` file (in that order).
///
/// # Examples
///
/// ```rust,no_run
/// use sw4rm_sdk::llm::AnthropicClient;
/// use sw4rm_sdk::llm::LlmClient;
///
/// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
/// let client = AnthropicClient::new(None, None, None)?;
/// let response = client.query(
///     "What is the meaning of life?",
///     Some("You are a thoughtful philosopher."),
///     4096,
///     1.0,
///     None,
/// ).await?;
/// println!("{}", response.content);
/// # Ok(())
/// # }
/// ```
#[derive(Debug, Clone)]
pub struct AnthropicClient {
    api_key: String,
    default_model: String,
    http_client: Client,
    #[allow(dead_code)]
    timeout_secs: u64,
}

impl AnthropicClient {
    /// Create a new Anthropic client.
    ///
    /// # Arguments
    ///
    /// * `api_key` - Explicit API key. Falls back to `ANTHROPIC_API_KEY` env var,
    ///   then `~/.anthropic` file.
    /// * `default_model` - Default model name. Falls back to
    ///   `ANTHROPIC_DEFAULT_MODEL` env var, then `"claude-sonnet-4-20250514"`.
    /// * `timeout_secs` - HTTP request timeout in seconds. Defaults to 300.
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
            .or_else(|| std::env::var("ANTHROPIC_DEFAULT_MODEL").ok())
            .unwrap_or_else(|| DEFAULT_MODEL.to_string());

        let resolved_key = resolve_api_key(api_key, "ANTHROPIC_API_KEY", ".anthropic")?;

        let timeout = timeout_secs.unwrap_or(300);
        let http_client = Client::builder()
            .timeout(std::time::Duration::from_secs(timeout))
            .build()
            .map_err(|e| LlmError::Http(format!("Failed to create HTTP client: {}", e)))?;

        tracing::info!(model = %resolved_model, "Initialized Anthropic LLM client");

        Ok(Self {
            api_key: resolved_key,
            default_model: resolved_model,
            http_client,
            timeout_secs: timeout,
        })
    }

    /// Build the request body for the Anthropic Messages API.
    fn build_request_body(
        &self,
        prompt: &str,
        system_prompt: Option<&str>,
        max_tokens: u32,
        temperature: f64,
        model: &str,
        stream: bool,
    ) -> serde_json::Value {
        let mut body = json!({
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": temperature,
        });

        if let Some(sys) = system_prompt {
            body["system"] = json!(sys);
        }
        if stream {
            body["stream"] = json!(true);
        }

        body
    }

    /// Add Anthropic-specific headers to a request builder.
    fn add_headers(&self, builder: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        builder
            .header("x-api-key", &self.api_key)
            .header("anthropic-version", ANTHROPIC_VERSION)
            .header("content-type", "application/json")
    }
}

#[async_trait]
impl LlmClient for AnthropicClient {
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

        let body = self.build_request_body(
            prompt,
            system_prompt,
            max_tokens,
            temperature,
            use_model,
            false,
        );

        let request = self.add_headers(self.http_client.post(ANTHROPIC_API_URL));

        let response = request
            .json(&body)
            .send()
            .await
            .map_err(|e| map_reqwest_error(e, "Anthropic"))?;

        let status = response.status();

        if !status.is_success() {
            let body_text = response.text().await.unwrap_or_default();
            // Check for billing/credit errors in the body
            let lower = body_text.to_lowercase();
            if lower.contains("credit balance") || lower.contains("billing") {
                return Err(LlmError::Authentication(format!(
                    "Anthropic billing error: {}",
                    body_text
                )));
            }
            return Err(map_http_status(status.as_u16(), &body_text, "Anthropic"));
        }

        rate_limiter::record_success();

        let resp_json: serde_json::Value = response.json().await.map_err(|e| {
            LlmError::Serialization(format!("Failed to parse Anthropic response: {}", e))
        })?;

        parse_anthropic_response(&resp_json, use_model)
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

        let body = self.build_request_body(
            prompt,
            system_prompt,
            max_tokens,
            temperature,
            &use_model,
            true,
        );

        let request = self.add_headers(self.http_client.post(ANTHROPIC_API_URL));

        let response = request
            .json(&body)
            .send()
            .await
            .map_err(|e| map_reqwest_error(e, "Anthropic"))?;

        let status = response.status();
        if !status.is_success() {
            let body_text = response.text().await.unwrap_or_default();
            return Err(map_http_status(status.as_u16(), &body_text, "Anthropic"));
        }

        let byte_stream = response.bytes_stream();
        let stream = anthropic_sse_stream(byte_stream);

        Ok(Box::pin(stream))
    }
}

/// Parse an Anthropic Messages API response JSON.
///
/// Extracts text from content blocks and maps usage fields.
fn parse_anthropic_response(
    resp: &serde_json::Value,
    fallback_model: &str,
) -> LlmResult<LlmResponse> {
    // Extract text from content blocks
    let mut text_parts = Vec::new();
    if let Some(content) = resp.get("content").and_then(|v| v.as_array()) {
        for block in content {
            if let Some(text) = block.get("text").and_then(|v| v.as_str()) {
                text_parts.push(text.to_string());
            }
        }
    }
    let content = text_parts.join("").trim().to_string();

    let model = resp
        .get("model")
        .and_then(|v| v.as_str())
        .unwrap_or(fallback_model)
        .to_string();

    let mut usage = HashMap::new();
    if let Some(u) = resp.get("usage") {
        let input = u
            .get("input_tokens")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        let output = u
            .get("output_tokens")
            .and_then(|v| v.as_u64())
            .unwrap_or(0);
        usage.insert("input_tokens".to_string(), input);
        usage.insert("output_tokens".to_string(), output);
        usage.insert("total_tokens".to_string(), input + output);
    }

    Ok(LlmResponse {
        content,
        model,
        usage,
        metadata: HashMap::new(),
    })
}

/// Create a stream that extracts text deltas from an Anthropic SSE byte stream.
///
/// Anthropic streaming uses SSE with event types. Content text deltas arrive
/// as `event: content_block_delta` with `data: {"type": "content_block_delta",
/// "delta": {"type": "text_delta", "text": "..."}}`.
fn anthropic_sse_stream(
    byte_stream: impl futures::Stream<Item = Result<bytes::Bytes, reqwest::Error>> + Send + 'static,
) -> impl Stream<Item = LlmResult<String>> + Send {
    use futures::StreamExt;

    futures::stream::unfold(
        (Box::pin(byte_stream), String::new()),
        |(mut stream, mut buf)| async move {
            loop {
                // Try to extract a complete line from the buffer
                if let Some(newline_pos) = buf.find('\n') {
                    let line = buf[..newline_pos].trim().to_string();
                    buf = buf[newline_pos + 1..].to_string();

                    if line.starts_with("data: ") {
                        let data = &line[6..];

                        // Check for stream end
                        if data.contains("\"type\":\"message_stop\"")
                            || data.contains("\"type\": \"message_stop\"")
                        {
                            rate_limiter::record_success();
                            return None;
                        }

                        match serde_json::from_str::<serde_json::Value>(data) {
                            Ok(json) => {
                                // Extract text delta from content_block_delta events
                                if json.get("type").and_then(|v| v.as_str())
                                    == Some("content_block_delta")
                                {
                                    if let Some(text) = json
                                        .pointer("/delta/text")
                                        .and_then(|v| v.as_str())
                                    {
                                        if !text.is_empty() {
                                            return Some((
                                                Ok(text.to_string()),
                                                (stream, buf),
                                            ));
                                        }
                                    }
                                }
                                // Other event types (message_start, content_block_start, etc.)
                                continue;
                            }
                            Err(e) => {
                                tracing::debug!(line = %data, error = %e, "Anthropic SSE parse skip");
                                continue;
                            }
                        }
                    }
                    // Not a data line (could be event: line or empty), skip
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
                        rate_limiter::record_success();
                        return None;
                    }
                }
            }
        },
    )
}
