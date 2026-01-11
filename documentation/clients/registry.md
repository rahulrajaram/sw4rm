# 6.3. Registry Client

The Registry Client talks to the `sw4rm.registry.RegistryService` service. Use it to:

- Register agents for discovery and scheduling.
- Send heartbeats with agent state and health metrics.
- Deregister agents during shutdown.

## 6.3.1. Service Overview

The service exposes three RPCs:

- `RegisterAgent(RegisterAgentRequest) -> RegisterAgentResponse`
- `Heartbeat(HeartbeatRequest) -> HeartbeatResponse`
- `DeregisterAgent(DeregisterAgentRequest) -> DeregisterAgentResponse`

### AgentDescriptor fields

| Field | Type | Description |
|-------|------|-------------|
| `agent_id` | string | Unique agent identifier |
| `name` | string | Human-readable agent name |
| `description` | string | Agent description (<= 200 words) |
| `capabilities` | string[] | Declared capability labels |
| `communication_class` | CommunicationClass | `PRIVILEGED`, `STANDARD`, or `BULK` |
| `modalities_supported` | string[] | Supported MIME types |
| `reasoning_connectors` | string[] | Reasoning connector URIs |
| `public_key` | bytes | Optional public key for signing |

### HeartbeatRequest fields

| Field | Type | Description |
|-------|------|-------------|
| `agent_id` | string | Agent identifier |
| `state` | AgentState | Current agent state |
| `health` | map<string,string> | Optional health metrics |

## 6.3.2. Constructors

### Python

`RegistryClient(channel: grpc.Channel, timeout: float = 30.0)`

- `channel`: A gRPC channel connected to the RegistryService endpoint (default port: 50052).
- `timeout`: Default timeout in seconds for RPC calls.

### JavaScript/TypeScript

`new RegistryClient(options: ClientOptions)`

- `options.address`: `host:port` for the RegistryService endpoint.
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`RegistryClient::new(endpoint: &str) -> Result<RegistryClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:50052`).

## 6.3.3. Key Methods

### `register`

**Python**
`register(agent_descriptor: dict) -> RegisterAgentResponse`

**JavaScript/TypeScript**
`registerAgent(agent: AgentDescriptor): Promise<{ accepted: boolean; reason?: string }>`

**Rust**
`register(&mut self, agent: &AgentDescriptor) -> Result<RegisterAgentResponse>`

**Response fields**

- `accepted` (bool): Whether the registration was accepted.
- `reason` (string): Optional rejection reason.

### `heartbeat`

**Python**
`heartbeat(agent_id: str, state: int, health: dict[str, str] | None = None) -> HeartbeatResponse`

**JavaScript/TypeScript**
`heartbeat(agentId: string, state: string, health?: Record<string, string>): Promise<boolean>`

**Rust**
`heartbeat(&mut self, agent_id: &str, state: AgentState, health: Option<HashMap<String, String>>) -> Result<HeartbeatResponse>`

**Response fields**

- `ok` (bool): Whether the heartbeat was accepted.

### `deregister`

**Python**
`deregister(agent_id: str, reason: str = "") -> DeregisterAgentResponse`

**JavaScript/TypeScript**
`deregisterAgent(agentId: string, reason?: string): Promise<boolean>`

**Rust**
`deregister(&mut self, agent_id: &str, reason: Option<&str>) -> Result<DeregisterAgentResponse>`

**Response fields**

- `ok` (bool): Whether deregistration succeeded.

### `health_check` (Rust convenience)

**Rust**
`health_check(&mut self) -> Result<bool>`

## 6.3.4. Usage Examples

=== "Python"
    ```python
    import grpc
    from sw4rm import constants as C
    from sw4rm.clients import RegistryClient

    channel = grpc.insecure_channel("localhost:50052")
    client = RegistryClient(channel)

    agent = {
        "agent_id": "agent-1",
        "name": "SupportAgent",
        "description": "Handles support tickets",
        "capabilities": ["triage", "escalation"],
        "communication_class": C.STANDARD,
        "modalities_supported": ["application/json"],
        "reasoning_connectors": ["http://localhost:7000"],
    }

    response = client.register(agent)
    print(f"Registered: {response.accepted}")

    hb = client.heartbeat("agent-1", C.RUNNING, {"uptime": "120s"})
    print(f"Heartbeat ok: {hb.ok}")

    client.deregister("agent-1", "normal shutdown")
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { RegistryClient } from '@sw4rm/js-sdk';

    const client = new RegistryClient({ address: 'localhost:50052' });

    const agent = {
      agent_id: 'agent-1',
      name: 'SupportAgent',
      description: 'Handles support tickets',
      capabilities: ['triage', 'escalation'],
      communication_class: 'STANDARD',
      modalities_supported: ['application/json'],
      reasoning_connectors: ['http://localhost:7000'],
    };

    const registration = await client.registerAgent(agent);
    console.log('Registered:', registration.accepted);

    const ok = await client.heartbeat('agent-1', 'RUNNING', { uptime: '120s' });
    console.log('Heartbeat ok:', ok);

    await client.deregisterAgent('agent-1', 'normal shutdown');
    ```

=== "Rust"
    ```rust
    use std::collections::HashMap;
    use sw4rm_sdk::clients::RegistryClient;
    use sw4rm_sdk::proto::sw4rm::common::AgentState;
    use sw4rm_sdk::types::AgentDescriptor;

    #[tokio::main]
    async fn main() -> sw4rm_sdk::Result<()> {
        let mut client = RegistryClient::new("http://localhost:50052").await?;

        let agent = AgentDescriptor::new(
            "agent-1".to_string(),
            "SupportAgent".to_string(),
        )
        .with_description("Handles support tickets".to_string())
        .with_capabilities(vec!["triage".to_string(), "escalation".to_string()])
        .with_modalities(vec!["application/json".to_string()])
        .with_reasoning_connectors(vec!["http://localhost:7000".to_string()]);

        let response = client.register(&agent).await?;
        println!("Registered: {}", response.accepted);

        let mut health = HashMap::new();
        health.insert("uptime".to_string(), "120s".to_string());
        let hb = client
            .heartbeat("agent-1", AgentState::Running, Some(health))
            .await?;
        println!("Heartbeat ok: {}", hb.ok);

        let dereg = client.deregister("agent-1", Some("normal shutdown")).await?;
        println!("Deregistered: {}", dereg.ok);

        Ok(())
    }
    ```

> **Tip:** If you see `RuntimeError: Protobuf stubs not generated`, run:

```bash
make protos
```
