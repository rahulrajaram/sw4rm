# 6. SDK Clients

The SW4RM SDKs expose gRPC clients for each protocol service. This section documents
the client layer APIs and the most common usage patterns across Python, Rust, and
JavaScript/TypeScript.

## 6.1. Conventions

- Python clients accept a gRPC channel and require generated protobuf stubs.
- JavaScript/TypeScript clients accept `ClientOptions` with a `address` string and
  handle metadata, deadlines, and retries internally.

- Rust clients are async and return `Result<T>` for all calls.

## 6.2. Documented Clients

- [Router Client](router.md)
- [Registry Client](registry.md)
- [Scheduler Client](scheduler.md)
- [Activity Client](activity.md)
- [Connector Client](connector.md)
- [Reasoning Client](reasoning.md)
- [Scheduler Policy Client](scheduler-policy.md)
- [Logging Client](logging.md)
- [Handoff Client](handoff.md)
- [HITL Client](hitl.md)
- [Negotiation Client](negotiation.md)
- [Negotiation Room Client](negotiation-room.md)
- [Tool Client](tool.md)
- [Workflow Client](workflow.md)
- [Worktree Client](worktree.md)
