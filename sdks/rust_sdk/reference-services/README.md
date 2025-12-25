# SW4RM Rust Reference Services

Minimal Registry, Router, and Scheduler services implemented in Rust using tonic/prost.

## Quick Start

- Local
  ```bash
  cd examples/reference-services/rust
  ./start_services_local.sh
  ./stop_services_local.sh
  ```

- Docker
  ```bash
  cd examples/reference-services/rust
  ./start_services.sh
  ./stop_services.sh
  ```

Ports: Router 50051, Registry 50052, Scheduler 50053. Run one language at a time.

Port conflicts
- Local scripts now preflight ports and exit with a clear message if busy.
- Resolve by stopping other stacks or using the Docker variant and editing `docker-compose.yml` to change host ports.

## What’s Included

- Binaries: `registry-service`, `router-service`, `scheduler-service` (built from `src/bin/*`)
- Compose: `docker-compose.yml`
- Dockerfiles: `Dockerfile.registry`, `Dockerfile.router`, `Dockerfile.scheduler`
- Helpers: `start_services*.sh`, `stop_services*.sh`

## Notes

- Protos: `build.rs` compiles from `../../protos` via `tonic-build`; no
  external `protoc` required.
- Local build uses your installed Rust toolchain; Dockerfiles build release
  binaries and copy into a slim runtime image.

## LLM Client/Server Demo

This mirrors the Python demo with two agents (frontend, backend). All orchestration is via CONTROL messages and all LLM calls use the local `claude` CLI.

- Paths
  - Code: binaries `backend-agent` and `frontend-agent`; generated outputs under `examples/reference-services/rust/agents/generated_app/{backend,frontend}` (ignored by Git).

- Behavior (CONTROL-only)
  - Agents subscribe to Router and react to `application/vnd.sw4rm.scheduler.command+json;v=1`.
  - `stage=generate`: invoke `claude` with the prompt; write files under the respective `generated_app` subdir.
  - `stage=run`: confirm/adjust a suggested `cmd` via `claude`, execute from `./generated_app`, write `.service.pid` and `service.log`.

- Run (local)
  - Start services (Router, Registry, Scheduler):
    - `cd examples/reference-services/rust && ./start_services_local.sh`
  - In two terminals, start agents from the same directory:
    - `cargo run --bin backend-agent`
    - `cargo run --bin frontend-agent`
  - Send a prompt or run trigger:
    - `cargo run --bin prompter -- --file agents/plan_prompt.txt`
    - `cargo run --bin prompter -- --file agents/run_trigger.txt`

- Requirements
  - Install and authenticate the `claude` CLI; agents invoke: `claude -p "<prompt>" --output-format stream-json --verbose`.
  - Ports: Router 50051, Registry 50052, Scheduler 50053 (env-overridable).
