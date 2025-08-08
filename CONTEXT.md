# AgentOS SDK Work Context

This file captures the current state, decisions, and next steps for building a Python SDK (SigAgent) and the gRPC contract defined in `spec.md`.

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
  - `Makefile`: `make protos` generates Python stubs into `py_sdk/sigagent/protos` and ensures the output directory exists.
- SDK scaffold (initial skeletons):
  - `py_sdk/sigagent/__init__.py`: version and exports.
  - `py_sdk/sigagent/config.py`: `Endpoints` and `AgentConfig` dataclasses.
  - `py_sdk/sigagent/envelope.py`: envelope builders, idempotency helpers, sequence tracker.
  - `py_sdk/sigagent/runtime/agent.py`: base `Agent` class with cooperative preemption helpers.
  - Clients:
    - `py_sdk/sigagent/clients/registry.py`
    - `py_sdk/sigagent/clients/router.py`
    - `py_sdk/sigagent/clients/scheduler.py`
    - `py_sdk/sigagent/clients/hitl.py`
    - `py_sdk/sigagent/clients/worktree.py`
    - `py_sdk/sigagent/clients/negotiation.py`
    - `py_sdk/sigagent/clients/reasoning.py`
    - `py_sdk/sigagent/clients/logging.py`
    - `py_sdk/sigagent/clients/tool.py`
    - `py_sdk/sigagent/clients/connector.py`

## Not Yet Implemented
- Runtime features:
  - Policy hooks for worktree binding; persist binding state (currently in-memory).
  - Activity buffer persistence beyond process lifetime and richer reconciliation.
  - ACK lifecycle integration with router responses in higher-level flows.
  - Metrics export and richer interceptors (timing, retry policies).
- Examples and docs:
  - Echo example exists at `examples/echo_agent.py` (registration + streaming). Still needed: ACK lifecycle demonstration and preemption hooks.
  - README/usage docs can expand around enums and multi-endpoint setups.
- CI and packaging:
  - Optional: package metadata, versioning, and publishing workflows.

## How To Generate Python Stubs
- Prerequisites (local dev): `pip install grpcio grpcio-tools googleapis-common-protos`
- Generate:
  - `make protos`
- Output: `py_sdk/sigagent/protos/*_pb2.py` and `*_pb2_grpc.py`

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
  - `make protos` to generate Python stubs into `py_sdk/sigagent/protos`.
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
