# Installation

Install only the toolchains you need. The repo checkout is the source of truth for local example runs and proto generation.

## Supported Toolchains

| SDK | Minimum | Install |
|---|---|---|
| Python | 3.11 | Editable install from the repo root |
| Rust | stable | Cargo install or local cargo run |
| JavaScript/TypeScript | Node.js 20+ | npm install in `sdks/js_sdk` |
| Common Lisp | SBCL 2.3+ or CCL 1.12+ | Load the ASDF system from `sdks/cl_sdk` |
| Elixir | Elixir 1.16+ | Work from the local `sdks/ex_sdk` checkout with `mix` |

## Repo Setup

```bash
make protos
```

Run that once from the repository root if your SDK or example depends on generated protobufs.

## Python

```bash
cd sdks/py_sdk
python -m pip install -e ".[dev]"
python examples/echo_agent.py --agent-id echo-1
```

## Rust

```bash
cd sdks/rust_sdk
cargo run --example echo_agent
```

## JavaScript / TypeScript

```bash
cd sdks/js_sdk
npm install
npx tsx examples/echoAgent.ts --agent-id echo-1
```

## Common Lisp

```bash
cd sdks/cl_sdk
sbcl --load examples/echo-agent.lisp
```

## Elixir

```bash
cd sdks/ex_sdk
mix run examples/basic_agent.exs
mix run examples/handoff.exs
```

## Notes

- Use the example matrix in `../examples/index.md` to pick the smallest runnable demo for a feature.
- Python remains the recommended first install path for new users.
