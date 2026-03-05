# A2A Gateway for SW4RM

Expose SW4RM-managed agents via the [A2A (Agent-to-Agent) protocol](https://a2a-protocol.org/). External A2A clients see standard A2A Agent Cards and task lifecycle; internally, SW4RM handles scheduling, persistence, and negotiation.

## Architecture

```
A2A Client ──── A2A Protocol ────► A2A Gateway ──── SW4RM Protocol ────► SW4RM Services
  (any A2A       (gRPC/JSON-RPC)    (this module)    (gRPC/protobuf)     Registry 50052
   agent)                                                                 Router   50051
                                                                          Scheduler 50053
```

## Quick Start

```bash
# 1. Start SW4RM services
./quickstart.sh

# 2. Start A2A gateway
python -m a2a_gateway.server --port 50054

# 3. Get the gateway's Agent Card
curl http://localhost:50054/.well-known/agent.json
```

## Mapping

| A2A Operation | SW4RM Operation |
|---------------|----------------|
| SendMessage | Router.SendMessage + Scheduler.SubmitTask |
| GetTask | TaskStore lookup (backed by Activity Buffer) |
| CancelTask | Scheduler.RequestPreemption |
| SubscribeToTask | Router.StreamIncoming (filtered by task correlation_id) |
| GetAgentCard | Registry agent descriptors → A2A Agent Card format |

## Agent Card Generation

SW4RM agent descriptors are automatically converted to A2A Agent Cards:

| SW4RM Field | A2A Field |
|-------------|-----------|
| agent_id | name |
| description | description |
| capabilities | skills[].tags |
| modalities_supported | supportedContentTypes |
| StreamIncoming support | capabilities.streaming = true |
| Activity Buffer | capabilities.stateTransitionHistory = true |

## Status

This is an MVP implementation. Current limitations:

- In-memory task store (not persisted across gateway restarts)
- No push notification support
- No REST/JSON-RPC transport binding (gRPC only)
- No A2A authentication scheme negotiation
- Agent Card served as JSON blob, not via `.well-known/agent.json` HTTP endpoint

## Files

| File | Description |
|------|-------------|
| `a2a.proto` | A2A protocol proto3 definitions (subset for MVP) |
| `agent_card.py` | SW4RM AgentDescriptor → A2A AgentCard conversion |
| `adapter.py` | Core A2A↔SW4RM operation mapping |
| `server.py` | gRPC server entry point |
