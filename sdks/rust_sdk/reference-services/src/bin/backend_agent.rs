use sw4rm_services::agents::backend;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();
    if let Err(e) = backend::run().await {
        eprintln!("error: {:?}", e);
        std::process::exit(1);
    }
}
