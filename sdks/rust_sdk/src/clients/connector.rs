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

#[cfg(test)]
mod tests {
    use super::*;

    /// Test ToolDescriptor construction with new()
    #[test]
    fn test_tool_descriptor_new() {
        let descriptor = ToolDescriptor::new(
            "read_file".to_string(),
            r#"{"type": "object"}"#.to_string(),
            r#"{"type": "string"}"#.to_string(),
        );

        assert_eq!(descriptor.tool_name, "read_file");
        assert!(!descriptor.input_schema.is_empty());
        assert!(!descriptor.output_schema.is_empty());
        // Check defaults
        assert!(descriptor.idempotent);
        assert!(!descriptor.needs_worktree);
        assert_eq!(descriptor.default_timeout_s, 30);
        assert_eq!(descriptor.max_concurrency, 1);
        assert_eq!(descriptor.side_effects, "none");
    }

    /// Test ToolDescriptor with_side_effects builder
    #[test]
    fn test_tool_descriptor_with_side_effects() {
        let descriptor =
            ToolDescriptor::new("write_file".to_string(), "{}".to_string(), "{}".to_string())
                .with_side_effects("filesystem".to_string());

        assert_eq!(descriptor.side_effects, "filesystem");
    }

    /// Test ToolDescriptor with_timeout builder
    #[test]
    fn test_tool_descriptor_with_timeout() {
        let descriptor =
            ToolDescriptor::new("slow_op".to_string(), "{}".to_string(), "{}".to_string())
                .with_timeout(120);

        assert_eq!(descriptor.default_timeout_s, 120);
    }

    /// Test ToolDescriptor with_concurrency builder
    #[test]
    fn test_tool_descriptor_with_concurrency() {
        let descriptor = ToolDescriptor::new(
            "parallel_op".to_string(),
            "{}".to_string(),
            "{}".to_string(),
        )
        .with_concurrency(10);

        assert_eq!(descriptor.max_concurrency, 10);
    }

    /// Test ToolDescriptor needs_worktree builder
    #[test]
    fn test_tool_descriptor_needs_worktree() {
        let descriptor =
            ToolDescriptor::new("git_op".to_string(), "{}".to_string(), "{}".to_string())
                .needs_worktree(true);

        assert!(descriptor.needs_worktree);
    }

    /// Test ToolDescriptor not_idempotent builder
    #[test]
    fn test_tool_descriptor_not_idempotent() {
        let descriptor = ToolDescriptor::new(
            "create_file".to_string(),
            "{}".to_string(),
            "{}".to_string(),
        )
        .not_idempotent();

        assert!(!descriptor.idempotent);
    }

    /// Test ToolDescriptor with all builders chained
    #[test]
    fn test_tool_descriptor_all_builders() {
        let descriptor = ToolDescriptor::new(
            "complex_op".to_string(),
            r#"{"path": "string"}"#.to_string(),
            r#"{"result": "string"}"#.to_string(),
        )
        .with_side_effects("filesystem".to_string())
        .with_timeout(60)
        .with_concurrency(5)
        .needs_worktree(true)
        .not_idempotent();

        assert_eq!(descriptor.tool_name, "complex_op");
        assert_eq!(descriptor.side_effects, "filesystem");
        assert_eq!(descriptor.default_timeout_s, 60);
        assert_eq!(descriptor.max_concurrency, 5);
        assert!(descriptor.needs_worktree);
        assert!(!descriptor.idempotent);
    }

    /// Test ToolDescriptor clone
    #[test]
    fn test_tool_descriptor_clone() {
        let descriptor =
            ToolDescriptor::new("test".to_string(), "{}".to_string(), "{}".to_string())
                .with_timeout(45);

        let cloned = descriptor.clone();
        assert_eq!(descriptor.tool_name, cloned.tool_name);
        assert_eq!(descriptor.default_timeout_s, cloned.default_timeout_s);
    }

    /// Test ToolDescriptor debug
    #[test]
    fn test_tool_descriptor_debug() {
        let descriptor =
            ToolDescriptor::new("debug_tool".to_string(), "{}".to_string(), "{}".to_string());

        let debug_str = format!("{:?}", descriptor);
        assert!(debug_str.contains("ToolDescriptor"));
        assert!(debug_str.contains("debug_tool"));
    }

    /// Test ProviderRegisterRequest construction
    #[test]
    fn test_provider_register_request() {
        let tool1 = ProtoToolDescriptor {
            tool_name: "tool1".to_string(),
            input_schema: "{}".to_string(),
            output_schema: "{}".to_string(),
            idempotent: true,
            needs_worktree: false,
            default_timeout_s: 30,
            max_concurrency: 1,
            side_effects: "none".to_string(),
        };

        let tool2 = ProtoToolDescriptor {
            tool_name: "tool2".to_string(),
            input_schema: "{}".to_string(),
            output_schema: "{}".to_string(),
            idempotent: false,
            needs_worktree: true,
            default_timeout_s: 60,
            max_concurrency: 5,
            side_effects: "filesystem".to_string(),
        };

        let request = ProviderRegisterRequest {
            provider_id: "provider-1".to_string(),
            tools: vec![tool1, tool2],
        };

        assert_eq!(request.provider_id, "provider-1");
        assert_eq!(request.tools.len(), 2);
        assert_eq!(request.tools[0].tool_name, "tool1");
        assert_eq!(request.tools[1].tool_name, "tool2");
    }

    /// Test DescribeToolsRequest construction
    #[test]
    fn test_describe_tools_request() {
        let request = DescribeToolsRequest {
            provider_id: "provider-1".to_string(),
        };

        assert_eq!(request.provider_id, "provider-1");
    }

    /// Test ProtoToolDescriptor conversion from ToolDescriptor
    #[test]
    fn test_tool_descriptor_to_proto() {
        let tool = ToolDescriptor::new(
            "test_tool".to_string(),
            r#"{"input": "string"}"#.to_string(),
            r#"{"output": "string"}"#.to_string(),
        )
        .with_side_effects("network".to_string())
        .with_timeout(45)
        .with_concurrency(3)
        .needs_worktree(true)
        .not_idempotent();

        // Convert to proto
        let proto = ProtoToolDescriptor {
            tool_name: tool.tool_name.clone(),
            input_schema: tool.input_schema.clone(),
            output_schema: tool.output_schema.clone(),
            idempotent: tool.idempotent,
            needs_worktree: tool.needs_worktree,
            default_timeout_s: tool.default_timeout_s,
            max_concurrency: tool.max_concurrency,
            side_effects: tool.side_effects.clone(),
        };

        assert_eq!(proto.tool_name, "test_tool");
        assert_eq!(proto.side_effects, "network");
        assert_eq!(proto.default_timeout_s, 45);
        assert_eq!(proto.max_concurrency, 3);
        assert!(proto.needs_worktree);
        assert!(!proto.idempotent);
    }

    /// Test multiple tools registration
    #[test]
    fn test_multiple_tools_registration() {
        let tools: Vec<ToolDescriptor> = vec!["read_file", "write_file", "delete_file", "list_dir"]
            .into_iter()
            .map(|name| ToolDescriptor::new(name.to_string(), "{}".to_string(), "{}".to_string()))
            .collect();

        assert_eq!(tools.len(), 4);
        assert_eq!(tools[0].tool_name, "read_file");
        assert_eq!(tools[3].tool_name, "list_dir");
    }

    /// Test tool with complex schemas
    #[test]
    fn test_tool_complex_schemas() {
        let input_schema = serde_json::json!({
            "type": "object",
            "properties": {
                "path": {"type": "string"},
                "recursive": {"type": "boolean"},
                "maxDepth": {"type": "integer"}
            },
            "required": ["path"]
        });

        let output_schema = serde_json::json!({
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "name": {"type": "string"},
                    "size": {"type": "integer"},
                    "isDirectory": {"type": "boolean"}
                }
            }
        });

        let descriptor = ToolDescriptor::new(
            "list_directory".to_string(),
            input_schema.to_string(),
            output_schema.to_string(),
        );

        assert!(descriptor.input_schema.contains("path"));
        assert!(descriptor.output_schema.contains("isDirectory"));
    }

    /// Test empty tools list
    #[test]
    fn test_empty_tools_list() {
        let request = ProviderRegisterRequest {
            provider_id: "empty-provider".to_string(),
            tools: vec![],
        };

        assert!(request.tools.is_empty());
    }

    /// Test tool side effects values
    #[test]
    fn test_side_effects_values() {
        let side_effects = vec!["none", "filesystem", "network", "database", "external_api"];

        for effect in side_effects {
            let descriptor =
                ToolDescriptor::new("test".to_string(), "{}".to_string(), "{}".to_string())
                    .with_side_effects(effect.to_string());
            assert_eq!(descriptor.side_effects, effect);
        }
    }

    /// Test timeout values
    #[test]
    fn test_timeout_values() {
        // Short timeout
        let short = ToolDescriptor::new("quick".to_string(), "{}".to_string(), "{}".to_string())
            .with_timeout(5);
        assert_eq!(short.default_timeout_s, 5);

        // Long timeout
        let long = ToolDescriptor::new("slow".to_string(), "{}".to_string(), "{}".to_string())
            .with_timeout(3600);
        assert_eq!(long.default_timeout_s, 3600);

        // Zero timeout (infinite)
        let infinite =
            ToolDescriptor::new("infinite".to_string(), "{}".to_string(), "{}".to_string())
                .with_timeout(0);
        assert_eq!(infinite.default_timeout_s, 0);
    }

    /// Test concurrency values
    #[test]
    fn test_concurrency_values() {
        // Serial (1)
        let serial = ToolDescriptor::new("serial".to_string(), "{}".to_string(), "{}".to_string())
            .with_concurrency(1);
        assert_eq!(serial.max_concurrency, 1);

        // Highly parallel
        let parallel =
            ToolDescriptor::new("parallel".to_string(), "{}".to_string(), "{}".to_string())
                .with_concurrency(100);
        assert_eq!(parallel.max_concurrency, 100);
    }
}
