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

Note: Deployments include additional declaration fields aligned with the spec, such as `communication_class` and `max_parallel_instances`. Field names and placement vary by schema version. Include these fields where supported to enable correct routing and scheduling policies.

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

### Negotiation Service

**Purpose**: Multi-agent consensus, artifact approval workflows, and coordination.

**Port**: 50064

#### Submit Proposal

```protobuf
rpc SubmitProposal(NegotiationProposal) returns (ProposalResponse);

message NegotiationProposal {
  string artifact_type = 1;           // REQUIREMENTS, PLAN, CODE, DEPLOYMENT
  string artifact_id = 2;             // Unique identifier
  bytes artifact = 3;                 // Binary content
  string artifact_content_type = 4;   // MIME type
  repeated string requested_critics = 5; // Critic agent IDs
  string negotiation_room_id = 6;     // Session identifier
  string producer_id = 7;             // Submitting agent
}

message ProposalResponse {
  bool accepted = 1;
  string proposal_id = 2;
  string negotiation_room_id = 3;
  repeated string assigned_critics = 4;
}
```

#### Submit Vote

```protobuf
rpc SubmitVote(NegotiationVote) returns (VoteResponse);

message NegotiationVote {
  string artifact_id = 1;
  string critic_id = 2;
  float score = 3;                    // 0-10 score
  float confidence = 4;               // 0-1 confidence level
  bool passed = 5;                    // Meets minimum criteria
  repeated string strengths = 6;
  repeated string weaknesses = 7;
  repeated string recommendations = 8;
  string negotiation_room_id = 9;
}
```

#### Wait for Decision

```protobuf
rpc WaitForDecision(WaitRequest) returns (NegotiationDecision);

message NegotiationDecision {
  string artifact_id = 1;
  DecisionOutcome outcome = 2;        // APPROVED, REVISION_REQUESTED, ESCALATED_TO_HITL
  repeated NegotiationVote votes = 3;
  AggregatedScore aggregated_score = 4;
  string rationale = 5;
  string policy_version = 6;
}

message AggregatedScore {
  float mean = 1;
  float weighted_mean = 2;
  float min_score = 3;
  float max_score = 4;
  float std_dev = 5;
  int32 vote_count = 6;
}
```

### Reasoning Service

**Purpose**: Decision support, parallelism evaluation, and debate orchestration.

**Port**: 50065

#### Evaluate Options

```protobuf
rpc EvaluateOptions(EvaluationRequest) returns (EvaluationResponse);

message EvaluationRequest {
  string evaluation_id = 1;
  repeated OptionCandidate candidates = 2;
  EvaluationCriteria criteria = 3;
  string context = 4;
}

message OptionCandidate {
  string option_id = 1;
  string description = 2;
  bytes data = 3;
  map<string, float> estimated_scores = 4;
}

message EvaluationCriteria {
  repeated CriterionWeight weights = 1;
  float minimum_threshold = 2;
  EvaluationStrategy strategy = 3;  // WEIGHTED_SUM, PARETO, MULTI_OBJECTIVE
}

message EvaluationResponse {
  string evaluation_id = 1;
  repeated RankedOption results = 2;
  string selected_option_id = 3;
  string rationale = 4;
}
```

#### Start Debate

```protobuf
rpc StartDebate(DebateRequest) returns (DebateSession);

message DebateRequest {
  string topic = 1;
  repeated string participant_agents = 2;
  DebateConfig config = 3;
}

message DebateConfig {
  int32 max_rounds = 1;
  int64 round_timeout_ms = 2;
  string moderator_policy = 3;
  repeated string position_types = 4;  // PRO, CON, NEUTRAL
}

message DebateSession {
  string session_id = 1;
  string status = 2;
  repeated DebateRound rounds = 3;
  DebateSummary summary = 4;
}
```

### Logging Service

**Purpose**: Distributed logging, audit trails, and compliance reporting.

**Port**: 50066

#### Emit Log Entry

```protobuf
rpc EmitLog(LogEntry) returns (LogResponse);

message LogEntry {
  string log_id = 1;
  string agent_id = 2;
  LogLevel level = 3;                 // DEBUG, INFO, WARN, ERROR, FATAL
  string message = 4;
  map<string, string> attributes = 5;
  string correlation_id = 6;
  string span_id = 7;
  uint64 timestamp = 8;
}

enum LogLevel {
  LOG_LEVEL_UNSPECIFIED = 0;
  DEBUG = 1;
  INFO = 2;
  WARN = 3;
  ERROR = 4;
  FATAL = 5;
}

message LogResponse {
  bool accepted = 1;
  string log_id = 2;
}
```

#### Query Logs

```protobuf
rpc QueryLogs(LogQuery) returns (stream LogEntry);

message LogQuery {
  repeated string agent_ids = 1;
  LogLevel min_level = 2;
  uint64 start_timestamp = 3;
  uint64 end_timestamp = 4;
  map<string, string> attribute_filters = 5;
  string correlation_id = 6;
  int32 limit = 7;
}
```

#### Emit Audit Event

```protobuf
rpc EmitAuditEvent(AuditEvent) returns (AuditResponse);

message AuditEvent {
  string event_id = 1;
  string actor_id = 2;                // Agent or user performing action
  string action = 3;                  // CREATE, READ, UPDATE, DELETE, EXECUTE
  string resource_type = 4;           // message, task, worktree, etc.
  string resource_id = 5;
  string result = 6;                  // SUCCESS, FAILURE, DENIED
  map<string, string> metadata = 7;
  uint64 timestamp = 8;
}
```

### Connector Service

**Purpose**: External API integration, tool provider registration, and capability bridging.

**Port**: 50067

#### Register Provider

```protobuf
rpc RegisterProvider(ProviderRegistration) returns (RegistrationResponse);

message ProviderRegistration {
  string provider_id = 1;
  string provider_name = 2;
  ProviderType provider_type = 3;     // MCP, REST, GRPC, CUSTOM
  repeated ToolDescriptor tools = 4;
  ConnectionConfig connection = 5;
  HealthCheckConfig health_config = 6;
}

message ToolDescriptor {
  string tool_name = 1;
  string description = 2;
  bytes input_schema = 3;             // JSON Schema
  bytes output_schema = 4;            // JSON Schema
  repeated string required_permissions = 5;
  bool is_idempotent = 6;
  bool supports_streaming = 7;
}

message ConnectionConfig {
  string endpoint = 1;
  AuthConfig auth = 2;
  TlsConfig tls = 3;
  int64 timeout_ms = 4;
  int32 max_concurrent_requests = 5;
}
```

#### Invoke Tool

```protobuf
rpc InvokeTool(ToolInvocation) returns (ToolResult);

message ToolInvocation {
  string provider_id = 1;
  string tool_name = 2;
  bytes arguments = 3;                // JSON-encoded arguments
  string correlation_id = 4;
  ExecutionPolicy policy = 5;
}

message ToolResult {
  bool success = 1;
  bytes result = 2;                   // JSON-encoded result
  string error_message = 3;
  int64 execution_time_ms = 4;
  map<string, string> metadata = 5;
}
```

#### List Providers

```protobuf
rpc ListProviders(ListProvidersRequest) returns (ListProvidersResponse);

message ListProvidersResponse {
  repeated ProviderInfo providers = 1;

  message ProviderInfo {
    string provider_id = 1;
    string provider_name = 2;
    ProviderType provider_type = 3;
    HealthStatus health_status = 4;
    repeated string available_tools = 5;
    uint64 last_seen_timestamp = 6;
  }
}
```

## Service Discovery and Health

### Service Registry Pattern

All services register with a central service registry. The following message defines the registration format:

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

Services support the following load balancing strategies:

- **Round Robin**: The load balancer distributes requests evenly across endpoints.
- **Least Connections**: The load balancer routes to the endpoint with fewest active connections.
- **Weighted**: The load balancer routes based on endpoint capacity weights.
- **Locality Aware**: The load balancer prefers endpoints in the same region or zone.
- **Health Based**: The load balancer excludes unhealthy endpoints from rotation.

### Circuit Breaker Pattern

All service clients implement circuit breakers with the following configuration:

```protobuf
message CircuitBreakerConfig {
  uint32 failure_threshold = 1;      // Failures before opening
  uint64 recovery_timeout_ms = 2;    // Time before trying to close
  uint64 request_timeout_ms = 3;     // Individual request timeout
  double failure_rate_threshold = 4; // Percentage failure rate
}
```

**States**:

- **CLOSED**: The circuit allows requests to pass through during normal operation.
- **OPEN**: The circuit rejects requests immediately during failure mode.
- **HALF_OPEN**: The circuit allows limited requests to test recovery.

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

All services implement exponential backoff with jitter. The following function shows the calculation:

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

Services use mutual TLS authentication with the following configuration:

```yaml
tls_config:
  cert_file: "/etc/certs/service.pem"
  key_file: "/etc/certs/service.key"
  ca_file: "/etc/certs/ca.pem"
  verify_client_cert: true
  min_tls_version: "1.3"
```

### Authorization

The system enforces role-based access control per service:

```protobuf
message ServicePermission {
  string service_name = 1;
  repeated string allowed_methods = 2;
  repeated string required_roles = 3;
  repeated ResourceConstraint resource_constraints = 4;
}
```

### Audit Logging

All service operations generate audit logs with the following structure:

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
