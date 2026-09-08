# SW4-015: A2A Gateway Binding

**Status:** Draft
**Version:** 0.1.0
**Date:** 2026-03-28
**Extends:** Core Spec §11 (request/response), SW4-007 (explicit request/response semantics)

## Abstract

This extension defines how SW4RM semantics are exposed through an Agent2Agent (A2A) gateway boundary. It is the transport-facing counterpart to SW4-007 and maps SW4RM request/response, lifecycle, timeout, and extension negotiation semantics onto A2A Agent Cards, `SendMessage` or `SendStreamingMessage`, task state updates, and cancellation behavior without redefining SW4RM core rules.

## Motivation

SW4RM and A2A overlap in agent-to-agent communication but serve different layers. Without an explicit binding, adapters will drift on:

- request and response mapping
- extension negotiation
- long-running task state translation
- gateway-visible errors and retries

## 1. Scope

SW4-015 defines:

- mapping between SW4RM request/response semantics and A2A task or message flows
- how SW4RM extensions are surfaced to A2A clients
- gateway-visible error and timeout translation
- constraints needed to preserve SW4RM semantics across the gateway boundary

SW4-015 must not become the home for core SW4RM semantics that matter regardless of transport. Those belong in SW4-007 or other SW4-native extensions.

SW4-015 assumes the current A2A model of:

- Agent Cards for discovery
- JSON-RPC 2.0 over HTTP(S) or equivalent supported bindings
- `SendMessage` and `SendStreamingMessage`
- `Task` lifecycle updates including `SUBMITTED`, `WORKING`, `COMPLETED`, `FAILED`, `CANCELED`, `INPUT_REQUIRED`, `REJECTED`, and `AUTH_REQUIRED`

## 2. Normative Language

The key words MUST, MUST NOT, SHOULD, SHOULD NOT, and MAY in this document are to be interpreted as described in RFC 2119.

## 3. Binding Model

### 3.1 Profile Identifier

SW4-015 is expressed as an A2A profile identifier:

```text
sw4rm.a2a.v1
```

An A2A-facing SW4RM gateway claiming this extension MUST advertise support for `sw4rm.a2a.v1`.

### 3.2 Gateway Boundary Rule

Only a gateway boundary MAY expose this binding. Internal SW4RM agents or child-swarm internals MUST NOT be exposed directly as independent A2A endpoints unless they independently satisfy gateway requirements.

## 4. A2A Discovery and Extension Advertisement

### 4.1 Agent Card Requirements

An SW4-015 gateway MUST publish an A2A Agent Card that:

1. advertises at least one supported A2A interface
2. identifies `sw4rm.a2a.v1` as an advertised extension or required profile marker
3. declares whether streaming is supported
4. exposes only gateway-safe public skills, not internal swarm topology

The RECOMMENDED extension URI is:

```text
urn:sw4rm:extension:sw4-015:a2a-gateway-binding:v1
```

A minimal conforming Agent Card (illustrative JSON):

```json
{
  "name": "sw4rm-gateway",
  "url": "https://gateway.example.internal/a2a",
  "capabilities": {"streaming": true},
  "skills": [
    {"id": "sw4rm.review", "name": "Review decision service"}
  ],
  "extensions": [
    {
      "uri": "urn:sw4rm:extension:sw4-015:a2a-gateway-binding:v1",
      "params": {
        "sw4rm_extensions": ["SW4-007", "SW4-013"],
        "gateway_version": "0.7.0",
        "sw4_007_response_semantics": true,
        "sw4_013_security_profile": true
      }
    }
  ]
}
```

### 4.2 Metadata Surface

The gateway SHOULD publish an A2A extension parameter object containing:

- supported SW4RM extension IDs
- gateway version
- whether SW4-007 request/response semantics are supported
- whether SW4-013 security wire profile requirements are also enforced

## 5. Request Mapping

### 5.1 Inbound A2A to SW4RM

When an A2A client sends `SendMessage` or `SendStreamingMessage` to a SW4-015 gateway:

1. the gateway MUST create or resolve a stable SW4RM `correlation_id`
2. the gateway MUST convert the A2A request into an internal SW4RM request envelope
3. if the operation expects a terminal result beyond simple acceptance, the gateway MUST use SW4-007 `response_required=true`
4. A2A `task.id` MUST remain stably associated with the internal SW4RM logical request

The RECOMMENDED mapping is:

| A2A surface | SW4RM surface |
|---|---|
| `Task.id` | logical request handle tracked by gateway |
| `Task.context_id` | `correlation_id` or stable conversation grouping key |
| inbound `Message` | SW4RM `DATA` request payload |
| `metadata` | gateway extension metadata and routing hints |

### 5.2 Return-Immediately Behavior

If A2A `SendMessageConfiguration.return_immediately=true`, the gateway MUST:

1. return once the SW4RM logical request is accepted or rejected for execution
2. create or update an A2A `Task`
3. continue reflecting later SW4RM progress through `GetTask`, `SubscribeToTask`, push notifications, or `SendStreamingMessage`

If `return_immediately=false`, the gateway MUST wait until the mapped SW4RM logical request reaches a terminal or interrupted state before returning, subject to gateway timeout policy.

## 6. Response and Lifecycle Mapping

### 6.1 SW4-007 Response Mapping

When the internal SW4RM request uses SW4-007 semantics:

1. a valid SW4RM terminal response MUST resolve the A2A task into either a terminal task state or a terminal message payload
2. the gateway MUST preserve linkage between the A2A `Task.id` and SW4RM `response_link`
3. the gateway MUST NOT expose a second independent terminal result for the same logical request

### 6.2 State Mapping

The binding MUST preserve meaning rather than internal implementation detail.

Required mappings:

| SW4RM condition | A2A task state |
|---|---|
| request accepted, awaiting execution | `SUBMITTED` |
| actively executing | `WORKING` |
| `WAITING` on external response or downstream dependency | `WORKING` or `INPUT_REQUIRED`, depending on whether external client action is needed |
| completed successfully | `COMPLETED` |
| terminal failure | `FAILED` |
| caller or policy cancellation | `CANCELED` |
| policy or capability refusal | `REJECTED` |
| explicit auth challenge at gateway boundary | `AUTH_REQUIRED` |

The gateway MUST use `INPUT_REQUIRED` only when external client input is actually required. Internal SW4RM waiting on downstream work MUST NOT be surfaced as `INPUT_REQUIRED`.

### 6.3 Streaming Updates

If the gateway supports `SendStreamingMessage` or `SubscribeToTask`, it SHOULD surface:

- task status updates when SW4RM state changes materially
- artifact updates when intermediate payloads are safe and meaningful to expose
- a final terminal task or message that reflects the authoritative SW4RM outcome

## 7. Timeout, Cancellation, and Late Results

### 7.1 Timeout Mapping

If SW4-007 `response_timeout_ms` expires:

1. the gateway MUST terminate the mapped A2A task as `FAILED`, `REJECTED`, or another gateway policy outcome consistent with the SW4RM terminal state
2. the timeout reason SHOULD be included in A2A task metadata or status message
3. the gateway MUST NOT keep the A2A task non-terminal after the underlying SW4RM logical request has terminalized on timeout

### 7.2 Cancellation Mapping

If an A2A client invokes `CancelTask`:

1. the gateway MUST propagate cancellation into the mapped SW4RM logical request
2. the gateway MUST NOT report `CANCELED` unless the underlying SW4RM operation has entered truthful cancellation handling
3. if cancellation races with successful completion, the gateway MUST publish the truthful terminal outcome and log the race

### 7.3 Late SW4RM Responses

If a late SW4RM response arrives after the A2A task has already terminalized:

1. the gateway MUST NOT reopen the A2A task
2. the late result MAY be retained for audit or diagnostics
3. conflicting late results MUST be surfaced as integrity warnings

## 8. Error Translation

SW4-015 requires bounded error translation rather than perfect one-to-one code mirroring.

Required rules:

1. SW4RM validation failures MUST become A2A-visible request or task failure information.
2. SW4RM permission or policy denials MUST become A2A-visible rejection or auth-required outcomes as appropriate.
3. SW4RM overload or transient routing failure SHOULD become retryable A2A task failure information or a transport-visible error, but MUST NOT be misreported as successful completion.
4. Gateway translation MUST preserve whether the failure was terminal, interrupted, or retryable.

## 9. Security and Capability Constraints

An SW4-015 gateway MUST preserve SW4RM security boundaries at the A2A edge.

Required behavior:

1. Internal swarm topology MUST NOT be exposed through the A2A Agent Card unless explicitly intended as public gateway surface.
2. Only extensions that are wire-visible and interoperable MAY be advertised to A2A clients.
3. If SW4-013 is enforced, the gateway MUST advertise that fact consistently in Agent Card extension metadata and request handling.
4. Authentication or authorization requirements at the gateway MUST map to A2A `AUTH_REQUIRED` or equivalent auth challenge behavior rather than silent rejection.

## 10. Worked Examples

### 10.1 Successful Gateway-Mediated Request

1. An A2A client calls `SendMessage` with `return_immediately=false`.
2. The gateway creates an internal SW4RM `DATA` request with SW4-007 `response_required=true`.
3. The downstream SW4RM request completes successfully.
4. The gateway returns an A2A `Task` or final message in `COMPLETED` state with stable `Task.id` to SW4RM linkage.

Representative exchange (illustrative JSON):

```json
// SendMessage request
{
  "message": {"role": "user", "parts": [{"type": "text", "text": "produce quarterly report"}]},
  "configuration": {"return_immediately": false}
}
```

```json
// Blocking result: one task lifecycle SUBMITTED -> WORKING -> COMPLETED
{
  "task": {
    "id": "task-7",
    "context_id": "wf-7",
    "status": {"state": "COMPLETED"},
    "metadata": {"sw4rm_correlation_id": "wf-7"}
  }
}
```

With `return_immediately=true`, the same call returns `"state": "SUBMITTED"`
immediately and later state changes surface through `GetTask`,
`SubscribeToTask`, push notifications, or `SendStreamingMessage`.

### 10.2 Timeout Visible at the A2A Boundary

1. An A2A client submits a long-running request with `return_immediately=true`.
2. The gateway returns quickly with a `SUBMITTED` task and continues polling or subscription updates.
3. The internal SW4RM request hits `response_timeout_ms` and terminalizes as timed out.
4. The gateway moves the A2A task to a terminal timeout-compatible outcome and records the reason in task metadata or status message.

### 10.3 A2A Cancellation Race

1. The client calls `CancelTask` on an active A2A task.
2. The gateway propagates cancellation into the mapped SW4RM logical request.
3. If SW4RM cancels first, the task becomes `CANCELED`.
4. If SW4RM completes first, the gateway preserves the truthful completed state and logs the race.

```mermaid
sequenceDiagram
    autonumber
    participant C as A2A client
    participant G as SW4-015 gateway
    participant S as SW4RM swarm
    C->>G: CancelTask (task-7)
    G->>S: cancel mapped logical request
    alt SW4RM cancels first
        S-->>G: CANCELLED
        G-->>C: task state = CANCELED
    else SW4RM completes first
        S-->>G: COMPLETED
        G-->>C: task state = COMPLETED (truthful; race logged)
    end
```

### 10.4 Late SW4RM Response After A2A Terminalization

1. The gateway has already terminalized an A2A task because the mapped SW4RM request timed out.
2. A late SW4RM response later arrives with valid response linkage.
3. The gateway records the late result for diagnostics.
4. The A2A task remains closed and is not reopened or overwritten.

```mermaid
sequenceDiagram
    autonumber
    participant S as SW4RM swarm
    participant G as SW4-015 gateway
    participant C as A2A client
    note over G: response_timeout_ms elapsed —<br/>task terminalized as timed out
    G-->>C: task state = FAILED (timeout)
    S-->>G: late terminal response (valid linkage)
    note over G: record late result for diagnostics only;<br/>task stays closed
```

## 11. Conformance Test Outline

| ID | Scenario | Expected Result |
|---|---|---|
| A2A-001 | Agent Card advertisement | Gateway advertises `sw4rm.a2a.v1` and public-safe skills only |
| A2A-002 | `return_immediately=true` | Task returns promptly and later updates are observable |
| A2A-003 | `return_immediately=false` | Response waits for terminal or interrupted state |
| A2A-004 | Successful SW4-007 response | A2A task reaches `COMPLETED` with linked result |
| A2A-005 | Internal `WAITING` without user input | Task remains `WORKING`, not `INPUT_REQUIRED` |
| A2A-006 | External user input needed | Task surfaces `INPUT_REQUIRED` |
| A2A-007 | A2A cancel | Underlying SW4RM logical request receives cancellation |
| A2A-008 | Late SW4RM response after terminal A2A task | Task is not reopened |
| A2A-009 | Auth challenge | Gateway surfaces `AUTH_REQUIRED` consistently |
| A2A-010 | Extension advertisement | Supported SW4RM extensions appear in A2A metadata surface |

## 12. Repository Alignment Review (Non-Normative)

This repository already includes an MVP A2A gateway under `a2a_gateway/`. As of 2026-03-28, that implementation is useful context but is not yet sufficient to claim SW4-015 conformance.

- `a2a_gateway/a2a.proto` currently exposes `MessageSendConfiguration.blocking` rather than the upstream-style `return_immediately` terminology used in this draft. Until the local gateway surface is updated, implementations SHOULD treat `blocking=true` as equivalent to `return_immediately=false` and `blocking=false` as equivalent to `return_immediately=true`.
- The local A2A subset exposes `SUBMITTED`, `WORKING`, `INPUT_REQUIRED`, `COMPLETED`, `FAILED`, `CANCELED`, and `AUTH_REQUIRED`, but not `REJECTED`. Gateways that need SW4-015 policy-refusal semantics MUST add an equivalent refusal surface instead of collapsing all refusals into `FAILED`.
- `a2a_gateway/adapter.py` currently maps SW4RM `WAITING` and `WAITING_RESOURCES` to `INPUT_REQUIRED`. That behavior is not conformant with this draft: internal downstream waiting MUST surface as `WORKING`, and `INPUT_REQUIRED` is reserved for truthful external-client input requirements.
- `a2a_gateway/agent_card.py` currently emits basic Agent Cards without `sw4rm.a2a.v1` or extension metadata advertising. A gateway MUST add that metadata before claiming SW4-015 support.
- The local gateway currently returns a task immediately from `SendMessage` and does not yet implement terminal blocking waits, `SendStreamingMessage`, or late-result reconciliation. Those behaviors remain required before conformance can be claimed.

## 13. Compatibility and Rollout

SW4-015 is optional and additive.

Compatibility rules:

1. SW4RM deployments with no A2A edge remain unaffected.
2. Gateways SHOULD implement SW4-007 internally before advertising SW4-015 externally.
3. Mixed deployments SHOULD roll out read-only A2A discovery first, then request submission, then streaming and cancellation features.

## 14. Implementation Requirements

### 14.1 MUST

1. Advertise the A2A binding profile and gateway-safe capabilities.
2. Map A2A requests into stable SW4RM correlation and logical request handles.
3. Preserve truthful terminal state across timeout and cancellation races.
4. Avoid exposing internal-only SW4RM topology or semantics as public A2A API.
5. Reconcile late SW4RM responses without reopening completed A2A tasks.

### 14.2 SHOULD

1. Support `SendStreamingMessage` or `SubscribeToTask` when SW4RM progress is materially observable.
2. Publish supported SW4RM extensions in Agent Card extension metadata.
3. Surface timeout or rejection reasons in task metadata or status messages.

### 14.3 MAY

1. Offer both synchronous and streaming bindings.
2. Translate selected SW4RM intermediate results into A2A artifact updates when safe.

## References

- [Core Protocol Specification](../spec.md)
- [SW4-007: Explicit Request/Response Semantics](./SW4-007-explicit-request-response-semantics.md)
- [A2A protocol overview in this repository](../index.md#39-comparison-with-googles-agent-to-agent-protocol)
- [A2A protocol repository](https://github.com/a2aproject/A2A)
