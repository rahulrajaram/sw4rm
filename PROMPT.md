# SW4RM SDK Spec Compliance — Ralph Loop

@include IMPLEMENTATION_PLAN.md

## Objective

Work through the IMPLEMENTATION_PLAN.md items in priority order (P0 → P5). For each item:

1. Read the relevant source files in the affected SDK(s)
2. Implement the fix or addition
3. Run the verification tasks below to confirm nothing is broken
4. Update the tracking table in IMPLEMENTATION_PLAN.md (Status → DONE, Owner → agent)
5. Move to the next item

## Constraints

- Do NOT modify proto files — only SDK source and tests
- Do NOT skip tests — every change must have at least one covering test
- P4 items (spec clarifications) should be written up as questions in a `SPEC_QUESTIONS.md` file, not implemented
- P5 items should be triaged and split into concrete sub-items or deferred with rationale

## Verification Tasks

```yarli-run
version = 1
objective = "Fix all spec-compliance and cross-SDK parity issues from the audit, in priority order P0 through P5."

[[tasks.items]]
key = "py-test"
cmd = "cd sdks/py_sdk && python -m pytest tests/ -x -q"
class = "io"

[[tasks.items]]
key = "js-test"
cmd = "cd sdks/js_sdk && npm test"
class = "io"

[[tasks.items]]
key = "rust-test"
cmd = "cd sdks/rust_sdk && cargo test --quiet"
class = "io"

[[tasks.items]]
key = "py-lint"
cmd = "cd sdks/py_sdk && python -m flake8 sw4rm/ --max-line-length=120 --count --statistics"
class = "io"

[[tasks.items]]
key = "rust-lint"
cmd = "cd sdks/rust_sdk && cargo clippy --quiet -- -D warnings"
class = "io"
```
