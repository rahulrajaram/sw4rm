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

//! Mock LLM client for testing.
//!
//! Provides deterministic responses without making actual API calls.
//! Takes a `Vec<String>` of canned responses and cycles through them.
//! Records call history for assertions.

use std::collections::HashMap;
use std::pin::Pin;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use tokio_stream::Stream;

use super::client::{LlmClient, LlmResponse, LlmResult};

/// A recorded call to the mock client.
///
/// Captures all parameters passed to [`MockLlmClient::query`] or
/// [`MockLlmClient::stream_query`] for later inspection in tests.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MockCallRecord {
    /// The user prompt.
    pub prompt: String,
    /// The system prompt, if provided.
    pub system_prompt: Option<String>,
    /// The max_tokens parameter.
    pub max_tokens: u32,
    /// The temperature parameter.
    pub temperature: f64,
    /// The model used (override or default).
    pub model: String,
}

/// Internal mutable state for the mock client, behind `Arc<Mutex<_>>`.
#[derive(Debug)]
struct MockState {
    responses: Vec<String>,
    response_index: usize,
    call_count: usize,
    call_history: Vec<MockCallRecord>,
}

/// Mock LLM client for testing without API calls.
///
/// Returns configurable canned responses and records all calls for assertions.
/// The client is `Clone`-able; all clones share the same internal state.
///
/// # Examples
///
/// ```
/// use sw4rm_sdk::llm::{MockLlmClient, LlmClient};
///
/// # async fn example() -> Result<(), Box<dyn std::error::Error>> {
/// // Simple usage - returns echo of prompt
/// let client = MockLlmClient::new("mock-model".to_string(), vec![]);
/// let response = client.query("Hello", None, 4096, 1.0, None).await?;
/// assert!(response.content.contains("Hello"));
///
/// // Custom canned responses (cycles)
/// let client = MockLlmClient::new(
///     "test-model".to_string(),
///     vec!["First".to_string(), "Second".to_string()],
/// );
/// let r1 = client.query("a", None, 100, 1.0, None).await?;
/// let r2 = client.query("b", None, 100, 1.0, None).await?;
/// let r3 = client.query("c", None, 100, 1.0, None).await?;
/// assert_eq!(r1.content, "First");
/// assert_eq!(r2.content, "Second");
/// assert_eq!(r3.content, "First"); // cycles back
/// assert_eq!(client.call_count(), 3);
/// # Ok(())
/// # }
/// ```
#[derive(Debug, Clone)]
pub struct MockLlmClient {
    default_model: String,
    state: Arc<Mutex<MockState>>,
}

impl MockLlmClient {
    /// Create a new mock client.
    ///
    /// # Arguments
    ///
    /// * `default_model` - Model name to include in responses.
    /// * `responses` - Canned responses to cycle through. If empty, the client
    ///   generates `"Mock response to: <prompt>"`.
    pub fn new(default_model: String, responses: Vec<String>) -> Self {
        tracing::info!("Initialized Mock LLM client");
        Self {
            default_model,
            state: Arc::new(Mutex::new(MockState {
                responses,
                response_index: 0,
                call_count: 0,
                call_history: Vec::new(),
            })),
        }
    }

    /// Number of queries made to this client.
    pub fn call_count(&self) -> usize {
        self.state.lock().unwrap().call_count
    }

    /// History of all calls made to this client.
    pub fn call_history(&self) -> Vec<MockCallRecord> {
        self.state.lock().unwrap().call_history.clone()
    }

    /// Reset call count, history, and response index.
    pub fn reset(&self) {
        let mut state = self.state.lock().unwrap();
        state.call_count = 0;
        state.call_history.clear();
        state.response_index = 0;
    }

    /// Generate or retrieve the next response.
    fn next_response(state: &mut MockState, prompt: &str) -> String {
        if state.responses.is_empty() {
            let truncated: String = prompt.chars().take(100).collect();
            format!("Mock response to: {}", truncated)
        } else {
            let idx = state.response_index % state.responses.len();
            state.response_index += 1;
            state.responses[idx].clone()
        }
    }
}

#[async_trait]
impl LlmClient for MockLlmClient {
    async fn query(
        &self,
        prompt: &str,
        system_prompt: Option<&str>,
        max_tokens: u32,
        temperature: f64,
        model_override: Option<&str>,
    ) -> LlmResult<LlmResponse> {
        let model = model_override.unwrap_or(&self.default_model).to_string();

        let content = {
            let mut state = self.state.lock().unwrap();
            state.call_count += 1;
            state.call_history.push(MockCallRecord {
                prompt: prompt.to_string(),
                system_prompt: system_prompt.map(String::from),
                max_tokens,
                temperature,
                model: model.clone(),
            });
            Self::next_response(&mut state, prompt)
        };

        let input_tokens = (prompt.len() as u64) / 4;
        let output_tokens = (content.len() as u64) / 4;

        let mut usage = HashMap::new();
        usage.insert("input_tokens".to_string(), input_tokens);
        usage.insert("output_tokens".to_string(), output_tokens);

        let mut metadata = HashMap::new();
        metadata.insert(
            "mock".to_string(),
            serde_json::Value::Bool(true),
        );
        metadata.insert(
            "call_count".to_string(),
            serde_json::Value::Number(serde_json::Number::from(
                self.state.lock().unwrap().call_count,
            )),
        );

        Ok(LlmResponse {
            content,
            model,
            usage,
            metadata,
        })
    }

    async fn stream_query(
        &self,
        prompt: &str,
        system_prompt: Option<&str>,
        max_tokens: u32,
        temperature: f64,
        model_override: Option<&str>,
    ) -> LlmResult<Pin<Box<dyn Stream<Item = LlmResult<String>> + Send>>> {
        // Get the full response, then stream it word-by-word
        let response = self
            .query(prompt, system_prompt, max_tokens, temperature, model_override)
            .await?;

        let words: Vec<String> = response
            .content
            .split_whitespace()
            .enumerate()
            .map(|(i, word)| {
                let total = response.content.split_whitespace().count();
                if i < total - 1 {
                    format!("{} ", word)
                } else {
                    word.to_string()
                }
            })
            .collect();

        let stream = tokio_stream::iter(words.into_iter().map(Ok));
        Ok(Box::pin(stream))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_mock_default_response() {
        let client = MockLlmClient::new("test-model".to_string(), vec![]);
        let resp = client.query("Hello world", None, 4096, 1.0, None).await.unwrap();
        assert!(resp.content.contains("Hello world"));
        assert_eq!(resp.model, "test-model");
        assert_eq!(client.call_count(), 1);
    }

    #[tokio::test]
    async fn test_mock_canned_responses_cycle() {
        let client = MockLlmClient::new(
            "test".to_string(),
            vec!["Alpha".to_string(), "Beta".to_string()],
        );

        let r1 = client.query("a", None, 100, 1.0, None).await.unwrap();
        let r2 = client.query("b", None, 100, 1.0, None).await.unwrap();
        let r3 = client.query("c", None, 100, 1.0, None).await.unwrap();

        assert_eq!(r1.content, "Alpha");
        assert_eq!(r2.content, "Beta");
        assert_eq!(r3.content, "Alpha"); // cycles
        assert_eq!(client.call_count(), 3);
    }

    #[tokio::test]
    async fn test_mock_call_history() {
        let client = MockLlmClient::new("m".to_string(), vec![]);
        client
            .query("test prompt", Some("system"), 256, 0.5, Some("custom-model"))
            .await
            .unwrap();

        let history = client.call_history();
        assert_eq!(history.len(), 1);
        assert_eq!(history[0].prompt, "test prompt");
        assert_eq!(history[0].system_prompt.as_deref(), Some("system"));
        assert_eq!(history[0].max_tokens, 256);
        assert!((history[0].temperature - 0.5).abs() < f64::EPSILON);
        assert_eq!(history[0].model, "custom-model");
    }

    #[tokio::test]
    async fn test_mock_reset() {
        let client = MockLlmClient::new(
            "m".to_string(),
            vec!["A".to_string(), "B".to_string()],
        );
        client.query("x", None, 100, 1.0, None).await.unwrap();
        assert_eq!(client.call_count(), 1);

        client.reset();
        assert_eq!(client.call_count(), 0);
        assert!(client.call_history().is_empty());

        // After reset, should start from first response again
        let r = client.query("y", None, 100, 1.0, None).await.unwrap();
        assert_eq!(r.content, "A");
    }

    #[tokio::test]
    async fn test_mock_usage_tokens() {
        let client = MockLlmClient::new("m".to_string(), vec![]);
        let resp = client.query("hello", None, 100, 1.0, None).await.unwrap();
        assert!(resp.usage.contains_key("input_tokens"));
        assert!(resp.usage.contains_key("output_tokens"));
    }

    #[tokio::test]
    async fn test_mock_model_override() {
        let client = MockLlmClient::new("default".to_string(), vec![]);
        let resp = client
            .query("test", None, 100, 1.0, Some("override-model"))
            .await
            .unwrap();
        assert_eq!(resp.model, "override-model");
    }

    #[tokio::test]
    async fn test_mock_stream_query() {
        use tokio_stream::StreamExt;

        let client = MockLlmClient::new(
            "m".to_string(),
            vec!["Hello beautiful world".to_string()],
        );
        let mut stream = client
            .stream_query("test", None, 100, 1.0, None)
            .await
            .unwrap();

        let mut collected = String::new();
        while let Some(chunk) = stream.next().await {
            collected.push_str(&chunk.unwrap());
        }
        assert_eq!(collected, "Hello beautiful world");
    }

    #[tokio::test]
    async fn test_mock_clone_shares_state() {
        let client1 = MockLlmClient::new("m".to_string(), vec!["X".to_string()]);
        let client2 = client1.clone();

        client1.query("a", None, 100, 1.0, None).await.unwrap();
        assert_eq!(client2.call_count(), 1); // shared state
    }

    #[tokio::test]
    async fn test_mock_metadata() {
        let client = MockLlmClient::new("m".to_string(), vec![]);
        let resp = client.query("test", None, 100, 1.0, None).await.unwrap();
        assert_eq!(resp.metadata.get("mock"), Some(&serde_json::Value::Bool(true)));
    }
}
