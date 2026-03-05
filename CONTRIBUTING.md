# Contributing to SW4RM

Thanks for your interest in contributing to SW4RM! This document covers the process for contributing code, reporting bugs, and proposing features.

## Quick Links

- **Issues:** [GitHub Issues](https://github.com/rahulrajaram/sw4rm/issues)
- **Website:** [sw4rm.ai](https://sw4rm.ai)
- **Protocol Spec:** `documentation/protocol/sw4rm_spec.md`
- **Extension Specs:** `documentation/protocol/extensions/SW4-001` through `SW4-005`

## Getting Started

```bash
git clone https://github.com/rahulrajaram/sw4rm.git
cd sw4rm
./quickstart.sh  # Start reference services + run demo
```

## Repository Structure

```
sw4rm/
  protos/              # Canonical protobuf service definitions
  documentation/       # Protocol spec, extensions, operational contracts
  sdks/
    py_sdk/            # Python SDK (PyPI: sw4rm-sdk)
    js_sdk/            # JavaScript/TypeScript SDK (npm: @sw4rm/js-sdk)
    rust_sdk/          # Rust SDK (crates.io: sw4rm-sdk)
    ex_sdk/            # Elixir SDK (Hex: sw4rm)
    cl_sdk/            # Common Lisp SDK
  tests/               # Cross-SDK integration tests
```

## Development Workflow

### 1. Fork and Branch

```bash
git checkout -b feature/your-feature-name
```

### 2. Make Changes

Follow the code style conventions of the SDK you're modifying:

| SDK | Style | Formatter | Test Runner |
|-----|-------|-----------|-------------|
| Python | PEP 8 | `black` | `pytest` |
| JavaScript | ESLint defaults | `prettier` | `jest` |
| Rust | `rustfmt` | `cargo fmt` | `cargo test` |
| Elixir | `mix format` | `mix format` | `mix test` |
| Common Lisp | Standard CL conventions | — | FiveAM / standalone |

### 3. Test Your Changes

Run the test suite for the SDK(s) you modified:

```bash
# Python
cd sdks/py_sdk && python -m pytest tests/ -x -q

# JavaScript
cd sdks/js_sdk && npm test

# Rust
cd sdks/rust_sdk && cargo test

# Elixir (requires Docker — no local Elixir needed)
docker run --rm -v $(pwd):/app -w /app/sdks/ex_sdk elixir:1.16 \
  bash -c "mix local.hex --force && mix local.rebar --force && mix deps.get && mix test"

# Common Lisp
cd sdks/cl_sdk && sbcl --load test/run-codec-tests.lisp
```

### 4. Submit a Pull Request

- Keep PRs focused on a single change
- Include tests for new functionality
- Update relevant documentation
- Reference the issue number if applicable

## What to Contribute

### Good First Issues

Look for issues labeled `good-first-issue` on GitHub. These are scoped, well-defined tasks suitable for newcomers.

### SDK Contributions

- Bug fixes and test improvements for any SDK
- New SDK implementations (Go and Java are most wanted)
- Cross-SDK parity fixes (ensure all SDKs encode/decode identically)

### Protocol Contributions

- Extension proposals (follow the `SW4-XXX` pattern in `documentation/protocol/extensions/`)
- Conformance test vectors
- Wire format compatibility testing

### Documentation

- Tutorial improvements
- API documentation
- Example code and cookbooks

## Protocol Change Process

Protocol changes follow a lightweight RFC process:

1. Open a GitHub issue describing the proposed change
2. Write a draft extension spec following the `SW4-XXX` template
3. Get feedback from maintainers
4. Implement in at least one SDK with conformance tests
5. Submit PR with spec + implementation + tests

## Code of Conduct

Be respectful, constructive, and professional. We're building infrastructure that agents depend on — the same reliability standard applies to our interactions.

## License

By contributing, you agree that your contributions will be licensed under the project's existing license (Apache 2.0).
