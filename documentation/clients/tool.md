# 6.15. Tool Client

The Tool Client talks to the `sw4rm.tool.ToolService` service. Use it to:

- Execute external tools with unary or streaming responses.
- Apply execution policies for timeouts, retries, and resource budgets.
- Cancel in-flight tool calls (best effort).

## 6.15.1. Service Overview

The service exposes three RPCs:

- `Call(ToolCall) -> ToolFrame`
- `CallStream(ToolCall) -> stream ToolFrame`
- `Cancel(ToolCall) -> ToolError`

### ExecutionPolicy fields

| Field | Type | Description |
|-------|------|-------------|
| `timeout` | `google.protobuf.Duration` | Execution timeout for the call. |
| `max_retries` | uint32 | Max retry attempts for transient failures. |
| `backoff` | string | Backoff strategy (for example, `exponential`). |
| `worktree_required` | bool | Whether a bound worktree is required. |
| `network_policy` | string | Network policy label (for example, `egress_restricted`). |
| `privilege_level` | string | Privilege level label (for example, `default`). |
| `budget_cpu_ms` | uint64 | CPU time budget in milliseconds. |
| `budget_wall_ms` | uint64 | Wall-clock budget in milliseconds. |

### ToolCall fields

| Field | Type | Description |
|-------|------|-------------|
| `call_id` | string | Unique call identifier. |
| `tool_name` | string | Tool name to execute. |
| `provider_id` | string | Tool provider identifier. |
| `content_type` | string | MIME type for `args` (for example, `application/json`). |
| `args` | bytes | Tool arguments payload. |
| `policy` | ExecutionPolicy | Optional execution policy overrides. |
| `stream` | bool | Whether the call expects streaming frames. |

### ToolFrame fields

| Field | Type | Description |
|-------|------|-------------|
| `call_id` | string | Call identifier. |
| `frame_no` | uint64 | Frame sequence number. |
| `final` | bool | Whether this is the last frame. |
| `content_type` | string | MIME type for `data`. |
| `data` | bytes | Frame payload. |
| `summary` | bytes | Optional final summary payload. |

### ToolError fields

| Field | Type | Description |
|-------|------|-------------|
| `call_id` | string | Call identifier. |
| `error_code` | string | Error code (for example, `TOOL_TIMEOUT`). |
| `message` | string | Human-readable error message. |

## 6.15.2. Constructors

### Python

`ToolClient(channel: grpc.Channel)`

- `channel`: A gRPC channel connected to the ToolService endpoint.

### JavaScript/TypeScript

`new ToolClient(options: ClientOptions)`

- `options.address`: `host:port` for the ToolService endpoint.
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`ToolClient::new(endpoint: &str) -> Result<ToolClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:port`).

## 6.15.3. Key Methods

### `call` / `call_tool`

**Python**
`call(call: dict) -> ToolFrame`

**JavaScript/TypeScript**
`call(req: ToolCall): Promise<ToolFrame>`

**Rust**
`call_tool(params: ToolCallParams) -> Result<ToolFrame>`

### `call_stream` / `callStream` / `call_tool_stream`

**Python**
`call_stream(call: dict) -> Iterable[ToolFrame]`

**JavaScript/TypeScript**
`callStream(req: ToolCall, meta?: Metadata): ClientReadableStream<ToolFrame>`

**Rust**
`call_tool_stream(call_id: &str, tool_name: &str, provider_id: &str, content_type: &str, args: Vec<u8>, policy: Option<ExecutionPolicyConfig>) -> Result<Stream<Item = Result<ToolFrame>>>`

### `cancel` / `cancel_tool`

**Python**
`cancel(call: dict) -> ToolError`

**JavaScript/TypeScript**
`cancel(req: ToolCall): Promise<ToolError>`

**Rust**
`cancel_tool(call_id: &str) -> Result<ToolError>`

## 6.15.4. Usage Examples

=== "Python"
    ```python
    import json
    import grpc
    from sw4rm.clients import ToolClient

    channel = grpc.insecure_channel("TOOL_HOST:50063")
    client = ToolClient(channel)

    call = {
        "call_id": "call-001",
        "tool_name": "read_file",
        "provider_id": "provider-1",
        "content_type": "application/json",
        "args": json.dumps({"path": "main.py"}).encode("utf-8"),
        "policy": {
            "timeout": {"seconds": 10},
            "max_retries": 2,
            "backoff": "exponential",
            "worktree_required": True,
        },
        "stream": False,
    }

    frame = client.call(call)
    print(frame.data)

    call["stream"] = True
    for frame in client.call_stream(call):
        print(frame.frame_no, frame.data)
        if frame.final:
            break

    client.cancel({"call_id": "call-001"})
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { ToolClient } from '@sw4rm/js-sdk';

    const client = new ToolClient({ address: 'TOOL_HOST:50063' });

    const call = {
      call_id: 'call-001',
      tool_name: 'read_file',
      provider_id: 'provider-1',
      content_type: 'application/json',
      args: Buffer.from(JSON.stringify({ path: 'main.py' })),
      policy: {
        timeout: { seconds: 10 },
        max_retries: 2,
        backoff: 'exponential',
        worktree_required: true,
      },
      stream: false,
    };

    const frame = await client.call(call);
    console.log(Buffer.from(frame.data).toString('utf-8'));

    call.stream = true;
    const stream = client.callStream(call);
    stream.on('data', (frame) => {
      console.log(frame.frame_no, frame.data);
    });
    stream.on('end', () => console.log('done'));

    await client.cancel({
      call_id: 'call-001',
      tool_name: '',
      content_type: 'application/json',
      args: new Uint8Array(),
    });
    ```

=== "Rust"
    ```rust
    use std::time::Duration;
    use sw4rm_sdk::clients::{ExecutionPolicyConfig, ToolCallParams, ToolClient};

    #[tokio::main]
    async fn main() -> sw4rm_sdk::Result<()> {
        let mut client = ToolClient::new("http://TOOL_HOST:50063").await?;
        let policy = ExecutionPolicyConfig {
            timeout: Some(Duration::from_secs(10)),
            max_retries: 2,
            backoff: "exponential".to_string(),
            worktree_required: true,
            ..ExecutionPolicyConfig::default()
        };

        let params = ToolCallParams {
            call_id: "call-001",
            tool_name: "read_file",
            provider_id: "provider-1",
            content_type: "application/json",
            args: br#"{"path":"main.py"}"#.to_vec(),
            policy: Some(policy),
            stream: false,
        };

        let frame = client.call_tool(params).await?;
        println!("{:?}", frame.data);

        client.cancel_tool("call-001").await?;
        Ok(())
    }
    ```

## 6.15.5. Error Handling

- Python raises `RuntimeError` if protobuf stubs are missing. Run `make protos`.
- JavaScript/TypeScript and Rust surface gRPC errors for connectivity and RPC failures.
- `cancel` is best-effort; the tool may already have completed.
