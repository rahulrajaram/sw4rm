# SW4RM Agentic Protocol — Examples (Python SDK)

This directory contains examples demonstrating the SW4RM Agentic Protocol using the reference Python SDK.

## Prerequisites

1. **Install the SDK in development mode:**
   ```bash
   python -m pip install -e ".[dev]"
   ```

2. **Generate protocol buffer stubs:**
   ```bash
   make protos
   ```

3. **Have SW4RM services running** (Registry and Router services at the specified addresses)

## Examples

### 1. Echo Agent (`echo_agent.py`)

A minimal agent that demonstrates basic SDK usage:
- Agent registration and deregistration
- Message streaming
- Basic message echoing

**Usage:**
```bash
python examples/echo_agent.py --agent-id echo-1 --name EchoAgent \
  --router localhost:50051 --registry localhost:50052
```

**Features demonstrated:**
- `RegistryClient` and `RouterClient` usage
- Basic envelope creation
- Message streaming loop
- Signal handling for graceful shutdown

### 2. Advanced Agent (`advanced_agent.py`)

A comprehensive agent showcasing all major SDK features:
- **Persistent Activity Buffer**: Messages tracked across restarts
- **Worktree Management**: Policy-driven worktree binding with persistence
- **ACK Lifecycle**: Automatic acknowledgment handling
- **Message Processing**: Handler-based message routing
- **State Persistence**: All state preserved across restarts

**Usage:**
```bash
python examples/advanced_agent.py --agent-id advanced-1 --name AdvancedAgent \
  --router localhost:50051 --registry localhost:50052 \
  --data-dir ./agent_data
```

**Command-line options:**
- `--agent-id`: Agent identifier (default: advanced-1)
- `--name`: Agent display name (default: AdvancedAgent)  
- `--router`: Router service address (default: localhost:50051)
- `--registry`: Registry service address (default: localhost:50052)
- `--data-dir`: Directory for persistent data (default: ./agent_data)

**Features demonstrated:**
- `PersistentActivityBuffer` with JSON persistence
- `PersistentWorktreeState` with custom policy hooks
- `ACKLifecycleManager` for automatic ACK handling
- `MessageProcessor` with type-specific handlers
- Custom worktree policies with repository validation
- Graceful shutdown with state preservation
- Cross-restart state recovery

### 3. Test Client (`test_client.py`)

A client for testing agent functionality by sending various message types:
- DATA messages (basic processing)
- CONTROL messages (status, reconcile, worktree binding)
- WORKTREE_CONTROL messages (bind, unbind, status)
- Unknown message types (error handling)

**Usage:**
```bash
# Run all tests
python examples/test_client.py --router localhost:50051 --target-agent advanced-1

# Run specific test
python examples/test_client.py --test data --target-agent advanced-1

# Custom timing
python examples/test_client.py --delay 5.0 --target-agent advanced-1
```

**Available tests:**
- `data`: Send DATA message for echo processing
- `status`: Request agent status via CONTROL message
- `reconcile`: Trigger ACK reconciliation check
- `bind`: Bind to worktree via WORKTREE_CONTROL
- `worktree-status`: Get worktree status
- `control-bind`: Bind worktree via CONTROL message
- `unknown`: Send unknown message type
- `all`: Run all tests (default)

## Message Types and Handlers

The advanced agent demonstrates handling different message types:

### DATA Messages
Echo back with processing metadata:
```json
{
  "original_id": "msg-123",
  "processed_at": 1703123456,
  "agent_id": "advanced-1", 
  "payload_size": 256,
  "worktree": {"bound": true, "repo_id": "main-repo"}
}
```

### CONTROL Messages
Support various commands:
- `status`: Show agent state (activity buffer, worktree, uptime)
- `reconcile`: Check for stale ACKs needing attention
- `bind_worktree`: Bind to specified worktree

### WORKTREE_CONTROL Messages  
Direct worktree operations:
- `bind`: Bind to repo/worktree with metadata
- `unbind`: Release current binding
- `status`: Get current worktree status

## Persistence

The advanced agent uses persistent storage for:

### Activity Buffer (`agent_data/activity.json`)
Tracks all incoming/outgoing messages with ACK status:
```json
{
  "records": {
    "msg-123": {
      "message_id": "msg-123",
      "direction": "in",
      "envelope": {...},
      "ts_ms": 1703123456789,
      "ack_stage": 3,
      "error_code": 0,
      "ack_note": ""
    }
  },
  "order": ["msg-123", "msg-124"]
}
```

### Worktree State (`agent_data/worktree.json`)
Current worktree binding:
```json
{
  "binding": {
    "repo_id": "main-repo",
    "worktree_id": "main-branch", 
    "bound_at": 1703123456,
    "metadata": {
      "branch": "main",
      "purpose": "production"
    }
  }
}
```

## Custom Worktree Policy

The advanced agent includes a custom worktree policy that:
- Restricts binding to authorized repositories
- Allows rebinding with validation
- Logs all binding operations
- Validates metadata requirements

```python
class CustomWorktreePolicy(DefaultWorktreePolicy):
    def before_bind(self, repo_id: str, worktree_id: str, current_binding) -> bool:
        if self.allowed_repos and repo_id not in self.allowed_repos:
            return False
        return super().before_bind(repo_id, worktree_id, current_binding)
```

## Testing the Examples

1. **Start the advanced agent:**
   ```bash
   python examples/advanced_agent.py
   ```

2. **In another terminal, run tests:**
   ```bash
   python examples/test_client.py
   ```

3. **Check persistence:**
   ```bash
   ls -la agent_data/
   cat agent_data/activity.json
   cat agent_data/worktree.json
   ```

4. **Test restart recovery:**
   - Stop the agent (Ctrl+C)
   - Restart it with the same data directory
   - Observe state restoration in logs

## ACK Lifecycle Demonstration

The advanced agent automatically handles ACK progression:

1. **RECEIVED**: Sent immediately when message arrives
2. **READ**: Sent before processing begins  
3. **FULFILLED**: Sent on successful processing
4. **REJECTED/FAILED**: Sent on processing errors

Monitor ACK progression in both agent and client logs.

## Error Handling

The examples demonstrate various error scenarios:
- Network failures (retry logic)
- Invalid message formats (graceful handling)  
- Policy violations (worktree binding restrictions)
- Unknown message types (default handlers)
- Persistence failures (fallback behavior)

## Extension Points

Use these examples as templates for:
- **Custom message handlers**: Add new message types and processing logic
- **Policy hooks**: Implement domain-specific validation rules
- **Persistence backends**: Replace JSON with database storage
- **Monitoring**: Add metrics and observability
- **Security**: Implement authentication and authorization
