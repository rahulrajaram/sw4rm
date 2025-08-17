# Bee DevCore — Architecture Overview

This document describes the in-repo DevCore used by the Bee CLI to provide local, development-grade implementations of the Registry, Router, Scheduler, and Negotiation services.

Scope: developer convenience. DevCore runs on localhost with in-memory state and no external dependencies. It enables end-to-end agent flows without Docker or remote services.

## Goals
- Run all core gRPC services locally with minimal friction
- Be wire-compatible with Rust SDK clients (tonic)
- Provide predictable behavior suitable for demos and tests

Non-Goals: production clustering, persistence, ACLs/quotas, HA.

## Topology & Ports
- Processes: single Bee process hosts all servers as Tokio tasks
- Ports:
  - Registry: 127.0.0.1:50051
  - Router:   127.0.0.1:50052
  - Scheduler:127.0.0.1:50053
  - Negotiation: 127.0.0.1:50054
- Note: The Rust SDK defaults to Negotiation at 50058; DevCore uses 50054 → set `BEE_NEGOTIATION=http://127.0.0.1:50054` for CLI commands.

## Components

### Registry
- API: `RegisterAgent`, `Heartbeat`, `DeregisterAgent`
- State: in-memory map of `agent_id → presence {name, description, last_heartbeat_ms}`
- Behavior: accepts all registrations (allowlist TODO), updates heartbeat timestamp, removes on deregister

### Router
- API: `SendMessage`, `StreamIncoming(agent_id)`
- State: `subscribers[agent_id] → Vec<mpsc::Sender<Envelope>>`
- Behavior: `StreamIncoming` subscribes the agent; internal Hub publishes envelopes to all subscribers of that agent_id
- Backpressure: best-effort; drops to closed/slow subscribers (TODO: buffering & policy)
- No-subscriber drops: envelopes to agents without active subscribers are dropped (warn logged); buffering/backpressure TBD.

### Scheduler
- API: `SubmitTask`, `RequestPreemption`, `ShutdownAgent`, `PollActivityBuffer`, `PurgeActivity`
- State: none persisted (queues TODO)
- Behavior:
  - `SubmitTask`: wraps params as a DATA envelope and publishes to the target agent via Router
  - `RequestPreemption`: emits CONTROL envelope with reason
  - `ShutdownAgent`: emits CONTROL envelope with shutdown notice
  - Activity endpoints: stubbed empty for MVP

### Negotiation
- API: `Open`, `Propose`, `Counter`, `Evaluate`, `Decide`, `Abort`
- State: rooms `id → {topic, participants, events(JSON-lines)}` (bounded ring TODO)
- Behavior: emits JSON negotiation events to all participants via Router using `MessageType::NEGOTIATION`
- CLI Convenience: the Bee CLI exposes a `negotiate consult` helper that opens a two-party session (frontend/backend) as a thin wrapper over the above RPCs; the server API remains unchanged.
- Scope: control-plane fanout only. Policy computation and enforcement (rounds, budgets, oscillation control, scoring) remain Scheduler-owned; DevCore Negotiation does not enforce policy.

- Policy Broadcast: on `open`, an initial `policy` event is broadcast to all participants with the computed `EffectivePolicy` and optional `profile`. The envelope `producer_id` is `scheduler` and `message_type=NEGOTIATION`.
- Event Shapes: payloads are JSON with fields `kind` and a stub timestamp. Proposals and counters include `payload_b64`; decisions include `result_b64`.
## Data Model
- All services keep state in memory (HashMaps, VecDeque). No persistence across restarts.

## Core Flows
- Submit → Deliver:
  1) Client calls Scheduler.SubmitTask(task_id, agent_id, params)
  2) Scheduler builds a DATA Envelope and publishes via Router Hub
  3) Agents subscribed via Router.StreamIncoming(agent_id) receive the Envelope

- Preempt/Shutdown:
  1) Client calls Scheduler.RequestPreemption/ShutdownAgent
  2) Scheduler publishes CONTROL Envelope(s) to the target agent

- Negotiation Fanout:
  1) Client calls Negotiation.Open with participants
  2) Negotiation records an event and publishes to each participant via Router
  3) Propose/Counter/Evaluate/Decide/Abort follow the same publish pattern

## Health & Telemetry
- Health command: `bee dev-core health` probes connections to all four services
- Metrics: Bee CLI starts a Prometheus endpoint (default `127.0.0.1:9464`)
  - When running multiple CLI processes concurrently, set `BEE_METRICS_ADDR=127.0.0.1:0`

## Artifacts and Persistence
- Activity Buffer: operational/short-lived store for event transcripts and summaries; suitable for observability and replay.
- Artifact Journal (planned): durable, append-only records for negotiation artifacts (contracts, diffs, decision reports) keyed by negotiation/session id. DevCore defers durable artifact storage to this future journal; do not write contracts/diffs into the Activity Buffer.

## Configuration
- Endpoints are resolved from `Endpoints::default()` with env overrides:
  - `BEE_REGISTRY`, `BEE_ROUTER`, `BEE_SCHEDULER`, `BEE_NEGOTIATION`
- For DevCore Negotiation, set `BEE_NEGOTIATION=http://127.0.0.1:50054`

### Policy Profiles and Agent Preferences
- Profiles: DevCore seeds `low`, `medium`, and `high` profiles derived from defaults; `low` clamps rounds/thresholds for higher safety, while `high` increases budgets and sets `hitl=PauseBetweenRounds`.
- Intensity Mapping: `Negotiation.open` maps intensity hints to an existing profile (`low|medium|high`) and computes an `EffectivePolicy` accordingly.
- Agent Preferences: The Scheduler loads optional per-agent preferences to clamp policy parameters.
  - File: `BEE_AGENT_PREFS_FILE` (defaults to `$BEE_HOME/agent_prefs.json`) mapping `agent_id → AgentPreferences`.
  - Env: `BEE_AGENT_PREFS_JSON` with the same JSON object shape.
  - Clamping: preferences reduce rounds/time/budgets or raise minimum score thresholds without exceeding Scheduler guardrails.

## Limitations (MVP)
- No persistence; all state lost on restart
- No queueing for disconnected Router streams
- No lane/scope routing (default lane only)
- Activity buffer RPCs are stubs
- Minimal input validation & error codes

## Roadmap (selected)
- Router buffering/backpressure, delivery semantics for brief disconnects
- Scheduler in-memory queues with task states, fairness by priority
- Lanes and scope-aware routing
- Negotiation room lifecycle (timeouts) and bounded event logs
- Structured errors and validation
- Basic metrics: agent count, stream count, queue depth
- Optional subprocess mode vs in-process tasks
- Containerization post-MVP

## Testing
- Unit tests cover MVP for all four services and Router Hub
- Future: integration tests (submit → stream receipt) and negotiation end-to-end

## Source Map
- Entrypoint & wiring: `bee/src/devcore/mod.rs`
- Shared state (Hub, presence, rooms): `bee/src/devcore/state.rs`
- Services: `bee/src/devcore/{registry,router,scheduler,negotiation}.rs`
- CLI: `bee/src/main.rs` (commands `dev-core up|down|health`)
