# SW4RM Python SDK

Reference Python SDK for the SW4RM Agentic Protocol. This is one of three SDKs in this repository (Python, Rust, JavaScript) and provides clients, a lightweight runtime, and helpers for ACK lifecycle, worktree/state handling, and more.

## Install

From the repo root (recommended during development):

```bash
python -m pip install -e ".[dev]"
```

## Quick Start with Working Services

🎉 **NEW**: Complete working example with services included! You can now run a full SW4RM setup locally.

### 1. Start the Services

```bash
cd ../../examples/reference-services/
./start_services_local.sh
```

### 2. Test the Setup

```bash
python test_complete_setup.py
```

### 3. Run the Echo Agent

```bash
cd ..
python examples/echo_agent.py --router localhost:50051 --registry localhost:50052
```

You should see:
```
✅ Registered successfully
🚀 Starting message loop for echo-1
```

### 4. Send Test Messages

In another terminal:
```bash
cd examples/reference-services/
python test_complete_setup.py
```

Your echo agent will receive and process the test message!

Runtime-only install (no dev tooling):

```bash
python -m pip install .
```

## Generate Protocol Stubs (dev)

If you plan to modify or regenerate protobuf stubs:

```bash
make protos
```

- Requires `grpcio-tools` (installed via the `dev` extra)
- Generated files live under `sdks/py_sdk/sw4rm/protos`

## Quick Start

```python
import grpc
from sw4rm.clients.registry import RegistryClient
from sw4rm.clients.router import RouterClient
from sw4rm.protos import common_pb2 as common

# Connect to services
router_ch = grpc.insecure_channel("localhost:50051")
registry_ch = grpc.insecure_channel("localhost:50052")
router = RouterClient(router_ch)
registry = RegistryClient(registry_ch)

# Register an agent
registry.register({
    "agent_id": "my-agent",
    "name": "My Agent",
    "description": "Example agent",
    "capabilities": ["processing"],
    "communication_class": common.CommunicationClass.STANDARD,
})

# (optional) Stream incoming messages
for item in router.stream_incoming("my-agent"):
    envelope = item.msg  # protobuf message
    # process envelope...
```

## Links

- Top-level README (overview and API): `../../README.md`
- Quickstart for running local services: `../../QUICKSTART.md`
- Rust SDK: `../rust_sdk/README.md`
- JavaScript SDK: `../js_sdk/README.md`
