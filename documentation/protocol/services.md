# Services

Complete API reference for all SW4RM protocol services. Each service provides specialized functionality and can be scaled independently in production deployments.

## Core Services

### Registry Service

**Purpose**: Agent lifecycle management, discovery, and health monitoring.

#### Register Agent

```protobuf
rpc Register(RegisterAgentRequest) returns (RegisterAgentResponse);

message RegisterAgentRequest {
  string agent_id = 1;
  string display_name = 2;
  repeated string capabilities = 3;
  map<string, string> metadata = 4;
  HealthConfig health_config = 5;
}

message RegisterAgentResponse {
  bool success = 1;
  string registration_token = 2;
  uint64 heartbeat_interval_ms = 3;
  repeated PolicyRule policies = 4;
}
```

**Example**:
```json
{
  "agent_id": "log-analyzer-001",
  "display_name": "Production Log Analyzer",
  "capabilities": ["log_parsing", "anomaly_detection", "alerting"],
  "metadata": {
    "version": "2.1.0",
    "environment": "production",
    "region": "us-west-2"
  },
  "health_config": {
    "check_interval_ms": 30000,
    "timeout_ms": 5000
  }
}
```

Note: Deployments commonly include additional declaration fields aligned with the spec, such as `communication_class` and `max_parallel_instances`. Field names and placement may vary by schema version; include them where supported to enable correct routing and scheduling policies.

#### Discover Agents

```protobuf
rpc DiscoverAgents(DiscoverAgentsRequest) returns (DiscoverAgentsResponse);

message DiscoverAgentsRequest {
  repeated string required_capabilities = 1;
  map<string, string> metadata_filters = 2;
  bool include_health_status = 3;
}

message DiscoverAgentsResponse {
  repeated AgentInfo agents = 1;
  
  message AgentInfo {
    string agent_id = 1;
    string display_name = 2;
    repeated string capabilities = 3;
    HealthStatus health_status = 4;
    uint64 last_seen_timestamp = 5;
  }
}
```

#### Health Monitoring

```protobuf
rpc SendHeartbeat(HeartbeatRequest) returns (HeartbeatResponse);

message HeartbeatRequest {
  string agent_id = 1;
  string registration_token = 2;
  HealthMetrics metrics = 3;
}

message HealthMetrics {
  uint64 messages_processed = 1;
  double cpu_usage_percent = 2;
  uint64 memory_usage_mb = 3;
  double error_rate_percent = 4;
  repeated string active_capabilities = 5;
}
```

### Router Service

**Purpose**: Reliable message routing, delivery guarantees, and load balancing.

#### Send Message

```protobuf
rpc SendMessage(SendMessageRequest) returns (SendMessageResponse);

message SendMessageRequest {
  Envelope envelope = 1;
  DeliveryOptions delivery_options = 2;
}

message DeliveryOptions {
  uint32 retry_attempts = 1;        // Max retry attempts
  uint64 retry_delay_ms = 2;        // Initial retry delay
  double retry_backoff_factor = 3;  // Exponential backoff multiplier
  uint64 ttl_ms = 4;               // Message time-to-live
  bool require_ack = 5;            // Wait for acknowledgment
  uint64 ack_timeout_ms = 6;       // Acknowledgment timeout
}

message SendMessageResponse {
  bool accepted = 1;
  string delivery_id = 2;
  ErrorCode error_code = 3;
  string error_message = 4;
}
```

#### Stream Messages

```protobuf
rpc StreamMessages(StreamMessagesRequest) returns (stream Envelope);

message StreamMessagesRequest {
  string agent_id = 1;
  repeated MessageType message_types = 2;
  map<string, string> filters = 3;
  uint32 buffer_size = 4;
  bool include_acks = 5;
}
```

#### Message Status

```protobuf
rpc GetMessageStatus(GetMessageStatusRequest) returns (GetMessageStatusResponse);

message GetMessageStatusRequest {
  repeated string message_ids = 1;
}

message GetMessageStatusResponse {
  map<string, MessageStatus> statuses = 1;
  
  message MessageStatus {
    string message_id = 1;
    DeliveryStage stage = 2;
    repeated Ack acknowledgments = 3;
    uint64 last_update_timestamp = 4;
    ErrorCode error_code = 5;
  }
}
```

### Scheduler Service

**Purpose**: Work coordination, task distribution, and resource management.

#### Submit Task

```protobuf
rpc SubmitTask(SubmitTaskRequest) returns (SubmitTaskResponse);

message SubmitTaskRequest {
  string task_id = 1;
  TaskDefinition task = 2;
  TaskConstraints constraints = 3;
  map<string, string> metadata = 4;
}

message TaskDefinition {
  string task_type = 1;
  bytes payload = 2;
  repeated string required_capabilities = 3;
  TaskPriority priority = 4;
  uint64 deadline_timestamp = 5;
}

message TaskConstraints {
  repeated string preferred_agents = 1;
  repeated string excluded_agents = 2;
  ResourceRequirements resources = 3;
  uint32 max_retries = 4;
  bool allow_preemption = 5;
}
```

#### Query Tasks

```protobuf
rpc QueryTasks(QueryTasksRequest) returns (QueryTasksResponse);

message QueryTasksRequest {
  repeated TaskStatus status_filter = 1;
  string agent_id_filter = 2;
  uint64 since_timestamp = 3;
  uint32 limit = 4;
}

message QueryTasksResponse {
  repeated TaskInfo tasks = 1;
  
  message TaskInfo {
    string task_id = 1;
    TaskStatus status = 2;
    string assigned_agent = 3;
    uint64 created_timestamp = 4;
    uint64 started_timestamp = 5;
    uint64 completed_timestamp = 6;
    ExecutionMetrics metrics = 7;
  }
}
```

## Extended Services

### HITL Service

**Purpose**: Human-in-the-loop workflows, approvals, and manual interventions.

#### Request Approval

```protobuf
rpc RequestApproval(ApprovalRequest) returns (ApprovalResponse);

message ApprovalRequest {
  string request_id = 1;
  ApprovalType approval_type = 2;
  string context = 3;
  repeated string approver_roles = 4;
  uint64 deadline_timestamp = 5;
  ApprovalPolicy policy = 6;
}

message ApprovalPolicy {
  uint32 required_approvals = 1;
  bool allow_self_approval = 2;
  string auto_timeout_action = 3;  // "APPROVE", "DENY", "ESCALATE"
  repeated ApprovalRule rules = 4;
}
```

#### Poll Decisions

```protobuf
rpc PollDecisions(PollDecisionsRequest) returns (stream ApprovalDecision);

message ApprovalDecision {
  string request_id = 1;
  DecisionType decision = 2;      // APPROVED, DENIED, ESCALATED
  string approver_id = 3;
  string reason = 4;
  uint64 timestamp = 5;
  map<string, string> metadata = 6;
}
```

### Worktree Service

**Purpose**: Repository context management, workspace isolation, and version control.

#### Bind Worktree

```protobuf
rpc BindWorktree(BindWorktreeRequest) returns (BindWorktreeResponse);

message BindWorktreeRequest {
  string agent_id = 1;
  string repo_id = 2;
  string worktree_id = 3;
  WorktreeConfig config = 4;
}

message WorktreeConfig {
  string branch = 1;
  string commit_sha = 2;
  IsolationLevel isolation_level = 3;
  repeated PolicyHook hooks = 4;
  map<string, string> environment = 5;
}

message BindWorktreeResponse {
  bool success = 1;
  string workspace_path = 2;
  WorktreeInfo info = 3;
  repeated string available_commands = 4;
}
```

#### Execute Git Command

```protobuf
rpc ExecuteGitCommand(GitCommandRequest) returns (GitCommandResponse);

message GitCommandRequest {
  string agent_id = 1;
  string worktree_id = 2;
  repeated string command_args = 3;
  map<string, string> options = 4;
  uint64 timeout_ms = 5;
}

message GitCommandResponse {
  int32 exit_code = 1;
  string stdout = 2;
  string stderr = 3;
  uint64 execution_time_ms = 4;
  WorktreeInfo updated_info = 5;
}
```

### Tool Service

**Purpose**: External tool execution, API integration, and result management.

#### Execute Tool

```protobuf
rpc ExecuteTool(ToolExecutionRequest) returns (ToolExecutionResponse);

message ToolExecutionRequest {
  string tool_name = 1;
  string operation = 2;
  map<string, bytes> parameters = 3;
  ExecutionPolicy policy = 4;
  string correlation_id = 5;
}

message ExecutionPolicy {
  uint64 timeout_ms = 1;
  uint32 retry_attempts = 2;
  IsolationLevel isolation = 3;
  ResourceLimits limits = 4;
  repeated string allowed_domains = 5;
  bool capture_output = 6;
}

message ToolExecutionResponse {
  bool success = 1;
  int32 exit_code = 2;
  bytes result_data = 3;
  string error_message = 4;
  ExecutionMetrics metrics = 5;
  repeated string logs = 6;
}
```

#### List Available Tools

```protobuf
rpc ListTools(ListToolsRequest) returns (ListToolsResponse);

message ListToolsResponse {
  repeated ToolDefinition tools = 1;
  
  message ToolDefinition {
    string name = 1;
    string description = 2;
    repeated string supported_operations = 3;
    ParameterSchema parameter_schema = 4;
    repeated string required_permissions = 5;
    ToolCapabilities capabilities = 6;
  }
}
```

## Service Discovery and Health

### Service Registry Pattern

All services register with a central service registry:

```protobuf
message ServiceRegistration {
  string service_name = 1;
  string service_version = 2;
  repeated ServiceEndpoint endpoints = 3;
  HealthCheckConfig health_config = 4;
  map<string, string> metadata = 5;
}

message ServiceEndpoint {
  string address = 1;          // host:port
  string protocol = 2;         // "grpc", "http"
  bool tls_enabled = 3;
  map<string, string> tags = 4; // "region", "zone", "env"
}
```

### Load Balancing Strategies

Services support multiple load balancing strategies:


- **Round Robin**: Distribute requests evenly across endpoints
- **Least Connections**: Route to endpoint with fewest active connections  
- **Weighted**: Route based on endpoint capacity weights
- **Locality Aware**: Prefer endpoints in same region/zone
- **Health Based**: Exclude unhealthy endpoints from rotation

### Circuit Breaker Pattern

All service clients implement circuit breakers:

```protobuf
message CircuitBreakerConfig {
  uint32 failure_threshold = 1;      // Failures before opening
  uint64 recovery_timeout_ms = 2;    // Time before trying to close
  uint64 request_timeout_ms = 3;     // Individual request timeout
  double failure_rate_threshold = 4; // Percentage failure rate
}
```

**States**:


- **CLOSED**: Normal operation, requests pass through
- **OPEN**: Failing fast, requests immediately rejected  
- **HALF_OPEN**: Testing recovery, limited requests allowed

## Error Handling Patterns

### Standard Error Response

```protobuf
message ErrorResponse {
  ErrorCode code = 1;
  string message = 2;
  repeated ErrorDetail details = 3;
  string request_id = 4;
  uint64 timestamp = 5;
}

message ErrorDetail {
  string field = 1;
  string violation = 2;
  string help_text = 3;
}
```

### Retry Policies

All services implement exponential backoff with jitter:

```python
def calculate_delay(attempt: int, base_delay_ms: int, max_delay_ms: int) -> int:
    """Calculate retry delay with exponential backoff and jitter."""
    delay = min(base_delay_ms * (2 ** attempt), max_delay_ms)
    jitter = random.uniform(0.1, 0.9) * delay
    return int(delay + jitter)
```

<!-- Performance and Scaling section removed to avoid implying guarantees. Configuration patterns should be documented alongside concrete implementations. -->

## Security Considerations

### Authentication

Services use mutual TLS authentication:

```yaml
tls_config:
  cert_file: "/etc/certs/service.pem"
  key_file: "/etc/certs/service.key"
  ca_file: "/etc/certs/ca.pem"
  verify_client_cert: true
  min_tls_version: "1.3"
```

### Authorization

Role-based access control per service:

```protobuf
message ServicePermission {
  string service_name = 1;
  repeated string allowed_methods = 2;
  repeated string required_roles = 3;
  repeated ResourceConstraint resource_constraints = 4;
}
```

### Audit Logging

All service operations generate audit logs:

```json
{
  "timestamp": "2024-08-08T15:30:00Z",
  "service": "router",
  "method": "SendMessage", 
  "agent_id": "log-analyzer-001",
  "resource": "msg-abc123",
  "action": "CREATE",
  "result": "SUCCESS",
  "duration_ms": 125,
  "request_id": "req-def456"
}
```
