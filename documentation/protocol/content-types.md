# Content Type Registry

The Content Type Registry provides centralized semantic content type management for SW4RM messages. It enables agents to understand message intent and validate payloads structurally using JSON schemas.

## Overview

SW4RM uses vendor-specific content types to convey semantic meaning beyond the base media type:

```
application/vnd.sw4rm.<category>.<type>+json[;v=<version>]
```

**Examples:**

- `application/vnd.sw4rm.scheduler.seed+json;v=1` - Scheduler seed data
- `application/vnd.sw4rm.negotiation.proposal+json` - Negotiation proposal
- `application/vnd.sw4rm.intent.query+json` - Query intent message

**Source:** `sdks/py_sdk/sw4rm/content_types.py`

## Standard Content Types

The following content types are defined by the SW4RM protocol:

### Intent Types

| Constant | Content Type | Purpose |
|----------|-------------|---------|
| `INTENT_QUERY` | `application/vnd.sw4rm.intent.query+json` | Query intent messages |
| `INTENT_ACTION` | `application/vnd.sw4rm.intent.action+json` | Action intent messages |

### Context Types

| Constant | Content Type | Purpose |
|----------|-------------|---------|
| `SHARED_CONTEXT` | `application/vnd.sw4rm.shared-context+json` | Shared context payloads |

### Scheduler Types

| Constant | Content Type | Purpose |
|----------|-------------|---------|
| `SCHEDULER_SEED` | `application/vnd.sw4rm.scheduler.seed+json;v=1` | Scheduler seed data |
| `SCHEDULER_COMMAND` | `application/vnd.sw4rm.scheduler.command+json;v=1` | Scheduler commands |
| `AGENT_REPORT` | `application/vnd.sw4rm.agent.report+json;v=1` | Agent status reports |

### Negotiation Types

| Constant | Content Type | Purpose |
|----------|-------------|---------|
| `NEGOTIATION_PROPOSAL` | `application/vnd.sw4rm.negotiation.proposal+json` | Negotiation proposals |
| `NEGOTIATION_VOTE` | `application/vnd.sw4rm.negotiation.vote+json` | Negotiation votes |

### Tool Types

| Constant | Content Type | Purpose |
|----------|-------------|---------|
| `TOOL_CALL` | `application/vnd.sw4rm.tool.call+json` | Tool invocations |
| `TOOL_RESULT` | `application/vnd.sw4rm.tool.result+json` | Tool results |

## ContentTypeRegistry

The `ContentTypeRegistry` class manages content types and their associated JSON schemas:

```python
class ContentTypeRegistry:
    """Registry for managing content types and their schemas.

    Provides centralized registration of content types, JSON schema
    validation, and semantic intent extraction from content type strings.
    """

    def __init__(self) -> None:
        """Initialize an empty content type registry."""
```

### register(content_type, schema)

```python
def register(self, content_type: str, schema: Optional[dict] = None) -> None:
    """Register a content type with an optional JSON schema.

    Args:
        content_type: The content type identifier
            (e.g., 'application/vnd.sw4rm.scheduler.seed+json;v=1')
        schema: Optional JSON schema dictionary for payload validation
    """
```

Example:

```python
from sw4rm.content_types import ContentTypeRegistry

registry = ContentTypeRegistry()

# Register with schema
registry.register(
    "application/vnd.sw4rm.custom.event+json",
    {
        "type": "object",
        "properties": {
            "event_type": {"type": "string"},
            "timestamp": {"type": "string"},
            "data": {"type": "object"}
        },
        "required": ["event_type", "timestamp"]
    }
)

# Register without schema (permissive validation)
registry.register("application/vnd.sw4rm.custom.log+json")
```

### get_schema(content_type)

```python
def get_schema(self, content_type: str) -> Optional[dict]:
    """Retrieve the JSON schema for a content type.

    Args:
        content_type: The content type identifier

    Returns:
        The JSON schema dictionary if registered, None otherwise
    """
```

Example:

```python
schema = registry.get_schema("application/vnd.sw4rm.scheduler.seed+json;v=1")
if schema:
    print(f"Required fields: {schema.get('required', [])}")
```

### validate(content_type, payload)

```python
def validate(self, content_type: str, payload: bytes) -> bool:
    """Validate a payload against the registered schema for a content type.

    Performs basic JSON schema validation including:
    - Type constraints (object, array, string, number, boolean)
    - Required field checking
    - Nested property type validation

    Args:
        content_type: The content type identifier
        payload: The payload bytes to validate

    Returns:
        True if validation succeeds or no schema is registered
        False if validation fails or payload is invalid JSON
    """
```

Example:

```python
from sw4rm.content_types import ContentTypeRegistry, SCHEDULER_SEED

registry = ContentTypeRegistry()
register_standard_types(registry)

# Valid payload
valid_payload = b'{"seed": "task-123"}'
assert registry.validate(SCHEDULER_SEED, valid_payload)

# Invalid payload (missing required field)
invalid_payload = b'{"not_seed": "value"}'
assert not registry.validate(SCHEDULER_SEED, invalid_payload)

# Unregistered type (permissive)
assert registry.validate("application/json", b'{}')
```

### parse_content_type(ct)

```python
def parse_content_type(self, ct: str) -> Tuple[str, Dict[str, str]]:
    """Parse a content type string into base type and parameters.

    Extracts the base media type and any parameters like version or charset.

    Args:
        ct: The content type string
            (e.g., 'application/json;v=1;charset=utf-8')

    Returns:
        Tuple of (base_type, parameters_dict)
    """
```

Example:

```python
base, params = registry.parse_content_type(
    "application/vnd.sw4rm.scheduler.seed+json;v=1;charset=utf-8"
)
# base = "application/vnd.sw4rm.scheduler.seed+json"
# params = {"v": "1", "charset": "utf-8"}

version = params.get("v")  # "1"
```

### get_intent(content_type)

```python
def get_intent(self, content_type: str) -> Optional[str]:
    """Extract the SW4RM intent from a vendor content type.

    Analyzes the content type structure to determine semantic intent.
    For SW4RM vendor types, extracts the category.type portion.

    Args:
        content_type: The content type identifier

    Returns:
        The extracted intent string (e.g., "scheduler.seed"),
        or None if not a SW4RM vendor type
    """
```

Example:

```python
# SW4RM vendor types
intent = registry.get_intent("application/vnd.sw4rm.scheduler.seed+json;v=1")
# intent = "scheduler.seed"

intent = registry.get_intent("application/vnd.sw4rm.intent.query+json")
# intent = "intent.query"

intent = registry.get_intent("application/vnd.sw4rm.negotiation.proposal+json")
# intent = "negotiation.proposal"

# Non-SW4RM types return None
intent = registry.get_intent("application/json")
# intent = None
```

## Global Functions

### get_default_registry()

```python
def get_default_registry() -> ContentTypeRegistry:
    """Get the global default content type registry.

    Returns:
        The default ContentTypeRegistry instance (shared singleton)
    """
```

Example:

```python
from sw4rm.content_types import get_default_registry

registry = get_default_registry()
registry.register("application/vnd.sw4rm.custom.type+json", {...})
```

### register_standard_types(registry)

```python
def register_standard_types(registry: Optional[ContentTypeRegistry] = None) -> None:
    """Register all standard SW4RM content types with basic schemas.

    Registers schemas for:
    - SCHEDULER_SEED, SCHEDULER_COMMAND, AGENT_REPORT
    - NEGOTIATION_PROPOSAL, NEGOTIATION_VOTE
    - SHARED_CONTEXT
    - INTENT_QUERY, INTENT_ACTION
    - TOOL_CALL, TOOL_RESULT

    Args:
        registry: Registry to use. If None, uses the global default registry.
    """
```

Example:

```python
from sw4rm.content_types import ContentTypeRegistry, register_standard_types

# Use default registry
register_standard_types()

# Or use custom registry
my_registry = ContentTypeRegistry()
register_standard_types(my_registry)
```

## Standard Schemas

### SCHEDULER_SEED Schema

```json
{
  "type": "object",
  "properties": {
    "seed": {"type": "string"}
  },
  "required": ["seed"]
}
```

### SCHEDULER_COMMAND Schema

```json
{
  "type": "object",
  "properties": {
    "schema_version": {"type": "number"},
    "to": {"type": "string"},
    "stage": {"type": "string"},
    "params": {"type": "object"}
  },
  "required": ["to", "stage"]
}
```

### AGENT_REPORT Schema

```json
{
  "type": "object",
  "properties": {
    "schema_version": {"type": "number"},
    "stage": {"type": "string"},
    "status": {"type": "string"},
    "logs": {"type": "string"},
    "diagnostics": {"type": "object"}
  },
  "required": ["stage", "status"]
}
```

### NEGOTIATION_PROPOSAL Schema

```json
{
  "type": "object",
  "properties": {
    "artifact_type": {"type": "string"},
    "artifact_id": {"type": "string"},
    "producer_id": {"type": "string"},
    "artifact": {"type": "object"},
    "requested_critics": {"type": "array"}
  },
  "required": ["artifact_type", "artifact_id", "producer_id", "artifact"]
}
```

### NEGOTIATION_VOTE Schema

```json
{
  "type": "object",
  "properties": {
    "artifact_id": {"type": "string"},
    "critic_id": {"type": "string"},
    "score": {"type": "number"},
    "passed": {"type": "boolean"},
    "strengths": {"type": "array"},
    "weaknesses": {"type": "array"},
    "recommendations": {"type": "array"}
  },
  "required": ["artifact_id", "critic_id", "score", "passed"]
}
```

### TOOL_CALL Schema

```json
{
  "type": "object",
  "properties": {
    "tool_name": {"type": "string"},
    "arguments": {"type": "object"}
  },
  "required": ["tool_name"]
}
```

## Usage Examples

### Registering Custom Content Types

```python
from sw4rm.content_types import ContentTypeRegistry

registry = ContentTypeRegistry()

# Define a custom content type for your domain
registry.register(
    "application/vnd.sw4rm.analytics.report+json;v=1",
    {
        "type": "object",
        "properties": {
            "report_id": {"type": "string"},
            "period": {
                "type": "object",
                "properties": {
                    "start": {"type": "string"},
                    "end": {"type": "string"}
                },
                "required": ["start", "end"]
            },
            "metrics": {
                "type": "array",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "value": {"type": "number"}
                    }
                }
            }
        },
        "required": ["report_id", "period", "metrics"]
    }
)
```

### Schema Validation Workflow

```python
from sw4rm.content_types import (
    ContentTypeRegistry,
    register_standard_types,
    NEGOTIATION_PROPOSAL
)

def process_message(envelope: dict) -> None:
    registry = get_default_registry()
    register_standard_types(registry)

    content_type = envelope.get("content_type", "")
    payload = envelope.get("payload", b"")

    # Validate payload against schema
    if not registry.validate(content_type, payload):
        raise ValueError(f"Invalid payload for {content_type}")

    # Extract intent for routing
    intent = registry.get_intent(content_type)
    if intent:
        route_by_intent(intent, envelope)
    else:
        route_default(envelope)
```

### Intent Extraction for Routing

```python
from sw4rm.content_types import get_default_registry

def route_message(envelope: dict) -> str:
    """Route message based on content type intent."""
    registry = get_default_registry()

    content_type = envelope.get("content_type", "")
    intent = registry.get_intent(content_type)

    if intent is None:
        return "default_handler"

    # Route based on category
    category = intent.split(".")[0]

    routing_table = {
        "scheduler": "scheduler_handler",
        "negotiation": "negotiation_handler",
        "intent": "intent_handler",
        "tool": "tool_handler",
    }

    return routing_table.get(category, "default_handler")
```

### Version Handling

```python
from sw4rm.content_types import ContentTypeRegistry

registry = ContentTypeRegistry()

# Register multiple versions
registry.register(
    "application/vnd.sw4rm.api.response+json;v=1",
    {"type": "object", "properties": {"data": {}}}
)

registry.register(
    "application/vnd.sw4rm.api.response+json;v=2",
    {
        "type": "object",
        "properties": {
            "data": {},
            "metadata": {"type": "object"}  # v2 adds metadata
        }
    }
)

def handle_response(content_type: str, payload: bytes) -> dict:
    """Handle response with version awareness."""
    base, params = registry.parse_content_type(content_type)
    version = params.get("v", "1")

    if not registry.validate(content_type, payload):
        raise ValueError("Invalid payload")

    data = json.loads(payload)

    if version == "2":
        # Handle v2-specific metadata
        return {"data": data["data"], "metadata": data.get("metadata", {})}
    else:
        # v1 compatibility
        return {"data": data["data"], "metadata": {}}
```

## Content Type Naming Convention

When defining custom content types, follow this pattern:

```
application/vnd.sw4rm.<category>.<type>+<format>[;v=<version>][;param=value]
```

| Component | Required | Description |
|-----------|----------|-------------|
| `application` | Yes | MIME type prefix |
| `vnd.sw4rm` | Yes | Vendor namespace |
| `<category>` | Yes | Domain category (e.g., `scheduler`, `negotiation`) |
| `<type>` | Yes | Specific type (e.g., `seed`, `proposal`) |
| `+<format>` | Yes | Serialization format (usually `json`) |
| `;v=<version>` | No | Schema version number |
| `;param=value` | No | Additional parameters |

**Examples:**

- `application/vnd.sw4rm.myapp.order+json;v=1`
- `application/vnd.sw4rm.myapp.event.created+json`
- `application/vnd.sw4rm.myapp.config+json;v=2;env=prod`

## See Also

- [Messages](messages.md) - Envelope structure and content types
- [Services](services.md) - Service message formats
- [Negotiation Room](../clients/negotiation-room.md) - Uses NEGOTIATION_* types
