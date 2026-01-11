# 6.10. Logging Client

The Logging Client talks to the `sw4rm.logging.LoggingService` service. Use it to:

- Ingest structured log events for audit trails and observability.
- Attach correlation IDs for tracing across agent workflows.

## 6.10.1. Service Overview

The service exposes one RPC:

- `Ingest(LogEvent) -> IngestResponse`

### LogEvent fields

| Field | Type | Description |
|-------|------|-------------|
| `ts` | `google.protobuf.Timestamp` | Event timestamp |
| `correlation_id` | string | Correlates related events across services |
| `agent_id` | string | Agent identifier |
| `event_type` | string | Event name (for example, `task_started`) |
| `level` | string | Log level (`INFO`, `WARN`, `ERROR`) |
| `details_json` | string | JSON-encoded details payload |

## 6.10.2. Constructors

### Python

`LoggingClient(channel: grpc.Channel)`

- `channel`: A gRPC channel connected to the LoggingService endpoint (default port: 50066).

### JavaScript/TypeScript

`new LoggingClient(options: ClientOptions)`

- `options.address`: `host:port` for the LoggingService endpoint.
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`LoggingClient::new(endpoint: &str) -> Result<LoggingClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:50066`).

## 6.10.3. Key Methods

### `ingest`

**Python**
`ingest(event: dict) -> IngestResponse`

**JavaScript/TypeScript**
`ingest(evt: LogEvent): Promise<boolean>`

**Rust**
`ingest(&mut self, event: LogEvent) -> Result<IngestResponse>`

**Response fields**

- `ok` (bool): Whether the ingest succeeded.

### `log` (Rust convenience)

**Rust**
`log(&mut self, agent_id: &str, event_type: &str, level: &str, details_json: &str, correlation_id: Option<&str>) -> Result<IngestResponse>`

## 6.10.4. Usage Examples

=== "Python"
    ```python
    import grpc
    import json
    from datetime import datetime, timezone
    from google.protobuf.timestamp_pb2 import Timestamp
    from sw4rm.clients import LoggingClient

    channel = grpc.insecure_channel("localhost:50066")
    client = LoggingClient(channel)

    ts = Timestamp()
    ts.FromDatetime(datetime.now(timezone.utc))

    event = {
        "ts": ts,
        "correlation_id": "corr-123",
        "agent_id": "agent-1",
        "event_type": "task_started",
        "level": "INFO",
        "details_json": json.dumps({
            "task_id": "task-1",
            "queue": "default",
        }),
    }

    response = client.ingest(event)
    print(f"Ingest ok: {response.ok}")
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { LoggingClient } from '@sw4rm/js-sdk';

    const client = new LoggingClient({ address: 'localhost:50066' });

    const nowMs = Date.now();
    const evt = {
      ts: {
        seconds: Math.floor(nowMs / 1000),
        nanos: (nowMs % 1000) * 1_000_000,
      },
      correlation_id: 'corr-123',
      agent_id: 'agent-1',
      event_type: 'task_started',
      level: 'INFO',
      details_json: JSON.stringify({
        task_id: 'task-1',
        queue: 'default',
      }),
    };

    const ok = await client.ingest(evt);
    console.log('Ingest ok:', ok);
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::clients::{LogEvent, LoggingClient};

    #[tokio::main]
    async fn main() -> sw4rm_sdk::Result<()> {
        let mut client = LoggingClient::new("http://localhost:50066").await?;

        let event = LogEvent::new(
            "agent-1".to_string(),
            "task_started".to_string(),
            "INFO".to_string(),
            r#"{"task_id": "task-1", "queue": "default"}"#.to_string(),
        )
        .with_correlation_id("corr-123".to_string());

        let response = client.ingest(event).await?;
        println!("Ingest ok: {}", response.ok);

        Ok(())
    }
    ```

> **Tip:** If you see `RuntimeError: Protobuf stubs not generated`, run:

```bash
make protos
```
