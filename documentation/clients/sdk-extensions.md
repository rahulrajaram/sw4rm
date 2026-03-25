# 6.22. SDK Extensions Reference

> **Version**: 0.6.0 | **Last updated**: 2026-03-24

SDK extensions are developer-convenience features that go beyond the normative protocol specification. See [sdk_extensions.md](../protocol/sdk_extensions.md) for the canonical extension catalog.

## Summary

| Feature | SDKs | Primary modules |
|---|---|---|
| Secret Management | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | `secrets/`, `sw4rm.secrets`, `sw4rm_sdk::secrets`, `src/secrets.lisp`, `Sw4rm.Secrets` |
| Negotiation Room Store | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | `negotiation_room_store`, negotiation-room helpers |
| Negotiation Coordinator | Python | `sw4rm.negotiation_coordinator` |
| Shared Context Manager | Python | `sw4rm.shared_context` |
| Feature Flags | Python | `sw4rm.feature_flags` |
| Content Types | Python | `sw4rm.content_types` |
| Preemption Manager | Rust | `sw4rm_sdk::runtime::preemption` |
| CONTROL Message Content Types | JavaScript/TypeScript | content-type helpers and client constants |
| Colony / Agent Spawning | Python | `colony/` |
| LLM Integration | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | `llm/` modules and factories |
| Envelope-Level Message Tracking | Python | `ActivityBuffer` |
| Extended Envelope Fields | Python, JavaScript/TypeScript, Rust | envelope builders and proto adapters |
| Voting / Aggregation Analytics | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | voting helpers and aggregators |
| Persistence Backends | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | JSON/file-backed stores and runtime persistence |

## Notes

- The protocol page is the canonical source for cross-SDK extension coverage.
- The client pages should match this table, especially for secret management, LLM integration, and persistence.
- Python remains the reference bar for extension behavior; SDK-specific helper differences should be explicit in the language docs.
