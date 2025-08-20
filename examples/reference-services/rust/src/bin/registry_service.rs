use sw4rm_services::registry;
use tonic::transport::Server;
use tracing::{info, error};
use tracing_subscriber;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    let addr = "127.0.0.1:50052".parse()?;
    let registry_service = registry::create_service();

    info!("Registry service starting on {}", addr);

    Server::builder()
        .add_service(registry_service)
        .serve(addr)
        .await?;

    Ok(())
}