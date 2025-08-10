# SW4RM Agentic Protocol Work Context

This file captures the current state, decisions, and next steps for the SW4RM Agentic Protocol and its reference Python SDK (clients + lightweight runtime) defined by the gRPC contracts in `spec.md`.

## Summary
- Goal: Define an open agentic protocol (services, envelopes, ACK lifecycle) with a reference Python SDK so agents can interoperate across implementations.
- Approach: Specify gRPC contracts (protos), generate Python stubs, and provide a minimal reference runtime with client wrappers and helper utilities.

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
- Reference SDK scaffold (initial skeletons):
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

### Documentation Content & Structure
- Implemented hierarchical numbering system across all documentation:
  - H1 headings numbered sequentially across pages (1-5)
  - H2 headings numbered as subsections (X.1, X.2, X.3, etc.)
  - H3 headings as sub-subsections (X.Y.1, X.Y.2, etc.)
  - H4 headings as sub-sub-subsections (X.Y.Z.1, X.Y.Z.2, etc.)
- Enhanced main documentation page (index.md):
  - Added comprehensive "Overview and Motivation" section emphasizing agent-to-agent communication
  - Combined sections 1.2/1.3 into unified "SW4RM: A Universal Agentic Protocol"
  - Emphasized autonomous agent vision and future of truly autonomous systems
  - Replaced "agent systems" with "agentic systems" terminology
  - Protocol-first approach with reference to Python SDK at rahulrajaram/sw4rm/py_sdk
  - Reframed enterprise problem as lack of standardized agentic IPC (primary) with distributed system failures as secondary concern
  - Removed unsubstantiated performance characteristics claims (throughput, latency metrics) pending demonstration
- Added Google A2A protocol comparison in Protocol Specification §3.10
- Fixed markdown formatting with proper spacing after bold headings
- Implemented fullscreen diagram functionality with click-to-expand using custom CSS and JavaScript

### Documentation Theme & Navigation
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
- Reference SDK runtime features:
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
- Use repo tooling (recommended):
  - `make venv && venv/bin/python -m pip install -e ".[dev]"`
  - `make protos` (outputs to `py_sdk/sw4rm/protos`)
- Output: `*_pb2.py`, `*_pb2_grpc.py`, and `*.pyi` under `py_sdk/sw4rm/protos/`

## Suggested Next Steps
1. Flesh out runtime helpers: activity buffer, worktree binding, ACK lifecycle utilities.
2. Implement a minimal example agent and quickstart docs.
3. Validate proto compatibility by compiling stubs and smoke-testing imports.
4. Optionally add tests for envelope helpers and client wrappers.

## Build, Docs, and Publish
- Local install (runtime only): `python -m pip install .`
- Local dev install (with codegen): `python -m pip install -e ".[dev]" && make protos`
- Docs (served from repo venv):
  - `make docs-deps`
  - `make docs-serve` (http://0.0.0.0:8010)
  - `make docs-build`
- Customize docs visuals: edit `documentation/assets/custom.css`; small-screen collapse shim at `documentation/assets/collapse-mobile-nav.js` wired via `mkdocs.yml` `extra_javascript`.
- Build distributables (wheel + sdist): `python -m pip install build twine && python -m build`
- Publish to PyPI: `python -m twine upload dist/*`
- Versioning: bump `version` in `pyproject.toml`, rebuild, and tag.

### Docs (local)
- Serve: `make docs-serve`
- Build: `make docs-build`
- Customize visuals: edit `documentation/assets/custom.css`.
- Optional: small-screen nav collapse via `documentation/assets/collapse-mobile-nav.js` (wired in `mkdocs.yml` `extra_javascript`).

## Open Questions
- Protocol vs. SDK split in docs: how much content should be protocol primers vs. SDK usage?
- Strict dependency on generated protobufs at import time vs. lazy/optional mode (current clients do the latter)?
- Default endpoint map to ship (current defaults are localhost ports)?
- Additional language SDKs to prioritize after Python?

## Quick Notes
- Network access may be restricted in some environments; the repo includes a `Makefile` to generate stubs locally when dependencies are available.
- The base `Agent` is intentionally minimal and non-networked; it is designed to be composed with the client wrappers generated from the protos.
