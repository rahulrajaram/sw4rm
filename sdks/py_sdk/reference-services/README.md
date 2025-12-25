# SW4RM Python Reference Services

Minimal but functional Registry and Router services implemented in Python.

## Quick Start

- Local
  ```bash
  cd examples/reference-services/python
  ./start_services_local.sh
  python test_complete_setup.py
  ./stop_services_local.sh
  ```

- Two agents talking (ping/pong)
  ```bash
  cd examples/reference-services/python
  ./start_services_local.sh
  python two_agent_demo.py
  ./stop_services_local.sh
  ```

## LLM Client/Server Demo

This demo runs a Scheduler plus two agents (frontend, backend). All orchestration is via CONTROL messages and all LLM calls use the local `claude` CLI.

Paths
- Code: `examples/reference-services/python/client_server_llm/`
- Generated outputs: `examples/reference-services/python/client_server_llm/generated_app/{backend,frontend}` (ignored by Git)

Behavior (CONTROL-only)
- Plan/prompt: Send CONTROL `stage: prompt` (or `plan`) with free-form text using `prompter.py`. The scheduler calls the LLM, extracts two prompts (frontend/backend), and dispatches `generate` to agents. If the LLM also returns `{commands}`, the scheduler auto-runs after both agents finish generate.
- Run: Send CONTROL `stage: run`. The scheduler ALWAYS calls the LLM to produce canonical `{commands}` and then dispatches run to agents. Each agent consults the LLM again to confirm/adjust its own `run_cmd` before executing.

Ports and CORS
- Backend: fixed port 8000, binds `0.0.0.0`, GET `/hello` returns JSON with CORS headers, OPTIONS 204.
- Frontend: serves static files on port 5173; reads `backend_url` from query and calls `${backend_url}/hello`.

Run (local)
- Start services (Router, Registry, Scheduler):
  ```bash
  cd examples/reference-services/python
  ./start_services.sh --local
  ```

- In two terminals, start agents:
  ```bash
  # Terminal A
  python client_server_llm/backend_agent.py

  # Terminal B
  python client_server_llm/frontend_agent.py
  ```

- Plan/prompt with a file:
  ```bash
  python client_server_llm/prompter.py --file client_server_llm/plan_prompt.txt
  ```

- Run (suggestions JSON or free-form guidance):
  ```bash
  python client_server_llm/prompter.py --file client_server_llm/run_trigger.txt
  ```

Run request (CONTROL, stage=run)
- Content-Type: `application/vnd.sw4rm.scheduler.command+json;v=1`
- Payload shape:
  - Required: `{ "schema_version":1, "to":"scheduler", "stage":"run", "params": { ... } }`
  - Optional in `params`:
    - `commands`: suggested run commands (LLM may confirm or adjust):
      `{ "backend": {"run_cmd": "cd backend && python3 server.py"},
         "frontend": {"run_cmd": "cd frontend && python3 -m http.server 5173"} }`
    - `prompt`: free-form run guidance.
- Scheduler always consults the LLM to produce canonical commands:
  JSON ONLY `{ "commands": { backend:{run_cmd}, frontend:{run_cmd} } }`.
- Agents consult the LLM again to confirm/adjust their command before executing.
- CWD is `./generated_app`; use `cd backend` and `cd frontend` (do not include `generated_app`).

Requirements
- Install the Python SDK locally if not already: `pip install -e sdks/py_sdk`
- Install and authenticate the `claude` CLI; agents and scheduler invoke:
  `claude -p "<prompt>" --output-format stream-json --verbose`

Notes
- Ports: Router 50051, Registry 50052, Scheduler 50053 (env-overridable).
- Generated outputs are ignored by Git; purge `generated_app/` if you want a fresh run.

- Docker
  ```bash
  cd examples/reference-services/python
  ./start_services.sh
  ./stop_services.sh
  ```

Ports: Router 50051, Registry 50052. Run one language at a time.

Port conflicts and overrides
- Default ports may be busy if another stack is running.
- Local scripts now preflight ports and exit with a clear message.
- Override ports via environment variables:
  - `REGISTRY_PORT=55052 ROUTER_PORT=55051 ./start_services_local.sh`
  - `ROUTER_HOST`/`ROUTER_PORT` are respected by `test_complete_setup.py`.

## What’s Included

- Services: `registry_service.py`, `router_service.py`
- Compose: `docker-compose.yml`
- Dockerfiles: `Dockerfile.registry`, `Dockerfile.router`
- Helpers: `start_services*.sh`, `stop_services*.sh`, `test_complete_setup.py`

## Notes

- Stubs: Imports prefer `sw4rm.protos` from the SDK. Dockerfiles install the
  local SDK from `sdks/py_sdk`, so no network needed. Local scripts install the
  SDK in editable mode if missing.

## Troubleshooting

- ImportError (sw4rm): install SDK locally
  ```bash
  cd sdks/py_sdk && pip install -e .
  ```
