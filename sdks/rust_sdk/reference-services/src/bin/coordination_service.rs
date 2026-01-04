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

//! SW4RM Coordination Services Server Binary.
//!
//! This binary runs a unified gRPC server that hosts all three coordination
//! services:
//! - HandoffService
//! - WorkflowService
//! - NegotiationRoomService
//!
//! Usage:
//!   # Run with default port (50060)
//!   cargo run --bin coordination-service
//!
//!   # Run with custom port
//!   cargo run --bin coordination-service -- --port 50061

use clap::Parser;
use std::net::SocketAddr;
use tonic::transport::Server;
use tracing::{info, Level};
use tracing_subscriber::FmtSubscriber;

use sw4rm_services::coordination::{
    HandoffServiceImpl, NegotiationRoomServiceImpl, WorkflowServiceImpl,
};

/// SW4RM Coordination Services Server
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Port to listen on
    #[arg(short, long, default_value = "50060", env = "COORDINATION_PORT")]
    port: u16,

    /// Enable verbose logging
    #[arg(short, long)]
    verbose: bool,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args = Args::parse();

    // Set up logging
    let level = if args.verbose {
        Level::DEBUG
    } else {
        Level::INFO
    };
    let subscriber = FmtSubscriber::builder()
        .with_max_level(level)
        .with_target(true)
        .with_thread_ids(false)
        .with_file(false)
        .with_line_number(false)
        .finish();
    tracing::subscriber::set_global_default(subscriber)?;

    let addr: SocketAddr = format!("0.0.0.0:{}", args.port).parse()?;

    info!("Starting SW4RM Coordination Services on {}", addr);

    // Create services
    let handoff = HandoffServiceImpl::new();
    let workflow = WorkflowServiceImpl::new();
    let negotiation_room = NegotiationRoomServiceImpl::new();

    info!("Services registered:");
    info!("  - HandoffService");
    info!("  - WorkflowService");
    info!("  - NegotiationRoomService");

    // Build and run server
    Server::builder()
        .add_service(handoff.into_service())
        .add_service(workflow.into_service())
        .add_service(negotiation_room.into_service())
        .serve(addr)
        .await?;

    Ok(())
}
