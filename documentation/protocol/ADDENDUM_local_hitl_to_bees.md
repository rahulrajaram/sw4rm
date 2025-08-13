Addendum: Optional Local HITL Access to Bees (Non‑Normative)
===========================================================

Status

- Draft, non‑normative. Captures a potential extension for local HITL interactions against bees. The authoritative HITL path remains Scheduler‑mediated per the core spec.

Motivation

- Improve developer UX and low‑risk operational flows (inspection, approvals) by allowing optional, strictly scoped interactions with a bee, without bypassing Scheduler authority or audit trails.

Goals

- Preserve centralized control and audit via Scheduler.
- Enable opt‑in local endpoints for read‑only inspection and proxied decisions.
- Allow limited direct actions only when explicitly authorized by the Scheduler (capability tokens).

Non‑Goals

- Changing message lifecycles, scheduling semantics, or global policy enforcement.
- Allowing bees to accept final HITL decisions that the Scheduler is unaware of.

Operating Modes (Opt‑In)

- off (default): No local HITL endpoints.
- read_only: Bee exposes inspection endpoints only (state, buffers, recent envelopes, worktree status).
- proxy: Bee accepts operator decisions and forwards them to the Scheduler via HitlClient (including correlation_id, negotiation_id); Scheduler remains source of truth.
- scoped: Bee may perform narrowly scoped actions locally when presented with a Scheduler‑minted capability token (time‑bound, audience=bee_id, scope, correlation_id). All actions are mirrored to Logging.

Security Considerations

- Transport security: Prefer mTLS between operator → bee. Fall back to loopback-only for dev.
- Capability tokens: Signed, short‑lived, single‑use recommended. Include scope, audience (bee_id), correlation_id, expiry. Format may be JWT or MAC‑tagged blob.
- RBAC: Hive/bee config SHOULD define which identities may use local HITL. Authorization is enforced locally and logged centrally.
- Audit: Every local HITL interaction MUST be mirrored to the Logging service with correlation metadata.

Suggested Minimal API (illustrative)

- GET /state: summary (agent_id, status, recent activity).
- GET /hitl/pending: proxied view of HITL invocations (Scheduler source).
- POST /hitl/decision: proxy; body carries decision and correlation metadata; bee forwards to Scheduler.
- POST /hitl/action: scoped; requires capability token for a specific action (e.g., approve tool call, confirm worktree switch).

CLI / Config Sketch (informative)

- bee run: `--hitl-local [off|read-only|proxy|scoped]` (default off), `--hitl-bind 127.0.0.1:7070`.
- hive config: `hitl: { mode, bind, rbac, require_tokens }` and `allowed_hitl_users`.
- bee hitl (future): `serve`, `list`, `approve`, `reject`, `attach`.

Compatibility

- No changes to on‑wire protocol or required services. Adds optional local surfaces that proxy and/or act with explicit capability tokens.

Open Questions

- Token format and minting endpoint (Scheduler side) and revocation semantics.
- Minimal required read‑only fields to balance utility and privacy.
- Whether local endpoints must be HTTP, gRPC, or both.
