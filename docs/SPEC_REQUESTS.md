# SW4RM Spec Requests and Recommended Conventions (Draft)

This document proposes conventions that sit above the core SW4RM protocol spec and can be adopted by implementations for interoperability.

## 1. MessageType Mapping + Vendor Content Types

- Seed to Scheduler
  - MessageType: DATA
  - content_type: `application/vnd.sw4rm.scheduler.seed+json;v=1`
  - payload: `{ "seed": string }`

- Scheduler → Agent Commands
  - MessageType: CONTROL
  - content_type: `application/vnd.sw4rm.scheduler.command+json;v=1`
  - payload: `{ "schema_version": 1, "to": "<agent_id>", "stage": "generate"|"run_probe"|"fix", "params": object }`
  - Notes: `to` is REQUIRED; agents MUST ignore commands where `to` does not match their `agent_id`.

- Agent → Scheduler Reports
  - MessageType: NOTIFICATION
  - content_type: `application/vnd.sw4rm.agent.report+json;v=1`
  - payload: `{ "schema_version": 1, "stage": string, "status": "ok"|"error", "logs"?: string, "diagnostics"?: object }`

Correlation MUST use `envelope.correlation_id` across a session; payloads SHOULD NOT duplicate it.

## 2. LLM Stream Result Rule

When consuming the `claude` CLI with `--output-format stream-json`, select stream events where `type == "result"` and parse the event’s `result` field:
- If `result` is a string, parse it as JSON when the schema requires a JSON object.
- If `result` is already an object, use it directly.

Ignore other stream events for deterministic processing. Log sample lines if no `result` event appears.

## 3. Deterministic Result Schemas

- Planner (LLM-driven scheduling)
  - Schema: `{ "commands": [ { "to": "frontend"|"backend", "stage": "generate"|"run_probe"|"fix", "params": object } ] }`

- Agent Generate/Fix Results (LLM-driven code changes)
  - Schema: `{ "files": [ { "path": "<relative>", "content": "<text>" } ], "notes"?: string }`
  - Paths are relative to the agent’s work root (e.g., `generated_app/frontend`).

- Agent Reports (machine-generated)
  - Schema: `{ "stage": string, "status": "ok"|"error", "logs"?: string, "diagnostics"?: object }`

## 4. Probe Conventions

Functional checks use simple HTTP where appropriate and do not introduce new gRPC APIs:
- Backend probe: default `GET /hello` on configurable port (e.g., 8000).
- Frontend probe: minimal Node.js fetch to the backend URL to validate connectivity.

## 5. Notes

- These conventions do not alter the core spec; they leverage MessageType and content_type for higher-level semantics.
- Content types are versioned with `;v=1` to allow evolutionary upgrades.

### 5.1 Protected Scheduler

- The Scheduler is a central authority and MUST NOT be removed implicitly by cleanup/expiry.
- Registry implementations SHOULD treat `agent_id == "scheduler"` (or an equivalent capability flag) as protected from automatic removal.
- Heartbeats remain recommended for telemetry/health, but lack of heartbeats MUST NOT cause the Scheduler to be expired.
