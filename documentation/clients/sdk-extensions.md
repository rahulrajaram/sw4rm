# 6.22. SDK Extensions Reference

> **Version**: 0.6.0 | **Last updated**: 2026-03-24

SDK extensions are developer-convenience features that go beyond the normative protocol specification. See [sdk_extensions.md](../protocol/sdk_extensions.md) for the canonical extension catalog.

## Summary

Each row links to the page that documents the feature in use.

| Feature | SDKs | Primary modules | Documented at |
|---|---|---|---|
| Secret Management | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | `secrets/`, `sw4rm.secrets`, `sw4rm_sdk::secrets`, `src/secrets.lisp`, `Sw4rm.Secrets` |  [secrets example (Python)](https://github.com/rahulrajaram/sw4rm/tree/master/sdks/py_sdk/examples/secrets_example.py) |
| Negotiation Room Store | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | `negotiation_room_store`, negotiation-room helpers | [Negotiation Room Client](negotiation-room.md) |
| Negotiation Coordinator | Python | `sw4rm.negotiation_coordinator` | [Negotiation Room Client](negotiation-room.md) |
| Shared Context Manager | Python | `sw4rm.shared_context` | [Shared Context Client](shared-context.md) |
| Feature Flags | Python | `sw4rm.feature_flags` | — (Python-only utility; not yet documented in its own page) |
| Content Types | Python | `sw4rm.content_types` | [Content Types](../protocol/content-types.md) |
| Preemption Manager | Rust | `sw4rm_sdk::runtime::preemption` | [State Machines](../architecture/state-machines.md) |
| CONTROL Message Content Types | JavaScript/TypeScript | content-type helpers and client constants | [Content Types](../protocol/content-types.md) |
| Colony / Agent Spawning | Python | `colony/` | [SW4-014: Dynamic Swarm Spawning](../protocol/extensions/SW4-014-dynamic-swarm-spawning.md) |
| LLM Integration | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | `llm/` modules and factories | [Reasoning Client](reasoning.md) |
| Envelope-Level Message Tracking | Python | `ActivityBuffer` | [Activity Client](activity.md) · [Activity Buffer](../protocol/activity-buffer.md) |
| Extended Envelope Fields | Python, JavaScript/TypeScript, Rust | envelope builders and proto adapters | [Message Types](../protocol/messages.md) |
| Voting / Aggregation Analytics | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | voting helpers and aggregators | [Voting Strategies](../protocol/voting-strategies.md) |
| Persistence Backends | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | JSON/file-backed stores and runtime persistence | [Persistence and recovery](../quickstart/persistence.md) |

## Notes

- The protocol page is the canonical source for cross-SDK extension coverage.
- Python remains the reference bar for extension behavior; SDK-specific helper differences should be explicit in the language docs.
