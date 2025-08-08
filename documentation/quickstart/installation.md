# Installation

Get the SigAgent SDK installed and configured for development.

## Install the SDK

=== "Development Setup (Recommended)"

    For development work with examples and code generation:

    ```bash
    # Clone or navigate to the SigAgent SDK directory
    cd /path/to/sigagent-sdk

    # Install with all dependencies
    pip install -e ".[dev,docs]"

    # Generate protocol buffer stubs
    make protos
    ```

=== "Runtime Only"

    For production deployments:

    ```bash
    pip install sigagent-sdk
    ```

=== "From Source"

    To install from source:

    ```bash
    git clone https://github.com/sigagent/sigagent-sdk.git
    cd sigagent-sdk
    pip install -e ".[dev]"
    make protos
    ```

## Verify Installation

Test that everything is working:

```python
# Test basic imports
python -c "import sigagent; print('✅ SDK installed successfully')"

# Test protobuf stubs
python -c "from sigagent.protos import common_pb2; print('✅ Protocol stubs generated')"

# Test all components
python -c """
from sigagent.activity_buffer import PersistentActivityBuffer
from sigagent.worktree_state import PersistentWorktreeState  
from sigagent.ack_integration import ACKLifecycleManager
print('✅ All components available')
"""
```

## Protocol Buffer Generation

The SDK uses protocol buffers for message serialization. Generate the Python stubs:

```bash
# Generate stubs (requires grpcio-tools)
make protos

# Verify generation
ls py_sdk/sigagent/protos/
# Should show: common_pb2.py, router_pb2.py, etc.
```

!!! note "Automatic Generation"
    The `make protos` command automatically:
    
    - Generates Python stubs from `.proto` files
    - Fixes relative imports for proper package structure
    - Creates type hint files (`.pyi`) for better IDE support

## Directory Structure

After installation, your project should look like:

```
sigagent-sdk/
├── py_sdk/
│   └── sigagent/
│       ├── __init__.py
│       ├── activity_buffer.py
│       ├── ack_integration.py
│       ├── clients/
│       ├── protos/           # Generated files
│       └── ...
├── examples/
│   ├── advanced_agent.py
│   ├── echo_agent.py
│   └── test_client.py
├── documentation/
└── mkdocs.yml
```

## Development Dependencies

The SDK includes several optional dependency groups:

=== "Development"

    ```bash
    pip install -e ".[dev]"
    ```

    Includes:
    - `grpcio-tools` - Protocol buffer compiler
    - Code generation utilities

=== "Documentation"

    ```bash
    pip install -e ".[docs]"  
    ```

    Includes:
    - `mkdocs-material` - Documentation theme
    - `mkdocstrings` - API documentation generator
    - Documentation build tools

=== "All Dependencies"

    ```bash
    pip install -e ".[dev,docs]"
    ```

## Runtime Requirements

The SDK has minimal runtime dependencies:

- **Python 3.9+** 
- **protobuf** `>=4.23,<5` - Message serialization
- **grpcio** `>=1.56,<2` - gRPC communication  
- **googleapis-common-protos** `>=1.60,<2` - Well-known types

## Common Issues

### Missing Protocol Stubs

**Error:** `ModuleNotFoundError: No module named 'sigagent.protos'`

**Solution:**
```bash
make protos
```

### grpcio-tools Missing

**Error:** `make: grpcio-tools: command not found`

**Solution:**
```bash
pip install grpcio-tools
# or
pip install -e ".[dev]"
```

### Permission Errors

**Error:** `Permission denied` when running `make protos`

**Solution:**
```bash
# Ensure write access to output directory
chmod 755 py_sdk/sigagent/
mkdir -p py_sdk/sigagent/protos
```

### Import Errors

**Error:** `ImportError: attempted relative import with no known parent package`

**Solution:**
```bash
# Install in development mode
pip install -e .

# Or add to PYTHONPATH
export PYTHONPATH="${PYTHONPATH}:$(pwd)/py_sdk"
```

## Next Steps

Now that you have the SDK installed:

1. **[Create Your First Agent](first-agent.md)** - Build a basic message-processing agent
2. **[View Examples](../examples/)** - See working agents in action
3. **[API Reference](../reference/)** - Explore all available components

Ready to build your first agent? Let's go! 🚀