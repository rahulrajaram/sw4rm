# 4. Examples

Examples are organized by capability and labeled by fidelity. Python is the reference bar; other SDKs are shown where they have a comparable walkthrough. The `Mode` column uses `service-backed`, `local`, or `mock/stub` so readers can tell which demos require running services.

## 4.1. Capability Matrix

| Capability | Python | JavaScript/TypeScript | Rust | Common Lisp | Elixir | Mode |
|---|---|---|---|---|---|---|
| Basic agent | [`echo_agent.py`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/echo_agent.py) | [`echoAgent.ts`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/echoAgent.ts) | [`echo_agent.rs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/echo_agent.rs) | [`echo-agent.lisp`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/cl_sdk/examples/echo-agent.lisp) | [`basic_agent.exs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/ex_sdk/examples/basic_agent.exs) | service-backed + local/stub |
| Activity / envelope lifecycle | [`three_id_demo.py`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/three_id_demo.py) | [`advancedAgent.ts`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/advancedAgent.ts) | [`activity_demo.rs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/activity_demo.rs) | [`advanced-agent.lisp`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/cl_sdk/examples/advanced-agent.lisp) | [`activity_walkthrough.exs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/ex_sdk/examples/activity_walkthrough.exs) | service-backed + local/stub |
| Negotiation / voting | [`negotiation_debate_example.py`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/negotiation_debate_example.py) | [`negotiationRoomExample.ts`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/negotiationRoomExample.ts) | [`negotiation_room.rs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/negotiation_room.rs) | [`negotiation-voting.lisp`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/cl_sdk/examples/negotiation-voting.lisp) | [`negotiation_flow.exs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/ex_sdk/examples/negotiation_flow.exs) | local + mock/stub |
| Handoff | [`handoff_example.py`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/handoff_example.py) | [`handoffExample.ts`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/handoffExample.ts) | [`handoff.rs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/handoff.rs) | [`handoff-example.lisp`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/cl_sdk/examples/handoff-example.lisp) | [`handoff.exs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/ex_sdk/examples/handoff.exs) | local + mock/stub |
| Workflow | [`workflow_orchestration_example.py`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/workflow_orchestration_example.py) | [`workflowExample.ts`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/workflowExample.ts) | [`workflow.rs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/workflow.rs) | [`workflow-orchestration.lisp`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/cl_sdk/examples/workflow-orchestration.lisp) | [`workflow.exs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/ex_sdk/examples/workflow.exs) | local + mock/stub |
| HITL | [`hitl_escalation_example.py`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/hitl_escalation_example.py) | [`hitlEscalation.ts`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/hitlEscalation.ts) | [`advanced_agent.rs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/advanced_agent.rs) | [`hitl-escalation.lisp`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/cl_sdk/examples/hitl-escalation.lisp) | service-backed only | local + mock |
| Voting (dedicated) | [`voting_example.py`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/voting_example.py) | [`votingExample.ts`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/votingExample.ts) | [`voting.rs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/voting.rs) | `-` | `-` | local |
| Tool execution / streaming | [`tool_streaming_example.py`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/tool_streaming_example.py) | [`toolStreamingExample.ts`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/toolStreamingExample.ts) | [`tool_streaming.rs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/tool_streaming.rs) | [`tool-streaming.lisp`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/cl_sdk/examples/tool-streaming.lisp) | [`tool_execution.exs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/ex_sdk/examples/tool_execution.exs) | local + mock/stub |
| Secrets | [`secrets_example.py`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/secrets_example.py) | [`secretsExample.ts`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/secretsExample.ts) | [`secrets.rs`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/secrets.rs) | [`secret-management.lisp`](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/cl_sdk/examples/secret-management.lisp) | `-` | local |

## 4.2. Run These First

```bash
# Python
cd sdks/py_sdk
python examples/echo_agent.py --agent-id echo-1
python examples/workflow_orchestration_example.py

# JavaScript / TypeScript
cd sdks/js_sdk
npx tsx examples/echoAgent.ts --agent-id echo-1
npx tsx examples/handoffExample.ts

# Rust
cd sdks/rust_sdk
cargo run --example echo_agent
cargo run --example workflow

# Common Lisp
cd sdks/cl_sdk
sbcl --load examples/echo-agent.lisp
sbcl --load examples/tool-streaming.lisp

# Elixir
cd sdks/ex_sdk
mix run examples/basic_agent.exs
mix run examples/handoff.exs
```

## 4.3. Notes

- Python has the broadest walkthrough coverage and is the reference bar.
- JS/TS and Rust examples are implemented, not planned, so the docs should not describe them as future work.
- Common Lisp and Elixir examples emphasize local or reference-style demos where the walkthrough is not service-backed.
- For protocol-backed APIs and SDK-specific helpers, see the client reference and SDK extensions pages.

## 4.4. Per-SDK Example Guides

- [Python example README](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/py_sdk/examples/README.md)
- [JavaScript/TypeScript example README](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/js_sdk/examples/README.md)
- [Rust example README](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/rust_sdk/examples/README.md)
- [Common Lisp example README](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/cl_sdk/examples/README.md)
- [Elixir example README](https://github.com/rahulrajaram/sw4rm/blob/master/sdks/ex_sdk/examples/README.md)
