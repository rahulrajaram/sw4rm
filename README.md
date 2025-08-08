# AgentOS Python SDK (experimental)

Lightweight runtime, clients, and helpers to build message-driven agents that speak the AgentOS gRPC protocol defined by the local `.proto` files.

## Install
- Runtime only:
  - `python -m pip install .`
- Dev (with codegen):
  - `python -m pip install -e ".[dev]"`
  - Generate stubs: `make protos` (requires `grpcio-tools`).

## Quickstart
```python
import grpc
from agentos.clients.registry import RegistryClient
from agentos.clients.router import RouterClient

channel = grpc.insecure_channel("localhost:50051")
registry = RegistryClient(channel)
router = RouterClient(channel)

# Register an agent (example descriptor fields)
reg_resp = registry.register({
    "agent_id": "echo-1",
    "name": "EchoAgent",
    "version": "0.1.0",
})
print("registered:", reg_resp)

# Send a message
send_resp = router.send_message({
    "message_id": "123",
    "producer_id": "echo-1",
    "message_type": 2,  # DATA
    "content_type": "text/plain",
    "content_length": 5,
    "payload": b"hello",
})
print("sent:", send_resp)
```

## Codegen
- Prereqs: `python -m pip install -e ".[dev]"`
- Generate Python stubs into `py_sdk/agentos/protos`: `make protos`

## Packaging
- Build: `python -m pip install build twine && python -m build`
- Upload: `python -m twine upload dist/*`

## Notes
- Clients lazily import protobuf stubs and raise a clear error if stubs are missing.
- Well-known types (Timestamp/Duration) are handled via generated modules inside clients.
- This SDK is early-stage; APIs may evolve.

