# 6.7. Connector Client

The Connector Client talks to the `sw4rm.connector.ConnectorService` service. Use it to:

- Register tool providers and the tools they expose.
- Describe available tools for a provider.

## 6.7.1. Service Overview

The service exposes two RPCs:

- `RegisterProvider(ProviderRegisterRequest) -> ProviderRegisterResponse`
- `DescribeTools(DescribeToolsRequest) -> DescribeToolsResponse`

### ToolDescriptor fields

| Field | Type | Description |
|-------|------|-------------|
| `tool_name` | string | Tool name |
| `input_schema` | string | JSON Schema or URL for input |
| `output_schema` | string | JSON Schema or URL for output |
| `idempotent` | bool | Whether the tool is idempotent |
| `needs_worktree` | bool | Whether the tool needs a worktree |
| `default_timeout_s` | uint32 | Default timeout in seconds |
| `max_concurrency` | uint32 | Maximum concurrent executions |
| `side_effects` | string | Side effects (for example, `filesystem`, `network`) |

## 6.7.2. Constructors

### Python

`ConnectorClient(channel: grpc.Channel, timeout: float = 30.0)`

- `channel`: A gRPC channel connected to the ConnectorService endpoint.
- `timeout`: Default timeout in seconds for RPC calls (default: 30.0).

### JavaScript/TypeScript

`new ConnectorClient(options: ClientOptions)`

- `options.address`: `host:port` for the ConnectorService endpoint.
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`ConnectorClient::new(endpoint: &str) -> Result<ConnectorClient>`

`ConnectorClient::with_timeout(endpoint: &str, timeout: Duration) -> Result<ConnectorClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:port`).

## 6.7.3. Key Methods

### `register_provider`

**Python**
`register_provider(provider_id: str, tools: list[dict[str, Any]], timeout: float | None = None) -> ProviderRegisterResponse`

**JavaScript/TypeScript**
`registerProvider(req: ProviderRegisterRequest): Promise<ProviderRegisterResponse>`

**Rust**
`register_provider(provider_id: &str, tools: Vec<ToolDescriptor>) -> Result<()>`

**Response fields**

- `ok` (bool): Whether the provider registration succeeded.
- `reason` (string): Optional failure reason.

### `describe_tools`

**Python**
`describe_tools(provider_id: str, timeout: float | None = None) -> DescribeToolsResponse`

**JavaScript/TypeScript**
`describeTools(providerId: string): Promise<ToolDescriptor[]>`

**Rust**
`describe_tools(provider_id: &str) -> Result<Vec<ToolDescriptor>>`

**Response fields**

- `tools` (list[ToolDescriptor]): Tools registered for the provider.

## 6.7.4. Usage Examples

=== "Python"
    ```python
    import grpc
    from sw4rm.clients import ConnectorClient

    channel = grpc.insecure_channel("CONNECTOR_HOST:CONNECTOR_PORT")
    client = ConnectorClient(channel)

    tools = [
        {
            "tool_name": "read_file",
            "input_schema": '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}',
            "output_schema": '{"type":"string"}',
            "idempotent": True,
            "needs_worktree": True,
            "default_timeout_s": 10,
            "max_concurrency": 4,
            "side_effects": "filesystem",
        }
    ]

    response = client.register_provider("provider-1", tools)
    print(response.ok, response.reason)

    described = client.describe_tools("provider-1")
    for tool in described.tools:
        print(tool.tool_name)
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { ConnectorClient } from '@sw4rm/js-sdk';

    const client = new ConnectorClient({
      address: 'CONNECTOR_HOST:CONNECTOR_PORT',
      deadlineMs: 20000,
    });

    await client.registerProvider({
      provider_id: 'provider-1',
      tools: [
        {
          tool_name: 'read_file',
          input_schema: '{"type":"object"}',
          output_schema: '{"type":"string"}',
          idempotent: true,
          needs_worktree: true,
          default_timeout_s: 10,
          max_concurrency: 4,
          side_effects: 'filesystem',
        },
      ],
    });

    const tools = await client.describeTools('provider-1');
    for (const tool of tools) {
      console.log(tool.tool_name);
    }
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::clients::{ConnectorClient, ToolDescriptor};

    #[tokio::main]
    async fn main() -> sw4rm_sdk::Result<()> {
        let mut client = ConnectorClient::new("http://CONNECTOR_HOST:CONNECTOR_PORT").await?;

        let tool = ToolDescriptor::new(
            "read_file".to_string(),
            r#"{"type":"object"}"#.to_string(),
            r#"{"type":"string"}"#.to_string(),
        )
        .with_side_effects("filesystem".to_string())
        .needs_worktree(true);

        client.register_provider("provider-1", vec![tool]).await?;

        let tools = client.describe_tools("provider-1").await?;
        for tool in tools {
            println!("{}", tool.tool_name);
        }

        Ok(())
    }
    ```

## 6.7.5. Error Handling

- Python raises `RuntimeError` if protobuf stubs are missing. Run `make protos`.
- JavaScript/TypeScript and Rust surface gRPC errors for connectivity and RPC failures.
