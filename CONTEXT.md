# AgentOS SDK Work Context

This file captures the current state, decisions, and next steps for building a Python SDK and the gRPC contract defined in `spec.md`.

## Summary
- Goal: Provide an SDK to implement message-driven agents conforming to the spec and `.proto` contracts, enabling a CLI or service to act as an Agent.
- Approach: Define gRPC contracts (protos), generate Python stubs, and build a minimal runtime with thin client wrappers and helper utilities.

## Changes Made
- Protos completed per `spec.md` (populated placeholders):
  - `common.proto`: Envelope, enums (MessageType, AckStage, ErrorCode, AgentState, CommunicationClass, DebateIntensity, HitlReasonType).
  - `registry.proto`: AgentDescriptor, Register/Heartbeat/Deregister APIs.
  - `router.proto`: SendMessage, StreamIncoming.
  - `scheduler.proto`: SubmitTask, RequestPreemption, ShutdownAgent, ActivityBuffer APIs.
  - `hitl.proto`: HitlInvocation/Decision, Decide service.
  - `worktree.proto`: Bind/Unbind/Switch/Status operations.
  - `tool.proto`: ExecutionPolicy, ToolCall/Frame/Error, ToolService.
  - `connector.proto`: ToolDescriptor, provider register/describe APIs.
  - `negotiation.proto`: Open/Propose/Counter/Evaluate/Decide/Abort.
  - `reasoning.proto`: CheckParallelism/EvaluateDebate
  - `logging.proto`: LogEvent, Ingest.
- Build helper:
  - `Makefile`: `make protos` generates Python stubs into `py_sdk/agentos/protos` and ensures the output directory exists.
- SDK scaffold (initial skeletons):
  - `py_sdk/agentos/__init__.py`: version and exports.
  - `py_sdk/agentos/config.py`: `Endpoints` and `AgentConfig` dataclasses.
  - `py_sdk/agentos/envelope.py`: envelope builders, idempotency helpers, sequence tracker.
  - `py_sdk/agentos/runtime/agent.py`: base `Agent` class with cooperative preemption helpers.
  - Clients:
    - `py_sdk/agentos/clients/registry.py`
    - `py_sdk/agentos/clients/router.py`
    - `py_sdk/agentos/clients/scheduler.py`
    - `py_sdk/agentos/clients/hitl.py`
    - `py_sdk/agentos/clients/worktree.py`
    - `py_sdk/agentos/clients/negotiation.py`
    - `py_sdk/agentos/clients/reasoning.py`
    - `py_sdk/agentos/clients/logging.py`
    - `py_sdk/agentos/clients/tool.py`
    - `py_sdk/agentos/clients/connector.py`

## Not Yet Implemented
- Runtime features:
  - Activity buffer store/reconciliation.
  - Worktree binding state manager and policy hooks.
  - Message ACK lifecycle helpers and error mapping utilities.
  - gRPC interceptors for correlation IDs and metrics.
- Examples and docs:
  - `examples/echo_agent.py` demonstrating registration, streaming, ACKs, preemption.
  - README/usage docs for running an agent.
- CI and packaging:
  - Optional: package metadata, versioning, and publishing workflows.

## How To Generate Python Stubs
- Prerequisites (local dev): `pip install grpcio grpcio-tools googleapis-common-protos`
- Generate:
  - `make protos`
- Output: `py_sdk/agentos/protos/*_pb2.py` and `*_pb2_grpc.py`

## Suggested Next Steps
1. Flesh out runtime helpers: activity buffer, worktree binding, ACK lifecycle utilities.
2. Implement a minimal example agent and quickstart docs.
3. Validate proto compatibility by compiling stubs and smoke-testing imports.
4. Optionally add tests for envelope helpers and client wrappers.

## Build & Publish
- Local install (runtime only):
  - `python -m pip install .`
- Local dev install (includes codegen tool):
  - `python -m pip install -e ".[dev]"`
  - `make protos` to generate Python stubs into `py_sdk/agentos/protos`.
- Build distributables (wheel + sdist):
  - `python -m pip install build twine`
  - `python -m build`
- Publish to PyPI (requires credentials):
  - `python -m twine upload dist/*`
- Versioning:
  - Bump `version` in `pyproject.toml`, rebuild, and tag the commit as needed.

## Open Questions
- Do we want a strict dependency on generated protobufs at import time, or allow a lazy/optional mode with friendly errors (current clients do the latter)?
- What default endpoint map should we ship (current defaults are localhost ports)?
- Any specific languages besides Python to target for the first SDK?

## Quick Notes
- Network access may be restricted in some environments; the repo includes a `Makefile` to generate stubs locally when dependencies are available.
- The base `Agent` is intentionally minimal and non-networked; it is designed to be composed with the client wrappers generated from the protos.
