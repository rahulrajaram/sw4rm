use sw4rm_services::agents::frontend;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt::init();
    if let Err(e) = frontend::run().await {
        eprintln!("error: {:?}", e);
        std::process::exit(1);
    }
}
