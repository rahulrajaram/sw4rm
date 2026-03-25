# SW4RM Python SDK Examples

This directory contains runnable Python examples for the SW4RM SDK. Some scripts connect to live services, while others intentionally stay local or mocked so the example remains easy to run and study.

## Prerequisites

- Python 3.11+
- `make protos`
- `python -m pip install -e ".[dev]"`
- SW4RM services running for the service-backed examples

## Example Matrix

| Example | What it shows | Fidelity |
|---|---|---|
| `echo_agent.py` | Registry registration, router streaming, basic ACK flow | Service-backed |
| `test_client.py` | Message injection for exercising another agent | Service-backed utility |
| `three_id_demo.py` | Three-ID envelope model and idempotency semantics | Local demo |
| `voting_example.py` | Negotiation vote aggregation strategies | Local demo |
| `workflow_orchestration_example.py` | DAG workflow orchestration with `WorkflowEngine` | Local engine demo |
| `handoff_example.py` | Handoff lifecycle and context preservation | Local demo |
| `negotiation_debate_example.py` | Producer/critic/coordinator negotiation room flow | Local demo |
| `hitl_escalation_example.py` | HITL escalation scenarios and decision handling | Mock-backed demo |
| `tool_streaming_example.py` | Streaming tool frames and cancellation flow | Mock-backed with optional service path |
| `secrets_example.py` | Scoped secret storage, resolver precedence, backend selection | Local demo |
| `code_agent_tutorial.py` | Narrative multi-agent review swarm tutorial | Standalone tutorial |
| `CODE_AGENT_TUTORIAL.md` | Written walkthrough for the tutorial script | Companion guide |

## Quick Start

From `sdks/py_sdk`:

```bash
python examples/echo_agent.py --agent-id echo-1 --name EchoAgent
python examples/test_client.py --router localhost:50051 --target-agent advanced-1
python examples/three_id_demo.py
python examples/voting_example.py
python examples/workflow_orchestration_example.py
python examples/handoff_example.py
python examples/negotiation_debate_example.py
python examples/hitl_escalation_example.py
python examples/tool_streaming_example.py
python examples/secrets_example.py
python examples/code_agent_tutorial.py
```

## Notes

- `echo_agent.py` is the best entry point for a real service-backed agent.
- `test_client.py` is a helper for driving another agent, not a standalone agent runtime.
- The mock-backed examples are still valuable because they document the coordination flow and the public API shape without requiring extra services.
- `CODE_AGENT_TUTORIAL.md` is included because it is part of the public example surface and gives a tighter narrative walkthrough of the swarm demo.
