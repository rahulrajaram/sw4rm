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

//! Factory for creating LLM clients.
//!
//! Provides a simple way to create the appropriate LLM client based on
//! environment configuration or explicit parameters.
//!
//! # Environment variables
//!
//! | Variable | Default | Description |
//! |----------|---------|-------------|
//! | `LLM_CLIENT_TYPE` | `"mock"` | Client type: `"groq"`, `"anthropic"`, or `"mock"` |
//! | `LLM_DEFAULT_MODEL` | (provider default) | Override the default model for any provider |

use super::client::{LlmClient, LlmError, LlmResult};

/// Create an LLM client based on explicit type or environment configuration.
///
/// Resolves the client type from:
/// 1. The `client_type` parameter (highest priority)
/// 2. The `LLM_CLIENT_TYPE` environment variable
/// 3. Default: `"mock"`
///
/// Resolves the model from:
/// 1. The `model` parameter (highest priority)
/// 2. The `LLM_DEFAULT_MODEL` environment variable
/// 3. The provider's built-in default
///
/// # Arguments
///
/// * `client_type` - Override client type. Supported: `"groq"`, `"anthropic"`, `"mock"`.
/// * `model` - Override the default model for the chosen provider.
///
/// # Returns
///
/// A boxed [`LlmClient`] trait object.
///
/// # Errors
///
/// Returns [`LlmError::Api`] if an unknown client type is specified.
/// Returns [`LlmError::Authentication`] if the chosen provider's credentials
/// cannot be resolved (does not apply to `"mock"`).
///
/// # Examples
///
/// ```
/// use sw4rm_sdk::llm::create_llm_client;
///
/// // Create a mock client (default)
/// let client = create_llm_client(None, None).unwrap();
///
/// // Explicitly create a mock client
/// let client = create_llm_client(Some("mock"), None).unwrap();
/// ```
///
/// ```rust,no_run
/// use sw4rm_sdk::llm::create_llm_client;
///
/// // Create a Groq client with default model
/// let client = create_llm_client(Some("groq"), None).unwrap();
///
/// // Create an Anthropic client with model override
/// let client = create_llm_client(Some("anthropic"), Some("claude-opus-4-20250514")).unwrap();
/// ```
pub fn create_llm_client(
    client_type: Option<&str>,
    model: Option<&str>,
) -> LlmResult<Box<dyn LlmClient>> {
    let resolved_type = client_type
        .map(String::from)
        .or_else(|| std::env::var("LLM_CLIENT_TYPE").ok())
        .unwrap_or_else(|| "mock".to_string());

    let resolved_model = model
        .map(String::from)
        .or_else(|| std::env::var("LLM_DEFAULT_MODEL").ok());

    let resolved_model_ref = resolved_model.as_deref();

    match resolved_type.to_lowercase().as_str() {
        "mock" => {
            tracing::info!("Creating Mock LLM client");
            let model_name = resolved_model_ref.unwrap_or("mock-model").to_string();
            Ok(Box::new(super::MockLlmClient::new(model_name, vec![])))
        }
        #[cfg(feature = "llm")]
        "groq" => {
            tracing::info!("Creating Groq LLM client");
            Ok(Box::new(super::GroqClient::new(
                None,
                resolved_model_ref,
                None,
            )?))
        }
        #[cfg(not(feature = "llm"))]
        "groq" => {
            Err(LlmError::Api(
                "Groq client requires the 'llm' feature. Enable it in Cargo.toml.".to_string(),
            ))
        }
        #[cfg(feature = "llm")]
        "anthropic" => {
            tracing::info!("Creating Anthropic LLM client");
            Ok(Box::new(super::AnthropicClient::new(
                None,
                resolved_model_ref,
                None,
            )?))
        }
        #[cfg(not(feature = "llm"))]
        "anthropic" => {
            Err(LlmError::Api(
                "Anthropic client requires the 'llm' feature. Enable it in Cargo.toml.".to_string(),
            ))
        }
        other => Err(LlmError::Api(format!(
            "Unknown LLM client type: '{}'. Valid types: 'groq', 'anthropic', 'mock'",
            other
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_mock_client() {
        let client = create_llm_client(Some("mock"), None);
        assert!(client.is_ok());
    }

    #[test]
    fn test_create_mock_with_model() {
        let client = create_llm_client(Some("mock"), Some("custom-model"));
        assert!(client.is_ok());
    }

    #[test]
    fn test_unknown_client_type_returns_error() {
        let result = create_llm_client(Some("nonexistent"), None);
        assert!(result.is_err());
        let err = result.err().unwrap();
        match err {
            LlmError::Api(msg) => assert!(msg.contains("nonexistent")),
            other => panic!("Expected Api error, got: {:?}", other),
        }
    }

    #[test]
    fn test_default_is_mock() {
        // When no env var is set and no explicit type, defaults to mock
        // Note: This test may fail if LLM_CLIENT_TYPE env var is set
        // in the test environment.
        let result = create_llm_client(None, None);
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn test_factory_mock_client_works() {
        let client = create_llm_client(Some("mock"), None).unwrap();
        let response = client.query("hello", None, 100, 1.0, None).await.unwrap();
        assert!(!response.content.is_empty());
    }
}
