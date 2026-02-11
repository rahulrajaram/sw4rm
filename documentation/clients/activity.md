# 6.6. Activity Client

The Activity Client talks to the `sw4rm.activity.ActivityService` service. Use it to:

- Append artifacts generated during negotiations or agent workflows.
- List and retrieve artifacts by negotiation ID and kind.

## 6.6.1. Service Overview

The service exposes two RPCs:

- `AppendArtifact(AppendArtifactRequest) -> AppendArtifactResponse`
- `ListArtifacts(ListArtifactsRequest) -> ListArtifactsResponse`

Artifacts are structured records that capture outputs from negotiations, debates, and workflows. Each artifact is associated with a negotiation ID and categorized by kind.

### Artifact Kinds

| Kind | Description |
|------|-------------|
| `contract` | Finalized agreement or policy document |
| `diff` | Change comparison between versions |
| `decision` | Recorded decision point |
| `score` | Evaluation or rating |
| `note` | Freeform annotation |

## 6.6.2. Constructors

### Python

`ActivityClient(channel: grpc.Channel)`

- `channel`: A gRPC channel connected to the ActivityService endpoint (default port: 50061).

### JavaScript/TypeScript

`new ActivityClient(options: ClientOptions)`

- `options.address`: `host:port` for the ActivityService endpoint.
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`ActivityClient::new(endpoint: &str) -> Result<ActivityClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:50061`).

## 6.6.3. Key Methods

### `append_artifact`

Appends a new artifact to the activity log.

**Python**
`append_artifact(negotiation_id: str, kind: str, version: str, content_type: str, content: bytes, created_at: str) -> AppendArtifactResponse`

**Rust**
`append_artifact(negotiation_id: &str, kind: &str, version: &str, content_type: &str, content: &[u8], created_at: &str) -> Result<AppendArtifactResponse>`

**Parameters**

| Parameter | Type | Description |
|-----------|------|-------------|
| `negotiation_id` | string | The negotiation or session this artifact belongs to |
| `kind` | string | Artifact kind: `contract`, `diff`, `decision`, `score`, or `note` |
| `version` | string | Version identifier (for example, `v1`, `v2`) |
| `content_type` | string | MIME type (for example, `application/json`, `text/plain`) |
| `content` | bytes | Binary content of the artifact |
| `created_at` | string | ISO-8601 timestamp |

**Response fields**

- `ok` (bool): Whether the append succeeded.
- `reason` (string): Explanation if `ok` is false.

### `list_artifacts`

Lists artifacts for a given negotiation, optionally filtered by kind.

**Python**
`list_artifacts(negotiation_id: str, kind: str | None = None) -> ListArtifactsResponse`

**Rust**
`list_artifacts(negotiation_id: &str, kind: Option<&str>) -> Result<ListArtifactsResponse>`

**Parameters**

| Parameter | Type | Description |
|-----------|------|-------------|
| `negotiation_id` | string | The negotiation or session to query |
| `kind` | string (optional) | Filter by artifact kind |

**Response fields**

- `items` (list[Artifact]): List of matching artifacts.

## 6.6.4. Usage Examples

=== "Python"
    ```python
    import grpc
    from sw4rm.clients import ActivityClient
    from datetime import datetime

    channel = grpc.insecure_channel("localhost:50061")
    client = ActivityClient(channel)

    # Append a decision artifact
    response = client.append_artifact(
        negotiation_id="neg-001",
        kind="decision",
        version="v1",
        content_type="application/json",
        content=b'{"approved": true, "by": "coordinator"}',
        created_at=datetime.utcnow().isoformat() + "Z",
    )
    print(f"Append succeeded: {response.ok}")

    # Append a contract artifact
    contract_content = b"""
    ## Agreement
    - All parties accept the proposed solution.
    - Implementation deadline: 2026-02-15.
    """
    response = client.append_artifact(
        negotiation_id="neg-001",
        kind="contract",
        version="v1",
        content_type="text/markdown",
        content=contract_content,
        created_at=datetime.utcnow().isoformat() + "Z",
    )

    # List all artifacts for the negotiation
    artifacts = client.list_artifacts(negotiation_id="neg-001")
    for artifact in artifacts.items:
        print(f"{artifact.kind} v{artifact.version}: {len(artifact.content)} bytes")

    # Filter by kind
    decisions = client.list_artifacts(negotiation_id="neg-001", kind="decision")
    print(f"Found {len(decisions.items)} decision artifacts")
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::clients::ActivityClient;
    use chrono::Utc;

    #[tokio::main]
    async fn main() -> sw4rm_sdk::Result<()> {
        let mut client = ActivityClient::new("http://localhost:50061").await?;

        // Append a decision artifact
        let response = client
            .append_artifact(
                "neg-001",
                "decision",
                "v1",
                "application/json",
                br#"{"approved": true, "by": "coordinator"}"#,
                &Utc::now().to_rfc3339(),
            )
            .await?;
        println!("Append succeeded: {}", response.ok);

        // List all artifacts
        let artifacts = client.list_artifacts("neg-001", None).await?;
        for artifact in artifacts.items {
            println!("{} v{}: {} bytes", artifact.kind, artifact.version, artifact.content.len());
        }

        // Filter by kind
        let decisions = client.list_artifacts("neg-001", Some("decision")).await?;
        println!("Found {} decision artifacts", decisions.items.len());

        Ok(())
    }
    ```

## 6.6.5. Integration with Negotiation Room

The ActivityClient works closely with the Negotiation Room pattern. During negotiations:

1. **Producers** submit proposals that may generate `diff` artifacts.
2. **Critics** provide evaluations recorded as `score` artifacts.
3. **Coordinators** finalize agreements as `contract` artifacts.
4. Any participant can add `note` artifacts for context.

```python
# Example: Recording negotiation progression
from sw4rm.clients import ActivityClient, NegotiationRoomClient

# After a negotiation round concludes
activity = ActivityClient(channel)
activity.append_artifact(
    negotiation_id=room.id,
    kind="score",
    version="round-3",
    content_type="application/json",
    content=json.dumps({
        "proposal_id": "prop-123",
        "critic_id": "critic-agent",
        "score": 0.85,
        "rationale": "Meets requirements with minor concerns"
    }).encode(),
    created_at=datetime.utcnow().isoformat() + "Z",
)
```

## Working Examples

For complete runnable examples demonstrating Activity usage:

- [:simple-rust: Rust activity demo](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/rust_sdk/examples/activity_demo.rs)

## 6.6.6. Error Handling

- Python raises `RuntimeError` if protobuf stubs are missing. Run `make protos` to generate them.
- If `append_artifact` returns `ok=False`, check the `reason` field for details.
- JavaScript/TypeScript methods reject with gRPC errors (wrapped as `Sw4rmError`).
- Rust returns `Result<T>`; handle transport errors and status codes via `?`.

## 6.6.7. Related Concepts

- [Negotiation Room Pattern](../protocol/advanced-patterns.md) - Multi-agent coordination using artifacts
- [ACK Lifecycle](../protocol/acks.md) - Message acknowledgment stages
- [Three-ID Model](../protocol/advanced-patterns.md) - Message identity and deduplication
