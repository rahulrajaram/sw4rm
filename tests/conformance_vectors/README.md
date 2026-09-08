# Cross-SDK Conformance Vectors

Shared vectors consumed by Python, JS/TS, Rust, Elixir and Common Lisp adapter tests.

## Suites

- `wire_vectors.json`: generated from the root protos; 15 services, 57 RPCs,
  128 non-map-entry messages and 512 cases including defaults and presence.
  Run `python scripts/generate_sdk_wire_contract.py` to detect drift or add
  `--write` after a reviewed schema change. Never hand-edit generated vectors.
- `idempotency_vectors.json`: the portable bytes-v1 token algorithm; legacy
  JSON/plist helpers are excluded because their serialization differs.

- `sw4_005_delegation_vectors.json` (`version: 2`)
- `sw4_004_cancellation_vectors.json` (`version: 1`)
- `score_aggregation_vectors.json`: arithmetic and confidence-weighted means,
  population deviation, bounds, zero-confidence fallback, and empty input.
- `quorum_vectors.json`: distinct critics, thresholds, timeout actions, and
  injected abstain records. Quorum and score vectors are consumed by all five SDKs.

## Adding a Vector

1. Add one entry under `vectors` in the appropriate suite file.
2. Keep each scenario SDK-agnostic (no language-specific fields).
3. Run all adapter suites so every SDK executes the new vector:
   - `cd sdks/py_sdk && python -m pytest tests/test_cross_sdk_conformance_vectors.py -q`
   - `cd sdks/js_sdk && npm test --silent -- --run test/conformanceVectors.test.ts`
   - `cd sdks/rust_sdk && PROTO_DIR=$(pwd)/protos cargo test --all --locked shared_conformance_vectors`
   - `cd sdks/cl_sdk && sbcl --load ~/quicklisp/setup.lisp --eval '(push (truename \".\") asdf:*central-registry*)' --eval '(ql:quickload :sw4rm-sdk)' --eval '(load \"test/suite.lisp\")' --eval '(fiveam:run! (quote sw4rm-test::sw4rm-suite))' --quit`
