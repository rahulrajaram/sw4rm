use sw4rm_services::router;
use tonic::transport::Server;
use tracing::{info, error};
use tracing_subscriber;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    let addr = "127.0.0.1:50051".parse()?;
    let router_service = router::create_service();

    info!("Router service starting on {}", addr);

    Server::builder()
        .add_service(router_service)
        .serve(addr)
        .await?;

    Ok(())
}