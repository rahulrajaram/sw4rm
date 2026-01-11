# 6.17. Worktree Client

The Worktree Client talks to the `sw4rm.worktree.WorktreeService` service. Use it to:

- Bind agents to repository worktrees for file system access.
- Request temporary worktree switches with optional HITL approval.
- Approve or reject pending switch requests.
- Query current binding state and unbind when work is complete.

Worktree bindings follow a simple state machine:

- `UNBOUND` -> `BOUND_HOME` via `bind`.
- `BOUND_HOME` -> `SWITCH_PENDING` via `request_switch`.
- `SWITCH_PENDING` -> `BOUND_NON_HOME` via `approve_switch`.
- `SWITCH_PENDING` -> `BOUND_HOME` via `reject_switch`.
- Any state -> `UNBOUND` via `unbind`.

## 6.17.1. Service Overview

The service exposes six RPCs:

- `Bind(BindRequest) -> BindResponse`
- `Unbind(UnbindRequest) -> UnbindResponse`
- `RequestSwitch(SwitchRequest) -> StatusResponse`
- `ApproveSwitch(SwitchApprove) -> StatusResponse`
- `RejectSwitch(SwitchReject) -> StatusResponse`
- `Status(StatusRequest) -> StatusResponse`

### Worktree state values

| Value | Description |
|-------|-------------|
| `UNBOUND` | Agent has no worktree binding. |
| `BOUND_HOME` | Agent is bound to its home worktree. |
| `SWITCH_PENDING` | Switch requested, awaiting approval. |
| `BOUND_NON_HOME` | Agent is bound to a non-home worktree. |
| `BIND_FAILED` | Last bind attempt failed. |

### BindRequest fields

| Field | Type | Description |
|-------|------|-------------|
| `agent_id` | string | Agent identifier to bind. |
| `repo_id` | string | Repository identifier containing the worktree. |
| `worktree_id` | string | Worktree identifier (becomes the home worktree). |

### BindResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `ok` | bool | Whether the bind succeeded. |
| `reason` | string | Optional failure reason. |

### UnbindRequest fields

| Field | Type | Description |
|-------|------|-------------|
| `agent_id` | string | Agent identifier to unbind. |

### UnbindResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `ok` | bool | Whether the unbind succeeded. |

### SwitchRequest fields

| Field | Type | Description |
|-------|------|-------------|
| `agent_id` | string | Agent identifier requesting the switch. |
| `target_worktree_id` | string | Worktree identifier to switch to. |
| `requires_hitl` | bool | Whether human approval is required. |

### SwitchApprove fields

| Field | Type | Description |
|-------|------|-------------|
| `agent_id` | string | Agent identifier being approved. |
| `target_worktree_id` | string | Worktree identifier to switch to. |
| `ttl_ms` | uint64 | Time-to-live for the non-home binding. |

### SwitchReject fields

| Field | Type | Description |
|-------|------|-------------|
| `agent_id` | string | Agent identifier being rejected. |
| `reason` | string | Optional human-readable reason. |

### StatusResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `repo_id` | string | Repository identifier for the active binding. |
| `worktree_id` | string | Active worktree identifier. |
| `state` | string | Current worktree state. |

## 6.17.2. Constructors

### Python

`WorktreeClient(channel: grpc.Channel)`

- `channel`: A gRPC channel connected to the WorktreeService endpoint (default port: 50062).

### JavaScript/TypeScript

`new WorktreeClient(options: ClientOptions)`

- `options.address`: `host:port` for the WorktreeService endpoint (default port: 50062).
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`WorktreeClient::new(endpoint: &str) -> Result<WorktreeClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:50062`).

## 6.17.3. Key Methods

### `bind` / `bind_worktree`

**Python**
`bind(agent_id: str, repo_id: str, worktree_id: str) -> BindResponse`

**JavaScript/TypeScript**
`bind(agentId: string, repoId: string, worktreeId: string): Promise<{ ok: boolean; reason?: string }>`

**Rust**
`bind_worktree(&mut self, agent_id: &str, repo_id: &str, worktree_id: &str) -> Result<()>`

**Response fields**

- `ok` (bool): Whether the bind succeeded.
- `reason` (string): Optional failure reason.

### `unbind` / `unbind_worktree`

**Python**
`unbind(agent_id: str) -> UnbindResponse`

**JavaScript/TypeScript**
`unbind(agentId: string): Promise<boolean>`

**Rust**
`unbind_worktree(&mut self, agent_id: &str, worktree_id: &str) -> Result<()>`

### `request_switch` / `requestSwitch` / `switch_worktree`

**Python**
`request_switch(agent_id: str, target_worktree_id: str, requires_hitl: bool = False) -> StatusResponse`

**JavaScript/TypeScript**
`requestSwitch(agentId: string, targetWorktreeId: string, requiresHitl: boolean): Promise<{ state: string; repo_id?: string; worktree_id?: string }>`

**Rust**
`switch_worktree(&mut self, agent_id: &str, from_worktree_id: &str, to_worktree_id: &str) -> Result<()>`

**Response fields**

- `state` (string): Worktree state after the request.
- `repo_id` (string): Repository identifier (if available).
- `worktree_id` (string): Active worktree identifier (if available).

### `approve_switch` / `approveSwitch`

**Python**
`approve_switch(agent_id: str, target_worktree_id: str, ttl_ms: int) -> StatusResponse`

**JavaScript/TypeScript**
`approveSwitch(agentId: string, targetWorktreeId: string, ttlMs: number): Promise<string>`

### `reject_switch` / `rejectSwitch`

**Python**
`reject_switch(agent_id: str, reason: str = "") -> StatusResponse`

**JavaScript/TypeScript**
`rejectSwitch(agentId: string, reason?: string): Promise<string>`

### `status` / `worktree_status`

**Python**
`status(agent_id: str) -> StatusResponse`

**JavaScript/TypeScript**
`status(agentId: string): Promise<{ state: string; repo_id?: string; worktree_id?: string }>`

**Rust**
`worktree_status(&mut self, agent_id: &str) -> Result<WorktreeStatusResponse>`

### Policy hooks (JavaScript/TypeScript)

**JavaScript/TypeScript**
`setPolicy(policy: WorktreePolicyHook): void`

The default policy allows all binds, unbinds, and switches. Provide a custom
`WorktreePolicyHook` to enforce allowlists or environment rules.

## 6.17.4. Usage Examples

=== "Python"
    ```python
    import grpc
    from sw4rm.clients import WorktreeClient

    channel = grpc.insecure_channel("localhost:50062")
    client = WorktreeClient(channel)

    client.bind(agent_id="dev-agent-1", repo_id="repo-main", worktree_id="wt-feature-123")
    status = client.status(agent_id="dev-agent-1")
    print(status.state, status.worktree_id)

    client.request_switch(
        agent_id="dev-agent-1",
        target_worktree_id="wt-hotfix-456",
        requires_hitl=True,
    )
    client.approve_switch(
        agent_id="dev-agent-1",
        target_worktree_id="wt-hotfix-456",
        ttl_ms=300000,
    )
    client.unbind(agent_id="dev-agent-1")
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { WorktreeClient } from '@sw4rm/js-sdk';

    const client = new WorktreeClient({ address: 'localhost:50062' });

    await client.bind('dev-agent-1', 'repo-main', 'wt-feature-123');
    const status = await client.status('dev-agent-1');
    console.log(status.state, status.worktree_id);

    await client.requestSwitch('dev-agent-1', 'wt-hotfix-456', true);
    await client.approveSwitch('dev-agent-1', 'wt-hotfix-456', 300000);
    await client.unbind('dev-agent-1');
    ```

=== "Rust"
    ```rust
    use sw4rm::clients::WorktreeClient;

    let mut client = WorktreeClient::new("http://localhost:50062").await?;
    client.bind_worktree("dev-agent-1", "repo-main", "wt-feature-123").await?;
    let status = client.worktree_status("dev-agent-1").await?;
    println!("{} {}", status.state, status.worktree_id);
    client.switch_worktree("dev-agent-1", "wt-feature-123", "wt-hotfix-456").await?;
    client.unbind_worktree("dev-agent-1", "wt-feature-123").await?;
    ```
