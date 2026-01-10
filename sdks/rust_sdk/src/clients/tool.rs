use crate::proto::sw4rm::tool::tool_service_client::ToolServiceClient;
use crate::proto::sw4rm::tool::{ExecutionPolicy, ToolCall, ToolError, ToolFrame};
use crate::{Error, Result};
use prost_types;
use std::pin::Pin;
use std::time::Duration;
use tokio_stream::Stream;
use tonic::transport::{Channel, Endpoint};
use tracing::{debug, error, info};

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

/// Parameters for a tool call
#[derive(Debug)]
pub struct ToolCallParams<'a> {
    pub call_id: &'a str,
    pub tool_name: &'a str,
    pub provider_id: &'a str,
    pub content_type: &'a str,
    pub args: Vec<u8>,
    pub policy: Option<ExecutionPolicyConfig>,
    pub stream: bool,
}

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
    pub async fn call_tool(&mut self, params: ToolCallParams<'_>) -> Result<ToolFrame> {
        let execution_policy = params.policy.map(|p| ExecutionPolicy {
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
            call_id: params.call_id.to_string(),
            tool_name: params.tool_name.to_string(),
            provider_id: params.provider_id.to_string(),
            content_type: params.content_type.to_string(),
            args: params.args,
            policy: execution_policy,
            stream: params.stream,
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
        let response = self.client.call_stream(request).await.map_err(|e| {
            error!("Failed to start streaming tool call {}: {}", call_id, e);
            Error::Status(e)
        })?;

        let stream = response.into_inner();
        info!("Streaming tool call started: {} ({})", call_id, tool_name);

        let call_id_owned = call_id.to_string();
        let mapped_stream = tokio_stream::StreamExt::map(stream, move |result| match result {
            Ok(frame) => {
                debug!("Received tool frame for call {}", call_id_owned);
                Ok(frame)
            }
            Err(status) => {
                error!("Stream error for tool call {}: {}", call_id_owned, status);
                Err(Error::Status(status))
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
            tool_name: "".to_string(), // Empty for cancel requests
            provider_id: "".to_string(),
            content_type: "application/json".to_string(),
            args: b"{}".to_vec(), // Empty JSON
            policy: None,
            stream: false,
        };

        let request = tonic::Request::new(cancel_tool_call);
        let response = self.client.cancel(request).await.map_err(|e| {
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

#[cfg(test)]
mod tests {
    use super::*;

    /// Test ExecutionPolicyConfig default values
    #[test]
    fn test_execution_policy_config_default() {
        let config = ExecutionPolicyConfig::default();

        assert_eq!(config.timeout, Some(Duration::from_secs(30)));
        assert_eq!(config.max_retries, 3);
        assert_eq!(config.backoff, "exponential");
        assert!(!config.worktree_required);
        assert_eq!(config.network_policy, "restricted");
        assert_eq!(config.privilege_level, "default");
        assert_eq!(config.budget_cpu_ms, 30000);
        assert_eq!(config.budget_wall_ms, 30000);
    }

    /// Test ExecutionPolicyConfig custom values
    #[test]
    fn test_execution_policy_config_custom() {
        let config = ExecutionPolicyConfig {
            timeout: Some(Duration::from_secs(60)),
            max_retries: 5,
            backoff: "linear".to_string(),
            worktree_required: true,
            network_policy: "full".to_string(),
            privilege_level: "elevated".to_string(),
            budget_cpu_ms: 60000,
            budget_wall_ms: 120000,
        };

        assert_eq!(config.timeout, Some(Duration::from_secs(60)));
        assert_eq!(config.max_retries, 5);
        assert_eq!(config.backoff, "linear");
        assert!(config.worktree_required);
        assert_eq!(config.network_policy, "full");
        assert_eq!(config.privilege_level, "elevated");
    }

    /// Test ExecutionPolicyConfig without timeout
    #[test]
    fn test_execution_policy_config_no_timeout() {
        let config = ExecutionPolicyConfig {
            timeout: None,
            ..ExecutionPolicyConfig::default()
        };

        assert!(config.timeout.is_none());
    }

    /// Test ToolCall construction
    #[test]
    fn test_tool_call_construction() {
        let tool_call = ToolCall {
            call_id: "call-123".to_string(),
            tool_name: "read_file".to_string(),
            provider_id: "provider-1".to_string(),
            content_type: "application/json".to_string(),
            args: b"{\"path\": \"/tmp/test.txt\"}".to_vec(),
            policy: None,
            stream: false,
        };

        assert_eq!(tool_call.call_id, "call-123");
        assert_eq!(tool_call.tool_name, "read_file");
        assert_eq!(tool_call.provider_id, "provider-1");
        assert_eq!(tool_call.content_type, "application/json");
        assert!(!tool_call.stream);
    }

    /// Test ToolCall with minimal parameters
    #[test]
    fn test_tool_call_minimal() {
        let tool_call = ToolCall {
            call_id: "call-1".to_string(),
            tool_name: "echo".to_string(),
            provider_id: String::new(),
            content_type: String::new(),
            args: vec![],
            policy: None,
            stream: false,
        };

        assert_eq!(tool_call.call_id, "call-1");
        assert_eq!(tool_call.tool_name, "echo");
        assert!(tool_call.provider_id.is_empty());
    }

    /// Test ToolCall with execution policy
    #[test]
    fn test_tool_call_with_policy() {
        let policy = ExecutionPolicy {
            timeout: Some(prost_types::Duration {
                seconds: 30,
                nanos: 0,
            }),
            max_retries: 3,
            backoff: "exponential".to_string(),
            worktree_required: false,
            network_policy: "restricted".to_string(),
            privilege_level: "default".to_string(),
            budget_cpu_ms: 30000,
            budget_wall_ms: 30000,
        };

        let tool_call = ToolCall {
            call_id: "call-1".to_string(),
            tool_name: "long_running".to_string(),
            provider_id: "provider-1".to_string(),
            content_type: "application/json".to_string(),
            args: vec![],
            policy: Some(policy),
            stream: false,
        };

        assert!(tool_call.policy.is_some());
        let p = tool_call.policy.unwrap();
        assert_eq!(p.max_retries, 3);
    }

    /// Test ToolCall with streaming enabled
    #[test]
    fn test_tool_call_streaming() {
        let tool_call = ToolCall {
            call_id: "call-1".to_string(),
            tool_name: "stream_logs".to_string(),
            provider_id: "provider-1".to_string(),
            content_type: "application/json".to_string(),
            args: vec![],
            policy: None,
            stream: true,
        };

        assert!(tool_call.stream);
    }

    /// Test ToolCallParams structure
    #[test]
    fn test_tool_call_params() {
        let params = ToolCallParams {
            call_id: "call-123",
            tool_name: "read_file",
            provider_id: "provider-1",
            content_type: "application/json",
            args: b"{\"path\": \"/test\"}".to_vec(),
            policy: None,
            stream: false,
        };

        assert_eq!(params.call_id, "call-123");
        assert_eq!(params.tool_name, "read_file");
        assert_eq!(params.provider_id, "provider-1");
        assert_eq!(params.content_type, "application/json");
        assert!(!params.stream);
    }

    /// Test ToolCallParams with policy
    #[test]
    fn test_tool_call_params_with_policy() {
        let policy_config = ExecutionPolicyConfig::default();

        let params = ToolCallParams {
            call_id: "call-1",
            tool_name: "test",
            provider_id: "provider",
            content_type: "application/json",
            args: vec![],
            policy: Some(policy_config),
            stream: false,
        };

        assert!(params.policy.is_some());
        let p = params.policy.unwrap();
        assert_eq!(p.max_retries, 3);
    }

    /// Test binary args
    #[test]
    fn test_binary_args() {
        let binary_data: Vec<u8> = vec![0x00, 0x01, 0x02, 0xff, 0xfe, 0xfd];

        let tool_call = ToolCall {
            call_id: "call-1".to_string(),
            tool_name: "process_binary".to_string(),
            provider_id: "provider-1".to_string(),
            content_type: "application/octet-stream".to_string(),
            args: binary_data.clone(),
            policy: None,
            stream: false,
        };

        assert_eq!(tool_call.args, binary_data);
    }

    /// Test large args payload
    #[test]
    fn test_large_args() {
        // 1MB of data
        let large_data: Vec<u8> = vec![b'x'; 1024 * 1024];

        let tool_call = ToolCall {
            call_id: "call-1".to_string(),
            tool_name: "process_large".to_string(),
            provider_id: "provider-1".to_string(),
            content_type: "application/octet-stream".to_string(),
            args: large_data.clone(),
            policy: None,
            stream: false,
        };

        assert_eq!(tool_call.args.len(), 1024 * 1024);
    }

    /// Test cancel request (minimal ToolCall)
    #[test]
    fn test_cancel_request() {
        let cancel_call = ToolCall {
            call_id: "call-to-cancel".to_string(),
            tool_name: String::new(),
            provider_id: String::new(),
            content_type: "application/json".to_string(),
            args: b"{}".to_vec(),
            policy: None,
            stream: false,
        };

        assert_eq!(cancel_call.call_id, "call-to-cancel");
        assert!(cancel_call.tool_name.is_empty());
    }

    /// Test ExecutionPolicy conversion
    #[test]
    fn test_execution_policy_conversion() {
        let config = ExecutionPolicyConfig {
            timeout: Some(Duration::from_secs(45)),
            max_retries: 5,
            backoff: "linear".to_string(),
            worktree_required: true,
            network_policy: "full".to_string(),
            privilege_level: "elevated".to_string(),
            budget_cpu_ms: 50000,
            budget_wall_ms: 60000,
        };

        let policy = ExecutionPolicy {
            timeout: config.timeout.map(|t| prost_types::Duration {
                seconds: t.as_secs() as i64,
                nanos: t.subsec_nanos() as i32,
            }),
            max_retries: config.max_retries,
            backoff: config.backoff.clone(),
            worktree_required: config.worktree_required,
            network_policy: config.network_policy.clone(),
            privilege_level: config.privilege_level.clone(),
            budget_cpu_ms: config.budget_cpu_ms,
            budget_wall_ms: config.budget_wall_ms,
        };

        assert_eq!(policy.max_retries, 5);
        assert_eq!(policy.backoff, "linear");
        assert!(policy.worktree_required);
        assert!(policy.timeout.is_some());
        let t = policy.timeout.unwrap();
        assert_eq!(t.seconds, 45);
    }

    /// Test multiple tool calls
    #[test]
    fn test_multiple_tool_calls() {
        let calls: Vec<ToolCall> = vec!["read_file", "write_file", "execute"]
            .into_iter()
            .enumerate()
            .map(|(i, name)| ToolCall {
                call_id: format!("call-{}", i),
                tool_name: name.to_string(),
                provider_id: "provider-1".to_string(),
                content_type: "application/json".to_string(),
                args: vec![],
                policy: None,
                stream: false,
            })
            .collect();

        assert_eq!(calls.len(), 3);
        assert_eq!(calls[0].tool_name, "read_file");
        assert_eq!(calls[1].tool_name, "write_file");
        assert_eq!(calls[2].tool_name, "execute");
    }
}
