# SW4RM Reference Services (Index)

Choose a language to view setup and usage:

- Python: `examples/reference-services/python/README.md`
- JavaScript: `examples/reference-services/js/README.md`
- Rust: `examples/reference-services/rust/README.md`

Ports: Router 50051, Registry 50052. Run one language at a time to avoid
conflicts.

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

## Example Usage

### 1. Start Services and Test

```bash
# Terminal 1: Start services
cd examples/reference-services/
./start_services_local.sh

# Terminal 2: Test the setup
python python/test_complete_setup.py
```

You should see:
```
🧪 Testing Complete SW4RM Setup
===============================
🔗 Connecting to router...
📤 Sending test message...
✅ Message sent successfully: Message delivered to 1 recipients
⏳ Waiting for agent to process...
🎉 Test completed successfully!

The complete setup is working:
  ✅ Registry service running (port 50052)
  ✅ Router service running (port 50051)
  ✅ Echo agent registered and receiving messages
  ✅ Message routing working end-to-end
```

### 2. Run Multiple Agents

```bash
# Terminal 3: Start echo agent
python ../examples/echo_agent.py --router localhost:50051 --registry localhost:50052

# Terminal 4: Start another agent
python ../examples/echo_agent.py --router localhost:50051 --registry localhost:50052
```

### 3. Send Messages Between Agents

```bash
# Send a message through the router
python -c "
import sys, grpc, json
sys.path.append('../sdks/py_sdk')
from sw4rm.clients.router import RouterClient
from sw4rm.envelope import build_envelope
from sw4rm import constants as C

router = RouterClient(grpc.insecure_channel('localhost:50051'))
envelope = build_envelope(
    producer_id='manual-sender',
    message_type=C.DATA,
    content_type='application/json',
    payload=json.dumps({'message': 'Hello, agents!'}).encode()
)
response = router.send_message(envelope)
print(f'Sent: {response.accepted}')
"
```

## Development and Customization

### Extending the Services

These services provide a minimal but complete implementation. You can extend them by:

1. **Adding persistence** (database storage instead of in-memory)
2. **Implementing authentication/authorization** 
3. **Adding more sophisticated routing** (topic-based, capability-based)
4. **Adding monitoring and metrics**
5. **Implementing clustering/high availability**

### Service Configuration

Both services can be configured by modifying the Python files:

- **Port numbers**: Change `listen_addr` in each service
- **Queue sizes**: Modify `maxsize` in RouterService
- **Heartbeat timeout**: Change `HEARTBEAT_TIMEOUT` in RegistryService
- **Log levels**: Modify `logging.basicConfig(level=...)`

### Adding New Services

The SW4RM protocol defines additional services (Scheduler, HITL, etc.). You can implement these following the same pattern:

1. Create a new service file (e.g., `scheduler_service.py`)
2. Implement the service interface from the protobuf definitions
3. Add to docker-compose.yml and startup scripts
4. Update documentation

## Troubleshooting

### Port Already in Use
```bash
# Check what's using the ports
netstat -tlnp | grep -E ":(50051|50052)"

# Kill existing processes
./stop_services_local.sh
```

### Import Errors
```bash
# These services prefer stubs from the SDK (sw4rm.protos).
# If you see: ModuleNotFoundError: sw4rm
# install the SDK locally in editable mode:
#   cd ../sdks/py_sdk && pip install -e .
#
# Docker images include locally generated stubs, so they work even
# without the SDK installed in the container. Local dev uses the SDK.
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
