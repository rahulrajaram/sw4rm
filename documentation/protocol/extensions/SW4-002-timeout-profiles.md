# SW4-002: Timeout Profiles Extension

**Status:** Draft
**Version:** 0.1.0
**Date:** 2026-01-10
**Extends:** Core Spec §5 (Transport), OPERATIONAL_CONTRACTS.md

## Abstract

This extension defines per-service timeout profiles for SW4RM operations, replacing the universal 30-second default with operation-appropriate timeouts. Implementations conforming to this extension provide predictable latency characteristics and better failure detection.

## Motivation

The core operational contracts define a universal 30-second timeout, but different operations have vastly different timing requirements:

- **Heartbeats**: Should fail fast (5s) to detect agent death quickly
- **Negotiations**: May require minutes for complex artifact review
- **Tool calls**: Vary from milliseconds to minutes depending on tool

A universal timeout either causes false failures (too short) or delayed detection (too long).

## 1. Timeout Profile Definition

### 1.1. Profile Structure

```protobuf
message TimeoutProfile {
  string profile_name = 1;           // e.g., "heartbeat", "negotiation", "tool"
  uint32 default_timeout_ms = 2;     // Default timeout in milliseconds
  uint32 min_timeout_ms = 3;         // Minimum allowed override
  uint32 max_timeout_ms = 4;         // Maximum allowed override
  bool allow_infinite = 5;           // Whether timeout=0 means infinite
}
```

### 1.2. Standard Profiles

Implementations MUST support these standard profiles:

| Profile | Default | Min | Max | Allow Infinite | Use Case |
|---------|---------|-----|-----|----------------|----------|
| `heartbeat` | 5,000ms | 1,000ms | 30,000ms | No | Agent liveness detection |
| `registration` | 30,000ms | 5,000ms | 120,000ms | No | Agent registration/deregistration |
| `task_submit` | 30,000ms | 5,000ms | 300,000ms | No | Task submission to scheduler |
| `message_route` | 10,000ms | 1,000ms | 60,000ms | No | Message routing operations |
| `negotiation_open` | 60,000ms | 10,000ms | 600,000ms | No | Opening negotiation sessions |
| `negotiation_vote` | 300,000ms | 30,000ms | 1,800,000ms | Yes | Vote collection (see SW4-001) |
| `negotiation_decision` | 60,000ms | 5,000ms | 300,000ms | No | Decision retrieval |
| `handoff` | 60,000ms | 10,000ms | 300,000ms | No | Agent handoff operations |
| `workflow_submit` | 30,000ms | 5,000ms | 120,000ms | No | Workflow submission |
| `workflow_status` | 10,000ms | 1,000ms | 60,000ms | No | Workflow status queries |
| `tool_call` | 30,000ms | 1,000ms | 3,600,000ms | Yes | Tool invocations |
| `hitl_escalate` | 300,000ms | 60,000ms | 3,600,000ms | Yes | HITL escalation (human response) |

## 2. Profile Selection

### 2.1. Automatic Selection

SDKs MUST automatically select the appropriate timeout profile based on the RPC being called:

```python
# Python SDK example
class RegistryClient:
    def heartbeat(self, agent_id: str, timeout: float | None = None) -> Any:
        effective_timeout = timeout or self._profiles["heartbeat"].default_timeout_ms / 1000
        return self._stub.Heartbeat(req, timeout=effective_timeout)
```

### 2.2. Override Rules

When a caller provides an explicit timeout:

1. If timeout < `min_timeout_ms`: Use `min_timeout_ms` and log warning
2. If timeout > `max_timeout_ms`: Use `max_timeout_ms` and log warning
3. If timeout = 0 and `allow_infinite = false`: Use `default_timeout_ms` and log warning
4. Otherwise: Use provided timeout

### 2.3. Profile Customization

Implementations SHOULD support profile customization at:

1. **Global level**: Environment variables or config file
2. **Client level**: Constructor options
3. **Per-call level**: Method parameter

Precedence: Per-call > Client > Global > Standard defaults

## 3. Service-Specific Guidance

### 3.1. Registry Service

| RPC | Profile | Notes |
|-----|---------|-------|
| RegisterAgent | `registration` | May involve capability validation |
| Heartbeat | `heartbeat` | Fast failure detection critical |
| DeregisterAgent | `registration` | Cleanup may take time |

### 3.2. Scheduler Service

| RPC | Profile | Notes |
|-----|---------|-------|
| SubmitTask | `task_submit` | Includes validation and queueing |
| CancelTask | `task_submit` | May need to signal running agent |
| GetTaskStatus | `workflow_status` | Read-only, should be fast |

### 3.3. NegotiationRoom Service

| RPC | Profile | Notes |
|-----|---------|-------|
| SubmitProposal | `negotiation_open` | Creates room state |
| SubmitVote | `negotiation_vote` | May be long for complex artifacts |
| GetDecision | `negotiation_decision` | Read-only |
| WaitForDecision | `negotiation_vote` | Blocking wait, may be very long |

### 3.4. Handoff Service

| RPC | Profile | Notes |
|-----|---------|-------|
| RequestHandoff | `handoff` | Includes context serialization |
| AcceptHandoff | `handoff` | May involve context restoration |
| RejectHandoff | `message_route` | Simple state change |

### 3.5. Tool Service

| RPC | Profile | Notes |
|-----|---------|-------|
| InvokeTool | `tool_call` | Highly variable, tool-dependent |
| DescribeTool | `message_route` | Metadata lookup |

## 4. Async/Streaming Considerations

### 4.1. Streaming RPCs

For server-streaming RPCs, the timeout applies to:

1. **Initial response**: Time to receive first message
2. **Inter-message gap**: Maximum time between consecutive messages

Implementations SHOULD support separate configuration:

```protobuf
message StreamingTimeoutPolicy {
  uint32 initial_timeout_ms = 1;    // Time to first message
  uint32 message_gap_timeout_ms = 2; // Max gap between messages
  uint32 total_timeout_ms = 3;       // Total stream duration (0 = unlimited)
}
```

### 4.2. Async Operations

For async SDK variants (Rust async, Python asyncio, JS promises):

- Timeouts MUST use async-native mechanisms (e.g., `tokio::time::timeout`)
- Cancellation MUST propagate to the underlying gRPC call
- Resources MUST be released on timeout

## 5. Error Handling

### 5.1. Timeout Error Codes

When a timeout occurs, implementations MUST return:

- gRPC status: `DEADLINE_EXCEEDED` (code 4)
- Error details SHOULD include:
  - `profile_name`: Which timeout profile was used
  - `configured_timeout_ms`: The timeout value that was exceeded
  - `elapsed_ms`: Actual elapsed time before timeout

### 5.2. Retry Guidance

Timeout errors are retryable, but implementations SHOULD:

1. Apply exponential backoff before retry
2. Consider reducing timeout on retry (fast-fail pattern)
3. Track retry budget to prevent infinite retry loops

## 6. Observability

Implementations conforming to SW4-002 SHOULD expose:

- **Metrics**: `sw4rm_rpc_timeout_total{profile, service, method}`
- **Metrics**: `sw4rm_rpc_duration_ms{profile, service, method}` (histogram)
- **Logs**: Timeout events with profile, configured timeout, and elapsed time

## 7. Implementation Requirements

### 7.1. MUST Requirements

Implementations MUST:

1. Support all standard timeout profiles
2. Apply automatic profile selection based on RPC
3. Enforce min/max bounds on timeout overrides
4. Return `DEADLINE_EXCEEDED` on timeout

### 7.2. SHOULD Requirements

Implementations SHOULD:

1. Support profile customization at global, client, and per-call levels
2. Log warnings when timeouts are clamped to bounds
3. Expose timeout-related metrics

## 8. Compatibility

This extension is backward-compatible. Implementations not conforming to SW4-002:

- Will use universal timeout (typically 30s)
- May experience suboptimal failure detection or false timeouts
- SHOULD document their timeout behavior

## 9. References

- Core Spec §5: Transport
- SW4-001: Failure Semantics Extension
- OPERATIONAL_CONTRACTS.md

---

*This extension is part of the SW4RM protocol extension series.*
