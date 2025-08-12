use sw4rm_sdk::{prelude::*, proto::sw4rm};
use tokio::sync::mpsc;
use tokio_stream::wrappers::UnboundedReceiverStream;
use tonic::{Request, Response, Status};

#[derive(Debug, Default)]
struct MockRegistryService;

#[tonic::async_trait]
impl sw4rm::registry::registry_service_server::RegistryService for MockRegistryService {
    async fn register_agent(
        &self,
        _request: Request<sw4rm::registry::RegisterAgentRequest>,
    ) -> std::result::Result<Response<sw4rm::registry::RegisterAgentResponse>, Status> {
        Ok(Response::new(sw4rm::registry::RegisterAgentResponse { accepted: true, reason: String::new() }))
    }
    async fn heartbeat(
        &self,
        _request: Request<sw4rm::registry::HeartbeatRequest>,
    ) -> std::result::Result<Response<sw4rm::registry::HeartbeatResponse>, Status> {
        Ok(Response::new(sw4rm::registry::HeartbeatResponse { ok: true }))
    }
    async fn deregister_agent(
        &self,
        _request: Request<sw4rm::registry::DeregisterAgentRequest>,
    ) -> std::result::Result<Response<sw4rm::registry::DeregisterAgentResponse>, Status> {
        Ok(Response::new(sw4rm::registry::DeregisterAgentResponse { ok: true }))
    }
}

#[derive(Debug, Clone, Default)]
struct MockRouterService {
    streams: std::sync::Arc<std::sync::Mutex<std::collections::HashMap<String, mpsc::UnboundedSender<std::result::Result<sw4rm::router::StreamItem, Status>>>>>,
}

impl MockRouterService {
    fn send_to(&self, agent_id: &str, env: sw4rm::common::Envelope) {
        if let Some(tx) = self.streams.lock().unwrap().get(agent_id) {
            let _ = tx.send(Ok(sw4rm::router::StreamItem { msg: Some(env) }));
        }
    }
}

#[tonic::async_trait]
impl sw4rm::router::router_service_server::RouterService for MockRouterService {
    async fn send_message(
        &self,
        _request: Request<sw4rm::router::SendMessageRequest>,
    ) -> std::result::Result<Response<sw4rm::router::SendMessageResponse>, Status> {
        Ok(Response::new(sw4rm::router::SendMessageResponse { accepted: true, reason: String::new() }))
    }

    type StreamIncomingStream = UnboundedReceiverStream<std::result::Result<sw4rm::router::StreamItem, Status>>;

    async fn stream_incoming(
        &self,
        request: Request<sw4rm::router::StreamRequest>,
    ) -> std::result::Result<Response<Self::StreamIncomingStream>, Status> {
        let agent_id = request.into_inner().agent_id;
        let (tx, rx) = mpsc::unbounded_channel::<std::result::Result<sw4rm::router::StreamItem, Status>>();
        self.streams.lock().unwrap().insert(agent_id, tx);
        Ok(Response::new(UnboundedReceiverStream::new(rx)))
    }
}

struct MockServer {
    addr: std::net::SocketAddr,
    router: MockRouterService,
}

impl MockServer {
    async fn start() -> Self {
        let addr: std::net::SocketAddr = "127.0.0.1:0".parse().unwrap();
        let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
        let addr = listener.local_addr().unwrap();
        let router = MockRouterService::default();
        let router_clone = router.clone();
        tokio::spawn(async move {
            tonic::transport::Server::builder()
                .add_service(sw4rm::registry::registry_service_server::RegistryServiceServer::new(MockRegistryService))
                .add_service(sw4rm::router::router_service_server::RouterServiceServer::new(router_clone))
                .serve_with_incoming(tokio_stream::wrappers::TcpListenerStream::new(listener))
                .await
                .unwrap();
        });
        Self { addr, router }
    }
    fn endpoint(&self) -> String { format!("http://{}", self.addr) }
    fn send_to_agent(&self, agent_id: &str, env: sw4rm::common::Envelope) { self.router.send_to(agent_id, env); }
}

struct SmokeAgent {
    config: AgentConfig,
    preemption: PreemptionManager,
    msgs: std::sync::Arc<std::sync::atomic::AtomicUsize>,
}

#[async_trait::async_trait]
impl Agent for SmokeAgent {
    async fn on_message(&mut self, _envelope: EnvelopeData) -> Result<()> {
        self.msgs.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
        Ok(())
    }
    fn config(&self) -> &AgentConfig { &self.config }
    fn preemption_manager(&self) -> &PreemptionManager { &self.preemption }
}

#[tokio::test]
async fn test_runtime_stream_and_preemption() {
    // Start mock server (registry + router)
    let server = MockServer::start().await;
    let endpoints = Endpoints {
        registry: server.endpoint(),
        router: server.endpoint(),
        scheduler: server.endpoint(),
        hitl: server.endpoint(),
        worktree: server.endpoint(),
        tool: server.endpoint(),
        connector: server.endpoint(),
        negotiation: server.endpoint(),
        reasoning: server.endpoint(),
        logging: server.endpoint(),
    };

    let config = AgentConfig::new("smoke-agent".to_string(), "Smoke".to_string()).with_endpoints(endpoints);
    let msgs = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let agent = SmokeAgent { config: config.clone(), preemption: PreemptionManager::new(), msgs: msgs.clone() };

    let mut runtime = AgentRuntime::new(config);

    // Run runtime in background
    let rt_handle = tokio::spawn(async move {
        // Run until shutdown (we'll trigger later)
        let _ = runtime.run(agent).await;
    });

    // Give runtime time to init
    tokio::time::sleep(std::time::Duration::from_millis(100)).await;

    // Send a DATA message to agent stream
    let env = sw4rm::common::Envelope {
        message_id: "m1".to_string(),
        idempotency_token: String::new(),
        producer_id: "tester".to_string(),
        correlation_id: String::new(),
        sequence_number: 1,
        retry_count: 0,
        message_type: sw4rm::common::MessageType::Data as i32,
        content_type: "text/plain".to_string(),
        content_length: 4,
        repo_id: String::new(),
        worktree_id: String::new(),
        hlc_timestamp: String::new(),
        ttl_ms: 0,
        timestamp: None,
        payload: b"ping".to_vec(),
    };
    server.send_to_agent("smoke-agent", env);

    // Wait for processing
    tokio::time::sleep(std::time::Duration::from_millis(100)).await;
    assert_eq!(msgs.load(std::sync::atomic::Ordering::SeqCst), 1);

    // Trigger preemption by sending a CONTROL JSON message
    let control_payload = serde_json::to_vec(&serde_json::json!({"type": "PREEMPT_REQUEST", "reason": "test"})).unwrap();
    let ctrl = sw4rm::common::Envelope {
        message_id: "m2".to_string(),
        idempotency_token: String::new(),
        producer_id: "tester".to_string(),
        correlation_id: String::new(),
        sequence_number: 2,
        retry_count: 0,
        message_type: sw4rm::common::MessageType::Control as i32,
        content_type: "application/json".to_string(),
        content_length: control_payload.len() as u64,
        repo_id: String::new(),
        worktree_id: String::new(),
        hlc_timestamp: String::new(),
        ttl_ms: 0,
        timestamp: None,
        payload: control_payload,
    };
    server.send_to_agent("smoke-agent", ctrl);

    // Allow shutdown to propagate
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;
    // stop runtime
    rt_handle.abort();
}
