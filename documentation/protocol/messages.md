# Message Types

Complete specification of all message types supported by the SW4RM protocol, including payload schemas, usage patterns, and examples.

## Message Type Enumeration

```protobuf
enum MessageType {
  MESSAGE_TYPE_UNSPECIFIED = 0;
  CONTROL = 1;
  DATA = 2;  
  HEARTBEAT = 3;
  NOTIFICATION = 4;
  ACKNOWLEDGEMENT = 5;
  HITL_INVOCATION = 6;
  WORKTREE_CONTROL = 7;
  NEGOTIATION = 8;
  TOOL_CALL = 9;
  TOOL_RESULT = 10;
  TOOL_ERROR = 11;
}
```

## DATA Messages (Type 2)

**Purpose**: Application-level data exchange between agents.

**Content Types**: 

- `application/json` - Structured data interchange
- `text/plain` - Simple text content
- `application/octet-stream` - Binary data
- `application/protobuf` - Protocol buffer messages

**Example**:
```json
{
  "envelope": {
    "message_type": 2,
    "content_type": "application/json",
    "payload": {
      "task_id": "analyze-logs-001",
      "input_files": ["app.log", "error.log"],
      "analysis_type": "error_detection",
      "parameters": {
        "lookback_hours": 24,
        "severity_threshold": "WARNING"
      }
    }
  }
}
```

**Usage Patterns**:


- Business logic execution results
- Data processing pipeline intermediates
- Agent-to-agent coordination data
- Response payloads from service calls

## CONTROL Messages (Type 1)

**Purpose**: System-level commands for agent management and coordination.

**Standard Commands**:

### Status Request
```json
{
  "command": "status",
  "include_details": true,
  "components": ["activity_buffer", "worktree", "health"]
}
```

### Configuration Update  
```json
{
  "command": "configure", 
  "settings": {
    "log_level": "DEBUG",
    "max_concurrent_tasks": 5,
    "heartbeat_interval_ms": 30000
  }
}
```

### Graceful Shutdown
```json
{
  "command": "shutdown",
  "reason": "maintenance_window",
  "drain_timeout_seconds": 300
}
```

### Resource Allocation
```json
{
  "command": "allocate_resources",
  "resources": {
    "cpu_cores": 2,
    "memory_gb": 4, 
    "disk_gb": 10
  },
  "priority": "HIGH"
}
```

## ACKNOWLEDGEMENT Messages (Type 5) 

**Purpose**: Confirm receipt and processing status of messages.

**Payload Schema**:
```protobuf
message Ack {
  string ack_for_message_id = 1;
  AckStage ack_stage = 2;
  ErrorCode error_code = 3;
  string note = 4;
}
```

**Example**:
```json
{
  "ack_for_message_id": "msg-abc123",
  "ack_stage": 3,  // FULFILLED
  "error_code": 0, // NO_ERROR
  "note": "Task completed successfully in 2.3s"
}
```

**ACK Stages**:


- `RECEIVED` (1): Delivered to target queue
- `READ` (2): Parsed and validated
- `FULFILLED` (3): Processing completed successfully
- `REJECTED` (4): Rejected by policy or validation
- `FAILED` (5): Processing encountered error
- `TIMED_OUT` (6): Processing exceeded deadline

## HITL_INVOCATION Messages (Type 6)

**Purpose**: Request human intervention or approval for automated processes.

**Invocation Types**:

### Approval Request
```json
{
  "reason_type": "SECURITY_APPROVAL",
  "context": {
    "agent_id": "file-processor-001",
    "operation": "delete_sensitive_files", 
    "risk_level": "HIGH",
    "affected_files": ["/data/customer_pii.csv", "/data/financial.xlsx"]
  },
  "approval_required_by": "2024-08-09T12:00:00Z",
  "approver_roles": ["security_admin", "data_steward"],
  "auto_timeout_action": "DENY"
}
```

### Conflict Resolution
```json
{
  "reason_type": "CONFLICT",
  "context": {
    "conflicting_agents": ["agent-a", "agent-b"],
    "resource": "shared_database_connection",
    "conflict_description": "Both agents requesting exclusive lock",
    "suggested_resolution": "time_sharing_allocation"
  }
}
```

### Manual Override
```json
{
  "reason_type": "MANUAL_OVERRIDE",
  "context": {
    "automated_decision": "reject_transaction",
    "confidence_score": 0.65,
    "business_context": "VIP customer with history of legitimate edge cases",
    "override_options": ["approve", "reject", "escalate"]
  }
}
```

## WORKTREE_CONTROL Messages (Type 7)

**Purpose**: Manage repository and worktree context for agents.

**Operations**:

### Bind to Worktree
```json
{
  "action": "bind",
  "repo_id": "customer-service-api",
  "worktree_id": "feature-auth-improvements",
  "metadata": {
    "branch": "feat/oauth-integration",
    "commit_sha": "abc123def456",
    "purpose": "security_audit",
    "isolation_level": "CONTAINER"
  }
}
```

### Switch Context
```json
{
  "action": "switch",
  "new_repo_id": "payment-processor", 
  "new_worktree_id": "hotfix-rate-limiting",
  "preserve_state": true,
  "migration_strategy": "COPY_ACTIVE_FILES"
}
```

### Status Check
```json
{
  "action": "status",
  "include_details": ["current_binding", "file_changes", "resource_usage"]
}
```

## TOOL_CALL Messages (Type 9)

**Purpose**: Execute external tools, APIs, or system commands.

**Execution Policy**:
```json
{
  "execution_policy": {
    "timeout_seconds": 120,
    "retry_attempts": 3,
    "isolation_level": "SANDBOX",
    "resource_limits": {
      "max_memory_mb": 512,
      "max_cpu_percent": 50
    }
  }
}
```

**Examples**:

### API Call
```json
{
  "tool_type": "http_client",
  "operation": "POST",
  "parameters": {
    "url": "https://api.github.com/repos/owner/repo/issues",
    "headers": {
      "Authorization": "token ${GITHUB_TOKEN}",
      "Content-Type": "application/json"
    },
    "body": {
      "title": "Automated issue from SW4RM",
      "body": "Security vulnerability detected in dependencies"
    }
  }
}
```

### Database Query
```json
{
  "tool_type": "database",
  "operation": "SELECT",
  "parameters": {
    "connection_string": "${DB_CONNECTION}",
    "query": "SELECT * FROM transactions WHERE status = ? AND created_at > ?",
    "parameters": ["PENDING", "2024-08-08T00:00:00Z"],
    "timeout_seconds": 30
  }
}
```

### File System Operation
```json
{
  "tool_type": "filesystem",
  "operation": "READ_FILE",
  "parameters": {
    "path": "/data/processing/input.csv",
    "encoding": "utf-8",
    "max_size_mb": 100,
    "validate_checksum": "sha256:abc123..."
  }
}
```

## NOTIFICATION Messages (Type 4)

**Purpose**: Fire-and-forget informational messages.

**Event Types**:

### System Event
```json
{
  "event_type": "AGENT_LIFECYCLE",
  "event_name": "AGENT_STARTED",
  "timestamp": "2024-08-08T15:30:00Z",
  "details": {
    "agent_id": "log-analyzer-003",
    "version": "2.1.0",
    "startup_time_ms": 1250,
    "capabilities": ["log_parsing", "anomaly_detection"]
  }
}
```

### Metric Update
```json
{
  "event_type": "METRICS",
  "metrics": {
    "messages_processed": 1547,
    "avg_processing_time_ms": 125.3,
    "error_rate_percent": 0.8,
    "memory_usage_mb": 256.7
  },
  "measurement_window": "LAST_5_MINUTES"
}
```

### Alert Notification  
```json
{
  "event_type": "ALERT", 
  "severity": "WARNING",
  "alert_name": "HIGH_ERROR_RATE",
  "description": "Error rate exceeded threshold (5%) in last 5 minutes",
  "details": {
    "current_rate": 7.2,
    "threshold": 5.0,
    "affected_services": ["user-auth", "payment-processing"]
  }
}
```

## Recommended Message Size Limits

| Message Type | Max Payload Size | Recommendations |
|--------------|------------------|------------------|
| `CONTROL` | 64 KB | Keep command payloads small |
| `DATA` | 16 MB | SHOULD use streaming for large data |
| `ACKNOWLEDGEMENT` | 4 KB | Brief status and error messages |
| `HITL_INVOCATION` | 256 KB | Include necessary context only |
| `TOOL_CALL` | 1 MB | Large data via external storage |
| `NOTIFICATION` | 32 KB | Aggregate metrics when possible |

## Content Type Guidelines

All payload-carrying messages MUST declare an appropriate `content_type`. When a payload is present, implementations MUST set an accurate `content_length`.

### JSON Payload Structure
```json
{
  "version": "1.0",
  "metadata": {
    "timestamp": "2024-08-08T15:30:00Z",
    "source": "agent-id",
    "schema": "task-request-v1"
  },
  "data": {
    // Application-specific content
  }
}
```

### Binary Payload Headers
```
Content-Type: application/octet-stream
Content-Encoding: gzip
Content-Length: 1048576
X-Data-Schema: log-entries-v2
X-Compression: gzip
```

## Validation Rules


1. **Required Fields**: `message_id`, `producer_id`, `correlation_id`, `sequence_number`, `retry_count`, `message_type`
2. **Payload Metadata**: When a payload is present, `content_type` and `content_length` are REQUIRED
3. **Optional Fields**: `idempotency_token`, HLC timestamp, `ttl_ms`
4. **Content Consistency**: `content_length` must match the actual payload size
5. **Type Safety**: Payload must be valid for the declared `content_type`
6. **Correlation**: Responses MUST include the original `correlation_id`
7. **Timestamps**: All timestamps MUST be ISO 8601 format with timezone when used
8. **Encoding**: Text payloads MUST be UTF-8 encoded
