use clap::Parser;
use std::process::{Command, Stdio};
use tokio::signal;
use tracing::{info, error};
use tracing_subscriber;

#[derive(Parser)]
#[command(name = "start-services")]
#[command(about = "Start SW4RM Registry and Router services")]
struct Args {
    #[arg(long, default_value = "127.0.0.1:50052")]
    registry_addr: String,
    
    #[arg(long, default_value = "127.0.0.1:50051")]
    router_addr: String,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt::init();
    
    let args = Args::parse();
    
    info!("🚀 Starting SW4RM Services (Rust)");
    info!("=================================");
    
    // Start registry service
    info!("📋 Starting Registry service on {}", args.registry_addr);
    let mut registry_child = Command::new("cargo")
        .args(&["run", "--bin", "registry-service"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    
    // Wait a moment
    tokio::time::sleep(tokio::time::Duration::from_secs(2)).await;
    
    // Start router service
    info!("🔀 Starting Router service on {}", args.router_addr);
    let mut router_child = Command::new("cargo")
        .args(&["run", "--bin", "router-service"])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;
    
    // Wait for services to start
    tokio::time::sleep(tokio::time::Duration::from_secs(3)).await;
    
    info!("");
    info!("🎉 SW4RM Services Started!");
    info!("");
    info!("Services running:");
    info!("  📋 Registry: {} (PID: {})", args.registry_addr, registry_child.id());
    info!("  🔀 Router:   {} (PID: {})", args.router_addr, router_child.id());
    info!("");
    info!("Now you can run your SW4RM agents! Try:");
    info!("  cargo run --example echo_agent");
    info!("");
    info!("Press Ctrl+C to stop all services...");
    
    // Wait for shutdown signal
    signal::ctrl_c().await?;
    
    info!("");
    info!("🛑 Stopping services...");
    
    // Kill child processes
    registry_child.kill()?;
    router_child.kill()?;
    
    info!("✅ Services stopped!");
    
    Ok(())
}