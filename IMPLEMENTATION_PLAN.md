# SW4RM — Implementation Plan

Phase 12: Cross-SDK Example Parity and Public Docs Closure (`I160`-`I179`) completed on 2026-03-25.

All 20 tranches (I160-I179) are complete. Cross-SDK example parity is achieved across Python, JS, Rust, Common Lisp, and Elixir for all capability categories: basic agent, activity/envelope lifecycle, negotiation/voting, handoff, workflow, HITL, tool execution/streaming, voting (dedicated), and secrets.

Deferred: Nit #10 (Phase label fix in `rust_sdk/src/clients/mod.rs`) requires a coordinated spec+SDK version bump — ride along with the next release.

## Completed Tranches

- `I160` — JS handoff example rewritten with real HandoffClient (6 scenarios incl. timeout + budget) — `97b8821`
- `I161` — JS workflow example rewritten with real WorkflowClient + resumeWorkflow + failure path — `97b8821`
- `I162` — JS negotiation example rewritten with real NegotiationRoomClient + HITL escalation — `97b8821`
- `I163` — Rust handoff example rewritten with real HandoffClient (6 scenarios incl. rejection codes + budget) — `97b8821`
- `I164` — Rust workflow example rewritten with real WorkflowClient + cancel_workflow + failure path — `97b8821`
- `I165` — Rust negotiation example rewritten with real NegotiationRoomClient + HITL escalation — `97b8821`
- `I166` — JS tool streaming example (mock-backed, 4 scenarios + real API reference)
- `I167` — Rust tool streaming example (mock-backed, tokio async, mpsc channels)
- `I168` — JS voting example (real SDK imports, 4 strategies + VotingAnalyzer analytics)
- `I169` — Rust voting example (real SDK imports, 4 strategies + VotingAggregator analytics)
- `I170` — Python secrets example (FileBackend, Resolver 4-level precedence, listing)
- `I171` — JS secrets example (async API, FileBackend in tempdir, Resolver precedence)
- `I172` — Rust secrets example (FileBackend, Resolver, BackendMode selection)
- `I173` — Elixir activity walkthrough (state machine, envelope lifecycle, activity buffer)
- `I174` — Elixir workflow example (Sw4rm.Workflow GenServer DAG engine, failure + cancel)
- `I175` — Elixir HITL documented as service-backed only (no standalone demo)
- `I176` — JS + Rust example verification harnesses (tsc --noEmit, cargo check --examples)
- `I177` — Python + Elixir verification (secrets_example.py runs, lockstep tests, docs matrix coverage)
- `I178` — Public docs and per-SDK READMEs synced with new parity rows and fidelity labels
- `I179` — Final cross-SDK parity audit passed (10/10 lockstep tests, all examples verified)

## Open Work Tranches

- None

## Deferred Backlog

- Legacy production-hardening items `I076`-`I130` remain backlog candidates, but they are not currently enqueued in Yarli.
- Broader launch and ecosystem items stay in `VISION.md` until the active example-parity queue is clear.
