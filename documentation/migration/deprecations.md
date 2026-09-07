# Deprecation Guide

This document tracks deprecated APIs in the SW4RM Python SDK and provides migration guides for transitioning to their replacements.

## Deprecation Policy

The SW4RM SDK follows these deprecation practices:

- **Announcement:** Deprecations are announced in minor version releases
- **Warning Period:** Deprecated APIs emit `DeprecationWarning` for at least one minor version
- **Removal:** Deprecated APIs are removed in the next major version
- **Minimum Period:** 6-month minimum between deprecation and removal
- **Documentation:** All deprecations are documented with migration guides

## Current Deprecations

| Deprecated API | Replacement | Version Deprecated | Removal Target |
|----------------|-------------|-------------------|----------------|
| `from sw4rm.handoff import HandoffClient` | `from sw4rm.clients import HandoffClient` | v0.5.0 | v1.0.0 |
| `sw4rm.acks.map_exception_to_error_code()` | `sw4rm.error_mapping.DEFAULT_MAPPER.map_exception()` | v0.5.0 | v1.0.0 |

---

## Migration: HandoffClient Import

### Background

The `HandoffClient` was originally located in `sw4rm.handoff` alongside handoff protocol types. To provide a consistent API where all clients are accessible from `sw4rm.clients`, the client has been moved.

### What actually breaks

The import path change itself is a soft deprecation (see Compatibility below), but the constructor signature changed hard: `HandoffClient(channel)` **now raises `ValueError`** for any non-`None` channel. The client has always been local-only — it keeps an in-memory store of handoff requests and never talked to a remote `HandoffService` — so passing a channel was silently ignored before and is rejected loudly now. There is no DeprecationWarning for this; the call simply fails at construction.

### Deprecated Usage

```python
# DEPRECATED - soft warning on the import, but this call raises ValueError
from sw4rm.handoff import HandoffClient

client = HandoffClient(channel)   # ValueError: HandoffClient is local-only
response = client.request_handoff(request)
```

### Recommended Usage

For **local in-memory storage** (development and testing), construct with no
arguments:

```python
# NEW - local storage, no channel
from sw4rm.clients import HandoffClient

client = HandoffClient()
response = client.request_handoff(request)
# accept_handoff / reject_handoff / complete_handoff / get_pending_handoffs
```

For a **remote handoff service**, use `ProtocolClient` and call the canonical
`HandoffService` RPCs (the handoff protos ship independently of this helper):

```python
# NEW - remote HandoffService via the canonical wire client
from sw4rm.clients import ProtocolClient
from sw4rm.protos import handoff_pb2

client = ProtocolClient(channel)
response = client.call(
    "/sw4rm.handoff.HandoffService/RequestHandoff",
    handoff_pb2.HandoffRequest(
        request_id="handoff-001",
        from_agent="agent-a",
        to_agent="agent-b",
        reason="specialist review",
    ),
)
```

### Why Changed

All SDK clients are now consolidated under `sw4rm.clients` for consistency:

```python
from sw4rm.clients import (
    RouterClient,
    RegistryClient,
    SchedulerClient,
    HandoffClient,      # Now here instead of sw4rm.handoff
    NegotiationClient,
    ToolClient,
    # ... all other clients
)
```

Because `HandoffClient` never had a real gRPC backend, the misleading
`channel` parameter was removed (rejected loudly) rather than kept as a
no-op: callers that want a remote handoff should use the canonical
`ProtocolClient`, and callers that want the lightweight local store use
`HandoffClient()`.

### Migration Steps

1. **Find usages:** Search for `from sw4rm.handoff import HandoffClient` and
   for `HandoffClient(` constructions that pass a channel.
2. **Replace the import:** Change to `from sw4rm.clients import HandoffClient`.
3. **Decide local vs remote:**
   - Local store: drop the `channel` argument.
   - Remote: replace the helper with `ProtocolClient` + the canonical
     `HandoffService` RPC (see Recommended Usage).
4. **Verify:** Re-run your tests; a surviving `HandoffClient(channel)` will
   raise `ValueError` at construction, which makes leftover call sites easy
   to find.

```bash
# Find files to update
rg "HandoffClient\(" --glob '*.py'
```

### Compatibility

The old import path continues to work but emits a warning:

```
DeprecationWarning: Importing HandoffClient from sw4rm.handoff is deprecated.
Use: from sw4rm.clients import HandoffClient
```

The old **usage** does not warn: constructing with a `channel` raises
`ValueError`, because the local-only client rejects the argument instead of
silently ignoring it.

---

## Migration: Error Code Mapping

### Background

The original `map_exception_to_error_code()` function provided a simple mapping from exceptions to error codes. The new `DictErrorCodeMapper` class provides more flexibility, including custom mappings and fallback behavior.

### Deprecated Usage

```python
# DEPRECATED
from sw4rm.acks import map_exception_to_error_code

try:
    process_message(envelope)
except Exception as exc:
    error_code = map_exception_to_error_code(exc)
    send_ack(error_code=error_code)
```

### Recommended Usage

```python
# NEW - using the default mapper
from sw4rm.error_mapping import DEFAULT_MAPPER

try:
    process_message(envelope)
except Exception as exc:
    error_code = DEFAULT_MAPPER.map_exception(exc)
    send_ack(error_code=error_code)
```

### Custom Mapping

The new system supports custom exception-to-error-code mappings:

```python
from sw4rm.error_mapping import DictErrorCodeMapper
from sw4rm import constants as C

# Define custom mappings
custom_mapper = DictErrorCodeMapper({
    MyDatabaseError: C.INTERNAL_ERROR,
    MyAuthError: C.PERMISSION_DENIED,
    MyRateLimitError: C.BUFFER_FULL,
})

# Use custom mapper
try:
    process_message(envelope)
except Exception as exc:
    error_code = custom_mapper.map_exception(exc)
```

### Combining Default and Custom Mappings

```python
from sw4rm.error_mapping import DictErrorCodeMapper, DEFAULT_MAPPER
from sw4rm import constants as C

_UNMAPPED = -1  # sentinel: not a protocol error code, signals "no match"

# Create custom mapper with fallback to default
class CombinedMapper:
    def __init__(self):
        self.custom = DictErrorCodeMapper(
            {MyCustomError: C.VALIDATION_ERROR},
            default=_UNMAPPED,
        )
        self.default = DEFAULT_MAPPER

    def map_exception(self, exc: Exception) -> int:
        # Try custom first. The sentinel default distinguishes "no match"
        # from a legitimate INTERNAL_ERROR mapping.
        code = self.custom.map_exception(exc)
        if code != _UNMAPPED:
            return code
        # Fall back to default
        return self.default.map_exception(exc)

mapper = CombinedMapper()
```

### Why Changed

The new `DictErrorCodeMapper` provides:

- **Customization:** Define your own exception-to-error mappings
- **Type Safety:** Clear protocol for error mapping
- **Composition:** Combine multiple mappers
- **Testability:** Inject custom mappers in tests

### Migration Steps

1. **Simple replacement:** Replace `map_exception_to_error_code(exc)` with `DEFAULT_MAPPER.map_exception(exc)`
2. **Add import:** Add `from sw4rm.error_mapping import DEFAULT_MAPPER`
3. **Optional customization:** Create `DictErrorCodeMapper` if you need custom mappings

---

## Detecting Deprecation Warnings

### Enable Warnings in Development

```python
import warnings

# Show all deprecation warnings
warnings.filterwarnings("default", category=DeprecationWarning, module="sw4rm")

# Or make them errors during testing
warnings.filterwarnings("error", category=DeprecationWarning, module="sw4rm")
```

### Run Tests with Warnings

```bash
# Show deprecation warnings during pytest
pytest -W default::DeprecationWarning

# Fail on deprecation warnings
pytest -W error::DeprecationWarning

# Show SW4RM-specific warnings
pytest -W default::DeprecationWarning:sw4rm
```

### CI/CD Integration

Add to your CI configuration to catch deprecations early:

```yaml
# .github/workflows/test.yml
- name: Test with deprecation warnings
  run: pytest -W error::DeprecationWarning --ignore=tests/legacy/
```

### Pre-commit Hook

```python
# scripts/check_deprecations.py
import ast
import sys

DEPRECATED_IMPORTS = [
    ("sw4rm.handoff", "HandoffClient"),
]

DEPRECATED_FUNCTIONS = [
    ("sw4rm.acks", "map_exception_to_error_code"),
]

def check_file(filepath):
    with open(filepath) as f:
        tree = ast.parse(f.read())

    issues = []
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom):
            module = node.module or ""
            for alias in node.names:
                for dep_module, dep_name in DEPRECATED_IMPORTS:
                    if module == dep_module and alias.name == dep_name:
                        issues.append(
                            f"{filepath}:{node.lineno}: "
                            f"Deprecated import: {dep_module}.{dep_name}"
                        )
        elif isinstance(node, ast.Call):
            func = node.func
            name = None
            if isinstance(func, ast.Name):
                name = func.id
            elif isinstance(func, ast.Attribute):
                name = func.attr
            if name is not None:
                for dep_module, dep_name in DEPRECATED_FUNCTIONS:
                    if name == dep_name.split(".")[-1]:
                        issues.append(
                            f"{filepath}:{node.lineno}: "
                            f"Deprecated call: {dep_module}.{dep_name}"
                        )
    return issues

if __name__ == "__main__":
    all_issues = []
    for filepath in sys.argv[1:]:
        all_issues.extend(check_file(filepath))

    for issue in all_issues:
        print(issue)

    sys.exit(1 if all_issues else 0)
```

---

## Version History

### v0.5.0

These deprecations were announced in 0.5.0 and remain deprecated in 0.6.0 and
0.7.0; see [release status](../release-status.md) for the current release
target.

**Deprecated:**

- `sw4rm.handoff.HandoffClient` - Use `sw4rm.clients.HandoffClient`
- `sw4rm.acks.map_exception_to_error_code()` - Use `sw4rm.error_mapping.DEFAULT_MAPPER`

### v1.0.0 (Planned)

**To Be Removed:**

- All v0.5.0 deprecated APIs

---

## Reporting Issues

If you encounter issues during migration:

1. Check this documentation for migration steps
2. Search [existing issues](https://github.com/rahulrajaram/sw4rm/issues)
3. Open a new issue with:
   - SW4RM version
   - Code sample showing the problem
   - Error message or unexpected behavior

## See Also

- [SDK Clients](../clients/index.md) - Current client API documentation
- [Exceptions Reference](../clients/exceptions.md) - Error handling
- [Changelog](https://github.com/rahulrajaram/sw4rm/blob/master/CHANGELOG.md) - Version history
