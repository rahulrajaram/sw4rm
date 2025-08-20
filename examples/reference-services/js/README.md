# SW4RM JavaScript Reference Services

Minimal Registry and Router services implemented with the JS SDK (TypeScript).

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

Ports: Router 50051, Registry 50052. Run one language at a time.

## What’s Included

- Sources: `src/registry-service.ts`, `src/router-service.ts`
- Compose: `docker-compose.yml`
- Dockerfiles: `Dockerfile.registry`, `Dockerfile.router`
- Helpers: `start_services*.sh`, `stop_services*.sh`

## Notes

- SDK: Dockerfiles copy the local JS SDK from `sdks/js_sdk` and run with `tsx`.
- Local: `start_services_local.sh` installs deps if `node_modules` is absent.

