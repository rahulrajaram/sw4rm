# Error Handling Patterns

This guide provides client-specific error handling patterns for SW4RM SDK clients. Each pattern addresses common failure modes and provides robust recovery strategies.

## Universal Pattern: Protobuf Stub Validation

All SW4RM clients require generated protobuf stubs. If stubs are missing, clients raise `RuntimeError`:

```python
from sw4rm.clients import RouterClient
import sys

try:
    client = RouterClient(channel)
    client.send_message(envelope)
except RuntimeError as e:
    if "Protobuf stubs not generated" in str(e):
        print("Error: Protobuf stubs not generated")
        print("Run: make protos")
        print("Or: python -m grpc_tools.protoc ...")
        sys.exit(1)
    raise
```

### Checking Stubs at Startup

```python
def check_protos_available() -> bool:
    """Check if protobuf stubs are available."""
    try:
        from sw4rm_proto import common_pb2, router_pb2
        return True
    except ImportError:
        return False

if not check_protos_available():
    print("Missing protobuf stubs. Run: make protos")
    sys.exit(1)
```

## Pattern: RPC Error Handling with Retry

gRPC errors require different handling based on the status code:

```python
from sw4rm.exceptions import RPCError
import time
import random

def send_with_retry(
    router,
    envelope,
    max_retries: int = 3,
    base_delay: float = 1.0
) -> None:
    """Send message with exponential backoff retry."""

    last_error = None

    for attempt in range(max_retries):
        try:
            router.send_message(envelope)
            return  # Success
        except RPCError as e:
            last_error = e

            # Determine if error is retryable
            if e.status_code in ("UNAVAILABLE", "DEADLINE_EXCEEDED", "RESOURCE_EXHAUSTED"):
                # Exponential backoff with jitter
                delay = base_delay * (2 ** attempt)
                jitter = random.uniform(0, delay * 0.1)
                time.sleep(delay + jitter)
                continue
            elif e.status_code in ("PERMISSION_DENIED", "UNAUTHENTICATED"):
                # Auth errors: don't retry, may need re-auth
                raise
            elif e.status_code == "NOT_FOUND":
                # Resource missing: don't retry
                raise
            else:
                # Unknown error: limited retry
                if attempt < 1:
                    time.sleep(base_delay)
                    continue
                raise

    raise last_error
```

### Status Code Decision Matrix

| Status Code | Retryable | Action |
|-------------|-----------|--------|
| `UNAVAILABLE` | Yes | Retry with backoff |
| `DEADLINE_EXCEEDED` | Yes | Retry, consider longer timeout |
| `RESOURCE_EXHAUSTED` | Yes | Retry with longer backoff |
| `ABORTED` | Yes | Retry immediately |
| `PERMISSION_DENIED` | No | Check credentials |
| `UNAUTHENTICATED` | No | Re-authenticate |
| `NOT_FOUND` | No | Resource doesn't exist |
| `INVALID_ARGUMENT` | No | Fix request |
| `INTERNAL` | Maybe | Limited retry |

## Pattern: Timeout Handling

Timeouts require context-aware handling:

```python
from sw4rm.exceptions import TimeoutError as SW4RMTimeout

class TimeoutHandler:
    """Context-aware timeout handling."""

    def __init__(self, default_timeout_ms: int = 30000):
        self.default_timeout_ms = default_timeout_ms
        self.timeout_history = {}  # operation -> [durations]

    def call_with_adaptive_timeout(
        self,
        operation: str,
        func,
        *args,
        **kwargs
    ):
        """Call function with adaptive timeout based on history."""

        # Calculate timeout based on history
        timeout_ms = self._get_adaptive_timeout(operation)
        kwargs["timeout_ms"] = timeout_ms

        start = time.time()
        try:
            result = func(*args, **kwargs)
            duration_ms = int((time.time() - start) * 1000)
            self._record_success(operation, duration_ms)
            return result
        except SW4RMTimeout as e:
            self._record_timeout(operation, e.timeout_ms)
            raise

    def _get_adaptive_timeout(self, operation: str) -> int:
        """Get timeout based on historical performance."""
        if operation not in self.timeout_history:
            return self.default_timeout_ms

        durations = self.timeout_history[operation]
        if not durations:
            return self.default_timeout_ms

        # Use 95th percentile + 50% buffer
        p95 = sorted(durations)[int(len(durations) * 0.95)]
        return int(p95 * 1.5)

    def _record_success(self, operation: str, duration_ms: int) -> None:
        if operation not in self.timeout_history:
            self.timeout_history[operation] = []
        self.timeout_history[operation].append(duration_ms)
        # Keep last 100 samples
        self.timeout_history[operation] = self.timeout_history[operation][-100:]

    def _record_timeout(self, operation: str, timeout_ms: int) -> None:
        # Timeout suggests we need longer timeout next time
        if operation not in self.timeout_history:
            self.timeout_history[operation] = []
        # Record timeout as at least the timeout value (since we don't know actual)
        self.timeout_history[operation].append(timeout_ms)
```

### Simple Timeout Pattern

```python
from sw4rm.exceptions import TimeoutError

def wait_for_decision(room, artifact_id, timeout_ms=30000):
    """Wait for negotiation decision with timeout handling."""
    try:
        decision = room.wait_for_decision(artifact_id, timeout_ms=timeout_ms)
        return decision
    except TimeoutError as e:
        print(f"Decision timed out after {e.timeout_ms}ms")

        # Option 1: Extend timeout and retry
        if timeout_ms < 120000:  # Max 2 minutes
            return wait_for_decision(room, artifact_id, timeout_ms * 2)

        # Option 2: Escalate to HITL
        escalate_to_human(artifact_id, "Negotiation timeout")

        # Option 3: Use default decision
        return {"decision": "timeout", "action": "reject"}
```

## Pattern: Validation Errors

Handle validation at client vs. protocol level:

```python
from sw4rm.exceptions import ValidationError

def process_vote(room, vote: dict) -> None:
    """Process a negotiation vote with validation handling."""

    # Client-side validation (ValueError)
    try:
        if not 0 <= vote.get("score", 0) <= 100:
            raise ValueError("Score must be between 0 and 100")

        if not vote.get("critic_id"):
            raise ValueError("critic_id is required")

        room.add_vote(vote)

    except ValueError as e:
        # Client-level validation failure
        print(f"Invalid vote data: {e}")
        return

    except ValidationError as e:
        # Protocol-level validation (server rejected)
        print(f"Server rejected vote: {e.field} - {e.constraint}")

        if e.field == "artifact_id":
            print("Artifact may have expired or been resolved")
        elif e.field == "critic_id":
            print("Critic not registered for this negotiation")
```

### Validation Error Context

| Source | Exception Type | When |
|--------|---------------|------|
| Client-side | `ValueError` | Before network call |
| Protocol-side | `ValidationError` | Server rejected request |

## Pattern: State Transition Errors

Handle agent lifecycle errors gracefully:

```python
from sw4rm.runtime.agent import Agent, AgentState
from sw4rm.exceptions import StateTransitionError

class ResilientAgent(Agent):
    """Agent with graceful state error handling."""

    def safe_schedule(self, task_id: str) -> bool:
        """Attempt to schedule with state awareness."""
        try:
            self.schedule(task_id)
            return True
        except StateTransitionError as e:
            return self._handle_schedule_error(e, task_id)

    def _handle_schedule_error(
        self,
        error: StateTransitionError,
        task_id: str
    ) -> bool:
        """Handle scheduling failure based on current state."""

        if error.current_state == "INITIALIZING":
            # Need to complete initialization first
            self.start()
            return self.safe_schedule(task_id)

        elif error.current_state == "SUSPENDED":
            # Resume then schedule
            self.resume()
            self.run()  # Back to RUNNING first
            self.complete()  # Finish current work
            # Now agent should be schedulable
            return False  # Caller should retry

        elif error.current_state == "RUNNING":
            # Already busy
            print(f"Agent busy with task: {self.current_task_id}")
            return False

        elif error.current_state == "FAILED":
            # Attempt recovery first
            self.recover()
            # Recovery might take time, return False
            return False

        else:
            # Unexpected state
            print(f"Cannot schedule from state: {error.current_state}")
            print(f"Allowed transitions: {error.allowed_transitions}")
            return False
```

## Pattern: Graceful Shutdown

Ensure clean shutdown even when errors occur:

```python
import signal
import sys
from contextlib import contextmanager

@contextmanager
def graceful_agent_lifecycle(agent, registry):
    """Context manager for graceful agent lifecycle."""

    # Track if we successfully registered
    registered = False

    def shutdown_handler(signum, frame):
        nonlocal registered
        if registered:
            try:
                registry.deregister(agent.agent_id, reason="shutdown")
            except Exception:
                pass  # Best effort
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown_handler)
    signal.signal(signal.SIGTERM, shutdown_handler)

    try:
        registry.register(agent.descriptor)
        registered = True
        yield agent
    except KeyboardInterrupt:
        pass
    finally:
        if registered:
            try:
                registry.deregister(agent.agent_id, reason="shutdown")
            except Exception:
                pass  # Best effort cleanup

# Usage
with graceful_agent_lifecycle(my_agent, registry) as agent:
    for message in router.stream_incoming(agent.agent_id):
        process(message)
```

### Shutdown with Activity Buffer Flush

```python
class ProductionAgent:
    """Agent with proper shutdown handling."""

    def __init__(self, agent_id: str, data_dir: str):
        self.agent_id = agent_id
        self.buffer = PersistentActivityBuffer(
            persistence=JSONFilePersistence(f"{data_dir}/activity.json")
        )
        self._setup_shutdown_handlers()

    def _setup_shutdown_handlers(self):
        signal.signal(signal.SIGINT, self._shutdown)
        signal.signal(signal.SIGTERM, self._shutdown)

    def _shutdown(self, signum, frame):
        print("Shutting down gracefully...")

        # Flush activity buffer
        try:
            self.buffer.flush()
            print("Activity buffer flushed")
        except Exception as e:
            print(f"Warning: Buffer flush failed: {e}")

        # Deregister
        try:
            self.registry.deregister(self.agent_id, reason="shutdown")
            print("Agent deregistered")
        except Exception as e:
            print(f"Warning: Deregistration failed: {e}")

        sys.exit(0)
```

## Pattern: Circuit Breaker

Protect against cascading failures:

```python
from enum import Enum
import time
from sw4rm.exceptions import RPCError

class CircuitState(Enum):
    CLOSED = "closed"      # Normal operation
    OPEN = "open"          # Failing, reject requests
    HALF_OPEN = "half_open"  # Testing if recovered

class CircuitBreaker:
    """Circuit breaker for SW4RM client calls."""

    def __init__(
        self,
        failure_threshold: int = 5,
        recovery_timeout_s: float = 30.0
    ):
        self.failure_threshold = failure_threshold
        self.recovery_timeout_s = recovery_timeout_s
        self.state = CircuitState.CLOSED
        self.failures = 0
        self.last_failure_time = 0

    def call(self, func, *args, **kwargs):
        """Execute function through circuit breaker."""

        if self.state == CircuitState.OPEN:
            if time.time() - self.last_failure_time > self.recovery_timeout_s:
                self.state = CircuitState.HALF_OPEN
            else:
                raise RuntimeError("Circuit breaker is OPEN")

        try:
            result = func(*args, **kwargs)
            self._record_success()
            return result
        except RPCError as e:
            self._record_failure()
            raise

    def _record_success(self):
        self.failures = 0
        if self.state == CircuitState.HALF_OPEN:
            self.state = CircuitState.CLOSED

    def _record_failure(self):
        self.failures += 1
        self.last_failure_time = time.time()
        if self.failures >= self.failure_threshold:
            self.state = CircuitState.OPEN


# Usage
router_breaker = CircuitBreaker(failure_threshold=3, recovery_timeout_s=60)

try:
    router_breaker.call(router.send_message, envelope)
except RuntimeError as e:
    if "Circuit breaker is OPEN" in str(e):
        # Service is down, use fallback
        queue_for_later(envelope)
```

## Client Error Summary

| Client | Common Errors | Handling Strategy |
|--------|--------------|-------------------|
| `RouterClient` | `RPCError`, `TimeoutError` | Retry with backoff, queue on failure |
| `RegistryClient` | `RPCError`, `ValidationError` | Validate before send, cache discovery |
| `SchedulerClient` | `RPCError`, `PolicyViolationError` | Check policies, handle rejection |
| `NegotiationRoomClient` | `ValueError`, `TimeoutError` | Validate votes, set appropriate timeout |
| `WorkflowClient` | `CycleDetectedError`, `WorkflowBuilderError` | Validate DAG structure before execution |
| `HandoffClient` | `RPCError`, `ValidationError` | Validate capabilities, handle rejection |
| `ToolClient` | `TimeoutError`, `RPCError` | Timeout handling, fallback tools |

## Best Practices

1. **Always handle stub errors at startup** - Check proto availability before creating clients

2. **Use specific exception types** - Catch specific errors before SW4RMError for appropriate handling

3. **Implement retry with backoff** - Use exponential backoff for transient errors

4. **Log error context** - Use `to_dict()` for structured logging

5. **Graceful degradation** - Have fallback strategies for critical paths

6. **Clean shutdown** - Always flush buffers and deregister on exit

7. **Circuit breakers for resilience** - Prevent cascading failures in distributed scenarios

## Dead Letter Queue (DLQ)

When messages exhaust their retry budget or encounter terminal errors, the Router moves them to a Dead Letter Queue for operator triage. Per spec §21.1, messages MUST be moved to DLQ when any of the following occur:

- **Retry budget exhausted** without successful processing.
- **Terminal error** indicating the operation cannot succeed (validation error, permission denied, malformed message).
- **Policy violation** (security, resource limits) or TTL expiry.

### DLQ Entry Contents

Each DLQ entry MUST include diagnostic context sufficient for operator triage:

| Field | Description |
|-------|-------------|
| Final error classification | The terminal error code and stage |
| Attempt history | Timestamps and failure reasons for each retry attempt |
| Routing context | Producer ID, route, hops traversed |
| Creation and failure times | When the message was created and when it finally failed |
| Payload size and content type | Message metadata for inspection |
| Payload excerpt or reference | Either a truncated payload or a secure reference to the full payload |

### DLQ Operations

Implementations SHOULD provide inspection and reprocessing tools. Operators MUST be able to:

- **Requeue** selected DLQ entries for reprocessing.
- **Export** diagnostic bundles for analysis.
- **Filter** entries by time range, error class, route, or producer.

### DLQ Retention

Implementations SHOULD enforce retention policies to bound storage. Configure retention based on:

- **Time-based eviction**: Remove entries older than a configured threshold (e.g., 30 days).
- **Count-based eviction**: Cap the total number of DLQ entries per route or producer.

### Python Example

```python
# DLQ inspection pattern (conceptual)
from sw4rm.clients import RouterClient

router = RouterClient(channel)

# List DLQ entries filtered by error class
dlq_entries = router.list_dlq(
    error_class="ack_timeout",
    time_from="2026-02-01T00:00:00Z",
    limit=50,
)

for entry in dlq_entries:
    print(f"message_id={entry.message_id} error={entry.error_code} "
          f"attempts={entry.retry_count} producer={entry.producer_id}")

# Requeue a specific entry for reprocessing
router.requeue_dlq(message_id=entry.message_id)
```

## See Also

- [Exceptions Reference](exceptions.md) - Complete exception hierarchy
- [State Machines](../architecture/state-machines.md) - Agent state errors
- [Activity Buffer](../protocol/activity-buffer.md) - Message persistence and recovery
