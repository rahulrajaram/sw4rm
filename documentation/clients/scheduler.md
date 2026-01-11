# 6.4. Scheduler Client

The Scheduler Client talks to the `sw4rm.scheduler.SchedulerService` service. Use it to:

- Submit tasks for scheduling and execution.
- Preempt running tasks when priorities change.
- Request graceful agent shutdowns.
- Inspect and purge the activity buffer for an agent.

## 6.4.1. Service Overview

The service exposes five RPCs:

- `SubmitTask(SubmitTaskRequest) -> SubmitTaskResponse`
- `RequestPreemption(PreemptRequest) -> PreemptResponse`
- `ShutdownAgent(ShutdownAgentRequest) -> ShutdownAgentResponse`
- `PollActivityBuffer(PollActivityBufferRequest) -> PollActivityBufferResponse`
- `PurgeActivity(PurgeActivityRequest) -> PurgeActivityResponse`

### SubmitTaskResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `accepted` | bool | Whether the scheduler accepted the task |
| `reason` | string | Optional rejection reason |

### PreemptResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `enqueued` | bool | Whether the preemption request was queued |

### ShutdownAgentResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `ok` | bool | Whether the shutdown request was accepted |

### ActivityEntry fields

| Field | Type | Description |
|-------|------|-------------|
| `task_id` | string | Task identifier |
| `repo_id` | string | Repository identifier |
| `worktree_id` | string | Worktree identifier |
| `branch` | string | Branch name |
| `description` | string | Task description |
| `timestamp` | string | ISO-8601 timestamp |

### PurgeActivityResponse fields

| Field | Type | Description |
|-------|------|-------------|
| `purged` | uint32 | Number of activity entries purged |

## 6.4.2. Constructors

### Python

`SchedulerClient(channel: grpc.Channel)`

- `channel`: A gRPC channel connected to the SchedulerService endpoint (default port: 50053).

### JavaScript/TypeScript

`new SchedulerClient(options: ClientOptions)`

- `options.address`: `host:port` for the SchedulerService endpoint.
- Optional: `deadlineMs`, `retry`, `userAgent`, `interceptors`, `errorMapper`.

### Rust

`SchedulerClient::new(endpoint: &str) -> Result<SchedulerClient>`

- `endpoint`: Full gRPC URL (for example, `http://host:50053`).

## 6.4.3. Key Methods

### `submit_task` / `submitTask`

**Python**
`submit_task(agent_id: str, task_id: str, priority: int = 0, scope: str = "", params: bytes = b"", content_type: str = "application/json") -> SubmitTaskResponse`

**JavaScript/TypeScript**
`submitTask(req: SubmitTaskRequest): Promise<{ accepted: boolean; reason?: string }>`

**Rust**
`submit_task(&mut self, task_id: &str, agent_id: &str, priority: i32, params: Vec<u8>, content_type: &str, scope: &str) -> Result<()>`

**Parameters**

| Parameter | Type | Description |
|-----------|------|-------------|
| `agent_id` | string | Agent to schedule the task on |
| `task_id` | string | Unique task identifier |
| `priority` | int | Priority in range `-19..20` (higher = more important) |
| `scope` | string | Resource scope descriptor for conflict detection |
| `params` | bytes | Task parameters payload |
| `content_type` | string | MIME type for `params` |

### `request_preemption` / `requestPreemption`

**Python**
`request_preemption(agent_id: str, task_id: str, reason: str = "") -> PreemptResponse`

**JavaScript/TypeScript**
`requestPreemption(agentId: string, taskId: string, reason?: string): Promise<{ enqueued: boolean }>`

**Rust**
`request_preemption(&mut self, agent_id: &str, task_id: &str, reason: &str) -> Result<()>`

**Response fields**

- `enqueued` (bool): Whether the preemption request was queued.

### `shutdown_agent` / `shutdownAgent`

**Python**
`shutdown_agent(agent_id: str, grace_period: Optional[timedelta] = None) -> ShutdownAgentResponse`

**JavaScript/TypeScript**
`shutdownAgent(agentId: string, graceMs: number): Promise<{ ok: boolean }>`

**Rust**
`shutdown_agent(&mut self, agent_id: &str, grace_period: Option<std::time::Duration>) -> Result<()>`

**Response fields**

- `ok` (bool): Whether the shutdown request was accepted.

### `poll_activity_buffer` / `pollActivityBuffer`

**Python**
`poll_activity_buffer(agent_id: str) -> PollActivityBufferResponse`

**JavaScript/TypeScript**
`pollActivityBuffer(agentId: string): Promise<ActivityEntry[]>`

**Rust**
`get_activity_buffer(&mut self, agent_id: &str) -> Result<Vec<ActivityEntry>>`

### `purge_activity` / `purgeActivity`

**Python**
`purge_activity(agent_id: str, task_ids: list[str]) -> PurgeActivityResponse`

**JavaScript/TypeScript**
`purgeActivity(agentId: string, taskIds: string[]): Promise<number>`

**Rust**
`purge_activities(&mut self, agent_id: &str, task_ids: Vec<String>) -> Result<u32>`

## 6.4.4. Usage Examples

=== "Python"
    ```python
    import grpc
    from datetime import timedelta
    from sw4rm.clients import SchedulerClient

    channel = grpc.insecure_channel("localhost:50053")
    scheduler = SchedulerClient(channel)

    response = scheduler.submit_task(
        agent_id="worker-1",
        task_id="task-123",
        priority=5,
        scope="global.resource",
        params=b'{"action": "process"}',
        content_type="application/json",
    )
    print("accepted:", response.accepted, "reason:", response.reason)

    scheduler.request_preemption(
        agent_id="worker-1",
        task_id="task-123",
        reason="Higher priority task arrived",
    )

    activities = scheduler.poll_activity_buffer(agent_id="worker-1")
    for entry in activities.entries:
        print(entry.task_id, entry.description)

    scheduler.purge_activity(
        agent_id="worker-1",
        task_ids=["task-123"],
    )

    scheduler.shutdown_agent(
        agent_id="worker-1",
        grace_period=timedelta(seconds=30),
    )
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { SchedulerClient } from '@sw4rm/js-sdk';

    const scheduler = new SchedulerClient({ address: 'localhost:50053' });

    const submit = await scheduler.submitTask({
      agent_id: 'worker-1',
      task_id: 'task-123',
      priority: 5,
      scope: 'global.resource',
      params: new TextEncoder().encode(JSON.stringify({ action: 'process' })),
      content_type: 'application/json',
    });
    console.log('accepted:', submit.accepted, submit.reason);

    await scheduler.requestPreemption('worker-1', 'task-123', 'Higher priority task');
    const entries = await scheduler.pollActivityBuffer('worker-1');
    console.log('entries:', entries.length);

    const purged = await scheduler.purgeActivity('worker-1', ['task-123']);
    console.log('purged:', purged);

    await scheduler.shutdownAgent('worker-1', 30_000);
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::clients::SchedulerClient;
    use std::time::Duration;

    #[tokio::main]
    async fn main() -> sw4rm_sdk::Result<()> {
        let mut scheduler = SchedulerClient::new("http://localhost:50053").await?;

        scheduler
            .submit_task(
                "task-123",
                "worker-1",
                5,
                br#"{"action":"process"}"#.to_vec(),
                "application/json",
                "global.resource",
            )
            .await?;

        scheduler
            .request_preemption("worker-1", "task-123", "Higher priority task")
            .await?;

        let entries = scheduler.get_activity_buffer("worker-1").await?;
        println!("entries: {}", entries.len());

        let purged = scheduler
            .purge_activities("worker-1", vec!["task-123".to_string()])
            .await?;
        println!("purged: {}", purged);

        scheduler
            .shutdown_agent("worker-1", Some(Duration::from_secs(30)))
            .await?;

        Ok(())
    }
    ```

> **Tip:** If you see `RuntimeError: Protobuf stubs not generated`, run:

```bash
make protos
```
