# SW4RM Reference Services

Complete, working implementations of the SW4RM Registry, Router, and demo Scheduler/agents across multiple languages. Use this as your starting point to run the stack locally or in Docker, and to build agents.

Choose a language to view setup and usage:

- Python: `examples/reference-services/python/README.md`
- JavaScript: `examples/reference-services/js/README.md`
- Rust: `examples/reference-services/rust/README.md`

Notes
- Default ports: Router `50051`, Registry `50052` (Scheduler may be `50053` in some examples).
- Run one language stack at a time to avoid port conflicts.
- Each language folder contains its own `start/stop` scripts and Docker configs.

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Echo Agent    │    │  Your Agent     │    │  Test Client    │
│                 │    │                 │    │                 │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          │ gRPC                 │ gRPC                 │ gRPC
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                   ┌─────────────┴─────────────┐
                   │                           │
         ┌─────────▼──────────┐    ┌──────────▼──────────┐
         │  Registry Service  │    │  Router Service     │
         │  (port 50052)      │    │  (port 50051)       │
         │                    │    │                     │
         │ • Agent Registry   │    │ • Message Routing   │
         │ • Heartbeats       │    │ • Stream Management │
         │ • Discovery        │    │ • Queue Management  │
         └────────────────────┘    └─────────────────────┘
```

## Service Features

### Registry Service Features

- **Agent Registration**: Register agents with capabilities and metadata
- **Heartbeat Monitoring**: Track agent health and automatically remove stale agents
- **Discovery**: Query registered agents and their capabilities
- **Automatic Cleanup**: Remove agents that haven't sent heartbeats (5-minute timeout)

### Router Service Features

- **Message Routing**: Route messages between agents based on agent IDs
- **Streaming**: Provide real-time message streams per agent
- **Queuing**: Buffer messages for agents with configurable queue sizes
- **Broadcasting**: Simple broadcast routing (messages sent to all agents except sender)
- **ACK Handling**: Accept and log acknowledgment messages

## Quick Start

- Pick a language and follow its README for exact commands and scripts.
  - Python: quickest path for development and demos (Scheduler + demo agents available).
  - Rust: high‑performance async services with binary targets.
  - JavaScript: Node.js/TypeScript services and demo agents.

Common patterns you’ll see in each README:
- Local start/stop scripts to run Registry and Router (and Scheduler where applicable).
- Docker Compose files under each language’s `docker/` folder.
- Demo agents and a prompter to exercise CONTROL flows (prompt/plan/run) where implemented.

## Development Notes

Extensibility ideas
- Persistence (swap in-memory maps for a DB)
- AuthZ/AuthN and TLS
- Topic/capability-based routing
- Monitoring/metrics and structured logging
- Clustering/high availability

Configuration knobs (vary by language)
- Ports and addresses via env vars
- Router queue sizes
- Registry heartbeat timeouts
- Log levels

## Troubleshooting

### Port Already in Use
```bash
# Check what's using the ports
netstat -tlnp | grep -E ":(50051|50052)"

# Kill existing processes
<use the language-specific stop script>
```

### Import Errors
```bash
# Python services prefer stubs from the SDK (sw4rm.protos).
# If you see: ModuleNotFoundError: sw4rm, install the SDK locally:
#   cd sdks/py_sdk && pip install -e .
# Docker images vendor what they need and do not require network.
```

### Connection Refused
```bash
# Check if services are running
ps aux | grep -E "(registry|router)_service"

# Check service logs
tail -f .registry.log .router.log
```

### Docker Issues
```bash
# Rebuild containers
docker-compose down --volumes
docker-compose up --build
```

## Production Considerations

⚠️ **Note**: These are minimal reference implementations for development and learning. For production use, consider:

- **Security**: Add authentication, authorization, and TLS
- **Persistence**: Use proper databases instead of in-memory storage
- **Monitoring**: Add metrics, health checks, and observability
- **Scaling**: Implement load balancing and clustering
- **Error Handling**: Add comprehensive error handling and recovery
- **Configuration**: Use environment variables and configuration files

## Contributing

When modifying these services:

1. Maintain compatibility with the SW4RM protocol specifications
2. Update tests and documentation
3. Ensure Docker setup continues to work
4. Test with multiple agents and concurrent connections

## License

These services are provided as part of the SW4RM project under the same license terms.
