use sw4rm_services::router;
use tonic::transport::Server;
use tracing::{info};
use tracing_subscriber;
use std::env;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    let port: u16 = env::var("ROUTER_PORT").ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(50051);
    let addr = format!("0.0.0.0:{}", port).parse()?;
    let router_service = router::create_service();

    info!("Router service started on {}", addr);

    Server::builder()
        .add_service(router_service)
        .serve(addr)
        .await?;

    Ok(())
}
