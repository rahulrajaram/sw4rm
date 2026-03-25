# SW4RM SDK Extensions

Version: 0.6.0 (2026-03-24)

This document catalogs SDK features that extend beyond the normative requirements of `spec.md`. These extensions are not part of the core protocol. The canonical public rule is simple: if a feature is shared across SDKs, the table below says so; if it is SDK-specific, that is called out explicitly.

## Extension Matrix

| Feature | SDKs | Notes |
|---|---|---|
| Secret Management (`secrets/`) | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | Local secret storage and resolver helpers; backends vary by language. |
| Negotiation Room Store | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | Local persistent state for negotiation-room workflows. |
| Negotiation Coordinator | Python | Opinionated policy coordinator on top of the negotiation-room pattern. |
| Shared Context Manager | Python | Optimistic-locking shared state for concurrent agents. |
| Feature Flags | Python | Runtime feature toggles for SDK behavior. |
| Content Types | Python | Vendor MIME types and registry helpers. |
| Preemption Manager | Rust | Cooperative preemption with safe-point checking. |
| CONTROL Message Content Types | JS/TS | Scheduler command and agent report content-type constants. |
| Colony / Agent Spawning | Python | Thread-based agent lifecycle support. |
| LLM Integration | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | Provider-agnostic adapters and factories. |
| Envelope-Level Message Tracking | Python | Per-envelope tracking on top of task-level activity entries. |
| Extended Envelope Fields | Python, JS/TS, Rust | SDK-level metadata fields pending proto expansion. |
| Voting / Aggregation Analytics | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | Analytics layered on top of the negotiation-room strategies. |
| Persistence Backends | Python, JavaScript/TypeScript, Rust, Common Lisp, Elixir | JSON/file-backed persistence for activity, worktree, and config data. |

## Notes

- Python remains the parity baseline for SDK extensions.
- When a feature is only partially implemented in one SDK, the example and client docs should say so directly instead of implying parity.
- This file should stay aligned with `documentation/clients/sdk-extensions.md`.
