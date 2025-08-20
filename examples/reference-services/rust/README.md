# SW4RM Rust Reference Services

Minimal Registry and Router services implemented in Rust using tonic/prost.

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

Ports: Router 50051, Registry 50052. Run one language at a time.

## What’s Included

- Binaries: `registry-service`, `router-service` (built from `src/bin/*`)
- Compose: `docker-compose.yml`
- Dockerfiles: `Dockerfile.registry`, `Dockerfile.router`
- Helpers: `start_services*.sh`, `stop_services*.sh`

## Notes

- Protos: `build.rs` compiles from `../../protos` via `tonic-build`; no
  external `protoc` required.
- Local build uses your installed Rust toolchain; Dockerfiles build release
  binaries and copy into a slim runtime image.

