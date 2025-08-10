# 4. Examples

Comprehensive examples showing SW4RM SDK usage from basic to advanced patterns.

## 4.1. Available Examples

<div class="grid cards" markdown>

-   :material-echo:{ .lg .middle } **Echo Agent**

    ---

    Simple agent demonstrating registration and message echoing

    [:octicons-arrow-right-24: View Code](echo-agent.md)

-   :material-robot:{ .lg .middle } **Advanced Agent**

    ---

    Full-featured agent with persistence, worktree management, and ACK lifecycle

    [:octicons-arrow-right-24: View Code](advanced-agent.md)

-   :material-test-tube:{ .lg .middle } **Test Client**

    ---

    Client for testing agent functionality with various message types

    [:octicons-arrow-right-24: View Code](test-client.md)

</div>

## 4.2. Running the Examples

All examples are located in the `examples/` directory:

```bash
# Basic echo agent
python examples/echo_agent.py --agent-id echo-1

# Advanced agent with persistence  
python examples/advanced_agent.py --data-dir ./agent_data

# Test client
python examples/test_client.py --target-agent advanced-1
```

See individual example pages for detailed usage instructions.