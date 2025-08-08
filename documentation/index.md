# SigAgent SDK

Production-ready Python SDK for building message-driven agents with persistent state, ACK lifecycle management, and worktree binding policies.

<div class="grid cards" markdown>

-   :material-rocket-launch:{ .lg .middle } **Quick Start**

    ---

    Get up and running with your first agent in 5 minutes

    [:octicons-arrow-right-24: Get Started](quickstart/)

-   :material-api:{ .lg .middle } **API Reference**

    ---

    Complete API documentation for all SDK components

    [:octicons-arrow-right-24: API Docs](https://github.com/sigagent/sigagent-sdk)

-   :material-code-braces:{ .lg .middle } **Examples**

    ---

    Comprehensive examples from basic to advanced agents

    [:octicons-arrow-right-24: View Examples](examples/)

-   :material-architecture:{ .lg .middle } **Architecture**

    ---

    Deep dive into SDK architecture and design patterns

    [:octicons-arrow-right-24: Learn More](architecture/)

</div>

## Core Features

### :material-database: **Persistent Activity Buffer**
Track all messages across restarts with automatic reconciliation. Never lose track of message state, even during network failures or agent restarts.

```python
from sigagent.activity_buffer import PersistentActivityBuffer

buffer = PersistentActivityBuffer(max_items=1000)
record = buffer.record_outgoing(envelope)
unacked = buffer.unacked()  # Messages needing attention
```

### :material-check-circle: **ACK Lifecycle Management**
Automatic acknowledgment handling integrated with router responses. Built-in error mapping and retry logic.

```python
from sigagent.ack_integration import ACKLifecycleManager

manager = ACKLifecycleManager(router, buffer, "my-agent")
result = manager.send_message_with_ack(envelope)
# Automatic ACK progression: RECEIVED → READ → FULFILLED
```

### :material-source-branch: **Worktree Management**
Policy-driven worktree binding with persistent state and custom validation hooks.

```python
from sigagent.worktree_state import PersistentWorktreeState

worktree = PersistentWorktreeState()
success = worktree.bind("repo-id", "worktree-id", {"branch": "main"})
```

### :material-message-processing: **Message Processing**
Handler-based message routing with built-in error handling and automatic ACK generation.

```python
from sigagent.ack_integration import MessageProcessor

processor = MessageProcessor(ack_manager)
processor.register_handler(MessageType.DATA, handle_data)
result = processor.process_message(envelope)  # Auto ACKs
```

## Installation

=== "Runtime Only"

    ```bash
    pip install sigagent-sdk
    ```

=== "Development"

    ```bash
    pip install -e ".[dev,docs]"
    make protos  # Generate protocol buffer stubs
    ```

=== "Documentation"

    ```bash
    pip install -e ".[docs]"
    mkdocs serve  # Start docs server
    ```

## Quick Example

Here's a minimal agent showcasing the key SDK features:

```python
import grpc
from sigagent.clients.registry import RegistryClient
from sigagent.clients.router import RouterClient
from sigagent.activity_buffer import PersistentActivityBuffer
from sigagent.ack_integration import ACKLifecycleManager, MessageProcessor
from sigagent import constants as C

# Initialize persistent components
buffer = PersistentActivityBuffer()
registry = RegistryClient(grpc.insecure_channel("localhost:50052"))
router = RouterClient(grpc.insecure_channel("localhost:50051"))

# Set up ACK lifecycle management
ack_manager = ACKLifecycleManager(router, buffer, "my-agent")
processor = MessageProcessor(ack_manager)

# Register message handler
def handle_data(envelope):
    print(f"Processing: {envelope['message_id']}")
    return "processed"

processor.register_handler(C.DATA, handle_data)

# Register agent
registry.register({
    "agent_id": "my-agent",
    "name": "My Agent", 
    "capabilities": ["processing"]
})

# Process incoming messages
for item in router.stream_incoming("my-agent"):
    envelope = convert_to_dict(item.msg)
    result = processor.process_message(envelope)  # Auto ACK handling
```

## Why SigAgent SDK?

<div class="grid cards" markdown>

-   **Production Ready**
    
    Battle-tested patterns for robust, stateful agents with comprehensive error handling

-   **Persistent by Design**
    
    Built-in persistence for activity tracking and worktree state across restarts

-   **ACK Lifecycle**
    
    Automatic acknowledgment handling with router integration and error mapping

-   **Extensible**
    
    Plugin architecture for custom persistence backends and worktree policies

-   **Developer Friendly**
    
    Rich examples, comprehensive docs, and clear APIs for rapid development

-   **Type Safe**
    
    Full type hints and protocol buffer integration for compile-time safety

</div>

## Next Steps

<div class="grid" markdown>

<div markdown>
**New to SigAgent?**

Start with our quickstart guide to build your first agent in minutes.

[Get Started :material-arrow-right:](quickstart/){ .md-button .md-button--primary }
</div>

<div markdown>
**Ready for Production?**

Check out our advanced examples and production deployment guides.

[View Examples :material-arrow-right:](examples/){ .md-button }
</div>

</div>