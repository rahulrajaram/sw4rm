# Cross-SDK Conformance Vectors

Shared SW4-004/SW4-005 vectors consumed by Python, JS/TS, Rust, and Common Lisp
adapter tests.

## Suites

- `sw4_005_delegation_vectors.json` (`version: 2`)
- `sw4_004_cancellation_vectors.json` (`version: 1`)

## Adding a Vector

1. Add one entry under `vectors` in the appropriate suite file.
2. Keep each scenario SDK-agnostic (no language-specific fields).
3. Run all adapter suites so every SDK executes the new vector:
   - `cd sdks/py_sdk && python -m pytest tests/test_cross_sdk_conformance_vectors.py -q`
   - `cd sdks/js_sdk && npm test --silent -- --run test/conformanceVectors.test.ts`
   - `cd sdks/rust_sdk && PROTO_DIR=$(pwd)/protos cargo test --all --locked shared_conformance_vectors`
   - `cd sdks/cl_sdk && sbcl --load ~/quicklisp/setup.lisp --eval '(push (truename \".\") asdf:*central-registry*)' --eval '(ql:quickload :sw4rm-sdk)' --eval '(load \"test/suite.lisp\")' --eval '(fiveam:run! (quote sw4rm-test::sw4rm-suite))' --quit`
