# SW4RM JavaScript Reference Services

Minimal Registry, Router, and Scheduler services implemented with the JS SDK (TypeScript).

## Quick Start

- Local (Node >= 18)
  ```bash
  cd examples/reference-services/js
  ./start_services_local.sh
  ./stop_services_local.sh
  ```

- Docker
  ```bash
  cd examples/reference-services/js
  ./start_services.sh
  ./stop_services.sh
  ```

Ports: Router 50051, Registry 50052, Scheduler 50053. Run one language at a time.

Port conflicts
- Local scripts now preflight ports and exit with a clear message if busy.
- Resolve by stopping other stacks or using the Docker variant and editing `docker-compose.yml` to change host ports.

## What’s Included

- Sources: `src/registry-service.ts`, `src/router-service.ts`, `src/scheduler-service.ts`
- Compose: `docker-compose.yml`
- Dockerfiles: `Dockerfile.registry`, `Dockerfile.router`, `Dockerfile.scheduler`
- Helpers: `start_services*.sh`, `stop_services*.sh`

## Notes

- SDK: Dockerfiles copy the local JS SDK from `sdks/js_sdk` and run with `tsx`.
- Local: `start_services_local.sh` installs deps if `node_modules` is absent.

## LLM Client/Server Demo

This mirrors the Python demo with two agents (frontend, backend). All orchestration is via CONTROL messages and all LLM calls use the local `claude` CLI.

- Paths
  - Code: `examples/reference-services/js/agents/`
  - Generated outputs: `examples/reference-services/js/agents/generated_app/{backend,frontend}` (ignored by Git)

- Behavior (CONTROL-only)
  - Agents subscribe to Router and react to `application/vnd.sw4rm.scheduler.command+json;v=1`.
  - `stage=generate`: invoke `claude` with the prompt; write files under the respective `generated_app` subdir.
  - `stage=run`: confirm/adjust a suggested `cmd` via `claude`, execute from `./generated_app`, write `.service.pid` and `service.log`.

- Run (local)
  - Start services (Router, Registry, Scheduler):
    - `cd examples/reference-services/js && ./start_services_local.sh`
  - In two terminals, start agents:
    - `npx tsx examples/reference-services/js/agents/backend_agent.ts`
    - `npx tsx examples/reference-services/js/agents/frontend_agent.ts`
  - Send a prompt or run trigger:
    - `npx tsx examples/reference-services/js/agents/prompter.ts --file examples/reference-services/js/agents/plan_prompt.txt`
    - `npx tsx examples/reference-services/js/agents/prompter.ts --file examples/reference-services/js/agents/run_trigger.txt`

- Requirements
  - Install and authenticate the `claude` CLI; agents invoke: `claude -p "<prompt>" --output-format stream-json --verbose`.
  - Ports: Router 50051, Registry 50052, Scheduler 50053 (env-overridable).
