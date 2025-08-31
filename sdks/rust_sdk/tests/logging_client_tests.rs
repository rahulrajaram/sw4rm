use sw4rm_sdk::clients::LoggingClient;
use sw4rm_sdk::proto::sw4rm;
use tonic::{Request, Response, Status};

#[derive(Default)]
struct MockLoggingService {
    events: std::sync::Mutex<Vec<sw4rm::logging::LogEvent>>,
}

#[tonic::async_trait]
impl sw4rm::logging::logging_service_server::LoggingService for MockLoggingService {
    async fn ingest(
        &self,
        request: Request<sw4rm::logging::LogEvent>,
    ) -> Result<Response<sw4rm::logging::IngestResponse>, Status> {
        let ev = request.into_inner();
        self.events.lock().unwrap().push(ev);
        Ok(Response::new(sw4rm::logging::IngestResponse { ok: true }))
    }
}

#[tokio::test]
async fn test_logging_client_ingest() {
    // Start server
    let addr: std::net::SocketAddr = "127.0.0.1:0".parse().unwrap();
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        tonic::transport::Server::builder()
            .add_service(
                sw4rm::logging::logging_service_server::LoggingServiceServer::new(
                    MockLoggingService::default(),
                ),
            )
            .serve_with_incoming(tokio_stream::wrappers::TcpListenerStream::new(listener))
            .await
            .unwrap();
    });

    let endpoint = format!("http://{}", addr);
    let mut client = LoggingClient::new(&endpoint).await.unwrap();

    let resp = client
        .log(
            "agent-x",
            "test-event",
            "INFO",
            "{\"ok\":true}",
            Some("corr-1"),
        )
        .await
        .unwrap();
    assert!(resp.ok);
}
