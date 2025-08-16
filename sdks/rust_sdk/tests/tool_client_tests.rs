use sw4rm_sdk::clients::ToolClient;
use sw4rm_sdk::proto::sw4rm;
use sw4rm_sdk::clients::tool::{ExecutionPolicyConfig, ToolCallParams};
use tokio::sync::mpsc;
use tokio_stream::{wrappers::UnboundedReceiverStream, StreamExt};
use tonic::{Request, Response, Status};

struct MockToolService;

#[tonic::async_trait]
impl sw4rm::tool::tool_service_server::ToolService for MockToolService {
    async fn call(
        &self,
        request: Request<sw4rm::tool::ToolCall>,
    ) -> Result<Response<sw4rm::tool::ToolFrame>, Status> {
        let call = request.into_inner();
        Ok(Response::new(sw4rm::tool::ToolFrame {
            call_id: call.call_id,
            frame_no: 1,
            r#final: true,
            content_type: call.content_type,
            data: call.args,
            summary: b"done".to_vec(),
        }))
    }

    type CallStreamStream = UnboundedReceiverStream<Result<sw4rm::tool::ToolFrame, Status>>;

    async fn call_stream(
        &self,
        request: Request<sw4rm::tool::ToolCall>,
    ) -> Result<Response<Self::CallStreamStream>, Status> {
        let call = request.into_inner();
        let (tx, rx) = mpsc::unbounded_channel();
        let call_id = call.call_id.clone();
        // send two frames
        let _ = tx.send(Ok(sw4rm::tool::ToolFrame {
            call_id: call_id.clone(),
            frame_no: 1,
            r#final: false,
            content_type: call.content_type.clone(),
            data: call.args.clone(),
            summary: Vec::new(),
        }));
        let _ = tx.send(Ok(sw4rm::tool::ToolFrame {
            call_id,
            frame_no: 2,
            r#final: true,
            content_type: call.content_type,
            data: b"final".to_vec(),
            summary: b"ok".to_vec(),
        }));
        Ok(Response::new(UnboundedReceiverStream::new(rx)))
    }

    async fn cancel(
        &self,
        request: Request<sw4rm::tool::ToolCall>,
    ) -> Result<Response<sw4rm::tool::ToolError>, Status> {
        let call = request.into_inner();
        Ok(Response::new(sw4rm::tool::ToolError {
            call_id: call.call_id,
            error_code: "CANCELED".to_string(),
            message: "canceled".to_string(),
        }))
    }
}

#[tokio::test]
async fn test_tool_client_unary_and_streaming() {
    // Start server
    let addr: std::net::SocketAddr = "127.0.0.1:0".parse().unwrap();
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    let addr = listener.local_addr().unwrap();

    tokio::spawn(async move {
        tonic::transport::Server::builder()
            .add_service(sw4rm::tool::tool_service_server::ToolServiceServer::new(MockToolService))
            .serve_with_incoming(tokio_stream::wrappers::TcpListenerStream::new(listener))
            .await
            .unwrap();
    });

    let endpoint = format!("http://{}", addr);
    let mut client = ToolClient::new(&endpoint).await.unwrap();

    // Unary call
    let frame = client
        .call_tool(ToolCallParams {
            call_id: "call-1",
            tool_name: "echo",
            provider_id: "provider",
            content_type: "application/octet-stream",
            args: b"data".to_vec(),
            policy: Some(ExecutionPolicyConfig::default()),
            stream: false,
        })
        .await
        .unwrap();

    assert_eq!(frame.frame_no, 1);
    assert!(frame.r#final);
    assert_eq!(frame.data, b"data");

    // Streaming call
    let mut stream = client
        .call_tool_stream(
            "call-2",
            "echo",
            "provider",
            "application/octet-stream",
            b"x".to_vec(),
            None,
        )
        .await
        .unwrap();

    let mut frames = Vec::new();
    while let Some(item) = stream.next().await {
        frames.push(item.unwrap());
    }
    assert_eq!(frames.len(), 2);
    assert!(!frames[0].r#final);
    assert!(frames[1].r#final);

    // Cancel
    let err = client.cancel_tool("call-3").await.unwrap();
    assert_eq!(err.error_code, "CANCELED");
}
