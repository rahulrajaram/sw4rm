# Policy Store - Phase 2.3 Implementation

## Overview

The Policy Store implementation provides a storage layer for managing `EffectivePolicy` instances in the SW4RM Python SDK. This enables policies to be treated as first-class, versioned, immutable entities that can be persisted, retrieved, and audited.

## Key Concepts

### Policy Versioning

Policies are **immutable once stored**. Each save operation creates a new versioned snapshot:

- Versions are auto-generated using format: `{timestamp_ms}_{uuid}`
- Timestamp provides chronological ordering
- UUID ensures uniqueness
- Version history is fully tracked

### Storage Backends

Two storage implementations are provided:

1. **InMemoryPolicyStore**: Fast, transient storage for testing and runtime
2. **JSONFilePolicyStore**: Persistent file-based storage with JSON serialization

Both implement the same `PolicyStore` protocol/ABC interface.

## Core API

### PolicyStore Protocol

```python
class PolicyStore(Protocol):
    def get_policy(self, policy_id: str) -> EffectivePolicy:
        """Retrieve the latest version of a policy by ID."""
        ...

    def save_policy(self, policy: EffectivePolicy) -> str:
        """Save a policy snapshot and return its policy_id."""
        ...

    def list_policies(self, prefix: str = "") -> list[str]:
        """List all policy IDs, optionally filtered by prefix."""
        ...

    def get_policy_history(self, policy_id: str) -> list[EffectivePolicy]:
        """Retrieve the complete version history for a policy."""
        ...
```

## Usage Examples

### Basic Usage with InMemoryPolicyStore

```python
from sw4rm.policy_store import InMemoryPolicyStore
from sw4rm.policy_types import EffectivePolicy, NegotiationPolicy

# Create store
store = InMemoryPolicyStore()

# Create and save a policy
policy = EffectivePolicy(
    policy_id="my_policy",
    negotiation=NegotiationPolicy(max_rounds=10)
)
policy_id = store.save_policy(policy)

# Retrieve the policy
retrieved = store.get_policy("my_policy")
print(f"Max rounds: {retrieved.negotiation.max_rounds}")
```

### Persistent Storage with JSONFilePolicyStore

```python
from sw4rm.policy_store import JSONFilePolicyStore
from sw4rm.policy_types import EffectivePolicy, NegotiationPolicy

# Create store with persistent directory
store = JSONFilePolicyStore("/path/to/policies")

# Policies are saved to disk as JSON files
policy = EffectivePolicy(
    policy_id="persistent_policy",
    negotiation=NegotiationPolicy(max_rounds=15)
)
store.save_policy(policy)

# Retrieve in a different process/session
store2 = JSONFilePolicyStore("/path/to/policies")
retrieved = store2.get_policy("persistent_policy")
```

### Policy Versioning and History

```python
from sw4rm.policy_store import InMemoryPolicyStore
from sw4rm.policy_types import EffectivePolicy, NegotiationPolicy

store = InMemoryPolicyStore()

# Save multiple versions of the same policy
for max_rounds in [5, 10, 15]:
    policy = EffectivePolicy(
        policy_id="evolving_policy",
        negotiation=NegotiationPolicy(max_rounds=max_rounds)
    )
    store.save_policy(policy)

# Get latest version
latest = store.get_policy("evolving_policy")
print(f"Latest max_rounds: {latest.negotiation.max_rounds}")  # 15

# Get full history
history = store.get_policy_history("evolving_policy")
print(f"Total versions: {len(history)}")  # 3

# Each version has a unique version ID
for version in history:
    print(f"Version {version.version}: max_rounds={version.negotiation.max_rounds}")
```

### Using Policies with Envelopes

```python
from sw4rm.policy_store import InMemoryPolicyStore
from sw4rm.policy_types import EffectivePolicy, NegotiationPolicy
from sw4rm.envelope import build_envelope

# Create and store policy
store = InMemoryPolicyStore()
policy = EffectivePolicy(
    policy_id="negotiation_policy_v1",
    negotiation=NegotiationPolicy(max_rounds=10)
)
policy_id = store.save_policy(policy)

# Attach policy to envelope
envelope = build_envelope(
    producer_id="agent_001",
    message_type=100,
    payload=b'{"task": "code_review"}',
    effective_policy_id=policy_id  # Policy reference
)

# Recipient retrieves policy from envelope
if envelope["effective_policy_id"]:
    policy = store.get_policy(envelope["effective_policy_id"])
    # Use policy to govern negotiation/execution
```

### Organizing Policies with Prefixes

```python
from sw4rm.policy_store import InMemoryPolicyStore
from sw4rm.policy_types import EffectivePolicy, NegotiationPolicy

store = InMemoryPolicyStore()

# Save policies with environment prefixes
store.save_policy(EffectivePolicy(
    policy_id="prod_critical_tasks",
    negotiation=NegotiationPolicy(max_rounds=20)
))

store.save_policy(EffectivePolicy(
    policy_id="dev_testing",
    negotiation=NegotiationPolicy(max_rounds=5)
))

# Filter by prefix
prod_policies = store.list_policies(prefix="prod_")
dev_policies = store.list_policies(prefix="dev_")
all_policies = store.list_policies()
```

## Integration with Envelope

The `build_envelope()` function now accepts an `effective_policy_id` parameter:

```python
def build_envelope(
    *,
    producer_id: str,
    message_type: int,
    effective_policy_id: Optional[str] = None,
    # ... other parameters
) -> dict:
    """Build a message envelope with Three-ID model support.

    Args:
        effective_policy_id: ID of the effective policy governing this operation.
            Should be attached when:
            - Initiating a negotiation (policy governs negotiation behavior)
            - Submitting tasks for execution (policy governs execution constraints)
            - When policy context is required for processing/auditing
    """
```

### When to Attach Policies to Envelopes

1. **Initiating negotiations**: Attach the policy that governs negotiation parameters
2. **Submitting tasks**: Attach the policy that defines execution constraints
3. **Audit requirements**: Attach policy when governance/compliance tracking is needed
4. **Multi-agent coordination**: Share policy context between agents

## JSON File Storage Format

Policies are stored in individual JSON files named `{policy_id}.json`:

```json
{
  "policy_id": "my_policy",
  "versions": [
    {
      "policy_id": "my_policy",
      "version": "1734989123456_a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "negotiation": {
        "max_rounds": 10,
        "score_threshold": 0.8,
        ...
      },
      "execution": {
        "timeout_ms": 60000,
        ...
      },
      "escalation": {
        "auto_escalate_on_deadlock": true,
        ...
      }
    },
    {
      "policy_id": "my_policy",
      "version": "1734989234567_b2c3d4e5-f6a7-8901-bcde-f23456789012",
      "negotiation": {
        "max_rounds": 15,
        ...
      },
      ...
    }
  ]
}
```

## Implementation Details

### Version Generation

```python
def generate_policy_version() -> str:
    """Generate a unique version identifier for a policy.

    Returns:
        A version string in the format: {timestamp_ms}_{uuid}
    """
    timestamp_ms = int(time.time() * 1000)
    unique_id = str(uuid.uuid4())
    return f"{timestamp_ms}_{unique_id}"
```

### Immutability Guarantees

Policies are deep-copied during storage to ensure immutability:

```python
# Create a snapshot by converting to/from dict (ensures immutability)
snapshot = EffectivePolicy.from_dict(policy.to_dict())
```

Modifying the original policy after saving does not affect the stored version.

### Thread Safety

**Important**: Neither `InMemoryPolicyStore` nor `JSONFilePolicyStore` are thread-safe by default. Use external synchronization (locks, queues) if accessing from multiple threads.

## Testing

Comprehensive tests are provided in `tests/test_policy_store.py`:

- Policy CRUD operations
- Version generation and uniqueness
- History tracking
- Persistence across store instances
- Prefix filtering
- Immutability guarantees
- Complex policy roundtrip
- Consistency between store implementations

Run tests:

```bash
pytest tests/test_policy_store.py -v
```

## Files Created

### Implementation

- `/home/rahul/Documents/sigagent/sdks/py_sdk/sw4rm/policy_store.py`
  - `PolicyStore` protocol
  - `PolicyStoreABC` abstract base class
  - `InMemoryPolicyStore` implementation
  - `JSONFilePolicyStore` implementation
  - `generate_policy_version()` utility

### Tests

- `/home/rahul/Documents/sigagent/sdks/py_sdk/tests/test_policy_store.py`
  - 27 comprehensive tests
  - Coverage for all store operations
  - Comparison tests between implementations

### Examples

- `/home/rahul/Documents/sigagent/sdks/py_sdk/sw4rm/examples/policy_store_example.py`
  - In-memory store usage
  - JSON file store usage
  - Policy versioning
  - Envelope integration
  - Prefix filtering

### Updates

- `/home/rahul/Documents/sigagent/sdks/py_sdk/sw4rm/envelope.py`
  - Added `effective_policy_id` parameter to `build_envelope()`
  - Updated documentation

## Design Decisions

### Why Two Storage Backends?

1. **InMemoryPolicyStore**: Fast, lightweight, perfect for testing and short-lived processes
2. **JSONFilePolicyStore**: Persistent, human-readable, suitable for production deployments

### Why Protocol + ABC?

- **Protocol**: Enables structural subtyping (duck typing)
- **ABC**: Provides inheritance-based interface for those who prefer it
- Both approaches are supported for maximum flexibility

### Why Timestamp + UUID for Versions?

- **Timestamp**: Provides chronological ordering for history
- **UUID**: Ensures global uniqueness even across distributed systems
- Combined: Best of both worlds

### Why Immutable Snapshots?

- **Auditability**: Historical policies remain unchanged for compliance
- **Reproducibility**: Can replay negotiations with exact policy used
- **Debugging**: Clear snapshot of policy state at any point in time

## Future Enhancements

Potential future additions:

1. **Remote storage backends**: Redis, PostgreSQL, S3
2. **Policy diffing**: Compare versions to see what changed
3. **Policy validation**: Schema validation before save
4. **Policy migration**: Upgrade old policies to new formats
5. **Policy search**: Query policies by criteria beyond ID/prefix
6. **Concurrent access**: Add locking/transactions for multi-process safety

## See Also

- `sw4rm/policy_types.py` - Policy dataclasses
- `sw4rm/envelope.py` - Envelope construction
- `tests/test_policy_store.py` - Comprehensive tests
- `sw4rm/examples/policy_store_example.py` - Usage examples
