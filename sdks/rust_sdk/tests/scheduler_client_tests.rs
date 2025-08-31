use sw4rm_sdk::clients::SchedulerClient;
use sw4rm_sdk::proto::sw4rm;
use tonic::{Request, Response, Status};

#[derive(Default)]
struct MockSchedulerService {
    entries:
        std::sync::Mutex<std::collections::HashMap<String, Vec<sw4rm::scheduler::ActivityEntry>>>,
}

#[tonic::async_trait]
impl sw4rm::scheduler::scheduler_service_server::SchedulerService for MockSchedulerService {
    async fn submit_task(
        &self,
        request: Request<sw4rm::scheduler::SubmitTaskRequest>,
    ) -> Result<Response<sw4rm::scheduler::SubmitTaskResponse>, Status> {
        let req = request.into_inner();
        let mut map = self.entries.lock().unwrap();
        map.entry(req.agent_id.clone())
            .or_default()
            .push(sw4rm::scheduler::ActivityEntry {
                task_id: req.task_id,
                repo_id: "repo".to_string(),
                worktree_id: "tree".to_string(),
                branch: "main".to_string(),
                description: "scheduled".to_string(),
                timestamp: "t".to_string(),
            });
        Ok(Response::new(sw4rm::scheduler::SubmitTaskResponse {
            accepted: true,
            reason: String::new(),
        }))
    }

    async fn request_preemption(
        &self,
        _request: Request<sw4rm::scheduler::PreemptRequest>,
    ) -> Result<Response<sw4rm::scheduler::PreemptResponse>, Status> {
        Ok(Response::new(sw4rm::scheduler::PreemptResponse {
            enqueued: true,
        }))
    }

    async fn shutdown_agent(
        &self,
        _request: Request<sw4rm::scheduler::ShutdownAgentRequest>,
    ) -> Result<Response<sw4rm::scheduler::ShutdownAgentResponse>, Status> {
        Ok(Response::new(sw4rm::scheduler::ShutdownAgentResponse {
            ok: true,
        }))
    }

    async fn poll_activity_buffer(
        &self,
        request: Request<sw4rm::scheduler::PollActivityBufferRequest>,
    ) -> Result<Response<sw4rm::scheduler::PollActivityBufferResponse>, Status> {
        let agent = request.into_inner().agent_id;
        let entries = self
            .entries
            .lock()
            .unwrap()
            .get(&agent)
            .cloned()
            .unwrap_or_default();
        Ok(Response::new(
            sw4rm::scheduler::PollActivityBufferResponse { entries },
        ))
    }

    async fn purge_activity(
        &self,
        request: Request<sw4rm::scheduler::PurgeActivityRequest>,
    ) -> Result<Response<sw4rm::scheduler::PurgeActivityResponse>, Status> {
        let req = request.into_inner();
        let mut map = self.entries.lock().unwrap();
        let v = map.entry(req.agent_id).or_default();
        let before = v.len();
        v.retain(|e| !req.task_ids.contains(&e.task_id));
        let purged = (before - v.len()) as u32;
        Ok(Response::new(sw4rm::scheduler::PurgeActivityResponse {
            purged,
        }))
    }
}

#[tokio::test]
async fn test_scheduler_client_basic_flows() {
    // Start server
    let addr: std::net::SocketAddr = "127.0.0.1:0".parse().unwrap();
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        tonic::transport::Server::builder()
            .add_service(
                sw4rm::scheduler::scheduler_service_server::SchedulerServiceServer::new(
                    MockSchedulerService::default(),
                ),
            )
            .serve_with_incoming(tokio_stream::wrappers::TcpListenerStream::new(listener))
            .await
            .unwrap();
    });

    let endpoint = format!("http://{}", addr);
    let mut client = SchedulerClient::new(&endpoint).await.unwrap();
    let agent = "agent-1";

    client
        .submit_task(
            "task-1",
            agent,
            0,
            b"{}".to_vec(),
            "application/json",
            "scope",
        )
        .await
        .unwrap();

    client
        .request_preemption(agent, "task-1", "test")
        .await
        .unwrap();

    let entries = client.get_activity_buffer(agent).await.unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0].task_id, "task-1");

    let purged = client
        .purge_activities(agent, vec!["task-1".to_string()])
        .await
        .unwrap();
    assert_eq!(purged, 1);

    client
        .shutdown_agent(agent, Some(std::time::Duration::from_millis(10)))
        .await
        .unwrap();
}
