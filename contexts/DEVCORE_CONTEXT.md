# DevCore — In-Repo Core Services (Registry, Router, Scheduler, Negotiation)

Updated: 2025-08-16

## 1. Scope
Implements development-grade, in-repo gRPC servers for the four core services (Registry, Router, Scheduler, Negotiation) that the Bee CLI and SDK clients already target. Runs as plain Linux processes on localhost ports 50051–50054 with in-memory state (no external DB), enabling end-to-end agent scenarios without external images. Containerization comes later as a build artifact of this work.

Out of scope: production clustering, persistent storage, auth/ACLs, multi-tenant quotas, external bus dependencies.

## 2. Objectives
- Unblock “agents operate on worktrees and coordinate via Scheduler” locally with minimal friction.
- Maintain wire-compatibility with existing SDK clients (`RegistryClient`, `RouterClient`, `SchedulerClient`, `NegotiationClient`).
- Keep the implementation modular so it can later be split into standalone services and container images.

## 3. Substreams (Components)
- Registry: agent register/heartbeat/deregister; simple allowlist and presence table.
- Router: per-agent streaming of envelopes; event fanout from Scheduler/Negotiation; cooperative preemption/control messages.
- Scheduler: in-memory queues per agent (lane="default" initially); submit→enqueue→deliver via Router; preempt/shutdown flows.
- Negotiation: rooms keyed by `negotiation_id`; verbs open/propose/counter/evaluate/decide/abort; emit events to participants via Router.
- Integrator: `bee dev-core up|down` to spawn/stop all servers; health checks; port coordination.

## 4. Interfaces (Ports, APIs)
- Ports: Registry 50051, Router 50052, Scheduler 50053, Negotiation 50054.
- APIs: Match current SDK method shapes (tonic). Any deliberate simplifications are documented with TODOs.
- Envelope: Leverage SDK envelope types for Router delivery; include minimal headers (type, ct, payload, ids).

## 5. Data Model
- In-memory maps only: agents table (Registry); per-agent consumer streams (Router); scheduler run queues and task states; negotiation room state and event log. No persistence across restarts.

## 6. Operational Model
- Start via Bee: `bee dev-core up` launches all servers within one process (Tokio tasks) or subprocesses; `bee dev-core down` stops them.
- Hive bootstrap continues to point Bee CLI to localhost ports; agents run on host with full filesystem access.

## 7. Dependencies and Non-Duplication
- Reuses existing context/worktrees for: Activity Buffer, Redis Streams Bus, Telemetry, Secrets, Scheduler Lanes (design).
- This DevCore provides local service endpoints; it does not replace the Activity Buffer or Redis Bus implementations. It forwards events internally and remains in-memory.

## 8. Milestones
- M1 (MVP): Registry + Router + Scheduler basic submit/preempt; Negotiation open/propose/decide; `bee dev-core up/down`; health endpoints.
- M2 (UX/Parity): Lanes (default only), aging knobs (minimal), better Router fanout, negotiation evaluate/counter, shell/TUI demos.
- M3 (Hardening): Structured errors, input validation, simple backpressure; optional persistence stubs behind flags; Dockerfiles.

## 9. Testing Strategy
- Unit tests: registry presence, scheduler enqueue/deliver/preempt, router stream fanout, negotiation room transitions.
- Integration tests: two local agents, submit via scheduler, deliver via router, negotiate consult, assert outcomes.
- Fault injection: server restarts (state lost but no panics), invalid inputs, slow consumer on Router stream.

## 10. Action Items (Prioritized)
1) Registry (MVP)
- [ ] tonic server with `register/heartbeat/deregister`
- [ ] In-memory agent table with timestamps and allowlist hooks
- [ ] Health check and logging

2) Router (MVP)
- [ ] Agent stream endpoints (server-side streaming)
- [ ] Broadcast/fanout channels; delivery from Scheduler/Negotiation
- [ ] Control messages for preempt/shutdown

3) Scheduler (MVP)
- [ ] Per-agent in-memory queues; states (queued/running/preempted/completed/failed)
- [ ] `submit` enqueues and triggers Router delivery
- [ ] `preempt` sends control via Router; `shutdown` supported

4) Negotiation (MVP)
- [ ] Rooms keyed by id; verbs open/propose/counter/evaluate/decide/abort
- [ ] Event emission to participants via Router

5) Integrator + CLI
- [ ] `bee dev-core up/down` wiring and lifecycle
- [ ] Health summary command and docs

6) Docs + Demos
- [ ] Update Quickstart with dev-core
- [ ] Two-agent demo: submit task + consult; TUI walkthrough

## 11. Notes
- Keep modules independent so future work can split into separate crates/services.
- Favor clarity and determinism over breadth; this is a developer aid, not production infra.
