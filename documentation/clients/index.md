# 6. SDK Clients

The SW4RM SDKs expose gRPC clients for the protocol services and a smaller set
of SDK-specific helpers. Python is the reference bar; JavaScript/TypeScript,
Rust, Common Lisp, and Elixir follow the same public protocol surface where
they implement it, but helper coverage is intentionally not identical.

As an agent developer, these clients take over the plumbing the protocol
already specifies: sending envelopes, receiving durable deliveries and
acknowledging them, tracking task and activity state, escalating HITL
decisions, and coordinating negotiation rooms — without hand-writing proto
bindings per service. Wire clients map one-to-one onto protocol services;
a few helpers (policy-store, shared-context, workflow-engine) run entirely in
your process. For what each SDK implements and how parity is verified, see
[SDK parity](../sdk-parity.md); for the service catalog, see
[protocol services](../protocol/services.md).

## 6.1. Conventions

- Python clients accept a gRPC channel and generated protobuf stubs.
- JavaScript/TypeScript clients accept `ClientOptions` with an `address` string and handle metadata, deadlines, and retries internally.
- Rust clients are async and return `Result<T>` for calls.
- SDK-only helpers such as `policy-store`, `shared-context`, and `workflow-engine` are documented alongside the language-specific pages that implement them.

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
- [Workflow Engine](workflow-engine.md)
- [Worktree Client](worktree.md)
- [Policy Store](policy-store.md)
- [Shared Context Manager](shared-context.md)

## 6.3. Error Handling

- [Exceptions Reference](exceptions.md) - Complete exception hierarchy and error codes
- [Error Handling Patterns](error-handling.md) - Client-specific error handling strategies
