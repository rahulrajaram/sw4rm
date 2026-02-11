# Changelog

All notable changes to the SW4RM Python SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - 2026-02-11

### Added
- `HandoffClient` now available from `sw4rm.clients` for consistent API with other service clients
- `WorkflowClient` added to `sw4rm.clients` as alias for `WorkflowEngine` (SDK parity with Rust/JS)
- Initial release with full SW4RM protocol support
- Service clients: Registry, Router, Scheduler, SchedulerPolicy, Tool, Worktree, Negotiation, NegotiationRoom, Hitl, Logging, Activity, Connector, Reasoning
- Agent runtime with 12-state lifecycle
- Workflow engine with DAG orchestration
- Voting aggregation strategies
- Policy store with versioning
- Handoff protocol for agent-to-agent transfers

### Changed
- **Client imports standardized**: All service clients now exportable from `sw4rm.clients`:
  ```python
  from sw4rm.clients import (
      HandoffClient,      # NEW
      WorkflowClient,     # NEW (alias for WorkflowEngine)
      NegotiationRoomClient,
      RegistryClient,
      RouterClient,
      SchedulerClient,
      # ... and 9 more
  )
  ```

### Deprecated
- Importing `HandoffClient` from `sw4rm.handoff` is deprecated. Use `from sw4rm.clients import HandoffClient` instead. The old import path will continue to work but emits a `DeprecationWarning`.

### Fixed
- Python Makefile now includes all proto files (`handoff.proto`, `workflow.proto`, `negotiation_room.proto`) preventing stub loss on `make protos`
- Service clients: Registry, Router, Scheduler, SchedulerPolicy, Tool, Worktree, Negotiation, NegotiationRoom, Hitl, Logging, Activity, Connector, Reasoning
- Agent runtime with 12-state lifecycle
- Workflow engine with DAG orchestration
- Voting aggregation strategies
- Policy store with versioning
- Handoff protocol for agent-to-agent transfers
