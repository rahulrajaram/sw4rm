use sw4rm_services::registry;
use tonic::transport::Server;
use tracing::{info};
use tracing_subscriber;
use std::env;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    let port: u16 = env::var("REGISTRY_PORT").ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(50052);
    let addr = format!("0.0.0.0:{}", port).parse()?;
    let registry_service = registry::create_service();

    info!("Registry service started on {}", addr);

    Server::builder()
        .add_service(registry_service)
        .serve(addr)
        .await?;

    Ok(())
}
