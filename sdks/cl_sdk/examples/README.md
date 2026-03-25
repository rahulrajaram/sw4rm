# SW4RM Common Lisp SDK Examples

This directory contains runnable Common Lisp reference examples for the SW4RM SDK. The scripts are intentionally local-first: they show the public API shape, the data model, and the coordination patterns without requiring a live backend for every flow.

## Prerequisites

- SBCL 2.3+ or a comparable Common Lisp implementation
- Quicklisp installed
- `sdks/cl_sdk` available on your ASDF source path
- `ql:quickload :sw4rm-sdk` before running the examples

## Example Matrix

| Example | What it shows | Fidelity |
|---|---|---|
| `echo-agent.lisp` | Basic agent lifecycle, envelope construction, and router call pattern | Stub transport demo |
| `advanced-agent.lisp` | Three-ID envelopes, ACK tracking, activity buffer, persistence, worktree binding | Stub transport demo |
| `handoff-example.lisp` | Handoff lifecycle and context preservation | Local in-memory demo |
| `hitl-escalation.lisp` | HITL escalation flows and decision handling | Mock service demo |
| `negotiation-debate.lisp` | Negotiation room flow with producer/critic/coordinator roles | Local in-memory demo |
| `negotiation-voting.lisp` | Negotiation events and voting aggregation strategies | Local demo |
| `secret-management.lisp` | File-backed secret storage and resolver behavior | Local demo |
| `tool-streaming.lisp` | Tool registration, unary calls, streaming calls, cancellation | Stub transport demo |
| `workflow-orchestration.lisp` | DAG workflow planning and execution | Local engine demo |

## Quick Start

From `sdks/cl_sdk`:

```bash
sbcl --load examples/echo-agent.lisp
sbcl --load examples/advanced-agent.lisp
sbcl --load examples/handoff-example.lisp
sbcl --load examples/hitl-escalation.lisp
sbcl --load examples/negotiation-debate.lisp
sbcl --load examples/negotiation-voting.lisp
sbcl --load examples/secret-management.lisp
sbcl --load examples/tool-streaming.lisp
sbcl --load examples/workflow-orchestration.lisp
```

## Notes

- `echo-agent.lisp` and `advanced-agent.lisp` are the best examples for understanding the agent runtime surface.
- `tool-streaming.lisp` shows the client call shape even though the transport is stubbed in the example.
- `secret-management.lisp` is completely local and is a good starting point for understanding the SDK extension layer.
