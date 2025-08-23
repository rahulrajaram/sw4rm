# SW4RM SDK Usage Examples (JS/TS)

Purpose
- Small, focused scripts showing how to use SW4RM clients (Registry, Router, Scheduler, Tool, Worktree, HITL, Negotiation, Reasoning, Logging).
- These are SDK usage examples, not service implementations. For full services and demo agents, see `examples/reference-services/js/`.

Run tips
- TypeScript‑style snippets; use `npx tsx` (or `ts-node`) to run.
- Services must be running that match the example (see matrix below).
- In external projects, import from `@sw4rm/js-sdk`. In this repo, imports use `../../sdks/js_sdk/src/index.ts`.

Addresses
- Defaults align with reference services: Router `localhost:50051`, Registry `localhost:50052`, Scheduler `localhost:50053`.
- Override via env vars: `SW4RM_ROUTER_ADDR`, `SW4RM_REGISTRY_ADDR`, `SW4RM_SCHEDULER_ADDR`, `SW4RM_TOOL_ADDR`, `SW4RM_WORKTREE_ADDR`, `SW4RM_HITL_ADDR`, `SW4RM_NEGOTIATION_ADDR`, `SW4RM_REASONING_ADDR`, `SW4RM_LOGGING_ADDR`.

Dependency matrix
- `register_agent.ts`: Registry
- `router_send_receive.ts`: Router (+ optional ACK agent). Demo runner: `./run_all.sh` (ack-demo)
- `scheduler_tasks.ts`: Scheduler
- `tool_call_unary.ts`, `tool_call_stream.ts`: Tool
- `worktree_bind_switch.ts`: Worktree
- `hitl_decide.ts`: HITL
- `negotiation_flow.ts`: Negotiation
- `reasoning_checks.ts`: Reasoning
- `logging_ingest.ts`: Logging
- `persistence_autosave.ts`: none (local file persistence demo)
- `end_to_end_smoke.ts`: Registry, Router, Scheduler, Tool, Logging

One-shot demo
- Use `./run_all.sh` (ack-demo) to spin up JS reference services, run an ACK agent, send a message with ACK, and clean up automatically.
