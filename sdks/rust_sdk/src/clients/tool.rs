use crate::proto::sw4rm::tool::tool_service_client::ToolServiceClient;
use crate::proto::sw4rm::tool::{ToolCall, ToolFrame, ToolError, ExecutionPolicy};
use crate::{Error, Result};
use tonic::transport::{Channel, Endpoint};
use tokio_stream::Stream;
use std::pin::Pin;
use prost_types;
use std::time::Duration;
use tracing::{debug, error, info};

/// Client for interacting with the SW4RM Tool service
#[derive(Debug, Clone)]
pub struct ToolClient {
    client: ToolServiceClient<Channel>,
    endpoint: String,
}

impl ToolClient {
    /// Create a new tool client
    pub async fn new(endpoint: &str) -> Result<Self> {
        debug!("Creating tool client for endpoint: {}", endpoint);
        
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid tool endpoint: {}", e)))?
            .connect()
            .await
            .map_err(|e| {
                error!("Failed to connect to tool service at {}: {}", endpoint, e);
                Error::Connection(format!("Tool service connection failed: {}", e))
            })?;

        info!("Successfully connected to tool service at {}", endpoint);

        Ok(Self {
            client: ToolServiceClient::new(channel),
            endpoint: endpoint.to_string(),
        })
    }


    /// Execute a tool call
    pub async fn call_tool(
        &mut self,
        call_id: &str,
        tool_name: &str,
        provider_id: &str,
        content_type: &str,
        args: Vec<u8>,
        policy: Option<ExecutionPolicyConfig>,
        stream: bool,
    ) -> Result<ToolFrame> {
        let execution_policy = policy.map(|p| ExecutionPolicy {
            timeout: p.timeout.map(|t| prost_types::Duration {
                seconds: t.as_secs() as i64,
                nanos: t.subsec_nanos() as i32,
            }),
            max_retries: p.max_retries,
            backoff: p.backoff,
            worktree_required: p.worktree_required,
            network_policy: p.network_policy,
            privilege_level: p.privilege_level,
            budget_cpu_ms: p.budget_cpu_ms,
            budget_wall_ms: p.budget_wall_ms,
        });

        let tool_call = ToolCall {
            call_id: call_id.to_string(),
            tool_name: tool_name.to_string(),
            provider_id: provider_id.to_string(),
            content_type: content_type.to_string(),
            args,
            policy: execution_policy,
            stream,
        };

        let request = tonic::Request::new(tool_call);
        let response = self.client.call(request).await?;
        Ok(response.into_inner())
    }

    /// Stream tool call responses (for long-running tools)
    pub async fn call_tool_stream(
        &mut self,
        call_id: &str,
        tool_name: &str,
        provider_id: &str,
        content_type: &str,
        args: Vec<u8>,
        policy: Option<ExecutionPolicyConfig>,
    ) -> Result<Pin<Box<dyn Stream<Item = Result<ToolFrame>> + Send>>> {
        debug!("Starting streaming tool call: {} ({})", call_id, tool_name);

        let execution_policy = policy.map(|p| ExecutionPolicy {
            timeout: p.timeout.map(|t| prost_types::Duration {
                seconds: t.as_secs() as i64,
                nanos: t.subsec_nanos() as i32,
            }),
            max_retries: p.max_retries,
            backoff: p.backoff,
            worktree_required: p.worktree_required,
            network_policy: p.network_policy,
            privilege_level: p.privilege_level,
            budget_cpu_ms: p.budget_cpu_ms,
            budget_wall_ms: p.budget_wall_ms,
        });

        let tool_call = ToolCall {
            call_id: call_id.to_string(),
            tool_name: tool_name.to_string(),
            provider_id: provider_id.to_string(),
            content_type: content_type.to_string(),
            args,
            policy: execution_policy,
            stream: true, // Enable streaming
        };

        let request = tonic::Request::new(tool_call);
        let response = self.client.call_stream(request).await
            .map_err(|e| {
                error!("Failed to start streaming tool call {}: {}", call_id, e);
                Error::Status(e)
            })?;

        let stream = response.into_inner();
        info!("Streaming tool call started: {} ({})", call_id, tool_name);

        let call_id_owned = call_id.to_string();
        let mapped_stream = tokio_stream::StreamExt::map(stream, move |result| {
            match result {
                Ok(frame) => {
                    debug!("Received tool frame for call {}", call_id_owned);
                    Ok(frame)
                }
                Err(status) => {
                    error!("Stream error for tool call {}: {}", call_id_owned, status);
                    Err(Error::Status(status))
                }
            }
        });

        Ok(Box::pin(mapped_stream))
    }

    /// Cancel a tool call
    pub async fn cancel_tool(&mut self, call_id: &str) -> Result<ToolError> {
        debug!("Canceling tool call: {}", call_id);
        
        // For cancellation, we send a minimal ToolCall to identify what to cancel
        let cancel_tool_call = ToolCall {
            call_id: call_id.to_string(),
            tool_name: "".to_string(),  // Empty for cancel requests
            provider_id: "".to_string(),
            content_type: "application/json".to_string(),
            args: b"{}".to_vec(),  // Empty JSON
            policy: None,
            stream: false,
        };

        let request = tonic::Request::new(cancel_tool_call);
        let response = self.client.cancel(request).await
            .map_err(|e| {
                error!("Failed to cancel tool call {}: {}", call_id, e);
                Error::Status(e)
            })?;
        
        info!("Tool call {} canceled successfully", call_id);
        Ok(response.into_inner())
    }

    /// Get the endpoint this client is connected to
    pub fn endpoint(&self) -> &str {
        &self.endpoint
    }
}

/// Configuration for tool execution policy
#[derive(Debug, Clone)]
pub struct ExecutionPolicyConfig {
    pub timeout: Option<Duration>,
    pub max_retries: u32,
    pub backoff: String,
    pub worktree_required: bool,
    pub network_policy: String,
    pub privilege_level: String,
    pub budget_cpu_ms: u64,
    pub budget_wall_ms: u64,
}

impl Default for ExecutionPolicyConfig {
    fn default() -> Self {
        Self {
            timeout: Some(Duration::from_secs(30)),
            max_retries: 3,
            backoff: "exponential".to_string(),
            worktree_required: false,
            network_policy: "restricted".to_string(),
            privilege_level: "default".to_string(),
            budget_cpu_ms: 30000,
            budget_wall_ms: 30000,
        }
    }
}

