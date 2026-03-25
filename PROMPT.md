# SW4RM — Post-Phase 12

@include IMPLEMENTATION_PLAN.md

## Objective

Phase 12 (I160-I179) is complete. No open tranche queue remains.

Cross-SDK example parity is achieved across Python, JS, Rust, Common Lisp, and Elixir for all capability categories: basic agent, activity/envelope lifecycle, negotiation/voting, handoff, workflow, HITL, tool execution/streaming, voting (dedicated), and secrets.

### What is done
1. Public docs treat Python as the reference SDK and signal fidelity explicitly.
2. All five public SDKs have example READMEs linked from the shared docs.
3. JS and Rust coordination examples use real SDK clients with in-memory backends (I160-I165).
4. Tool streaming, voting, and secrets examples added for JS, Rust, and Python (I166-I172).
5. Elixir activity walkthrough and workflow examples added; HITL documented as service-backed only (I173-I175).
6. Verification harnesses cover JS type checking, Rust cargo check, Python example execution, and docs matrix lockstep (I176-I177).
7. Public docs and per-SDK READMEs synced with final fidelity labels (I178).
8. Final cross-SDK parity audit passed: 10/10 lockstep tests, all examples verified (I179).
9. `tests/inter_swarm_testbed/test_sdk_docs_lockstep.py` guards the shared example matrix against doc drift.

### Deferred
- Nit #10: Phase label fix in `rust_sdk/src/clients/mod.rs` ("Phase 3" → "Phase 2") requires coordinated spec+SDK version bump. Ride along with next release.
- Legacy production-hardening items (I076-I130) remain backlog candidates.

## Operational Requirements (Long-Loop)

- Assume long unattended runs; keep changes idempotent and restart-safe.
- Use explicit python path fallback (`/home/rahul/311/bin/python`) if shell `python` resolution fails.
- Keep tranche evidence under `artifacts/verification/`; when a tranche scope excludes that path, record evidence under `.yarli/evidence/`.
- Treat `.yarli/tranches.toml` as dispatch authority; `PROMPT.md` and `IMPLEMENTATION_PLAN.md` must mirror its open tranche queue.
- Prefer truthful docs over fake parity. If a feature is not practical in the current SDK surface, document the unsupported state clearly and add a guardrail test.

## Constraints

- Do not run `yarli run` from inside tranche commands.
- Only the operator shell may invoke `yarli run`.
- Respect per-tranche `allowed_paths`.
- Do not edit unrelated files.
- Every behavioral change must include at least one covering test, example check, or explicit verification artifact.
- Keep public fidelity labels limited to `service-backed`, `local`, and `mock/stub`.
- `mix` is not available in the current operator shell; Elixir tranche work must either use non-`mix` verification or record the exact blocker honestly.

## Verification Commands

- `docs-lockstep`: `/home/rahul/311/bin/python -m pytest tests/inter_swarm_testbed/test_ci_docs_lockstep.py tests/inter_swarm_testbed/test_sdk_docs_lockstep.py`
- `docs-lint`: `/home/rahul/311/bin/python scripts/check_docs_style.py`
- `docs-build`: `/home/rahul/311/bin/python -m mkdocs build`
- `js-priority-examples`: `cd sdks/js_sdk && npx tsc --noEmit --target ES2022 --module NodeNext --moduleResolution NodeNext --lib ES2022 --types node examples/advancedAgent.ts examples/handoffExample.ts examples/hitlEscalation.ts examples/negotiationRoomExample.ts examples/workflowExample.ts`
- `rust-examples`: `cd sdks/rust_sdk && cargo check --examples`
- `yarli-recursive-guard`: `/home/rahul/311/bin/python scripts/check_recursive_dispatch_guard.py --prompt PROMPT.md --plan IMPLEMENTATION_PLAN.md`
- `yarli-invariants`: `/home/rahul/311/bin/python scripts/check_yarli_invariants.py --config yarli.toml`
- `dispatch-authority-check`: `/home/rahul/311/bin/python scripts/check_dispatch_authority.py --tranches .yarli/tranches.toml --plan IMPLEMENTATION_PLAN.md --prompt PROMPT.md`

## Anti-Recursive Dispatch Safeguards

- Only the operator shell may invoke `yarli run`.
- Tranche-local verification must use direct command families such as `docs-lockstep`, `docs-lint`, `docs-build`, `js-priority-examples`, `rust-examples`, and targeted SDK commands.
- If recursive dispatch is detected, terminate the inner dispatch, preserve the logs under `artifacts/verification/`, and resume from the active tranche.

## Preflight Checks

- Run `/home/rahul/311/bin/python scripts/check_recursive_dispatch_guard.py --prompt PROMPT.md --plan IMPLEMENTATION_PLAN.md`.
- Run `/home/rahul/311/bin/python scripts/check_yarli_invariants.py --config yarli.toml`.
- Run `/home/rahul/311/bin/python scripts/check_dispatch_authority.py --tranches .yarli/tranches.toml --plan IMPLEMENTATION_PLAN.md --prompt PROMPT.md`.

## Key References

- `documentation/examples/index.md`
- `documentation/clients/sdk-extensions.md`
- `documentation/protocol/sdk_extensions.md`
- `sdks/py_sdk/examples/README.md`
- `sdks/js_sdk/examples/README.md`
- `sdks/rust_sdk/examples/README.md`
- `sdks/cl_sdk/examples/README.md`
- `sdks/ex_sdk/examples/README.md`
- `tests/inter_swarm_testbed/test_ci_docs_lockstep.py`
- `tests/inter_swarm_testbed/test_sdk_docs_lockstep.py`
- `.yarli/tranches.toml`
