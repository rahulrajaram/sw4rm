use crate::proto::sw4rm::connector::connector_service_client::ConnectorServiceClient;
use crate::proto::sw4rm::connector::{
    DescribeToolsRequest, ProviderRegisterRequest, ToolDescriptor as ProtoToolDescriptor,
};
use crate::{Error, Result};
use std::time::Duration;
use tonic::transport::{Channel, Endpoint};

/// Client for interacting with the SW4RM Connector service
#[derive(Debug, Clone)]
pub struct ConnectorClient {
    client: ConnectorServiceClient<Channel>,
    timeout: Duration,
}

impl ConnectorClient {
    /// Create a new connector client with default 30 second timeout
    pub async fn new(endpoint: &str) -> Result<Self> {
        Self::with_timeout(endpoint, Duration::from_secs(30)).await
    }

    /// Create a new connector client with custom timeout
    pub async fn with_timeout(endpoint: &str, timeout: Duration) -> Result<Self> {
        let channel = Endpoint::from_shared(endpoint.to_string())
            .map_err(|e| Error::Config(format!("Invalid endpoint: {}", e)))?
            .timeout(timeout)
            .connect()
            .await?;

        Ok(Self {
            client: ConnectorServiceClient::new(channel),
            timeout,
        })
    }

    /// Register a tool provider
    pub async fn register_provider(
        &mut self,
        provider_id: &str,
        tools: Vec<ToolDescriptor>,
    ) -> Result<()> {
        let proto_tools: Vec<ProtoToolDescriptor> = tools
            .into_iter()
            .map(|tool| ProtoToolDescriptor {
                tool_name: tool.tool_name,
                input_schema: tool.input_schema,
                output_schema: tool.output_schema,
                idempotent: tool.idempotent,
                needs_worktree: tool.needs_worktree,
                default_timeout_s: tool.default_timeout_s,
                max_concurrency: tool.max_concurrency,
                side_effects: tool.side_effects,
            })
            .collect();

        let mut request = tonic::Request::new(ProviderRegisterRequest {
            provider_id: provider_id.to_string(),
            tools: proto_tools,
        });
        request.set_timeout(self.timeout);

        self.client.register_provider(request).await?;
        Ok(())
    }

    /// Describe available tools from a provider
    pub async fn describe_tools(&mut self, provider_id: &str) -> Result<Vec<ToolDescriptor>> {
        let mut request = tonic::Request::new(DescribeToolsRequest {
            provider_id: provider_id.to_string(),
        });
        request.set_timeout(self.timeout);

        let response = self.client.describe_tools(request).await?;
        let tools = response
            .into_inner()
            .tools
            .into_iter()
            .map(|tool| ToolDescriptor {
                tool_name: tool.tool_name,
                input_schema: tool.input_schema,
                output_schema: tool.output_schema,
                idempotent: tool.idempotent,
                needs_worktree: tool.needs_worktree,
                default_timeout_s: tool.default_timeout_s,
                max_concurrency: tool.max_concurrency,
                side_effects: tool.side_effects,
            })
            .collect();

        Ok(tools)
    }
}

/// Tool descriptor for registering tools with the connector
#[derive(Debug, Clone)]
pub struct ToolDescriptor {
    pub tool_name: String,
    pub input_schema: String,
    pub output_schema: String,
    pub idempotent: bool,
    pub needs_worktree: bool,
    pub default_timeout_s: u32,
    pub max_concurrency: u32,
    pub side_effects: String,
}

impl ToolDescriptor {
    pub fn new(tool_name: String, input_schema: String, output_schema: String) -> Self {
        Self {
            tool_name,
            input_schema,
            output_schema,
            idempotent: true,
            needs_worktree: false,
            default_timeout_s: 30,
            max_concurrency: 1,
            side_effects: "none".to_string(),
        }
    }

    pub fn with_side_effects(mut self, side_effects: String) -> Self {
        self.side_effects = side_effects;
        self
    }

    pub fn with_timeout(mut self, timeout_s: u32) -> Self {
        self.default_timeout_s = timeout_s;
        self
    }

    pub fn with_concurrency(mut self, max_concurrency: u32) -> Self {
        self.max_concurrency = max_concurrency;
        self
    }

    pub fn needs_worktree(mut self, needs_worktree: bool) -> Self {
        self.needs_worktree = needs_worktree;
        self
    }

    pub fn not_idempotent(mut self) -> Self {
        self.idempotent = false;
        self
    }
}
