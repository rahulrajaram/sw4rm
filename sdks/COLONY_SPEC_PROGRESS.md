# SW4RM Colony: Plugins & Ecosystem Extras

The "Colony" encompasses optional extensions, deployment tooling, and ecosystem integrations that build on the core SW4RM protocol. These are not part of the normative specification but enhance production deployments and developer experience.

## Current Version: v0.1.0

---

## Completed

### Storage Backends

1. **JSONFileNegotiationRoomStore moved from core to colony**
   - Python: `colony/stores/python/json_file_store.py`
   - Rust: `colony/stores/rust/json_file_store.rs`
   - TypeScript: `colony/stores/typescript/jsonFileStore.ts`
   - **Status:** Complete
   - **Note:** This store has known limitations (no file locking, race conditions) - see hardening TODO below

---

## TODO List

### Storage Backends

1. **Redis Store Implementation**
   - Implement `RedisNegotiationRoomStore`
   - Enables horizontal scaling with multiple server replicas
   - Current in-memory stores are process-bound
   - **Status:** Not started
   - **Priority:** High (required for production HA)

2. **PostgreSQL/SQL Store Implementation**
   - Alternative to Redis for teams preferring SQL
   - Provides durability and queryability
   - **Status:** Not started
   - **Priority:** Medium

3. **Harden JSONFileStore**
   - Add atomic writes (write to temp file, then rename)
   - Add file locking for concurrent access
   - Add crash recovery mechanisms
   - Document limitations for production use
   - **Status:** Not started
   - **Priority:** Medium (current implementation has race condition risks)

### Deployment & Packaging

4. **Dockerization**
   - Create Dockerfile for coordination server
   - Options: Rust binary (performance) or Python (ease of modification)
   - Add docker-compose for local development
   - **Status:** Not started
   - **Priority:** High

5. **Helm Charts**
   - Kubernetes deployment charts
   - Configurable replicas, resources, persistence
   - **Status:** Not started
   - **Priority:** Low

6. **Production Packaging**
   - Move servers from `reference-services` to formal packages
   - Consider `sw4rm-server` package naming
   - Add proper CLI with configuration options
   - **Status:** Not started
   - **Priority:** Medium (current "reference" naming implies non-production)

### Quality & Testing

7. **Cross-Language Integration Tests**
   - Create tests that run client in one SDK against server in another
   - Example: Python client → Rust server → JS client verification
   - Validates interoperability beyond proto compatibility
   - **Status:** Not started
   - **Priority:** High

8. **Runnable Examples in CI**
   - Ensure all SDK examples compile and run in CI
   - Add smoke tests for example code
   - **Status:** Not started
   - **Priority:** Low (prevents example staleness)

### Project Governance

9. **Release Cadence Planning**
   - Define versioning policy aligned with proto evolution
   - Plan deprecation timeline for old import paths
   - Target v1.0.0 for removing deprecated paths
   - **Status:** Not started
   - **Priority:** Low

---

## Completed Items

*None yet*

---

## Architecture Notes

### Store Plugin Interface

All store backends implement the same interface, allowing swappable deployment configurations:

```python
# Python
class NegotiationRoomStore(Protocol):
    def get_room(self, room_id: str) -> Optional[Room]: ...
    def save_room(self, room: Room) -> None: ...
    def add_participant(self, room_id: str, participant: Participant) -> None: ...
    # ... etc
```

```rust
// Rust
pub trait NegotiationRoomStore: Send + Sync {
    fn get_room(&self, room_id: &str) -> Option<Room>;
    fn save_room(&self, room: Room);
    fn add_participant(&self, room_id: &str, participant: Participant);
    // ... etc
}
```

```typescript
// TypeScript
interface NegotiationRoomStore {
    getRoom(roomId: string): Room | undefined;
    saveRoom(room: Room): void;
    addParticipant(roomId: string, participant: Participant): void;
    // ... etc
}
```

### Bundled vs. External

| Store | Location | Notes |
|-------|----------|-------|
| `InMemoryStore` | Core SDKs | Required for testing/dev, always available |
| `JSONFileStore` | Core SDKs | Simple persistence, not production-grade |
| `RedisStore` | Colony | Optional dependency, production-grade |
| `PostgresStore` | Colony | Optional dependency, production-grade |

---

## Future Considerations

- **Observability plugins**: OpenTelemetry exporters, Prometheus metrics
- **Auth plugins**: OAuth2, mTLS, API key validation
- **Rate limiting**: Token bucket, sliding window implementations
- **Service mesh integration**: Istio, Linkerd sidecars

---

*Last updated: 2026-01-10 | Version: 0.1.0*
