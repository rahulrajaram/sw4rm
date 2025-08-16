# DevCore — Local In-Repo Core Services

This is the active context for the `bee` DevCore work. See also `contexts/DEVCORE_CONTEXT.md` for full scope and milestones.

Status (MVP):
- Registry, Router, Scheduler, Negotiation implemented as tonic servers on localhost ports 50051–50054.
- In-memory state only; no persistence.
- `bee dev-core up|down|health` wired; health probes all four endpoints.

Verify locally:
1. Start: `cd bee && cargo run -- dev-core up`
2. Health: `bee dev-core health` (in another shell)
3. Router ping: `BEE_ROUTER=http://127.0.0.1:50052 bee router ping`
4. Stream delivery: `bee Shell` → `/from my-agent-1`, then `bee scheduler submit --endpoint http://127.0.0.1:50053 task-1 my-agent-1 --json '{}'`
5. Negotiation: `export BEE_NEGOTIATION=http://127.0.0.1:50054` then `bee negotiate open demo --topic demo --participants my-agent-1,other`

Notes:
- Multiple `bee` processes may clash on metrics port 9464; use `BEE_METRICS_ADDR=127.0.0.1:0` to auto-pick a free port.
- Activity Buffer RPCs currently stub empty.

TODOs

- Registry
  - [x] Implement `register/heartbeat/deregister` (in-memory presence)
  - [ ] Allowlist + basic validation (reject unknown/blocked agents)
  - [ ] Expire stale agents (heartbeat TTL) and emit events
  - [ ] Health/status endpoint with counts and timestamps

- Router
  - [x] Per-agent server-side streaming via subscriptions
  - [ ] Delivery semantics: queueing for briefly disconnected streams
  - [ ] Backpressure handling and slow consumer policy
  - [ ] Control channel helpers (preempt/shutdown typed events)
  - [ ] Fanout filtering by lane/scope when scheduler lanes land

- Scheduler
  - [x] `submit/preempt/shutdown` that fan out via Router
  - [ ] Per-agent in-memory queues with states (queued/running/...)
  - [ ] Basic fairness/priority (priority field honored)
  - [ ] Lanes: default now; add lane-aware routing and toggles
  - [ ] Activity buffer: wire `poll/purge` into Activity store

- Negotiation
  - [x] Rooms + verbs (open/propose/counter/evaluate/decide/abort)
  - [ ] Persist minimal event log in-memory ring with limits
  - [ ] Room lifecycle: auto-close/timeout, participant mutations
  - [ ] Structured event payloads and envelope headers

- Integrator/CLI
  - [x] `bee dev-core up|down|health`
  - [ ] Graceful shutdown signaling for all servers
  - [ ] Health summary includes counts, queue depth, room count
  - [ ] Optional: run in-process vs. child subprocesses flag

- Testing & Tooling
  - [x] Unit tests for all MVP services
  - [ ] Basic integration test: submit → router stream → receipt
  - [ ] Negotiation integration: open → propose → receive
  - [ ] Fuzz inputs and invalid payloads (structured errors)

- Observability
  - [ ] Structured tracing spans per RPC with IDs
  - [ ] Basic metrics: connected agents, stream count, queue depth
  - [ ] Log normalization and concise error mapping

- Hardening & Performance
  - [ ] Input validation and error codes
  - [ ] Limits: payload size, max rooms, max subscribers per agent
  - [ ] Benchmarks for stream throughput and fanout cost

- Packaging
  - [ ] Feature flags: persistence stubs, lanes, backpressure
  - [ ] Dockerfiles for services (post-MVP)

- Docs & Demos
  - [x] DevCore Quickstart in `QUICKSTART.md`
  - [ ] Two-agent demo script with submit+consult flow
  - [ ] TUI walkthrough and recorded session

