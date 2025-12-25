# 2.6 Persistence and State Management

This guide covers persistence options, recovery patterns, and state management strategies for building resilient SW4RM agents.

## 2.6.1 Overview

SW4RM agents maintain two primary types of persistent state:

| State Type | Purpose | Default Backend |
|------------|---------|-----------------|
| **Activity Buffer** | Message processing history and deduplication | JSON file |
| **Worktree State** | Git repository bindings and workspace context | JSON file |

## 2.6.2 Persistence Backends

### JSON File Backend (Development)

The default backend stores state as JSON files on disk. Use this backend for development and single-agent deployments.

```python
from sw4rm.activity_buffer import PersistentActivityBuffer
from sw4rm.persistence import JSONFilePersistence

# Configure file-based persistence
persistence = JSONFilePersistence(
    base_path="/var/lib/sw4rm/state",
    agent_id="my-agent-001"
)

buffer = PersistentActivityBuffer(
    persistence=persistence,
    max_entries=10000,      # Maximum buffered messages
    retention_hours=168     # 7 days
)
```

**File Structure:**
```
/var/lib/sw4rm/state/
  my-agent-001/
    activity_buffer.json
    worktree_state.json
    checkpoints/
      checkpoint_2025-12-24T10-30-00.json
```

### Redis Backend (Production)

Use Redis for distributed state management in multi-instance deployments.

```python
from sw4rm.persistence import RedisPersistence

persistence = RedisPersistence(
    host="redis.example.com",
    port=6379,
    password="secret",
    db=0,
    key_prefix="sw4rm:agent:"
)

buffer = PersistentActivityBuffer(
    persistence=persistence,
    max_entries=50000,
    retention_hours=168
)
```

**Redis Key Structure:**
```
sw4rm:agent:my-agent-001:activity_buffer
sw4rm:agent:my-agent-001:worktree_state
sw4rm:agent:my-agent-001:idempotency:{token}
```

### PostgreSQL Backend (Enterprise)

Use PostgreSQL for ACID-compliant persistence with advanced query capabilities.

```python
from sw4rm.persistence import PostgresPersistence

persistence = PostgresPersistence(
    connection_string="postgresql://user:pass@db.example.com:5432/sw4rm",
    schema="sw4rm_agents",
    pool_size=5
)
```

**Schema:**
```sql
CREATE TABLE activity_buffer (
    id SERIAL PRIMARY KEY,
    agent_id VARCHAR(255) NOT NULL,
    message_id VARCHAR(36) NOT NULL UNIQUE,
    envelope JSONB NOT NULL,
    status VARCHAR(20) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_activity_agent_status ON activity_buffer(agent_id, status);
CREATE INDEX idx_activity_created ON activity_buffer(created_at);
```

## 2.6.3 Activity Buffer Configuration

### Buffer Limits

You configure buffer size and overflow behavior using the following parameters:

```python
buffer = PersistentActivityBuffer(
    persistence=persistence,
    max_entries=10000,          # Maximum messages to retain
    retention_hours=168,        # Automatic cleanup after 7 days
    overflow_policy="drop_oldest",  # or "reject_new"
    checkpoint_interval=300     # Checkpoint every 5 minutes
)
```

### Overflow Policies

| Policy | Behavior |
|--------|----------|
| `drop_oldest` | The buffer removes the oldest entries when the limit is reached. |
| `reject_new` | The buffer rejects new messages with a `BUFFER_FULL` error. |

## 2.6.4 Message Deduplication

### Idempotency Token Processing

The activity buffer deduplicates messages using `idempotency_token`:

```python
# First attempt - processed normally
result = await buffer.process_message(envelope1)
# result.status = PROCESSED

# Retry with same idempotency_token - detected as duplicate
result = await buffer.process_message(envelope2)  # Same token
# result.status = DUPLICATE_DETECTED
```

### Deduplication Window

You set the time window for duplicate detection using `dedup_window_seconds`:

```python
buffer = PersistentActivityBuffer(
    persistence=persistence,
    dedup_window_seconds=3600,  # 1 hour (default)
)
```

### Fingerprint-Based Deduplication

The buffer uses SHA-256 fingerprinting for messages without explicit idempotency tokens. The fingerprint enables content-based deduplication:

```python
from sw4rm.activity_buffer import compute_fingerprint

# Fingerprint based on producer, correlation, and payload hash
fingerprint = compute_fingerprint(envelope)
```

## 2.6.5 Crash Recovery

### Recovery Flow

When an agent restarts after a crash, the activity buffer reconciles state. The following diagram shows the recovery sequence:

```mermaid
sequenceDiagram
    participant A as Agent (Restarting)
    participant P as Persistence
    participant R as Router

    A->>P: Load persisted state
    P-->>A: Activity buffer entries

    A->>A: Identify incomplete messages
    Note over A: Status = RECEIVED or READ

    A->>R: Re-request incomplete messages
    R-->>A: Message replay

    A->>A: Resume processing
    A->>P: Update state
```

### Recovery Configuration

```python
from sw4rm.activity_buffer import RecoveryConfig

recovery = RecoveryConfig(
    enable_crash_recovery=True,
    recovery_timeout_seconds=60,
    max_recovery_attempts=3,
    reconciliation_strategy="timestamp",  # or "vector_clock", "sequence"
    replay_incomplete=True  # Re-request messages in RECEIVED/READ state
)

buffer = PersistentActivityBuffer(
    persistence=persistence,
    recovery_config=recovery
)
```

### Reconciliation Strategies

| Strategy | Description | Use Case |
|----------|-------------|----------|
| `timestamp` | The buffer orders messages by timestamp. | Use when clocks are synchronized. |
| `sequence` | The buffer orders messages by sequence number. | Use for single-source ordering. |
| `vector_clock` | The buffer orders messages causally. | Use for distributed multi-agent systems. |

## 2.6.6 Worktree State Persistence

### Persisting Git Context

Use `PersistentWorktreeState` to track repository bindings across restarts:

```python
from sw4rm.worktree_state import PersistentWorktreeState

worktree = PersistentWorktreeState(
    persistence=persistence,
    cleanup_on_unbind=True,     # Remove worktree files on unbind
    validate_on_restore=True    # Verify repo state on recovery
)

# Bind to a repository
await worktree.bind(
    repo_url="https://github.com/org/repo.git",
    branch="main",
    worktree_path="/workspace/repo"
)

# State is automatically persisted
# On restart, worktree.restore() reloads bindings
```

### Worktree Lifecycle

```python
# Check current bindings
bindings = await worktree.list_bindings()
for binding in bindings:
    print(f"{binding.repo_url} -> {binding.worktree_path}")

# Switch branch (preserves state)
await worktree.switch_branch("feature/new-feature")

# Unbind and cleanup
await worktree.unbind(worktree_path="/workspace/repo")
```

## 2.6.7 Checkpointing

### Automatic Checkpoints

You enable periodic state snapshots for faster recovery using the following configuration:

```python
buffer = PersistentActivityBuffer(
    persistence=persistence,
    checkpoint_interval=300,     # Checkpoint every 5 minutes
    max_checkpoints=10,          # Keep last 10 checkpoints
    checkpoint_compression=True  # Compress checkpoint files
)
```

### Manual Checkpoints

You create explicit checkpoints at safe points using `create_checkpoint`:

```python
# Create named checkpoint
checkpoint_id = await buffer.create_checkpoint(
    name="pre-migration",
    metadata={"version": "1.2.3"}
)

# Restore from checkpoint if needed
await buffer.restore_checkpoint(checkpoint_id)
```

## 2.6.8 Multi-Instance Coordination

When you run multiple agent instances, use distributed locking to coordinate access:

```python
from sw4rm.persistence import DistributedLock

async with DistributedLock(
    persistence=redis_persistence,
    resource="agent:task-123",
    timeout_seconds=30
):
    # Exclusive access to task
    await process_task()
```

## 2.6.9 Retention and Cleanup

### Automatic Cleanup

You configure retention policies for automatic data expiration using the following parameters:

```python
buffer = PersistentActivityBuffer(
    persistence=persistence,
    retention_hours=168,         # Delete entries older than 7 days
    cleanup_interval=3600,       # Run cleanup every hour
    cleanup_batch_size=1000      # Delete 1000 entries per batch
)
```

### Manual Cleanup

```python
# Remove entries older than specified time
deleted_count = await buffer.cleanup(
    older_than_hours=24,
    status_filter=["FULFILLED", "FAILED"]  # Only completed messages
)
```

## 2.6.10 Monitoring and Diagnostics

### Health Checks

```python
# Check persistence health
health = await persistence.health_check()
print(f"Backend: {health.backend_type}")
print(f"Connected: {health.connected}")
print(f"Latency: {health.latency_ms}ms")

# Check buffer statistics
stats = buffer.get_statistics()
print(f"Total entries: {stats.total_entries}")
print(f"Pending: {stats.pending_count}")
print(f"Duplicates detected: {stats.duplicate_count}")
```

### Metrics Export

The persistence layer exports Prometheus-compatible metrics. The following example shows the available metrics:

```
# HELP sw4rm_activity_buffer_entries Current buffer entry count
# TYPE sw4rm_activity_buffer_entries gauge
sw4rm_activity_buffer_entries{agent_id="my-agent",status="pending"} 42

# HELP sw4rm_persistence_operations_total Total persistence operations
# TYPE sw4rm_persistence_operations_total counter
sw4rm_persistence_operations_total{operation="write",backend="redis"} 15234
```

## 2.6.11 Best Practices

### Development

- Use the JSON file backend for local development.
- Set short retention periods of 1-2 hours.
- Enable verbose logging for debugging.

### Production

- Use Redis or PostgreSQL for distributed deployments.
- Configure buffer limits based on expected message volume.
- Enable checkpointing for faster recovery.
- Monitor buffer health and latency metrics.
- Set up alerts for buffer overflow conditions.

### Security

- Encrypt sensitive payload data before persistence.
- Use TLS for Redis and PostgreSQL connections.
- Implement access control on persistence backends.
- Audit persistence access in compliance environments.

---

## See Also

- [First Agent Tutorial](first-agent.md) - Basic agent implementation
- [Installation Guide](installation.md) - Environment setup
- [ACK Lifecycle](../protocol/acks.md) - Message acknowledgment patterns
