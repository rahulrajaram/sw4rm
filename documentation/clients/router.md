# 6.2. Router Client

The Router Client talks to the `sw4rm.router.RouterService` service. Use it to:

- Send message envelopes to destination agents.
- Stream incoming envelopes for an agent.

## 6.2.1. Service Overview

The service exposes two RPCs:

- `SendMessage(SendMessageRequest) -> SendMessageResponse`
- `StreamIncoming(StreamRequest) -> (stream StreamItem)`

### SendMessageResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `accepted` | bool | Whether the router accepted the message |
| `reason` | string | Rejection reason (if any) |

### StreamItem fields

| Field | Type | Description |
|-------|------|-------------|
| `msg` | `Envelope` | Incoming envelope for the agent |

> See `documentation/protocol/messages.md` for the Envelope field definitions.

## 6.2.2. Constructors

### Python

`RouterClient(channel: grpc.Channel)`

- `channel`: A gRPC channel connected to the RouterService endpoint (default port: 50051).

### JavaScript/TypeScript

`new RouterClient(options: ClientOptions)`

- `options.address`: `host:port` for the RouterService endpoint.
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`RouterClient::new(endpoint: &str) -> Result<RouterClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:50051`).

## 6.2.3. Key Methods

### `send_message` / `sendMessage`

**Python**
`send_message(envelope: dict) -> SendMessageResponse`

**JavaScript/TypeScript**
`sendMessage(envelope: EnvelopeBuilt): Promise<{ accepted: boolean; reason?: string }>`

**Rust**
`send_message(&mut self, envelope: &EnvelopeData) -> Result<SendResult>`

### `stream_incoming` / `streamIncoming`

**Python**
`stream_incoming(agent_id: str) -> Iterable[StreamItem]`

**JavaScript/TypeScript**
`streamIncoming(agentId: string, meta?: Metadata) -> ClientReadableStream<{ msg: EnvelopeBuilt }>`

**Rust**
`stream_incoming(&mut self, agent_id: &str) -> Result<Pin<Box<dyn Stream<Item = Result<EnvelopeData>> + Send>>>`

### `health_check` (Rust convenience)

**Rust**
`health_check(&mut self) -> Result<bool>`

## 6.2.4. Usage Examples

=== "Python"
    ```python
    import grpc
    import json
    from sw4rm import constants as C
    from sw4rm.envelope import build_envelope
    from sw4rm.clients import RouterClient

    channel = grpc.insecure_channel("localhost:50051")
    client = RouterClient(channel)

    payload = json.dumps({"hello": "world"}).encode("utf-8")
    envelope = build_envelope(
        producer_id="agent-1",
        message_type=C.DATA,
        content_type="application/json",
        payload=payload,
    )

    response = client.send_message(envelope)
    print("accepted:", response.accepted, "reason:", response.reason)

    for item in client.stream_incoming("agent-1"):
        print("incoming:", item.msg)
        break
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { RouterClient, buildEnvelope, MessageType } from '@sw4rm/js-sdk';

    const router = new RouterClient({ address: 'localhost:50051' });
    const env = buildEnvelope({
      producer_id: 'agent-1',
      message_type: MessageType.DATA,
      content_type: 'application/json',
      payload: new TextEncoder().encode(JSON.stringify({ hello: 'world' })),
    });

    const result = await router.sendMessage(env);
    console.log('accepted:', result.accepted, 'reason:', result.reason);

    const stream = router.streamIncoming('agent-1');
    stream.on('data', (item) => {
      console.log('incoming:', item.msg);
    });
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::{clients::RouterClient, envelope::EnvelopeBuilder, constants, Result};
    use serde_json::json;
    use tokio_stream::StreamExt;

    #[tokio::main]
    async fn main() -> Result<()> {
        let mut client = RouterClient::new("http://localhost:50051").await?;

        let envelope = EnvelopeBuilder::new(
            "agent-1".to_string(),
            constants::message_type::DATA,
        )
        .with_json_payload(&json!({"hello": "world"}))?
        .build();

        let result = client.send_message(&envelope).await?;
        println!("accepted={} reason={}", result.accepted, result.reason);

        let mut stream = client.stream_incoming("agent-1").await?;
        if let Some(item) = stream.next().await {
            println!("incoming: {:?}", item?);
        }

        Ok(())
    }
    ```

> **Tip:** If you see `RuntimeError: Protobuf stubs not generated`, run:

```bash
make protos
```
