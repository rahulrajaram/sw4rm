# 2. Quickstart

Pick the SDK you want to use, install that toolchain, and run one of the example agents. Python is the shortest path for first-time users; the other SDKs follow the same high-level flow.

## 2.1. Fast Path

1. Install the SDK from your checkout or package manager.
2. Generate proto bindings if your language needs them.
3. Run the smallest example first, then move to the capability-specific walkthroughs in `documentation/examples/index.md`.

## 2.2. SDK Overview

| SDK | Install path | Example to start with |
|---|---|---|
| Python | Package install or editable repo install | `sdks/py_sdk/examples/echo_agent.py` |
| Rust | Crate install or local cargo run | `sdks/rust_sdk/examples/echo_agent.rs` |
| JavaScript/TypeScript | npm install from the SDK directory | `sdks/js_sdk/examples/echoAgent.ts` |
| Common Lisp | Load the local ASDF system from `sdks/cl_sdk` | `sdks/cl_sdk/examples/echo-agent.lisp` |
| Elixir | Run from the local `sdks/ex_sdk` checkout with `mix` | `sdks/ex_sdk/examples/basic_agent.exs` |

## 2.3. What To Read Next

- [Installation](installation.md) for language-specific setup.
- [Examples](../examples/index.md) for the capability matrix.
- [First Agent](first-agent.md) for a focused Python walkthrough.
