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

//! Abstract LLM client interface.
//!
//! This module provides the base trait and types for LLM clients used by SW4RM
//! agents. Implementations can use Groq, Anthropic, or mock clients for testing.

use std::collections::HashMap;
use std::pin::Pin;

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use tokio_stream::Stream;

/// Response from an LLM API call.
///
/// Contains the generated text, model identifier, token usage statistics,
/// and any additional provider-specific metadata.
///
/// # Examples
///
/// ```
/// use sw4rm_sdk::llm::LlmResponse;
/// use std::collections::HashMap;
///
/// let response = LlmResponse {
///     content: "Hello, world!".to_string(),
///     model: "llama-3.3-70b-versatile".to_string(),
///     usage: {
///         let mut m = HashMap::new();
///         m.insert("input_tokens".to_string(), 10);
///         m.insert("output_tokens".to_string(), 5);
///         m
///     },
///     metadata: HashMap::new(),
/// };
/// assert_eq!(response.content, "Hello, world!");
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LlmResponse {
    /// The generated text content.
    pub content: String,
    /// The model that generated the response.
    pub model: String,
    /// Token usage statistics (e.g., "input_tokens", "output_tokens").
    pub usage: HashMap<String, u64>,
    /// Additional provider-specific metadata.
    pub metadata: HashMap<String, serde_json::Value>,
}

/// Errors that can occur during LLM client operations.
///
/// Maps to the Python SDK's exception hierarchy:
/// - `LLMAuthenticationError` -> [`LlmError::Authentication`]
/// - `LLMRateLimitError` -> [`LlmError::RateLimit`]
/// - `LLMTimeoutError` -> [`LlmError::Timeout`]
/// - `LLMContextLengthError` -> [`LlmError::ContextLength`]
/// - `LLMError` -> [`LlmError::Api`]
#[derive(Error, Debug)]
pub enum LlmError {
    /// Authentication or authorization failure.
    ///
    /// Common causes: invalid API key, expired credentials, missing key file.
    #[error("Authentication error: {0}")]
    Authentication(String),

    /// API rate limit exceeded (HTTP 429).
    ///
    /// The caller should implement backoff or rely on the built-in rate limiter.
    #[error("Rate limit exceeded: {0}")]
    RateLimit(String),

    /// Request timed out before completion.
    ///
    /// Consider increasing the timeout or simplifying the prompt.
    #[error("Request timed out: {0}")]
    Timeout(String),

    /// Prompt exceeds the model's maximum context length.
    ///
    /// Consider truncating the input or using a model with larger context.
    #[error("Context length exceeded: {0}")]
    ContextLength(String),

    /// General API error not covered by other variants.
    #[error("API error: {0}")]
    Api(String),

    /// HTTP transport error from reqwest.
    #[error("HTTP error: {0}")]
    Http(String),

    /// JSON serialization/deserialization error.
    #[error("Serialization error: {0}")]
    Serialization(String),
}

/// Result type alias for LLM operations.
pub type LlmResult<T> = std::result::Result<T, LlmError>;

/// Abstract interface for LLM clients.
///
/// All LLM client implementations must implement this trait. This allows
/// SW4RM agents to be provider-agnostic, switching between Groq, Anthropic,
/// or mock backends without code changes.
///
/// # Implementations
///
/// - [`GroqClient`](super::GroqClient): Groq API (OpenAI-compatible)
/// - [`AnthropicClient`](super::AnthropicClient): Anthropic Messages API
/// - [`MockLlmClient`](super::MockLlmClient): Deterministic testing client
///
/// # Examples
///
/// ```rust,no_run
/// use sw4rm_sdk::llm::{create_llm_client, LlmClient};
///
/// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
/// let client = create_llm_client(Some("mock"), None)?;
/// let response = client.query(
///     "Analyze this data",
///     Some("You are a helpful analyst."),
///     4096,
///     1.0,
///     None,
/// ).await?;
/// println!("{}", response.content);
/// # Ok(())
/// # }
/// ```
#[async_trait]
pub trait LlmClient: Send + Sync {
    /// Send a query to the LLM and get a complete response.
    ///
    /// # Arguments
    ///
    /// * `prompt` - The user prompt/query to send.
    /// * `system_prompt` - Optional system prompt for context.
    /// * `max_tokens` - Maximum tokens to generate.
    /// * `temperature` - Sampling temperature (0.0-2.0).
    /// * `model_override` - Override the client's default model.
    ///
    /// # Returns
    ///
    /// An [`LlmResponse`] with the generated content and metadata.
    ///
    /// # Errors
    ///
    /// Returns [`LlmError`] on API errors, authentication failures,
    /// rate limit violations, or timeouts.
    async fn query(
        &self,
        prompt: &str,
        system_prompt: Option<&str>,
        max_tokens: u32,
        temperature: f64,
        model_override: Option<&str>,
    ) -> LlmResult<LlmResponse>;

    /// Stream a query response chunk by chunk.
    ///
    /// Returns a stream of text chunks as they arrive from the API.
    /// Not all providers support streaming; implementations that do not
    /// may return the full response as a single chunk.
    ///
    /// # Arguments
    ///
    /// * `prompt` - The user prompt/query to send.
    /// * `system_prompt` - Optional system prompt for context.
    /// * `max_tokens` - Maximum tokens to generate.
    /// * `temperature` - Sampling temperature (0.0-2.0).
    /// * `model_override` - Override the client's default model.
    ///
    /// # Returns
    ///
    /// A pinned stream yielding `Result<String>` chunks.
    ///
    /// # Errors
    ///
    /// Returns [`LlmError`] on API errors or connection failures.
    async fn stream_query(
        &self,
        prompt: &str,
        system_prompt: Option<&str>,
        max_tokens: u32,
        temperature: f64,
        model_override: Option<&str>,
    ) -> LlmResult<Pin<Box<dyn Stream<Item = LlmResult<String>> + Send>>>;
}
