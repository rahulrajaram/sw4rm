# SW4RM SDK Error Codes and Exception Handling

This document defines standard error codes and exception handling patterns for all SW4RM SDKs (Python, Rust, TypeScript).

## Status: Phase 2 (In-Memory Mode)

**Current Implementation**: All SDKs are in Phase 2 and use **in-memory storage** with **SDK-native exceptions**. They do not yet use gRPC status codes because they haven't integrated with actual gRPC services.

**Future Migration**: When migrating to Phase 3 (gRPC integration), all SDKs must map their errors to standard gRPC status codes defined in this document.

---

## Standard Error Code Mapping

### gRPC Status Codes (Future Phase 3)

When implementing gRPC clients, SDKs MUST use these standard status codes:

| Operation | Condition | gRPC Status Code | Description |
|-----------|-----------|-----------------|-------------|
| **Not Found** | Resource doesn't exist | `NOT_FOUND` (5) | Handoff ID, artifact ID, workflow ID, or instance ID not found |
| **Already Exists** | Duplicate resource | `ALREADY_EXISTS` (6) | Proposal, workflow definition, or handoff request with same ID already exists |
| **Invalid Argument** | Validation failure | `INVALID_ARGUMENT` (3) | Invalid score range, confidence range, empty required field, malformed input |
| **Failed Precondition** | Invalid state transition | `FAILED_PRECONDITION` (9) | Handoff not in PENDING status, workflow already terminal, double-vote attempt |
| **Permission Denied** | Authorization failure | `PERMISSION_DENIED` (7) | Agent lacks capability to accept handoff, unauthorized to submit proposal |
| **Resource Exhausted** | Rate limit / quota | `RESOURCE_EXHAUSTED` (8) | Too many pending handoffs, workflow instance limit exceeded |
| **Deadline Exceeded** | Timeout | `DEADLINE_EXCEEDED` (4) | Handoff timeout, decision wait timeout |
| **Internal** | Server error | `INTERNAL` (13) | Lock poisoned, storage backend failure, unexpected panic |
| **Unavailable** | Service down | `UNAVAILABLE` (14) | gRPC service unreachable, connection lost |
| **Unimplemented** | Feature not ready | `UNIMPLEMENTED` (12) | gRPC stub configured but service not deployed |

### Cross-SDK Error Mapping Table

| Error Scenario | Python SDK (Phase 2) | Rust SDK (Phase 2) | TypeScript SDK (Phase 2) | Future gRPC Status |
|----------------|----------------------|--------------------|--------------------------|-------------------|
| **Handoff not found** | `ValueError("Handoff {id} not found")` | `Error::Config("Handoff {id} not found")` | `HandoffValidationError("No handoff request found with ID '{id}'")` | `NOT_FOUND` |
| **Handoff already responded** | `ValueError("Handoff {id} has already been responded to")` | `Error::Config("Handoff {id} is not in PENDING status")` | `HandoffValidationError("Handoff request '{id}' has already been responded to")` | `FAILED_PRECONDITION` |
| **Proposal already exists** | `ValueError("Proposal with artifact_id '{id}' already exists")` | `Error::Config("Proposal with artifact_id '{id}' already exists")` | `NegotiationRoomStoreError("Proposal with artifact_id '{id}' already exists")` | `ALREADY_EXISTS` |
| **Proposal not found** | `ValueError("No proposal found for artifact_id '{id}'")` | `Error::Config("No proposal found for artifact_id '{id}'")` | `NegotiationValidationError("No proposal found for artifact_id '{id}'")` | `NOT_FOUND` |
| **Critic already voted** | `ValueError("Critic '{id}' has already voted for artifact '{id}'")` | `Error::Config("Critic '{id}' has already voted for artifact '{id}'")` | `NegotiationRoomStoreError("Critic '{id}' has already voted for artifact '{id}'")` | `FAILED_PRECONDITION` |
| **Decision already exists** | `ValueError("Decision already exists for artifact_id '{id}'")` | `Error::Config("Decision already exists for artifact_id '{id}'")` | `NegotiationRoomStoreError("Decision already exists for artifact_id '{id}'")` | `ALREADY_EXISTS` |
| **Workflow already exists** | N/A (workflow is alias) | `Error::Config("Workflow with id '{id}' already exists")` | `WorkflowValidationError("Workflow with ID '{id}' already exists")` | `ALREADY_EXISTS` |
| **Workflow not found** | N/A | `Error::Config("Workflow '{id}' not found")` | `WorkflowValidationError("Workflow with ID '{id}' does not exist")` | `NOT_FOUND` |
| **Instance not found** | N/A | `Error::Config("Instance '{id}' not found")` | `WorkflowValidationError("Workflow instance with ID '{id}' does not exist")` | `NOT_FOUND` |
| **Invalid terminal state** | N/A | `Error::Config("Instance '{id}' is already in terminal state")` | `WorkflowValidationError("Workflow instance '{id}' is already in terminal state")` | `FAILED_PRECONDITION` |
| **Workflow cycle detected** | N/A | `Error::Config("Cycle detected in workflow starting from node '{id}'")` | `WorkflowCycleError("Workflow contains a cycle involving node '{id}'")` | `INVALID_ARGUMENT` |
| **Invalid vote score** | N/A (validation at API boundary) | `Error::Config("score must be in range [0, 10], got {val}")` | `NegotiationValidationError("score must be in range [0, 10], got {val}")` | `INVALID_ARGUMENT` |
| **Invalid vote confidence** | N/A | `Error::Config("confidence must be in range [0, 1], got {val}")` | `NegotiationValidationError("confidence must be in range [0, 1], got {val}")` | `INVALID_ARGUMENT` |
| **Decision timeout** | `TimeoutError("No decision made for artifact '{id}' within {timeout} seconds")` | `Error::Timeout("No decision made for artifact '{id}' within {:?}")` | `NegotiationTimeoutError("No decision made for artifact '{id}' within {timeout} milliseconds")` | `DEADLINE_EXCEEDED` |
| **Handoff timeout** | N/A (handled in response) | N/A | Returned as rejection in response | `DEADLINE_EXCEEDED` |
| **Lock poisoned** | N/A | `Error::Internal("Lock poisoned")` | N/A (JavaScript is single-threaded) | `INTERNAL` |
| **gRPC not implemented** | `RuntimeError("gRPC handoff service not yet implemented")` | N/A | N/A | `UNIMPLEMENTED` |

---

## Error Payload Structure

### Python SDK (Current Phase 2)

```python
# Standard exception types
ValueError           # For validation errors, not found, already exists, invalid state
TimeoutError         # For timeout scenarios
RuntimeError         # For gRPC stub not implemented
```

**Future gRPC Integration**:
```python
from grpc import StatusCode, RpcError

try:
    response = client.submit_proposal(proposal)
except RpcError as e:
    if e.code() == StatusCode.NOT_FOUND:
        # Handle not found
    elif e.code() == StatusCode.ALREADY_EXISTS:
        # Handle duplicate
    # etc.
```

### Rust SDK (Current Phase 2)

```rust
pub enum Error {
    Config(String),      // Validation, not found, already exists, invalid state
    Internal(String),    // Lock poisoned, storage backend failure
    Timeout(String),     // Timeout scenarios
    // Future: Grpc(tonic::Status) for gRPC integration
}
```

**Future gRPC Integration**:
```rust
use tonic::Code;

match error {
    Error::Grpc(status) if status.code() == Code::NotFound => {
        // Handle not found
    },
    Error::Grpc(status) if status.code() == Code::AlreadyExists => {
        // Handle duplicate
    },
    // etc.
}
```

### TypeScript SDK (Current Phase 2)

```typescript
// Custom error classes
class HandoffValidationError extends Error
class HandoffTimeoutError extends Error
class WorkflowValidationError extends Error
class WorkflowCycleError extends Error
class NegotiationValidationError extends Error
class NegotiationTimeoutError extends Error
class NegotiationRoomStoreError extends Error
```

**Future gRPC Integration**:
```typescript
import { status as GrpcStatus } from '@grpc/grpc-js';

try {
    const response = await client.submitProposal(proposal);
} catch (error: any) {
    if (error.code === GrpcStatus.NOT_FOUND) {
        // Handle not found
    } else if (error.code === GrpcStatus.ALREADY_EXISTS) {
        // Handle duplicate
    }
    // etc.
}
```

---

## Service-Specific Error Patterns

### HandoffClient

| Method | Common Errors | Current Implementation | Future gRPC Status |
|--------|--------------|------------------------|-------------------|
| `request_handoff()` | Duplicate request ID | ValueError / Error::Config / HandoffValidationError | ALREADY_EXISTS |
| `accept_handoff()` | Handoff not found | ValueError / Error::Config / HandoffValidationError | NOT_FOUND |
| `accept_handoff()` | Already responded | ValueError / Error::Config / HandoffValidationError | FAILED_PRECONDITION |
| `reject_handoff()` | Handoff not found | ValueError / Error::Config / HandoffValidationError | NOT_FOUND |
| `reject_handoff()` | Already responded | ValueError / Error::Config / HandoffValidationError | FAILED_PRECONDITION |
| `complete_handoff()` | Handoff not found | ValueError / Error::Config / HandoffValidationError | NOT_FOUND |
| `complete_handoff()` | Not in ACCEPTED status | ValueError / Error::Config / HandoffValidationError | FAILED_PRECONDITION |

### WorkflowClient

| Method | Common Errors | Current Implementation | Future gRPC Status |
|--------|--------------|------------------------|-------------------|
| `create_workflow()` | Duplicate workflow ID | N/A / Error::Config / WorkflowValidationError | ALREADY_EXISTS |
| `create_workflow()` | Cycle detected | N/A / Error::Config / WorkflowCycleError | INVALID_ARGUMENT |
| `create_workflow()` | Invalid dependency | N/A / Error::Config / WorkflowValidationError | INVALID_ARGUMENT |
| `start_workflow()` | Workflow not found | N/A / Error::Config / WorkflowValidationError | NOT_FOUND |
| `get_workflow_status()` | Instance not found | N/A / Error::Config / WorkflowValidationError | NOT_FOUND |
| `cancel_workflow()` | Instance not found | N/A / Error::Config / WorkflowValidationError | NOT_FOUND |
| `cancel_workflow()` | Already terminal | N/A / Error::Config / WorkflowValidationError | FAILED_PRECONDITION |
| `update_node_state()` | Instance not found | N/A / Error::Config / WorkflowValidationError | NOT_FOUND |
| `update_node_state()` | Node not found | N/A / Error::Config / WorkflowValidationError | NOT_FOUND |

### NegotiationRoomClient

| Method | Common Errors | Current Implementation | Future gRPC Status |
|--------|--------------|------------------------|-------------------|
| `submit_proposal()` | Duplicate artifact ID | ValueError / Error::Config / NegotiationRoomStoreError | ALREADY_EXISTS |
| `submit_vote()` | Proposal not found | ValueError / Error::Config / NegotiationValidationError | NOT_FOUND |
| `submit_vote()` | Invalid score range | N/A / Error::Config / NegotiationValidationError | INVALID_ARGUMENT |
| `submit_vote()` | Invalid confidence range | N/A / Error::Config / NegotiationValidationError | INVALID_ARGUMENT |
| `submit_vote()` | Critic already voted | ValueError / Error::Config / NegotiationRoomStoreError | FAILED_PRECONDITION |
| `get_votes()` | Proposal not found | ValueError / Error::Config / NegotiationValidationError | NOT_FOUND |
| `get_decision()` | Proposal not found | ValueError / Error::Config / NegotiationValidationError | NOT_FOUND |
| `store_decision()` | Proposal not found | ValueError / Error::Config / NegotiationValidationError | NOT_FOUND |
| `store_decision()` | Decision already exists | ValueError / Error::Config / NegotiationRoomStoreError | ALREADY_EXISTS |
| `wait_for_decision()` | Proposal not found | ValueError / Error::Config / NegotiationValidationError | NOT_FOUND |
| `wait_for_decision()` | Timeout | TimeoutError / Error::Timeout / NegotiationTimeoutError | DEADLINE_EXCEEDED |

---

## Normalization Requirements for Phase 3 Migration

When implementing gRPC integration, SDKs MUST:

1. **Map local exceptions to gRPC status codes** according to the table above
2. **Preserve error messages** for debugging - include original message in gRPC status details
3. **Include error metadata** in gRPC status trailers:
   - `resource-id`: The ID of the resource that caused the error
   - `resource-type`: Type of resource (handoff, proposal, workflow, instance, etc.)
   - `operation`: The operation that failed
   - `retry-able`: Whether the client should retry

4. **Handle gRPC errors consistently**:
   - Python: Catch `grpc.RpcError`, check `e.code()`, re-raise as appropriate SDK exception
   - Rust: Convert `tonic::Status` to `Error::Grpc(status)`, provide helper methods to check codes
   - TypeScript: Catch gRPC errors, check `error.code`, throw appropriate typed exception

5. **Timeout handling**:
   - Use gRPC deadline mechanisms instead of client-side polling
   - Set appropriate default deadlines (30s for decision wait, 5s for standard operations)
   - Python: Use `timeout` parameter in gRPC calls
   - Rust: Use `tonic::Request::set_timeout()`
   - TypeScript: Use `deadline` in call options

---

## Implementation Standards

### Error Message Format

All error messages MUST follow this format:

```
{ErrorDescription} for {ResourceType} '{ResourceID}'
```

Examples:
- `"Handoff '12345' not found"`
- `"Proposal with artifact_id 'code-123' already exists"`
- `"Critic 'critic-1' has already voted for artifact 'code-123'"`
- `"Workflow instance 'wf-456' is already in terminal state 'COMPLETED'"`

### Validation Error Messages

Validation errors MUST include the invalid value:

```
{FieldName} must be {Constraint}, got {ActualValue}
```

Examples:
- `"score must be in range [0, 10], got 15.0"`
- `"confidence must be in range [0, 1], got 1.5"`
- `"node_id must be a non-empty string"`

### Timeout Error Messages

Timeout errors MUST include the timeout duration:

```
No {ResourceType} for {ResourceID} within {Duration} {Units}
```

Examples:
- `"No decision made for artifact 'code-123' within 30 seconds"` (Python)
- `"No decision made for artifact 'code-123' within 30s"` (Rust)
- `"No decision made for artifact 'code-123' within 30000 milliseconds"` (TypeScript)

---

## Testing Requirements

All SDKs MUST have integration tests that verify:

1. **Correct error codes** for each operation
2. **Consistent error messages** across SDKs
3. **Error metadata** is properly included
4. **Retry logic** respects retry-able flag
5. **Timeout behavior** is consistent

---

## Migration Checklist (Phase 3)

- [ ] Replace in-memory storage with gRPC stub
- [ ] Map all SDK-native exceptions to gRPC status codes
- [ ] Update error messages to match standard format
- [ ] Add error metadata to all gRPC status details
- [ ] Implement gRPC deadline/timeout handling
- [ ] Update tests to verify gRPC error codes
- [ ] Update SDK documentation with gRPC error examples
- [ ] Verify cross-SDK consistency with integration tests

---

## Notes

- **Why no gRPC codes yet?**: All SDKs are in Phase 2 (in-memory mode) and don't use gRPC. Phase 3 will add gRPC integration.
- **Python SDK uniqueness**: Python's `WorkflowClient` is just an alias for `WorkflowEngine` (local orchestration), so it doesn't have the same error patterns as Rust/TypeScript.
- **TypeScript timeout units**: Uses milliseconds (JavaScript convention) while Python uses seconds and Rust uses Duration.
- **Rust lock poisoning**: Rust's thread-safe RwLock can be poisoned; this maps to INTERNAL error in gRPC.

---

**Last Updated**: 2026-01-10
**SDK Versions**: Python 0.5.0, Rust 0.5.0, TypeScript 0.5.0
**Phase**: 2 (In-Memory Mode)
