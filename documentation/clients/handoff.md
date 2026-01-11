# 6.11. Handoff Client

The Handoff Client talks to the `sw4rm.handoff.HandoffService` service. Use it to:

- Request agent-to-agent handoffs with context snapshots.
- Accept or reject pending handoffs.
- Query pending handoffs and handoff status.
- Mark handoffs complete (Python/Rust SDKs).

## 6.11.1. Service Overview

The service exposes five RPCs:

- `RequestHandoff(HandoffRequest) -> Empty`
- `AcceptHandoff(HandoffResponse) -> Empty`
- `RejectHandoff(HandoffResponse) -> Empty`
- `GetPendingHandoffs(GetPendingHandoffsRequest) -> GetPendingHandoffsResponse`
- `CompleteHandoff(CompleteHandoffRequest) -> CompleteHandoffResponse`

Current SDKs provide an in-memory implementation for development and testing.

### HandoffStatus values

| Value | Description |
|-------|-------------|
| `PENDING` | Awaiting acceptance or rejection |
| `ACCEPTED` | Accepted by the target agent |
| `REJECTED` | Rejected by the target agent |
| `COMPLETED` | Completed by the receiving agent |
| `EXPIRED` | Timed out before acceptance |

### HandoffRequest fields

| Field | Type | Description |
|-------|------|-------------|
| `request_id` | string | Request identifier (JS/TS supplies this; Rust generates it) |
| `from_agent` | string | Initiating agent ID |
| `to_agent` | string | Target agent ID (may be empty for capability routing) |
| `reason` | string | Human-readable reason |
| `context_snapshot` | bytes | Serialized context for the receiving agent |
| `capabilities_required` | list[string] | Required capabilities for the target agent |
| `priority` | int | Priority (lower is higher priority) |
| `timeout` | duration | Timeout for acceptance (optional) |

### HandoffResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `request_id` | string | Request identifier being responded to |
| `accepted` | bool | Whether the handoff was accepted |
| `accepting_agent` | string | Agent that accepted the handoff |
| `rejection_reason` | string | Reason for rejection (if any) |

### GetPendingHandoffsResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `pending_requests` | list[HandoffRequest] | Pending requests for the agent |

### CompleteHandoffResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `success` | bool | Whether the completion was recorded |
| `message` | string | Optional message on completion |

## 6.11.2. Constructors

### Python

`HandoffClient(channel: grpc.Channel | None = None)`

- `channel`: Optional gRPC channel. If omitted, uses in-memory storage.

### JavaScript/TypeScript

`new HandoffClient()`

- In-memory client (no gRPC options yet).

### Rust

`HandoffClient::new() -> HandoffClient`

## 6.11.3. Key Methods

### `request_handoff` / `requestHandoff`

**Python**
`request_handoff(request: HandoffRequest) -> HandoffResponse`

**JavaScript/TypeScript**
`requestHandoff(request: HandoffRequest): Promise<HandoffResponse>`

**Rust**
`request_handoff(&self, request: HandoffRequest) -> Result<HandoffResponse>`

### `accept_handoff` / `acceptHandoff`

**Python**
`accept_handoff(handoff_id: str) -> HandoffResponse`

**JavaScript/TypeScript**
`acceptHandoff(handoffId: string): Promise<void>`

**Rust**
`accept_handoff(&self, handoff_id: &str) -> Result<()>`

### `reject_handoff` / `rejectHandoff`

**Python**
`reject_handoff(handoff_id: str, reason: str) -> HandoffResponse`

**JavaScript/TypeScript**
`rejectHandoff(handoffId: string, reason: string): Promise<void>`

**Rust**
`reject_handoff(&self, handoff_id: &str, reason: &str) -> Result<()>`

### `complete_handoff`

**Python**
`complete_handoff(handoff_id: str) -> HandoffResponse`

**Rust**
`complete_handoff(&self, handoff_id: &str) -> Result<()>`

### `get_pending_handoffs` / `getPendingHandoffs`

**Python**
`get_pending_handoffs(agent_id: str) -> list[HandoffRequest]`

**JavaScript/TypeScript**
`getPendingHandoffs(agentId: string): Promise<HandoffRequest[]>`

**Rust**
`get_pending_handoffs(&self, agent_id: &str) -> Result<Vec<HandoffRequest>>`

### `get_handoff_status` / `getHandoffResponse`

**Python**
`get_handoff_status(handoff_id: str) -> HandoffResponse | None`

**JavaScript/TypeScript**
`getHandoffResponse(handoffId: string): Promise<HandoffResponse | null>`

**Rust**
`get_handoff_status(&self, handoff_id: &str) -> Result<Option<HandoffResponse>>`

### `clear_all_handoffs`

**Python**
`clear_all_handoffs() -> None` (static, testing only)

**Rust**
`clear_all_handoffs(&self) -> Result<()>`

## 6.11.4. Usage Examples

=== "Python"
    ```python
    from sw4rm.clients import HandoffClient
    from sw4rm.handoff.types import HandoffRequest

    client = HandoffClient()

    request = HandoffRequest(
        from_agent="agent-a",
        to_agent="agent-b",
        reason="Need code review",
        capabilities_required=["code_review"],
    )

    response = client.request_handoff(request)
    print(response.handoff_id, response.status)

    pending = client.get_pending_handoffs("agent-b")
    if pending:
        accepted = client.accept_handoff(response.handoff_id)
        client.complete_handoff(accepted.handoff_id)
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { HandoffClient } from '@sw4rm/js-sdk';

    const client = new HandoffClient();

    const responsePromise = client.requestHandoff({
      requestId: 'handoff-123',
      fromAgent: 'agent-a',
      toAgent: 'agent-b',
      reason: 'Need code review',
      contextSnapshot: new TextEncoder().encode('{"state":"in_progress"}'),
      capabilitiesRequired: ['code_review'],
      priority: 5,
    });

    const pending = await client.getPendingHandoffs('agent-b');
    if (pending.length > 0) {
      await client.acceptHandoff(pending[0].requestId);
    }

    const response = await responsePromise;
    console.log(response.accepted, response.rejectionReason);
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::clients::handoff::{HandoffClient, HandoffRequest};

    let client = HandoffClient::new();
    let request = HandoffRequest::new(
        "agent-a".to_string(),
        "agent-b".to_string(),
        "Need code review".to_string(),
    )
    .with_capabilities(vec!["code_review".to_string()])
    .with_priority(5);

    let response = client.request_handoff(request)?;
    let pending = client.get_pending_handoffs("agent-b")?;
    if !pending.is_empty() {
        client.accept_handoff(&response.handoff_id)?;
        client.complete_handoff(&response.handoff_id)?;
    }
    ```

## 6.11.5. Error Handling

- Python raises `RuntimeError` if a gRPC stub is configured but unavailable.
- Python raises `ValueError` for missing handoff IDs or invalid state transitions.
- JavaScript/TypeScript throws `HandoffValidationError` for invalid requests and `HandoffTimeoutError` when a request times out.
- Rust returns `Error::Config` for invalid state transitions and `Error::Internal` for storage lock failures.
