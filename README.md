# SigAgent Python SDK (experimental)

Lightweight runtime, clients, and helpers to build message-driven agents that speak the AgentOS gRPC protocol defined by the local `.proto` files.

## Install
- Runtime only:
  - `python -m pip install .`
- Dev (with codegen):
  - `python -m pip install -e ".[dev]"`
  - Generate stubs: `make protos` (requires `grpcio-tools`).

## Before You Start
- For local development, install dev deps and generate protobuf stubs:
  - `python -m pip install -e ".[dev]"`
  - `make protos`
  - Stubs are generated under `py_sdk/sigagent/protos`.

## Quickstart
```python
import grpc
from sigagent.clients.registry import RegistryClient
from sigagent.clients.router import RouterClient

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
    # Prefer named enums if stubs are generated:
    #   from sigagent.protos import common_pb2 as common
    #   "message_type": common.DATA,
    # Otherwise, numeric value works as well:
    "message_type": 2,  # DATA
    "content_type": "text/plain",
    "content_length": 5,
    "payload": b"hello",
})
print("sent:", send_resp)
```

## Codegen
- Prereqs: `python -m pip install -e ".[dev]"`
- Generate Python stubs into `py_sdk/sigagent/protos`: `make protos`

## Packaging
- Build: `python -m pip install build twine && python -m build`
- Upload: `python -m twine upload dist/*`

## Notes
- Clients lazily import protobuf stubs and raise a clear error if stubs are missing.
- Well-known types (Timestamp/Duration) are handled via generated modules inside clients.
- This SDK is early-stage; APIs may evolve.

## Examples
- Minimal echo agent demonstrating registration and streaming: `examples/echo_agent.py`
- Run it (router and registry may be the same host:port or separate):
  - `python examples/echo_agent.py --agent-id echo-1 --name EchoAgent \\
    --router localhost:50051 --registry localhost:50052`
  - Note: In simple deployments, Registry and Router may share the same address; pass the same value to both flags if so.
