# 6.20. Shared Context Manager

The Shared Context Manager is a lightweight, in-process utility for sharing
mutable state between agents. It stores contexts in memory, uses optimistic
locking via version strings, and provides an explicit lock flag to temporarily
block updates during critical sections.

Use it when you need:

- A process-local store for shared coordination state.
- Version-checked updates to detect conflicts.
- A simple lock flag to pause updates while work is in progress.

## 6.20.1. Data Model

### SharedContext

Each context is represented by a `SharedContext` dataclass.

| Field | Type | Description |
| --- | --- | --- |
| `context_id` | `str` | Unique identifier for the context. |
| `version` | `str` | Optimistic lock version, incremented on update. |
| `data` | `dict` | Context payload (stored as a shallow copy). |
| `locked_by` | `Optional[str]` | Agent ID holding the lock, if any. |
| `created_at` | `datetime` | UTC timestamp for creation. |
| `updated_at` | `datetime` | UTC timestamp of last update. |

Use `SharedContext.to_dict()` to serialize for JSON payloads and
`SharedContext.from_dict()` to reconstruct from stored data.

## 6.20.2. Constructor

### Python

`SharedContextManager()`

## 6.20.3. Core Methods

### `create`

`create(context_id: str, initial_data: dict) -> SharedContext`

Creates a new context with version `"1"` and copies the initial data.
Raises `ValueError` if the context ID already exists.

### `get`

`get(context_id: str) -> SharedContext | None`

Returns the context or `None` if it does not exist.

### `update`

`update(context_id: str, data: dict, expected_version: str) -> SharedContext`

Replaces the stored data, increments the version, and updates `updated_at`.
Raises `ValueError` if the context is missing, locked, or the version does
not match `expected_version`.

### `lock`

`lock(context_id: str, agent_id: str) -> bool`

Sets `locked_by` for the context. Returns `True` if the lock is acquired or
already held by the same agent. Returns `False` if another agent holds the lock.

### `unlock`

`unlock(context_id: str, agent_id: str) -> bool`

Clears the lock if held by `agent_id`. Returns `False` if the lock is held by
another agent or not set.

### `delete`

`delete(context_id: str) -> bool`

Deletes the context and returns `True` if it existed.

### `list_contexts`

`list_contexts() -> list[str]`

Lists all context IDs.

### `clear`

`clear() -> None`

Removes all contexts from the manager.

## 6.20.4. Usage Examples

=== "Python"
    ```python
    from sw4rm.shared_context import SharedContextManager

    manager = SharedContextManager()
    ctx = manager.create("workflow-1", {"step": 1, "status": "running"})

    ctx = manager.update("workflow-1", {"step": 2, "status": "running"}, ctx.version)
    print(ctx.version)

    try:
        manager.update("workflow-1", {"step": 3}, "1")
    except ValueError as exc:
        print(f"Conflict: {exc}")
    ```

=== "Python (Locking)"
    ```python
    from sw4rm.shared_context import SharedContextManager

    manager = SharedContextManager()
    manager.create("resource-1", {"count": 0})

    if manager.lock("resource-1", "agent-a"):
        # Perform work while updates are blocked.
        manager.unlock("resource-1", "agent-a")

    ctx = manager.get("resource-1")
    ctx = manager.update("resource-1", {"count": 1}, ctx.version)
    ```

## 6.20.5. Error Handling

`SharedContextManager` raises `ValueError` when:

- Creating a duplicate context ID.
- Updating, locking, or unlocking a missing context.
- Updating a locked context.
- Updating with a stale version.

## 6.20.6. Notes

- The manager is in-memory and process-local; it is not a distributed store.
- Locks are cooperative flags and do not include TTL or deadlock recovery.
- No thread synchronization is provided; wrap access if you need thread safety.
