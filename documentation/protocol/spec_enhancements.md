# Proposed SW4RM Spec Enhancements

Version: draft
Date: 2025-12-25

## 1) Explicit Request/Response Semantics

Problem: The protocol defines message lifecycle + agent WAITING, but does not
define a first-class request/response contract. Implementations are forced to
invent "wait_for_response" semantics and response schemas.

Proposed additions:

- Add a standard response linkage field: `in_response_to` (message_id) and/or
  `response_for_idempotency_token` (idempotency token).

- Define a request flag: `response_required` (bool) or a `ResponsePolicy`
  sub-structure with `timeout_ms`, `retry_policy`, `max_attempts`.

- Require that when `response_required=true`, the sender transitions to
  WAITING state and the Scheduler tracks a pending response entry keyed by
  message_id and idempotency_token.

- On response arrival, the Scheduler transitions the sender back to RUNNING
  (or RESUMED), and the original request transitions to FULFILLED.

- On response timeout, apply the message lifecycle: TIMED_OUT -> RETRYING with
  new message_id and same idempotency_token; after retry exhaustion, transition
  to FAILED or REJECTED with a clear error_code.

## 2) WAITING State Guidance for Responses

Problem: WAITING state exists, but there is no standard behavior for request
round-trips or timeouts.

Proposed additions:

- When a request requires a response, the Agent MUST enter WAITING and MUST
  preserve task assignment; execution is suspended until response or timeout.

- WAITING MUST be bounded by `response_timeout_ms` (no indefinite waits).

- Deployments without HITL MUST define a fallback on timeout (retry, fail, or
  continue with default behavior) and MUST document/log the choice.

## 3) Response Message Type / Envelope

Problem: The spec enumerates core message types but does not explicitly define
response payloads for inter-agent coordination.

Proposed additions:

- Add a canonical response payload schema (JSON/protobuf) containing:
  `in_response_to`, `status` (ok|error), `payload`, `error_code`, and `note`.

- Clarify that responses may be sent as message_type=DATA with a required
  `in_response_to`, or add a new message_type=RESPONSE if preferred.

## 4) Message Authorization (Agent Scope)

Problem: The spec states message type authorization via ACLs but does not
explicitly affirm that any Agent may emit messages/handoffs if authorized.

Proposed addition:

- State explicitly: "Any Agent MAY emit messages and handoffs subject to
  Scheduler-enforced ACLs and policy." This avoids tool-specific constraints
  that are not part of protocol intent.

## 5) Idempotency Token Guidance for Responses

Problem: Idempotency guidance exists for retries, but response semantics are
unclear.

Proposed addition:

- Define response idempotency rules: responses to the same request should carry
  a deterministic idempotency token derived from the request token and response
  type; duplicates must be deduped by the Scheduler.

## 6) Activity Buffer Interaction with WAITING

Problem: Activity Buffer is defined but does not specify behavior for WAITING.

Proposed addition:

- When an Agent enters WAITING due to response_required, it MUST update its
  Activity Buffer entry with a "waiting_on" field (message_id or correlation_id)
  and a timestamp, to support auditability and operator visibility.

## 7) Backpressure + Response Required

Problem: Buffer/backpressure rules exist but do not mention response-required
messages.

Proposed addition:

- If a response-required message is rejected due to buffer_full, the sender MUST
  NOT enter WAITING; it MUST receive a NACK with error_code=buffer_full and
  decide whether to retry or fail.

## 8) Handoff Context Content-Type

Problem: Handoff context_snapshot is defined but content types are not.

Proposed addition:

- Require `context_snapshot_content_type` (application/json, application/protobuf,
  text/plain) and enforce modality compatibility with target Agent.

