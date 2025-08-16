# Swarm Core Quickstart

This guide shows how to spin up the SW4RM core (Registry, Router, Scheduler, Negotiation) locally and drive a demo with two Bee agents.

## Prerequisites
- Docker with Compose v2 (`docker compose`)
- Built Bee CLI binary at `./bee/target/debug/bee` (or set `BEE_BIN`)
- Container images for the core services

## One‑Command Core Setup

1) Set the images to use:
Option A (env file):
```
cp bee/scripts/swarm-core.env.example bee/scripts/swarm-core.env
# edit bee/scripts/swarm-core.env with your image names
```

Option B (export variables):
```
export SWARM_REGISTRY_IMAGE=ghcr.io/yourorg/sw4rm-registry:latest
export SWARM_ROUTER_IMAGE=ghcr.io/yourorg/sw4rm-router:latest
export SWARM_SCHEDULER_IMAGE=ghcr.io/yourorg/sw4rm-scheduler:latest
export SWARM_NEGOTIATION_IMAGE=ghcr.io/yourorg/sw4rm-negotiation:latest
```

2) Bring up the core and bootstrap a local hive:
Option A (Cargo tasks):
```
cd bee
cargo swarm-core-up
cargo swarm-hive-bootstrap   # creates hive 'dev' @ localhost:50051/52/53
```

Option B (Bee CLI binary):
```
./bee/target/debug/bee swarm core-up
./bee/target/debug/bee swarm hive-bootstrap   # creates hive 'dev' @ localhost:50051/52/53
```
Option C (Make targets, optional):
```
make swarm-core-up
make swarm-hive-bootstrap
```

3) Start demo agents and run a consult negotiation:
Cargo tasks:
```
cd bee
cargo swarm-agents-up
export BEE_NEGOTIATION=http://127.0.0.1:50054
cargo swarm-demo-consult
```

Bee CLI binary:
```
./bee/target/debug/bee swarm agents-up
export BEE_NEGOTIATION=http://127.0.0.1:50054
./bee/target/debug/bee swarm demo-consult
```
or Make (optional):
```
make swarm-agents-up
export BEE_NEGOTIATION=http://127.0.0.1:50054
make swarm-demo-consult
```

## Useful Commands
Cargo tasks:
```
cd bee
cargo swarm-core-status
cargo swarm-core-logs
cargo swarm-agents-down
cargo swarm-core-down
```

Bee CLI binary:
```
./bee/target/debug/bee swarm core-status
./bee/target/debug/bee swarm core-logs
./bee/target/debug/bee swarm agents-down
./bee/target/debug/bee swarm core-down
```
Make (optional):
```
make swarm-core-status
make swarm-core-logs
make swarm-agents-down
make swarm-core-down
```

## Notes
- Ports: Registry 50051, Router 50052, Scheduler 50053, Negotiation 50054.
- The hive stores only Registry/Router/Scheduler endpoints. Set `BEE_NEGOTIATION` for negotiation CLI.
- Override paths/env via: `COMPOSE_FILE`, `BEE_BIN`, `HIVE`, `LOG_DIR`.
- The compose file lives under `bee/scripts/swarm-core.yml`; `bee/scripts/swarmctl.sh` drives operations. The script auto-resolves its compose path relative to its own location.
