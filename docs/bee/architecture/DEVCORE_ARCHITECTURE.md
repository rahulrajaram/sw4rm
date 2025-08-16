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

## Configuration
- Endpoints are resolved from `Endpoints::default()` with env overrides:
  - `BEE_REGISTRY`, `BEE_ROUTER`, `BEE_SCHEDULER`, `BEE_NEGOTIATION`
- For DevCore Negotiation, set `BEE_NEGOTIATION=http://127.0.0.1:50054`

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

