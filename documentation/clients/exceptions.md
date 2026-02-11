# Exception Types Reference

This document provides a comprehensive reference for all exception types in the SW4RM Python SDK, including the exception hierarchy, fields, error codes, and usage patterns.

## Exception Hierarchy

The SW4RM SDK defines a structured exception hierarchy for different error categories:

```
SW4RMError (base)
├── ValidationError
├── RPCError
├── PolicyViolationError
├── TimeoutError
├── PreemptionError
├── WorktreeError
├── NegotiationError
└── StateTransitionError

WorkflowEngineError (separate base)
├── CycleDetectedError
└── WorkflowValidationError

WorkflowBuilderError (standalone)

SecretError (base)
├── SecretNotFound
├── SecretScopeError
├── SecretBackendError
├── SecretPermissionError
└── SecretValidationError
```

## Core Exceptions

### SW4RMError

Base exception for all SW4RM errors. All SDK-specific exceptions inherit from this class.

**Source:** `sw4rm/exceptions.py`

```python
class SW4RMError(Exception):
    """Base exception for all SW4RM errors.

    Attributes:
        message: Human-readable error description
        error_code: Protocol error code from constants.py
    """

    def __init__(
        self,
        message: str,
        error_code: Optional[int] = None
    ) -> None: ...

    def to_dict(self) -> dict[str, Any]:
        """Serialize exception for logging/debugging."""
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `message` | `str` | Required | Human-readable error description |
| `error_code` | `int` | `INTERNAL_ERROR` | Protocol error code |

**Usage:**

```python
from sw4rm.exceptions import SW4RMError

try:
    agent.process_message(envelope)
except SW4RMError as e:
    print(f"SW4RM error: {e.message}")
    print(f"Error code: {e.error_code}")
    log_error(e.to_dict())
```

### RPCError

Exception for gRPC communication failures.

```python
class RPCError(SW4RMError):
    """Exception for gRPC communication failures.

    Attributes:
        status_code: gRPC status code (e.g., "UNAVAILABLE")
        details: Detailed error information from gRPC
    """

    def __init__(
        self,
        message: str,
        status_code: str,
        details: str,
        error_code: Optional[int] = None  # defaults to NO_ROUTE
    ) -> None: ...
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `message` | `str` | Required | Human-readable error description |
| `status_code` | `str` | Required | gRPC status code |
| `details` | `str` | Required | Detailed error information |
| `error_code` | `int` | `NO_ROUTE` | Protocol error code |

**Common gRPC Status Codes:**

| Status | Description |
|--------|-------------|
| `UNAVAILABLE` | Service temporarily unavailable |
| `DEADLINE_EXCEEDED` | Request timeout |
| `NOT_FOUND` | Resource not found |
| `PERMISSION_DENIED` | Authorization failed |
| `INTERNAL` | Internal server error |

**Usage:**

```python
from sw4rm.exceptions import RPCError

try:
    router.send_message(envelope)
except RPCError as e:
    if e.status_code == "UNAVAILABLE":
        # Retry with backoff
        retry_with_backoff(lambda: router.send_message(envelope))
    elif e.status_code == "DEADLINE_EXCEEDED":
        # Increase timeout
        router.send_message(envelope, timeout_ms=60000)
    else:
        raise
```

### ValidationError

Exception for input validation failures.

```python
class ValidationError(SW4RMError):
    """Exception for input validation failures.

    Attributes:
        field: Name of the field that failed validation
        constraint: Description of the violated constraint
    """

    def __init__(
        self,
        message: str,
        field: str,
        constraint: str,
        error_code: Optional[int] = None  # defaults to VALIDATION_ERROR
    ) -> None: ...
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `message` | `str` | Required | Human-readable error description |
| `field` | `str` | Required | Field that failed validation |
| `constraint` | `str` | Required | Violated constraint description |
| `error_code` | `int` | `VALIDATION_ERROR` | Protocol error code |

**Usage:**

```python
from sw4rm.exceptions import ValidationError

def validate_envelope(envelope: dict) -> None:
    if "producer_id" not in envelope:
        raise ValidationError(
            message="Missing required field",
            field="producer_id",
            constraint="required"
        )

    if len(envelope.get("payload", b"")) > 1_000_000:
        raise ValidationError(
            message="Payload too large",
            field="payload",
            constraint="max_size=1000000"
        )
```

### StateTransitionError

Exception for invalid agent state transitions.

```python
class StateTransitionError(SW4RMError):
    """Exception for invalid agent state transitions.

    Attributes:
        current_state: The agent's current state
        requested_state: The state that was requested
        allowed_transitions: List of valid transitions from current state
    """

    def __init__(
        self,
        message: str,
        current_state: str,
        requested_state: str,
        allowed_transitions: list[str],
        error_code: Optional[int] = None  # defaults to INTERNAL_ERROR
    ) -> None: ...
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `message` | `str` | Required | Human-readable error description |
| `current_state` | `str` | Required | Current agent state |
| `requested_state` | `str` | Required | Requested target state |
| `allowed_transitions` | `list[str]` | Required | Valid transitions from current |
| `error_code` | `int` | `INTERNAL_ERROR` | Protocol error code |

**Usage:**

```python
from sw4rm.exceptions import StateTransitionError

try:
    agent.schedule("task-123")
except StateTransitionError as e:
    print(f"Cannot transition from {e.current_state} to {e.requested_state}")
    print(f"Allowed transitions: {e.allowed_transitions}")
    # Agent may need to complete initialization first
    if e.current_state == "INITIALIZING":
        agent.start()
        agent.schedule("task-123")
```

### PolicyViolationError

Exception for policy enforcement failures.

```python
class PolicyViolationError(SW4RMError):
    """Exception for policy enforcement failures.

    Attributes:
        policy_id: Identifier of the violated policy
        violation: Description of what was violated
    """

    def __init__(
        self,
        message: str,
        policy_id: str,
        violation: str,
        error_code: Optional[int] = None  # defaults to PERMISSION_DENIED
    ) -> None: ...
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `message` | `str` | Required | Human-readable error description |
| `policy_id` | `str` | Required | Violated policy identifier |
| `violation` | `str` | Required | Violation description |
| `error_code` | `int` | `PERMISSION_DENIED` | Protocol error code |

**Usage:**

```python
from sw4rm.exceptions import PolicyViolationError

try:
    scheduler.dispatch_task(task, agent_id)
except PolicyViolationError as e:
    print(f"Policy {e.policy_id} violated: {e.violation}")
    # May need to request permission or use different agent
```

### TimeoutError

Exception for operation timeouts.

```python
class TimeoutError(SW4RMError):
    """Exception for operation timeouts.

    Note: Shadows built-in TimeoutError for SW4RM-specific context.

    Attributes:
        operation: Name of the timed-out operation
        timeout_ms: Timeout duration in milliseconds
    """

    def __init__(
        self,
        message: str,
        operation: str,
        timeout_ms: int,
        error_code: Optional[int] = None  # defaults to ACK_TIMEOUT
    ) -> None: ...
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `message` | `str` | Required | Human-readable error description |
| `operation` | `str` | Required | Timed-out operation name |
| `timeout_ms` | `int` | Required | Timeout duration in ms |
| `error_code` | `int` | `ACK_TIMEOUT` | Protocol error code |

**Usage:**

```python
from sw4rm.exceptions import TimeoutError

try:
    result = tool_client.call(tool_name, args, timeout_ms=30000)
except TimeoutError as e:
    print(f"Operation {e.operation} timed out after {e.timeout_ms}ms")
    # Consider increasing timeout or falling back
```

### PreemptionError

Exception for preemption-related failures.

```python
class PreemptionError(SW4RMError):
    """Exception for preemption-related failures.

    Attributes:
        reason: Explanation of why preemption occurred
        was_forced: Whether this was a forced (non-graceful) preemption
    """

    def __init__(
        self,
        message: str,
        reason: str,
        was_forced: bool,
        error_code: Optional[int] = None  # FORCED_PREEMPTION if forced
    ) -> None: ...
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `message` | `str` | Required | Human-readable error description |
| `reason` | `str` | Required | Preemption reason |
| `was_forced` | `bool` | Required | Whether forced preemption |
| `error_code` | `int` | `FORCED_PREEMPTION`/`INTERNAL_ERROR` | Protocol error code |

### WorktreeError

Exception for worktree binding and management failures.

```python
class WorktreeError(SW4RMError):
    """Exception for worktree binding and management failures.

    Attributes:
        worktree_id: Identifier of the affected worktree
        state: Current state of the worktree
    """

    def __init__(
        self,
        message: str,
        worktree_id: str,
        state: str,
        error_code: Optional[int] = None  # defaults to INTERNAL_ERROR
    ) -> None: ...
```

### NegotiationError

Exception for negotiation protocol failures.

```python
class NegotiationError(SW4RMError):
    """Exception for negotiation protocol failures.

    Attributes:
        negotiation_id: Identifier of the failed negotiation
        phase: Current phase of the negotiation
    """

    def __init__(
        self,
        message: str,
        negotiation_id: str,
        phase: str,
        error_code: Optional[int] = None  # defaults to INTERNAL_ERROR
    ) -> None: ...
```

## Workflow Exceptions

**Source:** `sw4rm/workflow/engine.py`

### WorkflowEngineError

Base exception for workflow engine errors.

```python
class WorkflowEngineError(Exception):
    """Base exception for workflow engine errors."""
    pass
```

### CycleDetectedError

Raised when a cycle is detected in the workflow DAG.

```python
class CycleDetectedError(WorkflowEngineError):
    """Raised when a cycle is detected in the workflow DAG.

    Attributes:
        cycle_path: List of node IDs forming the cycle
    """

    def __init__(self, cycle_path: list[str]) -> None: ...
```

| Field | Type | Description |
|-------|------|-------------|
| `cycle_path` | `list[str]` | Node IDs forming the cycle (e.g., `["A", "B", "C", "A"]`) |

**Usage:**

```python
from sw4rm.workflow.engine import WorkflowEngine, CycleDetectedError

try:
    engine = WorkflowEngine(workflow_def)
except CycleDetectedError as e:
    print(f"Workflow has cycle: {' -> '.join(e.cycle_path)}")
    # Fix the workflow definition to remove the cycle
```

### WorkflowValidationError

Raised when workflow validation fails.

```python
class WorkflowValidationError(WorkflowEngineError):
    """Raised when workflow validation fails."""
    pass
```

## Secret Exceptions

**Source:** `sw4rm/secrets/errors.py`

### SecretError

Base exception for all secret-related errors.

```python
class SecretError(Exception):
    """Base exception for secret management errors."""
    pass
```

### SecretNotFound

Raised when a secret is not found.

```python
class SecretNotFound(SecretError):
    """Raised when a secret is not found.

    Attributes:
        scope: The secret scope
        key: The secret key that was not found
    """

    def __init__(self, scope: str, key: str) -> None: ...
```

**Usage:**

```python
from sw4rm.secrets.errors import SecretNotFound

try:
    api_key = secrets.get("production", "api_key")
except SecretNotFound as e:
    print(f"Secret not found: scope={e.scope} key={e.key}")
```

### Other Secret Exceptions

| Exception | When Raised |
|-----------|-------------|
| `SecretScopeError` | Invalid or inaccessible scope |
| `SecretBackendError` | Backend storage failure |
| `SecretPermissionError` | Insufficient permissions |
| `SecretValidationError` | Invalid secret format or value |

## Error Codes Reference

Error codes are defined in `sw4rm/constants.py`:

| Constant | Value | Description |
|----------|-------|-------------|
| `ERROR_CODE_UNSPECIFIED` | 0 | No error code specified |
| `BUFFER_FULL` | 1 | Message buffer is full |
| `NO_ROUTE` | 2 | No route to destination |
| `ACK_TIMEOUT` | 3 | ACK not received in time |
| `AGENT_UNAVAILABLE` | 4 | Target agent not available |
| `AGENT_SHUTDOWN` | 5 | Agent is shutting down |
| `VALIDATION_ERROR` | 6 | Input validation failed |
| `PERMISSION_DENIED` | 7 | Permission denied |
| `UNSUPPORTED_MESSAGE_TYPE` | 8 | Message type not supported |
| `OVERSIZE_PAYLOAD` | 9 | Payload exceeds size limit |
| `TOOL_TIMEOUT` | 10 | Tool execution timeout |
| `PARTIAL_DELIVERY` | 11 | Partial delivery (reserved) |
| `FORCED_PREEMPTION` | 12 | Agent forcefully preempted |
| `TTL_EXPIRED` | 13 | Message TTL expired |
| `DUPLICATE_DETECTED` | 14 | Duplicate idempotency token |
| `INTERNAL_ERROR` | 99 | Internal server error |

## Catching Exceptions

### Catch All SW4RM Errors

```python
from sw4rm.exceptions import SW4RMError

try:
    process_message(envelope)
except SW4RMError as e:
    logger.error(f"SW4RM error: {e.to_dict()}")
    send_error_ack(envelope, e.error_code)
```

### Catch Specific Errors

```python
from sw4rm.exceptions import (
    SW4RMError,
    ValidationError,
    RPCError,
    TimeoutError,
    StateTransitionError,
)

def handle_message(agent, message):
    try:
        agent.process(message)
    except ValidationError as e:
        logger.warning(f"Validation failed: {e.field} - {e.constraint}")
        return {"error": "invalid_input", "field": e.field}
    except RPCError as e:
        logger.error(f"RPC failed: {e.status_code}")
        if e.status_code in ("UNAVAILABLE", "DEADLINE_EXCEEDED"):
            schedule_retry(message)
        else:
            return {"error": "service_error"}
    except TimeoutError as e:
        logger.warning(f"Timeout: {e.operation} after {e.timeout_ms}ms")
        return {"error": "timeout"}
    except StateTransitionError as e:
        logger.error(f"Invalid state: {e.current_state} -> {e.requested_state}")
        return {"error": "invalid_state"}
    except SW4RMError as e:
        logger.error(f"Unexpected SW4RM error: {e}")
        return {"error": "internal_error"}
```

### Serialize for Logging

```python
import json
from sw4rm.exceptions import SW4RMError

try:
    risky_operation()
except SW4RMError as e:
    # to_dict() returns all relevant fields
    error_data = e.to_dict()
    logger.error(json.dumps(error_data))

    # Example output:
    # {
    #   "type": "ValidationError",
    #   "message": "Invalid payload format",
    #   "error_code": 6,
    #   "field": "payload",
    #   "constraint": "json_format"
    # }
```

## See Also

- [Error Handling Patterns](error-handling.md) - Client-specific error handling
- [State Machines](../architecture/state-machines.md) - StateTransitionError context
- [ACK Lifecycle](../protocol/acks.md) - Error codes in acknowledgments
