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

//! SW4RM LLM -- LLM client abstraction for SW4RM agents.
//!
//! This module provides a unified interface for LLM interactions, supporting:
//! - **Groq API** (API key from `~/.groq` or `GROQ_API_KEY`)
//! - **Anthropic API** (API key from `~/.anthropic` or `ANTHROPIC_API_KEY`)
//! - **Mock client** for testing
//!
//! # Usage
//!
//! ```rust,no_run
//! use sw4rm_sdk::llm::{create_llm_client, LlmClient};
//!
//! # async fn example() -> Result<(), Box<dyn std::error::Error>> {
//! // Create client via environment (LLM_CLIENT_TYPE=groq|anthropic|mock)
//! let client = create_llm_client(None, None)?;
//!
//! // Or explicitly
//! let client = create_llm_client(Some("groq"), None)?;
//!
//! // Query the LLM
//! let response = client.query(
//!     "Analyze this task and suggest next steps",
//!     Some("You are a helpful task analysis agent."),
//!     4096,
//!     1.0,
//!     None,
//! ).await?;
//! println!("{}", response.content);
//! # Ok(())
//! # }
//! ```
//!
//! # Testing
//!
//! ```
//! use sw4rm_sdk::llm::{MockLlmClient, LlmClient};
//!
//! # async fn example() -> Result<(), Box<dyn std::error::Error>> {
//! let client = MockLlmClient::new(
//!     "test-model".to_string(),
//!     vec!["Response 1".to_string(), "Response 2".to_string()],
//! );
//!
//! let r = client.query("hello", None, 4096, 1.0, None).await?;
//! assert_eq!(r.content, "Response 1");
//! # Ok(())
//! # }
//! ```

pub mod client;
pub mod rate_limiter;
pub mod mock;
pub mod factory;

#[cfg(feature = "llm")]
pub mod groq;
#[cfg(feature = "llm")]
pub mod anthropic;

// Re-export public API
pub use client::{LlmClient, LlmError, LlmResponse, LlmResult};
pub use factory::create_llm_client;
pub use mock::{MockCallRecord, MockLlmClient};
pub use rate_limiter::{RateLimiterConfig, TokenBucket};

#[cfg(feature = "llm")]
pub use groq::GroqClient;
#[cfg(feature = "llm")]
pub use anthropic::AnthropicClient;
