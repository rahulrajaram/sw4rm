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

- Docker
  ```bash
  cd examples/reference-services/python
  ./start_services.sh
  ./stop_services.sh
  ```

Ports: Router 50051, Registry 50052. Run one language at a time.

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

