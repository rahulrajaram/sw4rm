# Cross-Cutting Concerns (Phase 3.6)

This document describes the cross-cutting concerns implementation in the SW4RM Python SDK, including structured logging, distributed tracing, configuration management, and feature flags.

## Overview

Phase 3.6 implements the following cross-cutting concerns:

1. **Structured Logging** (`sw4rm/logging.py`) - Consistent log format with correlation IDs
2. **Distributed Tracing** (`sw4rm/tracing.py`) - Trace context propagation across operations
3. **Configuration Management** (`sw4rm/config.py`) - Unified configuration from multiple sources
4. **Feature Flags** (`sw4rm/feature_flags.py`) - Runtime feature toggles

## Structured Logging

### Features

- Structured log format with timestamp, level, agent_id, correlation_id, message, extra fields
- JSON output format for log aggregation systems
- Standard log levels: DEBUG, INFO, WARNING, ERROR, CRITICAL
- Integration with trace context for automatic correlation ID propagation

### Usage

```python
from sw4rm import logging

# Configure global logging
logging.configure_logging(level="INFO", use_json=False)

# Get a logger
logger = logging.get_logger(__name__, agent_id="agent-42")

# Log messages with extra fields
logger.info("Agent started", version="1.0.0", environment="production")
logger.warning("High memory usage", usage_mb=1024)
logger.error("Failed to connect", exc_info=True, service="router")
```

### JSON Output

Set `use_json=True` for structured JSON logs suitable for log aggregation:

```python
logging.configure_logging(level="INFO", use_json=True)
```

Example JSON output:
```json
{
  "timestamp": "2025-12-23T20:30:00.123456+00:00",
  "level": "INFO",
  "logger": "sw4rm.agent",
  "message": "Agent started",
  "agent_id": "agent-42",
  "correlation_id": "a1b2c3d4e5f6",
  "extra": {
    "version": "1.0.0",
    "environment": "production"
  }
}
```

## Distributed Tracing

### Features

- Trace context with trace_id, span_id, parent_span_id, correlation_id
- Automatic span creation and propagation
- Context-aware tracing using contextvars
- `@traced` decorator for automatic span creation
- Integration with structured logging
- Envelope-sidecar propagation for cross-service tracing continuity

### Usage

```python
from sw4rm import tracing

# Create a root trace
trace = tracing.create_trace(metadata={"agent_id": "agent-42", "operation": "process"})

# Use trace context
with tracing.with_trace_context(trace):
    # All operations in this context are part of the trace
    logger.info("Processing started")  # Includes correlation_id

    # Create child span
    child = tracing.create_child_span(
        trace,
        metadata={"operation": "sub_task"}
    )

    with tracing.with_trace_context(child):
        logger.info("Sub-task started")  # Same correlation_id, different span

# Use decorator for automatic tracing
@tracing.traced(operation="process_message", metadata={"component": "router"})
def process_message(msg):
    # Automatically creates a span
    logger.info("Processing message")
    return msg

# Works with async functions too
@tracing.traced()
async def handle_request(request):
    await process_async_operation()

# Router client trace propagation
from sw4rm.interceptors import TracingClientInterceptor

trace = tracing.create_trace(metadata={"operation": "send_router_message"})
with tracing.with_trace_context(trace):
    interceptor = TracingClientInterceptor()
    # The interceptor injects trace headers on outbound gRPC metadata.
    # RouterClient adds trace context to envelope metadata as `_trace_context`
    # then strips it before protobuf serialization.
```

### Trace Context Structure

```python
@dataclass
class TraceContext:
    trace_id: str           # Unique ID for the entire trace
    span_id: str            # Unique ID for this span
    parent_span_id: str     # ID of parent span (or None for root)
    correlation_id: str     # For log correlation (defaults to trace_id)
    metadata: dict          # Additional metadata
```

## Configuration Management

### Features

- Centralized configuration with `SW4RMConfig` dataclass
- Multiple configuration sources (priority order):
  1. Environment variables (highest priority)
  2. Configuration files (JSON/YAML)
  3. Default values (lowest priority)
- Singleton global configuration
- Type-safe configuration access

### Configuration Fields

```python
@dataclass
class SW4RMConfig:
    router_addr: str            # Router service address
    registry_addr: str          # Registry service address
    default_timeout_ms: int     # Default timeout in milliseconds
    max_retries: int            # Maximum retry attempts
    enable_metrics: bool        # Enable metrics collection
    enable_tracing: bool        # Enable distributed tracing
    log_level: str             # Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
    feature_flags: dict        # Feature flag overrides
```

### Usage

```python
from sw4rm import config

# Load from environment only
cfg = config.load_config()

# Load from JSON file with environment overrides
cfg = config.load_config("/etc/sw4rm/config.json")

# Load from YAML file
cfg = config.load_config("/etc/sw4rm/config.yaml")

# Set as global configuration
config.set_config(cfg)

# Access global configuration
cfg = config.get_config()
print(f"Router: {cfg.router_addr}")
print(f"Timeout: {cfg.default_timeout_ms}ms")

# Programmatic configuration
custom_config = config.SW4RMConfig(
    router_addr="localhost:50051",
    enable_metrics=False,
    log_level="DEBUG"
)
config.set_config(custom_config)
```

### Environment Variables

All configuration can be overridden via environment variables:

- `SW4RM_ROUTER_ADDR` - Router service address
- `SW4RM_REGISTRY_ADDR` - Registry service address
- `SW4RM_DEFAULT_TIMEOUT_MS` - Default timeout in milliseconds
- `SW4RM_MAX_RETRIES` - Maximum retry attempts
- `SW4RM_ENABLE_METRICS` - Enable metrics (true/false)
- `SW4RM_ENABLE_TRACING` - Enable tracing (true/false)
- `SW4RM_LOG_LEVEL` - Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)

### Configuration Files

**JSON Example:**
```json
{
  "router_addr": "router.example.com:50051",
  "registry_addr": "registry.example.com:50052",
  "default_timeout_ms": 15000,
  "max_retries": 5,
  "enable_metrics": true,
  "enable_tracing": true,
  "log_level": "INFO",
  "feature_flags": {
    "ENABLE_WORKFLOW": true,
    "ENABLE_AUDIT": false
  }
}
```

**YAML Example:**
```yaml
router_addr: router.example.com:50051
registry_addr: registry.example.com:50052
default_timeout_ms: 15000
max_retries: 5
enable_metrics: true
enable_tracing: true
log_level: INFO
feature_flags:
  ENABLE_WORKFLOW: true
  ENABLE_AUDIT: false
```

## Feature Flags

### Features

- Runtime feature toggles
- Multiple flag sources (priority order):
  1. Programmatic overrides (highest priority)
  2. Environment variables (`SW4RM_FEATURE_*`)
  3. Configuration file (`feature_flags` section)
  4. Default values (lowest priority)
- Standard flags for major SDK features
- Type-safe flag access

### Standard Feature Flags

- `ENABLE_WORKFLOW` - Enable workflow orchestration
- `ENABLE_HANDOFF` - Enable agent handoff protocol
- `ENABLE_AUDIT` - Enable audit logging
- `ENABLE_VOTING` - Enable voting mechanisms

### Usage

```python
from sw4rm import feature_flags

# Get global feature flags
flags = feature_flags.get_feature_flags()

# Check if feature is enabled
if flags.is_enabled(feature_flags.FeatureFlags.ENABLE_WORKFLOW):
    # Workflow is enabled
    setup_workflow_engine()

# Get flag value with default
max_retries = flags.get_value("MAX_RETRIES", default=3)
deployment_env = flags.get_value("DEPLOYMENT_ENV", default="development")

# Programmatically set flags
flags.set_flag(feature_flags.FeatureFlags.ENABLE_AUDIT, True)
flags.set_flag("CUSTOM_FEATURE", "enabled")

# Get all flags
all_flags = flags.get_all_flags()
for name, value in all_flags.items():
    print(f"{name}: {value}")
```

### Environment Variables

Feature flags can be set via environment variables with the `SW4RM_FEATURE_` prefix:

```bash
export SW4RM_FEATURE_ENABLE_WORKFLOW=true
export SW4RM_FEATURE_ENABLE_AUDIT=false
export SW4RM_FEATURE_MAX_CONNECTIONS=100
export SW4RM_FEATURE_DEPLOYMENT_ENV=production
```

## Integration Example

Here's how all cross-cutting concerns work together:

```python
import asyncio
from sw4rm import config, feature_flags, logging, tracing

# 1. Configure logging
logging.configure_logging(level="INFO", use_json=False)

# 2. Load configuration
cfg = config.load_config("/etc/sw4rm/config.json")
config.set_config(cfg)

# 3. Get logger
logger = logging.get_logger(__name__, agent_id="agent-42")

# 4. Check feature flags
flags = feature_flags.get_feature_flags()

@tracing.traced(operation="process_request")
async def process_request(request_id: str):
    # Automatic tracing and correlation ID propagation
    logger.info("Processing request", request_id=request_id)

    # Conditional logic based on feature flags
    if flags.is_enabled(feature_flags.FeatureFlags.ENABLE_WORKFLOW):
        await run_workflow(request_id)
    else:
        await run_simple_processing(request_id)

    logger.info("Request completed", request_id=request_id)

async def main():
    # Create root trace
    trace = tracing.create_trace(metadata={"operation": "main"})

    with tracing.with_trace_context(trace):
        # All logs include correlation_id
        logger.info("Application started")

        # Process requests
        await process_request("req-123")
        await process_request("req-456")

        logger.info("Application finished")

asyncio.run(main())
```

## Testing

Run the comprehensive test suite:

```bash
pytest tests/test_cross_cutting.py -v
```

Tests cover:
- Structured logging (human-readable and JSON formats)
- Correlation ID propagation
- Trace context creation and serialization
- `@traced` decorator
- Configuration loading from files and environment
- Feature flag resolution and precedence
- Integration between all components

## Example

See `sw4rm/examples/cross_cutting_example.py` for a complete working example demonstrating all cross-cutting concerns.

Run the example:
```bash
python -m sw4rm.examples.cross_cutting_example
```

## Implementation Files

- `/home/rahul/Documents/sigagent/sdks/py_sdk/sw4rm/logging.py` - Structured logging
- `/home/rahul/Documents/sigagent/sdks/py_sdk/sw4rm/tracing.py` - Distributed tracing
- `/home/rahul/Documents/sigagent/sdks/py_sdk/sw4rm/interceptors.py` - Tracing client interceptor
- `/home/rahul/Documents/sigagent/sdks/py_sdk/sw4rm/clients/router.py` - Envelope trace propagation and cleanup
- `/home/rahul/Documents/sigagent/sdks/py_sdk/sw4rm/config.py` - Configuration management (enhanced)
- `/home/rahul/Documents/sigagent/sdks/py_sdk/sw4rm/feature_flags.py` - Feature flags
- `/home/rahul/Documents/sigagent/sdks/py_sdk/tests/test_cross_cutting.py` - Comprehensive tests
- `/home/rahul/Documents/sigagent/sdks/py_sdk/sw4rm/examples/cross_cutting_example.py` - Usage example
