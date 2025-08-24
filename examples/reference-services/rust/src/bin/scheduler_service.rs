use sw4rm_services::scheduler;
use sw4rm_services::agents::scheduler as control;
use tonic::transport::Server;
use tracing::info;
use tracing_subscriber;
use std::env;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    let port: u16 = env::var("SCHEDULER_PORT").ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(50053);
    let addr = format!("0.0.0.0:{}", port).parse()?;
    let scheduler_service = scheduler::create_service();

    info!("Scheduler service started on {}", addr);

    let grpc = Server::builder()
        .add_service(scheduler_service)
        .serve(addr);

    // Run gRPC server and CONTROL loop concurrently
    tokio::select! {
        res = grpc => { res?; },
        res = control::run_control() => { res?; },
    }

    Ok(())
}
