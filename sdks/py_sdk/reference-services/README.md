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

Optional JWT auth for reference services
- Enable with:
  - `REFERENCE_AUTH_ENABLED=1`
  - `REFERENCE_AUTH_JWT_SECRET=<shared-secret>`
- Optional defaults:
  - `REFERENCE_AUTH_ADMIN_AGENTS=scheduler` (comma-separated list)
  - `REFERENCE_AUTH_POLICY_PATH=/path/to/reference-auth-policy.json`
- `Authorization` token format: `Authorization: Bearer <jwt>` using HS256 claims `sub`, `iat`, and `exp`.
- Minimal policy JSON (optional):
  - `admin_agents`: list of scheduler/admin identities.
  - `method_permissions`: map of method name to allowed actor list (`*` means any authenticated actor).
  - `agent_permissions`: map of actor to method overrides.
- `self_bound_methods`: methods requiring request-target identity match.

Optional per-agent SendMessage rate limiting for the reference services
- Configure with:
  - `REFERENCE_RATE_LIMIT_ENABLED=1`
  - `REFERENCE_RATE_LIMIT_MESSAGES_PER_SECOND=10`
  - `REFERENCE_RATE_LIMIT_BURST_SIZE=10`
  - `REFERENCE_RATE_LIMIT_TARGET_METHODS=SendMessage`
- Limits apply before auth decisions in the gRPC interceptor chain; each actor is keyed by JWT `sub` when available, otherwise request actor fields (`producer_id` for `SendMessage`).

Structured logging and correlation IDs
- By default, all reference services emit JSON logs for aggregation.
- Configure output format with:
  - `REFERENCE_LOG_FORMAT=json` (default)
  - `REFERENCE_LOG_FORMAT=plain` (human-readable)
- Override level with `REFERENCE_LOG_LEVEL` (for example `DEBUG`, `INFO`, `WARNING`).
- Correlation IDs are extracted from message envelopes and gRPC metadata (`x-correlation-id`, `correlation-id`, `x-request-id`, `request-id`).
- gRPC interceptors set request-scoped correlation context so logs for one RPC share the same correlation identifier.

Distributed tracing
- Traces are propagated using both gRPC metadata and envelope-sidecar metadata.
- The server-side tracing interceptor reads:
  - OpenTelemetry/`traceparent` headers when present.
  - SW4RM metadata headers (`x-sw4rm-trace-id`, `x-sw4rm-span-id`, optional parent and correlation id).
  - `TraceContext` from `request.msg["_trace_context"]` (envelope payload) when metadata headers are absent.
- Python clients add `_trace_context` to envelopes for Router sends and strip it before protobuf serialization so message schema compatibility is preserved.
- Outbound `SendMessage` RPCs include both generated trace metadata and envelope-sidecar trace context to support hop-by-hop continuity across services.

Prometheus metrics exporter
- Enabled by default on registry/router/scheduler with dedicated ports:
  - Registry: 9100
  - Router: 9101
  - Scheduler: 9102
- Exported endpoint: `http://<host>:<port>/metrics`
- Default metric names:
  - `sw4rm_reference_messages_total`
  - `sw4rm_reference_request_latency_seconds`
  - `sw4rm_reference_rpc_errors_total`
  - `sw4rm_reference_active_connections`
- Configure the exporter with:
  - `REFERENCE_METRICS_ENABLED=0|1` (default `1`)
  - `REFERENCE_METRICS_HOST` (default `0.0.0.0`)
  - `REFERENCE_METRICS_PORT` (service default fallback)
  - `<SERVICE>_METRICS_PORT` (`REGISTRY_METRICS_PORT`, `ROUTER_METRICS_PORT`, `SCHEDULER_METRICS_PORT`)

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

## Containerized deployment

### Docker images and compose

The Python reference services are packaged as Docker images through these build targets:

- `Dockerfile.registry` → `sw4rm-reference-registry`
- `Dockerfile.router` → `sw4rm-reference-router`
- `Dockerfile.scheduler` → `sw4rm-reference-scheduler`

Build all three images from repository root:

```bash
cd /home/rahul/Documents/sigagent/sdks/py_sdk/reference-services
docker build -t sw4rm/reference-registry:0.6.0 -f docker/Dockerfile.registry .
docker build -t sw4rm/reference-router:0.6.0 -f docker/Dockerfile.router .
docker build -t sw4rm/reference-scheduler:0.6.0 -f docker/Dockerfile.scheduler .
```

Run the packaged services with compose:

```bash
cd /home/rahul/Documents/sigagent/sdks/py_sdk/reference-services
SW4RM_REFERENCE_REGISTRY_IMAGE=sw4rm/reference-registry:0.6.0 \
SW4RM_REFERENCE_ROUTER_IMAGE=sw4rm/reference-router:0.6.0 \
SW4RM_REFERENCE_SCHEDULER_IMAGE=sw4rm/reference-scheduler:0.6.0 \
docker compose -f docker/docker-compose.yml up --build -d
```

Stop stack:

```bash
cd /home/rahul/Documents/sigagent/sdks/py_sdk/reference-services
docker compose -f docker/docker-compose.yml down -v
```

### Kubernetes Helm chart

Install or upgrade the reference control-plane stack with Helm:

```bash
cd /home/rahul/Documents/sigagent/sdks/py_sdk/reference-services
helm install sw4rm-reference-services helm/sw4rm-reference-services \
  --namespace sw4rm-reference --create-namespace

# or upgrade
helm upgrade --install sw4rm-reference-services helm/sw4rm-reference-services \
  --namespace sw4rm-reference --create-namespace \
  --set services.registry.image.repository=sw4rm/reference-registry \
  --set services.registry.image.tag=0.6.0 \
  --set services.router.image.repository=sw4rm/reference-router \
  --set services.router.image.tag=0.6.0 \
  --set services.scheduler.image.repository=sw4rm/reference-scheduler \
  --set services.scheduler.image.tag=0.6.0
```

Useful overrides:

- `services.<name>.replicas`
- `services.<name>.image.repository`
- `services.<name>.image.tag`
- `services.<name>.env`
- `global.imagePullSecrets`

Render locally before install:

```bash
helm template sw4rm-reference-services helm/sw4rm-reference-services \
  --values helm/sw4rm-reference-services/values.yaml
```

## Health checks

All three Python reference servers now expose the standard gRPC health protocol:
- Service: `grpc.health.v1.Health`
- Methods: `Check`, `Watch`

Both endpoints report `SERVING` for the local service name and `SERVICE_UNKNOWN` for unregistered service names, matching common Kubernetes and `grpc_health_probe` expectations.

## Graceful shutdown and in-flight request draining

Registry, Router, and Scheduler now support graceful shutdown with connection draining:

- `SIGINT` and `SIGTERM` begin a draining phase via a shared coordinator.
- New RPCs are rejected once draining starts with service-specific shutdown reasons.
- In-flight tracked requests are allowed to complete before gRPC transport shutdown.
- Configure shutdown grace behavior with:

  ```bash
  REFERENCE_SHUTDOWN_GRACE_SECONDS=5.0
  ```

Port conflicts and overrides
- Default ports may be busy if another stack is running.
- Local scripts now preflight ports and exit with a clear message.
- Override ports via environment variables:
  - `REGISTRY_PORT=55052 ROUTER_PORT=55051 ./start_services_local.sh`
  - `ROUTER_HOST`/`ROUTER_PORT` are respected by `test_complete_setup.py`.

## Configuration and hot-reload

The Python reference services read runtime settings from environment variables and
optionally a JSON/TOML config file. `file` mode supports hot reload by watching
the config file and applying supported values at runtime.

Runtime resolution precedence:

1. service-specific environment variables
2. service-specific fields in config file (or top-level service section)
3. global config file values
4. static defaults

Supported environment variables:

- `REFERENCE_CONFIG_BACKEND` (`file`/`env`/`etcd`/`consul`; `file` default)
- `REFERENCE_CONFIG_FILE` (path to config file when using `file` backend)
- `REFERENCE_CONFIG_RELOAD_SECONDS`
- `REFERENCE_SERVICE_DB_DIR`
- `REFERENCE_REGISTRY_HEARTBEAT_TIMEOUT_SECONDS`
- `REFERENCE_REGISTRY_CLEANUP_INTERVAL_SECONDS`
- `REFERENCE_ROUTER_MAX_QUEUE_SIZE`
- `REFERENCE_SHUTDOWN_GRACE_SECONDS`
- `REGISTRY_HOST`, `ROUTER_HOST`, `SCHEDULER_HOST`
- `REGISTRY_PORT`, `ROUTER_PORT`, `SCHEDULER_PORT`
- `REGISTRY_DB_PATH`, `ROUTER_DB_PATH`, `SCHEDULER_DB_PATH`

Example config file (`reference-config.json`):

```json
{
  "global": {
    "host": "localhost",
    "port": 50050,
    "heartbeat_timeout_seconds": 300,
    "cleanup_interval_seconds": 60,
    "max_queue_size": 100,
    "shutdown_grace_seconds": 5,
    "db_path": "/var/lib/sw4rm/reference.sqlite3"
  },
  "services": {
    "registry": {
      "port": 50052,
      "heartbeat_timeout_seconds": 120,
      "db_path": "/var/lib/sw4rm/registry.sqlite3"
    },
    "router": {
      "port": 50051,
      "max_queue_size": 200,
      "host": "127.0.0.1",
      "db_path": "/var/lib/sw4rm/router.sqlite3"
    }
  },
  "scheduler": {
    "port": 50053,
    "db_path": "/var/lib/sw4rm/scheduler.sqlite3"
  }
}
```

`etcd` and `consul` backends are accepted as placeholders and currently log a warning while falling back to file-backed config.

## What’s Included

- Services: `registry_service.py`, `router_service.py`
- Compose: `docker/docker-compose.yml`
- Dockerfiles: `docker/Dockerfile.registry`, `docker/Dockerfile.router`, `docker/Dockerfile.scheduler`
- Helm chart: `helm/sw4rm-reference-services`
- Helpers: `start_services*.sh`, `stop_services*.sh`, `test_complete_setup.py`

## Notes

- Stubs: Imports prefer `sw4rm.protos` from the SDK. Dockerfiles install the
  local SDK from `sdks/py_sdk`, so no network needed. Local scripts install the
  SDK in editable mode if missing.

## Persistence

- Registry/Router/Scheduler now use SQLite-backed persistence by default so pending
  queue rows, registered agents, tasks, and activity entries survive process restarts.
- DB files default to `.reference_services_state/*.sqlite3` in the process working
  directory.
- Override each service DB path with environment variables:
  - `REFERENCE_SERVICE_DB_DIR` (shared default directory)
  - `REGISTRY_DB_PATH`
  - `ROUTER_DB_PATH`
  - `SCHEDULER_DB_PATH`

## Troubleshooting

- ImportError (sw4rm): install SDK locally
  ```bash
  cd sdks/py_sdk && pip install -e .
  ```
