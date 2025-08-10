# AgentOS SDK Work Context

This file captures the current state, decisions, and next steps for building a Python SDK (SW4RM) and the gRPC contract defined in `spec.md`.

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
  - `Makefile`: `make protos` generates Python stubs into `py_sdk/sw4rm/protos` and ensures the output directory exists.
- SDK scaffold (initial skeletons):
  - `py_sdk/sw4rm/__init__.py`: version and exports.
  - `py_sdk/sw4rm/config.py`: `Endpoints` and `AgentConfig` dataclasses.
  - `py_sdk/sw4rm/envelope.py`: envelope builders, idempotency helpers, sequence tracker.
  - `py_sdk/sw4rm/runtime/agent.py`: base `Agent` class with cooperative preemption helpers.
  - Clients:
    - `py_sdk/sw4rm/clients/registry.py`
    - `py_sdk/sw4rm/clients/router.py`
    - `py_sdk/sw4rm/clients/scheduler.py`
    - `py_sdk/sw4rm/clients/hitl.py`
    - `py_sdk/sw4rm/clients/worktree.py`
    - `py_sdk/sw4rm/clients/negotiation.py`
    - `py_sdk/sw4rm/clients/reasoning.py`
    - `py_sdk/sw4rm/clients/logging.py`
    - `py_sdk/sw4rm/clients/tool.py`
    - `py_sdk/sw4rm/clients/connector.py`

### Documentation Theme & Navigation (SW4RM site)
- Theme: minimalist dark with black/off-black surfaces, yellow accents, and indigo header/tabs.
- Desktop header:
  - Indigo header (`#157795`) with subtle divider; tabs row matches header.
  - Active tab: solid yellow rectangular background (no underline, sharp corners); hover/focus tabs are sharp rectangles.
  - Tabs strip (desktop): removed bottom border and extra padding; tightened item padding; adjusted tab list offset for alignment.
  - Logo/title sizing: logo image 3.8rem height; title (`.md-header__title .md-ellipsis`) at 3em.
  - Header inner spacing: uses only top padding for breathing room.
- Mobile/medium primary nav:
  - Expands inline (no overlay panels); caret toggles the hidden checkbox to show children.
  - Yellow highlight on the list item (li) only; link/caret do not draw left borders.
  - Removed tree connector lines; kept indentation; normalized gaps between items and before nested groups.
  - Disabled `navigation.expand` to avoid default-open sections; optional JS shim collapses all groups by default on small screens.
- In-page TOC: current section highlights in yellow while scrolling.

Artifacts:
- `documentation/assets/custom.css` — site overrides and layout tweaks.
- `documentation/assets/collapse-mobile-nav.js` — optional small-screen “collapse all” shim.
- `mkdocs.yml` — Material theme config, features, and asset wiring.

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
- Output: `py_sdk/sw4rm/protos/*_pb2.py` and `*_pb2_grpc.py`

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
  - `make protos` to generate Python stubs into `py_sdk/sw4rm/protos`.
- Build distributables (wheel + sdist):
  - `python -m pip install build twine`
  - `python -m build`
- Publish to PyPI (requires credentials):
  - `python -m twine upload dist/*`
- Versioning:
  - Bump `version` in `pyproject.toml`, rebuild, and tag the commit as needed.

### Docs (local)
- Serve: `make docs-serve`
- Build: `make docs-build`
- Customize visuals: edit `documentation/assets/custom.css`.
- Optional: small-screen nav collapse via `documentation/assets/collapse-mobile-nav.js` (wired in `mkdocs.yml` `extra_javascript`).

## Open Questions
- Do we want a strict dependency on generated protobufs at import time, or allow a lazy/optional mode with friendly errors (current clients do the latter)?
- What default endpoint map should we ship (current defaults are localhost ports)?
- Any specific languages besides Python to target for the first SDK?

## Quick Notes
- Network access may be restricted in some environments; the repo includes a `Makefile` to generate stubs locally when dependencies are available.
- The base `Agent` is intentionally minimal and non-networked; it is designed to be composed with the client wrappers generated from the protos.
