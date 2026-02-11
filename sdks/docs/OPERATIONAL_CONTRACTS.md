# SW4RM SDK Operational Contracts

**Version:** 0.5.0
**Last Updated:** 2026-01-10
**Status:** Normative

This document defines the operational contracts that all SW4RM SDK implementations MUST honor. These are protocol-level guarantees that clients can rely on when building distributed agent systems.

## 1. Overview

SW4RM SDKs provide gRPC-based clients for interacting with protocol services. This document specifies:

- Connection and timeout behavior
- Retry policies and error handling
- Data consistency guarantees
- Idempotency contracts
- State persistence guarantees

These contracts apply to all official SDKs (Python, Rust, JavaScript/TypeScript) unless explicitly noted otherwise.

## 2. Connection Management

### 2.1. Connection Establishment

**Python SDK:**
- Uses `grpc.insecure_channel()` for unencrypted connections
- Channel creation is lazy (deferred until first RPC)
- No automatic connection retry on client construction
- Connection state: managed transparently by gRPC channel

**Rust SDK:**
- Uses `tonic::transport::Endpoint::connect()` for async connection
- Connection is eager (established during `new()` for most clients)
- Returns `Error::Connection` if initial connection fails
- Connection pooling: handled by tonic's channel implementation

**JavaScript SDK:**
- Uses `@grpc/grpc-js` for Node.js gRPC support
- Channel credentials: `grpc.credentials.createInsecure()` by default
- Connection is lazy (established on first RPC call)
- Connection state: managed by gRPC-JS library

### 2.2. Default Timeouts

| SDK        | Connection Timeout | Request Deadline | Configurable |
|------------|-------------------|------------------|--------------|
| Python     | N/A (lazy)        | 30s              | Yes          |
| Rust       | N/A (async)       | 30s              | Yes          |
| JavaScript | N/A (lazy)        | 30s              | Yes          |

**All SDKs:** Normative default deadline is 30 seconds for all RPC calls.

**Python:** Default 30s timeout configurable via `timeout` parameter in client constructor and per-method calls.

**Rust:** Default 30s timeout set via `Endpoint::timeout()` and per-request `set_timeout()`. Use `with_timeout()` constructor for custom timeout.

**JavaScript:** Default 30s timeout (30000ms). Configurable via `ClientOptions.deadlineMs`.

### 2.3. Keep-Alive Settings

**All SDKs:** Keep-alive is controlled by the underlying gRPC implementation:

- **gRPC Default:** 2-hour idle timeout with keep-alive probes
- **Customization:** Set via channel arguments (platform-dependent)
- **Recommendation:** For long-running agents, enable keep-alive with 60s interval

Example (Python):
```python
channel_options = [
    ('grpc.keepalive_time_ms', 60000),
    ('grpc.keepalive_timeout_ms', 20000),
]
channel = grpc.insecure_channel('localhost:50051', options=channel_options)
```

Example (Rust):
```rust
// tonic handles keep-alive automatically; configure via http2_keep_alive_interval
let endpoint = Endpoint::from_shared("http://localhost:50051")?
    .http2_keep_alive_interval(Duration::from_secs(60));
```

Example (JavaScript):
```javascript
// Keep-alive configured via channel options
const client = new RegistryClient({
  address: 'localhost:50051',
  deadlineMs: 10000,
  // Channel options passed to underlying gRPC-JS client
});
```

## 3. Retry Policies

### 3.1. Automatic Retry Behavior

| SDK        | Max Attempts | Backoff Strategy     | Backoff Range    |
|------------|-------------|----------------------|------------------|
| Python     | 1 (no retry)| N/A                  | N/A              |
| Rust       | 1 (no retry)| N/A                  | N/A              |
| JavaScript | 1 (no retry)| N/A                  | N/A              |

**All SDKs:** NO automatic retries by default. All errors propagate immediately to caller.

**Rationale:** Retry logic is application-specific. Some operations should not be retried automatically (e.g., non-idempotent operations). Applications should implement their own retry logic based on business requirements.

**Python SDK:** All errors propagate immediately as exceptions.

**Rust SDK:** All errors return as `Result<T, Error>`.

**JavaScript SDK:** No automatic retry by default (maxAttempts: 1). Configure via `ClientOptions.retry` for opt-in retry behavior.

**Recommendation for Production:**

For production systems, implement application-level retry logic with:
- Exponential backoff with jitter
- Circuit breaker pattern for cascading failures
- Retry budgets to prevent retry storms
- Selective retry based on error type (see section 3.2)

### 3.2. Retryable vs Non-Retryable Errors

The following gRPC status codes are **retryable** (safe to retry without side effects):

- `UNAVAILABLE` (14): Service temporarily unavailable
- `DEADLINE_EXCEEDED` (4): Request timeout
- `RESOURCE_EXHAUSTED` (8): Rate limit or quota exceeded
- `ABORTED` (10): Transient conflict (e.g., optimistic locking)

The following gRPC status codes are **NOT retryable**:

- `INVALID_ARGUMENT` (3): Bad request data
- `NOT_FOUND` (5): Resource does not exist
- `ALREADY_EXISTS` (6): Resource already exists
- `PERMISSION_DENIED` (7): Insufficient permissions
- `FAILED_PRECONDITION` (9): System not in required state
- `UNAUTHENTICATED` (16): Missing or invalid credentials
- `UNIMPLEMENTED` (12): Method not supported

**JavaScript SDK:** No automatic retry by default (as of v0.5.0). Applications must explicitly configure retry policy via `ClientOptions.retry` if needed.

## 4. Data Consistency Guarantees

### 4.1. Registry Service (RegistryClient)

**Operations:**
- `register(agent_descriptor)` - Register agent with registry
- `heartbeat(agent_id, state, health)` - Send keepalive heartbeat
- `deregister(agent_id, reason)` - Remove agent from registry

**Consistency Model:**
- **Registration:** Eventual consistency. Agent may not be immediately visible to other services.
- **Heartbeat:** Last-write-wins. No ordering guarantees across concurrent heartbeats.
- **Deregistration:** Eventual consistency. Registry may continue routing messages briefly after deregistration.

**Idempotency:**
- `register()`: NOT idempotent. Re-registration may fail if agent already registered.
- `heartbeat()`: Idempotent. Safe to retry.
- `deregister()`: Idempotent. Safe to call multiple times for same agent.

**State Persistence:**
- Depends on backend implementation (spec does not mandate persistence)
- Clients MUST NOT assume registry state survives service restart
- Agents SHOULD re-register on reconnection

### 4.2. Scheduler Service (SchedulerClient)

**Operations:**
- `submit_task(agent_id, task_id, priority, scope, params)` - Submit task for scheduling
- `request_preemption(agent_id, task_id, reason)` - Request task preemption
- `shutdown_agent(agent_id, grace_period)` - Graceful agent shutdown
- `poll_activity_buffer(agent_id)` - Retrieve activity log
- `purge_activity(agent_id, task_ids)` - Clean up activity buffer

**Consistency Model:**
- **Task Submission:** Atomic. Task is accepted or rejected as a unit.
- **Task Ordering:** Total ordering within scope. Tasks with same scope are serialized.
- **Preemption:** Best-effort. No guarantee preemption succeeds.

**Idempotency:**
- `submit_task()`: NOT idempotent if `task_id` is regenerated. Use stable `task_id` for idempotent submission.
- `request_preemption()`: Idempotent. Safe to retry.
- `shutdown_agent()`: Idempotent. Multiple shutdown requests are coalesced.
- `poll_activity_buffer()`: Read-only, inherently idempotent.
- `purge_activity()`: Idempotent. Purging same task_ids multiple times is safe.

**State Persistence:**
- Activity buffer: In-memory by default, bounded size (implementation-dependent)
- Task queue: May persist depending on scheduler implementation
- No guaranteed durability across scheduler restarts unless explicitly documented

**Ordering Guarantees:**
- Tasks with identical `scope` execute serially (FIFO within priority)
- Tasks with different scopes may execute concurrently
- Priority: Higher priority preempts lower priority (priority range: -19 to 20)

### 4.3. Negotiation Service (NegotiationClient)

**Operations:**
- `open(negotiation_id, correlation_id, topic, participants, intensity, timeout)` - Start negotiation
- `propose(negotiation_id, from_agent, content_type, payload)` - Submit proposal
- `counter(negotiation_id, from_agent, content_type, payload)` - Submit counter-proposal
- `evaluate(negotiation_id, from_agent, confidence_score, notes)` - Evaluate proposal
- `decide(negotiation_id, decided_by, content_type, result)` - Finalize negotiation
- `abort(negotiation_id, reason)` - Cancel negotiation

**Consistency Model:**
- **Session State:** Eventually consistent. Participants may observe proposal/counter in different orders.
- **Termination:** Terminal states (decided/aborted) are final and idempotent.
- **Timeout:** Negotiation may timeout per `debate_timeout`. Implementations MAY clean up timed-out sessions.

**Idempotency:**
- `open()`: NOT idempotent. Opening same `negotiation_id` twice may fail.
- `propose()`, `counter()`, `evaluate()`: NOT idempotent. Each call creates a new entry.
- `decide()`: Idempotent once decided. Subsequent decides on same negotiation_id fail.
- `abort()`: Idempotent. Aborting already-aborted negotiation is safe.

**State Persistence:**
- Negotiation history: Implementation-dependent (may be in-memory or persistent)
- Timeout enforcement: Best-effort. Timeouts may not fire precisely.

### 4.4. Handoff Service (HandoffClient)

**Current Implementation:** Local in-memory storage (all SDKs). Future: gRPC-based service.

**Operations:**
- `request_handoff(request)` - Initiate handoff to target agent
- `accept_handoff(handoff_id)` - Accept pending handoff
- `reject_handoff(handoff_id, reason)` - Reject pending handoff
- `complete_handoff(handoff_id)` - Mark handoff as completed
- `get_pending_handoffs(agent_id)` - Query pending handoffs for agent
- `get_handoff_status(handoff_id)` - Query handoff status

**Consistency Model:**
- **Local Storage:** Thread-safe via locks (Python/Rust) or single-threaded (JS async)
- **State Transitions:** Atomic within process. PENDING → ACCEPTED/REJECTED → COMPLETED
- **Visibility:** Shared in-memory storage within same process

**Idempotency:**
- `request_handoff()`: NOT idempotent. Generates new handoff_id each time.
- `accept_handoff()`, `reject_handoff()`: NOT idempotent. Fails if handoff not in PENDING state.
- `complete_handoff()`: NOT idempotent. Fails if handoff not in ACCEPTED state.
- `get_pending_handoffs()`, `get_handoff_status()`: Read-only, inherently idempotent.

**State Persistence:**
- **In-Memory Only:** All handoff state is lost on process restart
- **Future:** gRPC service will provide persistence and distributed state

**Known Limitations:**
- Single-process only (no cross-process visibility)
- No timeout enforcement (handoffs remain PENDING indefinitely)
- No durability (state lost on crash)

### 4.5. Workflow Service (WorkflowClient)

**Current Implementation:** Local orchestration engine (Python SDK). Alias for WorkflowEngine.

**Operations:**
- Workflow definition, DAG construction, node execution
- See `sw4rm.workflow` module for full API

**Consistency Model:**
- **Local Execution:** All state in-memory within WorkflowEngine instance
- **No Distribution:** Workflow state not shared across processes

**Idempotency:**
- Workflow operations are NOT idempotent by default
- User must implement idempotency in task handlers

**State Persistence:**
- **None:** All workflow state is in-memory
- **Future:** Backend service may provide durable workflow state

### 4.6. Negotiation Room Service (NegotiationRoomClient)

**Current Implementation:** Pluggable storage backend (default: in-memory shared store)

**Operations:**
- `submit_proposal(proposal)` - Submit artifact for review
- `submit_vote(vote)` - Submit critic vote
- `get_votes(artifact_id)` - Retrieve all votes
- `get_decision(artifact_id)` - Get decision if available
- `store_decision(decision)` - Store decision (coordinator use)
- `wait_for_decision(artifact_id, timeout_s, poll_interval_s)` - Block until decision

**Consistency Model:**
- **Storage Backend:** Consistency depends on backend (InMemoryNegotiationRoomStore, JSONFile, Redis, PostgreSQL)
- **Default (InMemory):** Strong consistency within process, thread-safe via locks
- **Shared Store:** All clients using same store instance share state

**Idempotency:**
- `submit_proposal()`: NOT idempotent. Fails if `artifact_id` already exists.
- `submit_vote()`: NOT idempotent. Fails if critic already voted.
- `store_decision()`: NOT idempotent. Fails if decision already exists.
- `get_votes()`, `get_decision()`, `wait_for_decision()`: Read-only, idempotent.

**State Persistence:**
- **InMemoryNegotiationRoomStore:** No persistence, lost on process exit
- **Persistent Backends (colony/stores):** Durable storage with backend-specific guarantees

**Concurrency:**
- **v0.5.0 Fix:** Multiple client instances now share state via pluggable backend
- **Producer/Critic/Coordinator:** Can run in same or different processes if using shared backend

## 5. Error Handling

### 5.1. Error Types by SDK

**Python SDK:**
- `RuntimeError`: Protobuf stubs not generated or gRPC stub unavailable
- `ValueError`: Invalid arguments (e.g., handoff not found, priority out of range)
- `grpc.RpcError`: gRPC transport errors (connection, deadline, status codes)

**Rust SDK:**
- `Error::Config`: Invalid configuration or argument
- `Error::Connection`: Connection establishment failed
- `Error::Status(tonic::Status)`: gRPC status error
- `Error::Internal`: Lock poisoning or internal inconsistency

**JavaScript SDK:**
- `Sw4rmError`: Wrapped gRPC error with error code mapping
- `HandoffValidationError`: Handoff operation validation failed
- `HandoffTimeoutError`: Handoff request timed out
- `grpc.ServiceError`: Raw gRPC error (propagated by base client)

### 5.2. Error Recovery Guidance

**Connection Failures:**
- Retry connection establishment with exponential backoff
- Consider circuit breaker pattern after N consecutive failures
- Log connection failures for observability

**Deadline Exceeded:**
- Increase deadline for long-running operations
- Check for network latency or service overload
- May indicate need for async/streaming patterns

**Resource Exhausted:**
- Implement backoff and jitter
- Respect retry-after headers if provided
- Consider load shedding or circuit breaking

**Invalid Argument:**
- Do NOT retry - fix the request
- Validate input before submission
- Log validation errors for debugging

## 6. Production Configuration Recommendations

### 6.1. Connection Pooling

**Python:**
```python
# Share channel across clients
channel = grpc.insecure_channel('localhost:50051', options=[
    ('grpc.keepalive_time_ms', 60000),
    ('grpc.max_connection_idle_ms', 300000),
])
registry_client = RegistryClient(channel)
scheduler_client = SchedulerClient(channel)
```

**Rust:**
```rust
// tonic manages connection pooling automatically
// Share endpoint across clients if possible
let endpoint = Endpoint::from_shared("http://localhost:50051")?
    .http2_keep_alive_interval(Duration::from_secs(60));
let channel = endpoint.connect().await?;
```

**JavaScript:**
```javascript
// Create clients with shared channel via address
// Note: Retry is opt-in; configure only if your application needs it
const opts = {
  address: 'localhost:50051',
  deadlineMs: 30000,
  // Optional: Enable retry for specific use cases
  // retry: { maxAttempts: 3, initialBackoffMs: 500, maxBackoffMs: 5000, multiplier: 2 }
};
const registryClient = new RegistryClient(opts);
const schedulerClient = new SchedulerClient(opts);
```

### 6.2. Timeout Configuration

**Critical Operations (Registration, Shutdown):**
- Deadline: 30-60 seconds
- Retry: Yes, with exponential backoff

**Routine Operations (Heartbeat, Polling):**
- Deadline: 5-10 seconds
- Retry: Limited (2-3 attempts)

**Long Operations (Workflow Execution, Decision Waiting):**
- Deadline: 5-10 minutes
- Retry: Application-specific

### 6.3. Retry Budget

To prevent retry storms, implement a retry budget:

```python
class RetryBudget:
    def __init__(self, max_retry_ratio=0.1):
        self.total_requests = 0
        self.total_retries = 0
        self.max_retry_ratio = max_retry_ratio

    def can_retry(self) -> bool:
        if self.total_requests == 0:
            return True
        retry_ratio = self.total_retries / self.total_requests
        return retry_ratio < self.max_retry_ratio

    def record_request(self, retries: int):
        self.total_requests += 1
        self.total_retries += retries
```

### 6.4. Circuit Breaker Pattern

For cascading failure prevention:

```python
from enum import Enum
import time

class CircuitState(Enum):
    CLOSED = 1      # Normal operation
    OPEN = 2        # Failing, reject immediately
    HALF_OPEN = 3   # Testing if service recovered

class CircuitBreaker:
    def __init__(self, failure_threshold=5, timeout_seconds=60):
        self.failure_threshold = failure_threshold
        self.timeout_seconds = timeout_seconds
        self.failure_count = 0
        self.last_failure_time = None
        self.state = CircuitState.CLOSED

    def call(self, func, *args, **kwargs):
        if self.state == CircuitState.OPEN:
            if time.time() - self.last_failure_time > self.timeout_seconds:
                self.state = CircuitState.HALF_OPEN
            else:
                raise Exception("Circuit breaker is OPEN")

        try:
            result = func(*args, **kwargs)
            self.on_success()
            return result
        except Exception as e:
            self.on_failure()
            raise

    def on_success(self):
        self.failure_count = 0
        self.state = CircuitState.CLOSED

    def on_failure(self):
        self.failure_count += 1
        self.last_failure_time = time.time()
        if self.failure_count >= self.failure_threshold:
            self.state = CircuitState.OPEN
```

### 6.5. Observability

**Metrics to Track:**
- Request latency (p50, p95, p99)
- Request success/failure rate
- Retry count and retry ratio
- Circuit breaker state transitions
- Connection pool utilization

**Tracing:**
- Propagate `correlation_id` in metadata
- Log RPC start/end with correlation_id
- Use structured logging for searchability

**Example (Python):**
```python
import logging
import uuid

logger = logging.getLogger(__name__)

def call_with_correlation(client_method, *args, **kwargs):
    correlation_id = str(uuid.uuid4())
    logger.info("RPC start", extra={
        "correlation_id": correlation_id,
        "method": client_method.__name__
    })
    try:
        result = client_method(*args, **kwargs)
        logger.info("RPC success", extra={"correlation_id": correlation_id})
        return result
    except Exception as e:
        logger.error("RPC failed", extra={
            "correlation_id": correlation_id,
            "error": str(e)
        })
        raise
```

## 7. Known Limitations and Edge Cases

### 7.1. Handoff Service

**Limitation:** In-memory only, no distributed state
**Impact:** Handoffs only work within single process
**Workaround:** Use persistent backend or wait for gRPC service implementation
**Timeline:** gRPC service planned for v0.7.0

### 7.2. Workflow Orchestration

**Limitation:** Local execution engine, no backend service
**Impact:** Workflows cannot span multiple processes
**Workaround:** Use external workflow engine (Temporal, Cadence) for distributed workflows
**Timeline:** Backend service planned for v0.8.0

### 7.3. Negotiation Room Concurrency

**Fixed in v0.5.0:** Multiple client instances now share state via pluggable backend
**Migration:** Update to use shared default store or explicit store instances
**See:** Migration guide in `sdks/py_sdk/CHANGELOG.md`

### 7.4. Activity Buffer Bounds

**Limitation:** Activity buffer has finite capacity (implementation-dependent)
**Impact:** Old activity entries may be evicted under load
**Workaround:** Poll and archive activity regularly
**Recommendation:** Purge processed activity to free space

### 7.5. Negotiation Timeout Enforcement

**Limitation:** `debate_timeout` enforcement is best-effort
**Impact:** Negotiations may exceed specified timeout
**Workaround:** Implement application-level timeout monitoring
**Recommendation:** Use conservative timeouts with margin

### 7.6. Shared Channel Safety

**Python:** Channel sharing is thread-safe (gRPC guarantee)
**Rust:** Channel cloning is safe (Arc-based internally)
**JavaScript:** Client instances are NOT thread-safe (Node.js is single-threaded)

### 7.7. Protobuf Stub Availability

**Python:** Clients check for protobuf stubs and raise `RuntimeError` if not generated
**Rust:** Proto generation is build-time via `build.rs` (compile-time guarantee)
**JavaScript:** Proto loading is dynamic at runtime (may fail on missing proto files)

**Resolution:** Run `make protos` before using SDK clients

## 8. Version Compatibility

**SDK Version:** 0.5.0
**Protocol Version:** 0.5.0
**Proto Compatibility:** All SDKs use same proto definitions from `protos/`

**Backward Compatibility:**
- SDKs maintain backward compatibility within MINOR versions (0.x.y)
- Breaking changes increment MINOR version until 1.0 (per semver pre-1.0 rules)
- Protobuf additions (new fields) are backward-compatible
- Service method additions do not break existing clients

**Forward Compatibility:**
- Older clients MAY work with newer servers (server ignores unknown fields)
- Newer clients MAY fail with older servers (missing RPC methods)
- Always deploy clients and servers with matching MINOR versions

## 9. Security Considerations

### 9.1. Transport Security

**Current:** All SDKs default to insecure channels (no TLS)
**Production:** MUST use TLS in production environments

**Python:**
```python
credentials = grpc.ssl_channel_credentials()
channel = grpc.secure_channel('server:50051', credentials)
```

**Rust:**
```rust
let endpoint = Endpoint::from_shared("https://server:50051")?
    .tls_config(ClientTlsConfig::new())?;
```

**JavaScript:**
```javascript
const credentials = grpc.credentials.createSsl();
// Configure via gRPC-JS channel options
```

### 9.2. Authentication

**Current:** No authentication by default
**Recommendation:** Implement metadata-based auth (API keys, JWT)

**Example (Python):**
```python
class AuthInterceptor(grpc.UnaryUnaryClientInterceptor):
    def __init__(self, api_key):
        self.api_key = api_key

    def intercept_unary_unary(self, continuation, client_call_details, request):
        metadata = list(client_call_details.metadata or [])
        metadata.append(('authorization', f'Bearer {self.api_key}'))
        new_details = client_call_details._replace(metadata=metadata)
        return continuation(new_details, request)

channel = grpc.insecure_channel('localhost:50051')
intercepted_channel = grpc.intercept_channel(channel, AuthInterceptor('my-api-key'))
```

### 9.3. Input Validation

**All SDKs:** Basic validation (e.g., priority range in SchedulerClient)
**Responsibility:** Clients SHOULD validate inputs before submission
**Server-Side:** Services MUST validate all inputs and reject invalid requests

## 10. References

- SW4RM Protocol Specification: `documentation/protocol/spec.md`
- SDK Implementation Progress: `sdks/SDK_IMPLEMENTATION_PROGRESS.md`
- Python SDK README: `sdks/py_sdk/README.md`
- Rust SDK README: `sdks/rust_sdk/README.md`
- JavaScript SDK README: `sdks/js_sdk/README.md`

---

**Document Status:** Normative
**Maintenance:** This document MUST be updated when SDK operational behavior changes
**Review Cycle:** Quarterly or before MINOR version releases
