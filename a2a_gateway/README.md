# A2A Gateway for SW4RM

Expose SW4RM-managed agents via the [A2A (Agent-to-Agent) protocol](https://a2a-protocol.org/). External A2A clients see standard A2A Agent Cards and task lifecycle; internally, SW4RM handles scheduling, persistence, and negotiation.

## Architecture

```
A2A Client ──── A2A Protocol ────► A2A Gateway ──── SW4RM Protocol ────► SW4RM Services
  (any A2A       (HTTP/JSON-RPC)    (this module)    (gRPC/protobuf)     Registry 50052
   agent)                                                                 Router   50051
                                                                          Scheduler 50053
```

## Quick Start

### Local (Python)

```bash
# 1. Start SW4RM services
./quickstart.sh

# 2. Start A2A gateway
python -m a2a_gateway.server --port 50054 --http-port 8080

# 3. Get the gateway's Agent Card
curl http://localhost:8080/.well-known/agent.json

# 4. JSON-RPC: Get Agent Card
curl -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"GetAgentCard","params":{},"id":1}'

# 5. JSON-RPC: Send a message
curl -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"SendMessage","params":{"message":{"role":"user","parts":[{"text":{"text":"Hello"}}],"metadata":{"sw4rm.target_agent":"my-agent"}}},"id":2}'

# 6. JSON-RPC: Get task status
curl -X POST http://localhost:8080/ \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","method":"GetTask","params":{"task_id":"<task-id>"},"id":3}'
```

### Docker

```bash
docker compose up --build -d
curl http://localhost:8080/.well-known/agent.json
```

## Mapping

| A2A Operation | SW4RM Operation |
|---------------|----------------|
| SendMessage | Router.SendMessage + Scheduler.SubmitTask |
| GetTask | TaskStore lookup (in-memory or SQLite) |
| CancelTask | Scheduler.RequestPreemption |
| GetAgentCard | Registry agent descriptors → A2A Agent Card format |

## Agent Card Generation

SW4RM agent descriptors are automatically converted to A2A Agent Cards:

| SW4RM Field | A2A Field |
|-------------|-----------|
| agent_id | name |
| description | description |
| capabilities | skills[].tags |
| modalities_supported | supportedContentTypes |
| Activity Buffer | capabilities.stateTransitionHistory = true |

## Status

Current capabilities:

- HTTP server with `.well-known/agent.json` endpoint
- JSON-RPC 2.0 transport (SendMessage, GetTask, CancelTask, GetAgentCard)
- In-memory task store (default) and SQLite task store (persistent)
- Docker Compose integration with health checks
- 35+ unit tests

Current limitations:

- No SSE streaming (capabilities.streaming = false)
- No push notification support
- No A2A authentication scheme negotiation

## Files

| File | Description |
|------|-------------|
| `a2a.proto` | A2A protocol proto3 definitions (subset for MVP) |
| `agent_card.py` | SW4RM AgentDescriptor → A2A AgentCard conversion |
| `adapter.py` | Core A2A↔SW4RM operation mapping + TaskStore/SqliteTaskStore |
| `server.py` | gRPC servicer + HTTP/JSON-RPC server entry point |
| `test_adapter.py` | Unit tests for all gateway components |
| `Dockerfile` | Container image for the gateway |
| `requirements.txt` | Python dependencies |
