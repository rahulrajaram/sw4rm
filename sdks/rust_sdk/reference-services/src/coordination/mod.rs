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

//! SW4RM Coordination Services.
//!
//! This module provides gRPC server implementations for the three in-memory
//! coordination services:
//!
//! - [`HandoffServiceImpl`]: Agent-to-agent task handoff coordination
//! - [`WorkflowServiceImpl`]: DAG-based workflow orchestration
//! - [`NegotiationRoomServiceImpl`]: Multi-agent artifact approval workflows
//!
//! These services maintain centralized state that can be shared across
//! distributed agent deployments. All three SDKs (Python, Rust, TypeScript)
//! can connect to these services as gRPC clients.
//!
//! # Example
//!
//! ```rust,no_run
//! use sw4rm_services::coordination::{
//!     HandoffServiceImpl,
//!     WorkflowServiceImpl,
//!     NegotiationRoomServiceImpl,
//! };
//! use tonic::transport::Server;
//!
//! #[tokio::main]
//! async fn main() -> Result<(), Box<dyn std::error::Error>> {
//!     let addr = "[::1]:50060".parse()?;
//!
//!     Server::builder()
//!         .add_service(HandoffServiceImpl::new().into_service())
//!         .add_service(WorkflowServiceImpl::new().into_service())
//!         .add_service(NegotiationRoomServiceImpl::new().into_service())
//!         .serve(addr)
//!         .await?;
//!
//!     Ok(())
//! }
//! ```

pub mod handoff;
pub mod workflow;
pub mod negotiation_room;

pub use handoff::HandoffServiceImpl;
pub use workflow::WorkflowServiceImpl;
pub use negotiation_room::NegotiationRoomServiceImpl;
