# 6.13. Negotiation Client

The Negotiation Client talks to the `sw4rm.negotiation.NegotiationService` service. Use it to:

- Open multi-agent negotiation sessions.
- Exchange proposals and counter-proposals.
- Collect evaluations and record a final decision.

## 6.13.1. Service Overview

The service exposes six RPCs:

- `Open(NegotiationOpen) -> Empty`
- `Propose(Proposal) -> Empty`
- `Counter(CounterProposal) -> Empty`
- `Evaluate(Evaluation) -> Empty`
- `Decide(Decision) -> Empty`
- `Abort(AbortRequest) -> Empty`

`Empty` is `sw4rm.common.Empty` (no fields).

### NegotiationOpen fields

| Field | Type | Description |
|-------|------|-------------|
| `negotiation_id` | string | Unique negotiation identifier |
| `correlation_id` | string | Links the negotiation to a larger workflow |
| `topic` | string | Human-readable description of the decision |
| `participants` | list[string] | Agent IDs participating in the negotiation |
| `intensity` | `DebateIntensity` | Debate intensity (`LOWEST` .. `HIGHEST`) |
| `debate_timeout` | duration | Optional total negotiation timeout |

### Proposal / CounterProposal fields

| Field | Type | Description |
|-------|------|-------------|
| `negotiation_id` | string | Negotiation identifier |
| `from_agent` | string | Agent sending the proposal |
| `content_type` | string | Payload MIME type (for example, `application/json`) |
| `payload` | bytes | Proposal payload |

### Evaluation fields

| Field | Type | Description |
|-------|------|-------------|
| `negotiation_id` | string | Negotiation identifier |
| `from_agent` | string | Agent submitting the evaluation |
| `confidence_score` | double | Confidence score (0.0-1.0) |
| `notes` | string | Optional evaluation notes |

### Decision fields

| Field | Type | Description |
|-------|------|-------------|
| `negotiation_id` | string | Negotiation identifier |
| `decided_by` | string | Agent or policy making the final decision |
| `content_type` | string | Result MIME type |
| `result` | bytes | Final decision payload |

### AbortRequest fields

| Field | Type | Description |
|-------|------|-------------|
| `negotiation_id` | string | Negotiation identifier |
| `reason` | string | Optional abort reason |

## 6.13.2. Constructors

### Python

`NegotiationClient(channel: grpc.Channel)`

- `channel`: A gRPC channel connected to the NegotiationService endpoint (default port: 50064).

### JavaScript/TypeScript

`new NegotiationClient(options: ClientOptions)`

- `options.address`: `host:port` for the NegotiationService endpoint.
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`NegotiationClient::new(endpoint: &str) -> Result<NegotiationClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:50064`).

## 6.13.3. Key Methods

### `open`

**Python**
`open(negotiation_id: str, correlation_id: str, topic: str, participants: list[str], intensity: int = 0, debate_timeout_seconds: int | None = None) -> Empty`

**JavaScript/TypeScript**
`open(req: NegotiationOpen): Promise<Empty>`

**Rust**
`open(&mut self, negotiation_id: &str, correlation_id: &str, topic: &str, participants: Vec<String>, intensity: DebateIntensity, debate_timeout: Option<std::time::Duration>) -> Result<()>`

**Parameters**

| Parameter | Type | Description |
|-----------|------|-------------|
| `negotiation_id` | string | Unique negotiation identifier |
| `correlation_id` | string | Workflow correlation identifier |
| `topic` | string | Description of the negotiation |
| `participants` | list[string] | Participating agent IDs |
| `intensity` | int/enum | Debate intensity (`LOWEST` .. `HIGHEST`) |
| `debate_timeout_seconds` | int | Optional timeout in seconds |

### `propose`

**Python**
`propose(negotiation_id: str, from_agent: str, content_type: str, payload: bytes) -> Empty`

**JavaScript/TypeScript**
`propose(req: Proposal): Promise<Empty>`

**Rust**
`propose(&mut self, negotiation_id: &str, from_agent: &str, content_type: &str, payload: Vec<u8>) -> Result<()>`

### `counter`

**Python**
`counter(negotiation_id: str, from_agent: str, content_type: str, payload: bytes) -> Empty`

**JavaScript/TypeScript**
`counter(req: CounterProposal): Promise<Empty>`

**Rust**
`counter(&mut self, negotiation_id: &str, from_agent: &str, content_type: &str, payload: Vec<u8>) -> Result<()>`

### `evaluate`

**Python**
`evaluate(negotiation_id: str, from_agent: str, confidence_score: float | None = None, notes: str = "") -> Empty`

**JavaScript/TypeScript**
`evaluate(req: Evaluation): Promise<Empty>`

**Rust**
`evaluate(&mut self, negotiation_id: &str, from_agent: &str, confidence_score: f64, notes: &str) -> Result<()>`

### `decide`

**Python**
`decide(negotiation_id: str, decided_by: str, content_type: str, result: bytes) -> Empty`

**JavaScript/TypeScript**
`decide(req: Decision): Promise<Empty>`

**Rust**
`decide(&mut self, negotiation_id: &str, decided_by: &str, content_type: &str, result: Vec<u8>) -> Result<()>`

### `abort`

**Python**
`abort(negotiation_id: str, reason: str = "") -> Empty`

**JavaScript/TypeScript**
`abort(req: AbortRequest): Promise<Empty>`

**Rust**
`abort(&mut self, negotiation_id: &str, reason: &str) -> Result<()>`

## 6.13.4. Usage Examples

=== "Python"
    ```python
    import grpc
    from sw4rm.clients import NegotiationClient

    channel = grpc.insecure_channel("localhost:50064")
    client = NegotiationClient(channel)

    client.open(
        negotiation_id="neg-design-001",
        correlation_id="workflow-123",
        topic="API Design Review",
        participants=["architect-1", "security-agent", "reviewer-1"],
        intensity=3,
        debate_timeout_seconds=300,
    )

    client.propose(
        negotiation_id="neg-design-001",
        from_agent="architect-1",
        content_type="application/json",
        payload=b'{"endpoint": "/api/v2/users", "method": "POST"}',
    )

    client.evaluate(
        negotiation_id="neg-design-001",
        from_agent="reviewer-1",
        confidence_score=0.85,
        notes="Looks good with auth requirement",
    )

    client.decide(
        negotiation_id="neg-design-001",
        decided_by="architect-1",
        content_type="application/json",
        result=b'{"endpoint": "/api/v2/users", "method": "POST", "auth": "required"}',
    )
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { NegotiationClient } from '@sw4rm/js-sdk';

    const client = new NegotiationClient({ address: 'localhost:50064' });

    await client.open({
      negotiation_id: 'neg-design-001',
      correlation_id: 'workflow-123',
      topic: 'API Design Review',
      participants: ['architect-1', 'security-agent', 'reviewer-1'],
      intensity: 'MEDIUM',
      debate_timeout: { seconds: 300 },
    });

    await client.propose({
      negotiation_id: 'neg-design-001',
      from_agent: 'architect-1',
      content_type: 'application/json',
      payload: new TextEncoder().encode('{"endpoint": "/api/v2/users", "method": "POST"}'),
    });

    await client.evaluate({
      negotiation_id: 'neg-design-001',
      from_agent: 'reviewer-1',
      confidence_score: 0.85,
      notes: 'Looks good with auth requirement',
    });

    await client.decide({
      negotiation_id: 'neg-design-001',
      decided_by: 'architect-1',
      content_type: 'application/json',
      result: new TextEncoder().encode('{"endpoint": "/api/v2/users", "method": "POST", "auth": "required"}'),
    });
    ```

=== "Rust"
    ```rust
    use std::time::Duration;
    use sw4rm_sdk::clients::NegotiationClient;
    use sw4rm_sdk::proto::sw4rm::common::DebateIntensity;

    #[tokio::main]
    async fn main() -> sw4rm_sdk::Result<()> {
        let mut client = NegotiationClient::new("http://localhost:50064").await?;

        client
            .open(
                "neg-design-001",
                "workflow-123",
                "API Design Review",
                vec![
                    "architect-1".to_string(),
                    "security-agent".to_string(),
                    "reviewer-1".to_string(),
                ],
                DebateIntensity::Medium,
                Some(Duration::from_secs(300)),
            )
            .await?;

        client
            .propose(
                "neg-design-001",
                "architect-1",
                "application/json",
                br#"{"endpoint": "/api/v2/users", "method": "POST"}"#.to_vec(),
            )
            .await?;

        client
            .evaluate("neg-design-001", "reviewer-1", 0.85, "Looks good with auth requirement")
            .await?;

        client
            .decide(
                "neg-design-001",
                "architect-1",
                "application/json",
                br#"{"endpoint": "/api/v2/users", "method": "POST", "auth": "required"}"#.to_vec(),
            )
            .await?;

        Ok(())
    }
    ```

## 6.13.5. Error Handling

- Python raises `RuntimeError` if protobuf stubs are missing. Run `make protos`.
