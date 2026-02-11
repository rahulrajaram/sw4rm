# 6.19. Policy Store

The Policy Store provides in-process storage for `EffectivePolicy` snapshots.
Policies are versioned and immutable once stored, allowing you to audit changes
over time and fetch the latest policy for a negotiation or execution run.

The Policy Store is not a gRPC service; it is a local SDK utility that other
components (like negotiation rooms or schedulers) can use to persist policy
guardrails.

## 6.19.1. Core Concepts

- **Immutable snapshots**: Saving a policy creates a new version rather than
  mutating previous entries.

- **Versioned policies**: If `version` is unset (or `"1.0"` in Python/Rust),
  the store generates a `{timestamp_ms}_{uuid}` version string.

- **History**: Each policy ID maintains a chronological list of versions.

## 6.19.2. Implementations

- **InMemoryPolicyStore** (Python/Rust/JS): Fast, process-local storage.

- **JSON/JsonFilePolicyStore** (Python/Rust/JS): Persists policies to disk as
  JSON files (one file per policy ID).

Concurrency notes:

- Python stores are not thread-safe; use external synchronization.

- Rust stores are thread-safe (`RwLock`) and safe for concurrent access.

- JavaScript stores are safe for single-threaded Node runtimes; use care with
  worker threads.

## 6.19.3. Constructors

### Python

- `InMemoryPolicyStore()`
- `JSONFilePolicyStore(storage_dir: str | Path)`

### JavaScript/TypeScript

- `new InMemoryPolicyStore()`
- `new JsonFilePolicyStore(directory: string)` (call `await store.initialize()`)

### Rust

- `InMemoryPolicyStore::new()`
- `JsonFilePolicyStore::new(storage_dir: impl AsRef<Path>) -> Result<Self>`

## 6.19.4. Core Methods

### `get_policy` / `getPolicy`

- **Python**: `get_policy(policy_id: str) -> EffectivePolicy`
- **JavaScript/TypeScript**: `getPolicy(policyId: string): Promise<EffectivePolicy | null>`
- **Rust**: `get_policy(policy_id: &str) -> Result<EffectivePolicy>`

Returns the most recent policy snapshot for an ID.

### `save_policy` / `savePolicy`

- **Python**: `save_policy(policy: EffectivePolicy) -> str`
- **JavaScript/TypeScript**: `savePolicy(policy: EffectivePolicy): Promise<string>`
- **Rust**: `save_policy(policy: EffectivePolicy) -> Result<String>`

Stores a new snapshot and returns the policy ID.

### `list_policies` / `listPolicies`

- **Python**: `list_policies(prefix: str = "") -> list[str]`
- **JavaScript/TypeScript**: `listPolicies(prefix?: string): Promise<string[]>`
- **Rust**: `list_policies(prefix: &str) -> Result<Vec<String>>`

Lists policy IDs, optionally filtered by prefix.

### `get_policy_history` / `getHistory`

- **Python**: `get_policy_history(policy_id: str) -> list[EffectivePolicy]`
- **JavaScript/TypeScript**: `getHistory(policyId: string): Promise<EffectivePolicy[]>`
- **Rust**: `get_policy_history(policy_id: &str) -> Result<Vec<EffectivePolicy>>`

Returns all versions (oldest to newest).

### JavaScript/TypeScript-only helpers

- `deletePolicy(policyId: string): Promise<boolean>`
- `getProfile(name: string): Promise<PolicyProfile | null>`
- `saveProfile(profile: PolicyProfile): Promise<string>`
- `listProfiles(): Promise<string[]>`
- `createEffectivePolicy(profileName: string, agentPrefs?: Record<string, AgentPreferences>, negotiationId?: string)`

## 6.19.5. Usage Examples

=== "Python"
    ```python
    from sw4rm.policy_store import InMemoryPolicyStore, JSONFilePolicyStore
    from sw4rm.policy_types import EffectivePolicy, NegotiationPolicy

    memory_store = InMemoryPolicyStore()

    policy = EffectivePolicy(
        policy_id="review-policy",
        negotiation=NegotiationPolicy(max_rounds=8),
    )
    policy_id = memory_store.save_policy(policy)
    latest = memory_store.get_policy(policy_id)
    print(latest.negotiation.max_rounds)

    file_store = JSONFilePolicyStore("/tmp/sw4rm-policies")
    file_store.save_policy(policy)
    ```

=== "JavaScript/TypeScript"
    ```ts
    import {
      DEFAULT_ESCALATION_POLICY,
      DEFAULT_EXECUTION_POLICY,
      DEFAULT_NEGOTIATION_POLICY,
      InMemoryPolicyStore,
      JsonFilePolicyStore,
    } from '@sw4rm/js-sdk';

    const memoryStore = new InMemoryPolicyStore();
    const policyId = await memoryStore.savePolicy({
      policyId: 'review-policy',
      version: '',
      negotiation: { ...DEFAULT_NEGOTIATION_POLICY, maxRounds: 8 },
      execution: { ...DEFAULT_EXECUTION_POLICY },
      escalation: { ...DEFAULT_ESCALATION_POLICY },
    });

    const fileStore = new JsonFilePolicyStore('/tmp/sw4rm-policies');
    await fileStore.initialize();
    const latest = await memoryStore.getPolicy(policyId);
    if (latest) {
      await fileStore.savePolicy(latest);
    }
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::{EffectivePolicy, InMemoryPolicyStore, NegotiationPolicy, PolicyStore};

    let store = InMemoryPolicyStore::new();
    let policy = EffectivePolicy::new("review-policy".to_string())
        .with_negotiation(NegotiationPolicy {
            max_rounds: 8,
            ..Default::default()
        });

    let policy_id = store.save_policy(policy)?;
    let latest = store.get_policy(&policy_id)?;
    println!("{}", latest.negotiation.max_rounds);
    ```

## 6.19.6. Error Behavior

- **Python**: missing policies raise `KeyError`.

- **Rust**: missing policies return `Error::Config`.

- **JavaScript/TypeScript**: missing policies return `null` or empty arrays;
  `createEffectivePolicy` throws `PolicyStoreError` for unknown profiles.
