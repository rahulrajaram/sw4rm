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

//! SW4RM Agentic Protocol - Reference Rust SDK
//! 
//! This crate provides a Rust implementation of the SW4RM Agentic Protocol,
//! offering clients, runtime helpers, and utilities for building distributed
//! agents that communicate via gRPC.
//!
//! ## Features
//!
//! - **Type-safe gRPC clients** for all SW4RM protocol services
//! - **Async/await runtime** built on Tokio for high concurrency  
//! - **Cooperative preemption** support for graceful agent shutdown
//! - **Envelope helpers** for message construction and parsing
//! - **Built-in logging and tracing** via tracing crate
//! - **Configurable endpoints** with sensible defaults
//! - **Production-ready** error handling and resource management
//!
//! ## Quick Start
//!
//! ```rust,no_run
//! use sw4rm_sdk::*;
//! use async_trait::async_trait;
//!
//! struct MyAgent {
//!     config: AgentConfig,
//!     preemption: PreemptionManager,
//! }
//!
//! #[async_trait]
//! impl Agent for MyAgent {
//!     async fn on_message(&mut self, envelope: EnvelopeData) -> Result<()> {
//!         println!("Received: {}", envelope.message_id);
//!         Ok(())
//!     }
//!
//!     fn config(&self) -> &AgentConfig { &self.config }
//!     fn preemption_manager(&self) -> &PreemptionManager { &self.preemption }
//! }
//!
//! #[tokio::main]
//! async fn main() -> Result<()> {
//!     let config = AgentConfig::new("my-agent".into(), "My Agent".into());
//!     let agent = MyAgent { 
//!         config: config.clone(), 
//!         preemption: PreemptionManager::new() 
//!     };
//!     let mut runtime = AgentRuntime::new(config);
//!     runtime.run(agent).await
//! }
//! ```

pub mod clients;
pub mod envelope;
pub mod runtime;
pub mod types;
pub mod error;
pub mod config;
pub mod constants;
pub mod activity_buffer;
pub mod persistence;
pub mod acks;
pub mod ack_integration;
pub mod worktree_state;
pub mod interceptors;
pub mod secrets;
pub mod negotiation_events;

// Re-export commonly used types
pub use envelope::*;
pub use error::{Error, Result};
pub use config::*;
pub use types::*;
pub use runtime::*;
pub use clients::*;
pub use secrets::*;
pub use negotiation_events::*;

// Generated protobuf code
#[cfg(feature = "proto")]
pub mod proto {
    // Include generated protobuf files from OUT_DIR
    include!(concat!(env!("OUT_DIR"), "/mod.rs"));
}

// Fallback implementation when proto feature is not available
#[cfg(not(feature = "proto"))]
pub mod proto {
    // Include minimal stubs from OUT_DIR 
    include!(concat!(env!("OUT_DIR"), "/mod.rs"));
}

/// SDK version
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// SDK name  
pub const SDK_NAME: &str = "sw4rm-rust-sdk";

/// Prelude module for common imports
pub mod prelude {
    pub use crate::{
        Agent, AgentRuntime, BaseAgent,
        AgentConfig, Endpoints,
        EnvelopeBuilder, EnvelopeData,
        Error, Result,
        PreemptionManager,
        new_uuid, now_hlc_stub,
        constants,
    };
    pub use async_trait::async_trait;
}
