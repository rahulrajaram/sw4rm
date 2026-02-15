# 6.22. SDK Extensions Reference

> **Version**: 0.5.0 | **Last updated**: 2026-02-15

SDK extensions provide developer-convenience features that go beyond the normative
protocol specification. These are NOT part of the core protocol; conformant SDKs
are NOT REQUIRED to implement them. See
[sdk_extensions.md](../protocol/sdk_extensions.md) for the canonical extension
catalog.

## 6.22.1. Secret Management

**SDKs**: Python, JS/TS, Rust

Pluggable secret storage backends for managing API keys, tokens, and credentials
used by agents. Local-only concern not specified in the protocol.

### Backend Interface

All SDKs implement the same `SecretsBackend` interface:

| Method | Signature | Description |
|--------|-----------|-------------|
| `set` | `(scope, key, value) -> void` | Store a secret |
| `get` | `(scope, key) -> string` | Retrieve a secret |
| `list` | `(scope?) -> map` | List secrets, optionally filtered by scope |

### Backends

| Backend | Description | SDKs |
|---------|-------------|------|
| `FileBackend` | JSON file storage (`~/.config/sw4rm/secrets.json` on Linux) | Python, Rust, JS/TS |
| `KeyringBackend` | OS keyring integration (`keyring` / `keytar`) | Python, Rust, JS/TS |

### Types

- **Scope**: Global (`None`/`null`) or named scope for secret isolation.
- **SecretKey**: Dotted-format string (e.g., `openai.api_key`). Validated on construction.
- **SecretValue**: String value, maximum 8 KB.
- **SecretSource** (enum): `CLI`, `ENV`, `SCOPED`, `GLOBAL` — indicates provenance.

### Resolution Order

The `Resolver` resolves secrets with the following precedence:

1. Explicit value (passed programmatically)
2. Environment variable (e.g., `SW4RM_SECRET_OPENAI_API_KEY`)
3. Scoped secret (from backend)
4. Global secret (from backend)

### Factory

`select_backend(mode?)` auto-selects the best backend:

- **auto** (default): Prefers keyring if available, falls back to file.
- **file**: Force JSON file backend.
- **keyring**: Force OS keyring backend.

Override via environment variable: `SW4RM_SECRETS_BACKEND`.

=== "Python"
    ```python
    from sw4rm.secrets import Secrets, Scope, SecretKey, SecretValue

    secrets = Secrets()  # auto-selects backend
    secrets.set(Scope("myproject"), SecretKey("openai.api_key"), SecretValue("sk-..."))
    value = secrets.get(Scope("myproject"), SecretKey("openai.api_key"))
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::secrets::{Secrets, Scope, SecretKey, SecretValue};

    let secrets = Secrets::new(None)?;  // auto-selects backend
    secrets.set(&Scope::new("myproject"), &SecretKey::new("openai.api_key"), &SecretValue::new("sk-...")?)?;
    let value = secrets.get(&Scope::new("myproject"), &SecretKey::new("openai.api_key"))?;
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { Secrets, Scope, SecretKey, SecretValue } from '@sw4rm/js-sdk';

    const secrets = await Secrets.create();  // auto-selects backend
    await secrets.set(new Scope('myproject'), new SecretKey('openai.api_key'), new SecretValue('sk-...'));
    const value = await secrets.get(new Scope('myproject'), new SecretKey('openai.api_key'));
    ```

---

## 6.22.2. Negotiation Room Store

**SDKs**: Python, JS/TS, Rust

Local persistent storage for negotiation room state. The spec defines the
negotiation protocol (§17.5) but does not prescribe local state management.
See [Negotiation Room Client](negotiation-room.md) for usage.

### Store Interface

| Method | Description |
|--------|-------------|
| `has_proposal(artifact_id)` | Check if proposal exists |
| `get_proposal(artifact_id)` | Retrieve a proposal |
| `save_proposal(proposal)` | Store a proposal (raises on duplicate) |
| `list_proposals(room_id?)` | List proposals, optionally filtered by room |
| `get_votes(artifact_id)` | Get all votes for a proposal |
| `add_vote(vote)` | Add a critic vote (raises on duplicate critic) |
| `get_decision(artifact_id)` | Get the decision for a proposal |
| `save_decision(decision)` | Store a decision (raises on duplicate) |

### Implementations

| Store | Description | SDKs |
|-------|-------------|------|
| `InMemoryNegotiationRoomStore` | Thread-safe in-process store (default) | Python, Rust, JS/TS |
| `JSONFileNegotiationRoomStore` | JSON file-backed persistence | Python (colony module) |

---

## 6.22.3. Negotiation Coordinator

**SDK**: Python only

Policy-based decision coordination for multi-agent negotiation. Provides
automated scoring, threshold-based auto-approval, and coordinator-role
orchestration on top of the spec's Negotiation Room pattern (§17.5).

### Key Methods

| Method | Description |
|--------|-------------|
| `apply_policy(scores, policy)` | Evaluate scores against policy thresholds. Returns `APPROVED`, `REVISION_REQUESTED`, or `ESCALATED_TO_HITL`. |
| `should_auto_approve(score, policy)` | Check if score meets auto-approve threshold. |
| `should_escalate(votes, policy)` | Check for escalation triggers: failed votes, high variance, low confidence. |
| `generate_decision_reason(outcome, scores, votes, policy)` | Generate human-readable explanation. |

```python
from sw4rm.negotiation_coordinator import NegotiationCoordinator

coordinator = NegotiationCoordinator()
outcome = coordinator.apply_policy(aggregated_scores, policy)
reason = coordinator.generate_decision_reason(outcome, aggregated_scores, votes, policy)
```

---

## 6.22.4. Shared Context Manager

**SDK**: Python only

Optimistic-locking shared context store for concurrent agent access. Not part
of the protocol; agents communicate shared state via messages per spec. See
[Shared Context Manager Client](shared-context.md) for the full API reference.

### Key Features

- **Optimistic locking**: `update()` requires `expected_version`; raises `ValueError` on conflict.
- **Explicit locking**: `lock(context_id, agent_id)` blocks updates from other agents.
- **Version tracking**: Versions auto-increment on each update.

---

## 6.22.5. Feature Flags

**SDK**: Python only

Runtime feature flag system for SDK behavior toggles. Allows enabling/disabling
experimental features without code changes.

### Built-in Flags

| Flag | Purpose |
|------|---------|
| `ENABLE_WORKFLOW` | Enable workflow orchestration |
| `ENABLE_HANDOFF` | Enable agent handoff |
| `ENABLE_AUDIT` | Enable audit trail generation |
| `ENABLE_VOTING` | Enable negotiation voting |

### Resolution Order

1. Programmatic overrides (`set_flag()`)
2. Environment variables (`SW4RM_FEATURE_*`, e.g., `SW4RM_FEATURE_ENABLE_WORKFLOW=true`)
3. Config dictionary (passed at construction)
4. Default value

```python
from sw4rm.feature_flags import get_feature_flags

flags = get_feature_flags()
if flags.is_enabled("ENABLE_WORKFLOW"):
    # workflow-specific logic
    pass

flags.set_flag("ENABLE_AUDIT", True)
```

---

## 6.22.6. Content Types

**SDK**: Python only

Vendor-specific MIME type constants (`application/vnd.sw4rm.*`) extending the
spec-required `application/json` and `application/protobuf` support. See
[Content Types](../protocol/content-types.md) for the protocol-level reference.

### Vendor Content Types

| Constant | MIME Type |
|----------|-----------|
| `INTENT_QUERY` | `application/vnd.sw4rm.intent.query+json` |
| `INTENT_ACTION` | `application/vnd.sw4rm.intent.action+json` |
| `SHARED_CONTEXT` | `application/vnd.sw4rm.shared-context+json` |
| `SCHEDULER_SEED` | `application/vnd.sw4rm.scheduler.seed+json;v=1` |
| `SCHEDULER_COMMAND` | `application/vnd.sw4rm.scheduler.command+json;v=1` |
| `AGENT_REPORT` | `application/vnd.sw4rm.agent.report+json;v=1` |
| `NEGOTIATION_PROPOSAL` | `application/vnd.sw4rm.negotiation.proposal+json` |
| `NEGOTIATION_VOTE` | `application/vnd.sw4rm.negotiation.vote+json` |
| `TOOL_CALL` | `application/vnd.sw4rm.tool.call+json` |
| `TOOL_RESULT` | `application/vnd.sw4rm.tool.result+json` |

### Content Type Registry

The `ContentTypeRegistry` provides registration, schema validation, and parsing:

```python
from sw4rm.content_types import get_default_registry, register_standard_types

registry = get_default_registry()
register_standard_types(registry)

# Register custom type
registry.register("application/vnd.myapp.data+json", schema={"type": "object"})
valid = registry.validate("application/vnd.myapp.data+json", payload)
```

---

## 6.22.7. Preemption Manager

**SDK**: Rust only

Cooperative agent preemption with cancellation tokens and safe-point checking.
The spec defines preemption semantics (RUNNING → SUSPENDED, §8) but does not
prescribe the cooperative implementation pattern.

### Key API

| Method | Description |
|--------|-------------|
| `new()` | Create a new `PreemptionManager` (Clone-able for sharing across tasks). |
| `is_preemption_requested()` | Check if preemption was requested. |
| `request_preemption(reason)` | Signal that preemption is needed. |
| `set_deadline(deadline_ms)` | Set a preemption deadline. |
| `clear_preemption()` | Clear the preemption request. |
| `preemption_reason()` | Get the reason string, if any. |
| `non_preemptible()` | Acquire an RAII guard that temporarily disables preemption. |

```rust
use sw4rm_sdk::runtime::PreemptionManager;

let pm = PreemptionManager::new();
let pm_clone = pm.clone(); // share with spawned task

// In agent processing loop:
loop {
    if pm.is_preemption_requested() {
        println!("Preempted: {:?}", pm.preemption_reason());
        break;
    }
    // Safe point — do work
    {
        let _guard = pm.non_preemptible(); // critical section
        // non-preemptible work here
    }
}
```

---

## 6.22.8. CONTROL Message Content Types

**SDK**: JS/TS only

Custom content-type constants and codecs for CONTROL messages. The spec defines
the CONTROL `MessageType` but does not enumerate content-type subtypes.

### Constants

| Constant | Value |
|----------|-------|
| `CT_SCHEDULER_COMMAND_V1` | `application/vnd.sw4rm.scheduler.command+json;v=1` |
| `CT_AGENT_REPORT_V1` | `application/vnd.sw4rm.agent.report+json;v=1` |

### Interfaces

**SchedulerCommandV1**: `{ stage: 'prompt' | 'plan' | 'run', input?: unknown }`

**AgentReportV1**: `{ agent_id?, stage?, success?, files?: AgentReportFileV1[], logs?, error? }`

```ts
import { encodeSchedulerCommandV1, decodeAgentReportV1 } from '@sw4rm/js-sdk/internal/control';

const payload = encodeSchedulerCommandV1({ stage: 'run', input: { task: 'analyze' } });
const report = decodeAgentReportV1(receivedPayload);
```

---

## 6.22.9. Colony / Agent Spawning

**SDK**: Python only

Agent thread spawning infrastructure (`colony/` module). Provides lifecycle
management for dynamically spawned agents. Application-level concern not
specified in the protocol.

### Spawn Modes

| Mode | Description |
|------|-------------|
| `THREAD` | In-process thread (default) |
| `PROCESS` | Separate OS process |
| `CONTAINER` | Container-based (requires `container_image` in config) |

### Agent Lifecycle

`SPAWNING` → `STARTING` → `READY` → `BUSY` → `TERMINATING` → `TERMINATED`

Error states: `UNHEALTHY`, `FAILED`

### Key API

| Method | Description |
|--------|-------------|
| `spawn_agent(config)` | Spawn an agent synchronously. Returns `AgentHandle`. |
| `spawn_agent_async(config)` | Spawn asynchronously. |
| `wait_ready(agent_id, timeout_s?)` | Block until agent reaches READY. |
| `terminate_agent(agent_id, reason?, force?)` | Terminate a spawned agent. |
| `list_agents(status_filter?, label_filter?)` | List agents with optional filters. |
| `cleanup_terminated(max_age_s?)` | Remove old terminated agent records. |

```python
from sw4rm.colony.spawner import ThreadSpawner, SpawnerConfig

spawner = ThreadSpawner(max_agents=50)
config = SpawnerConfig(
    agent_role="critic",
    agent_type="code_reviewer",
    capabilities=["code_review", "security_audit"],
)
handle = spawner.spawn_agent(config)
spawner.wait_ready(handle.agent_id, timeout_s=10.0)
```

---

## 6.22.10. LLM Integration

**SDK**: Python only

Claude SDK adapter (`llm/` module) for integrating language model inference
into agent decision-making. Protocol-agnostic; the spec does not prescribe
inference engine integration.

### Client Interface

| Method | Description |
|--------|-------------|
| `query(prompt, system_prompt?, max_tokens?, temperature?, model?)` | Single query, returns `LLMResponse`. |
| `stream_query(prompt, ...)` | Streaming query, returns `AsyncIterator[str]`. |

### Implementations

| Client | Description |
|--------|-------------|
| `ClaudeSDKClient` | Claude Agent SDK integration. Models: `sonnet`, `opus`, `haiku`. |
| `MockLLMClient` | Testing mock with call history and configurable responses. |

### Factory

```python
from sw4rm.llm import create_llm_client

# Auto-selects based on LLM_CLIENT_TYPE env var (default: "claude_sdk")
client = create_llm_client(model="sonnet")
response = await client.query("Analyze this code for security issues")
print(response.content, response.model, response.usage)
```

### Error Hierarchy

`LLMError` → `LLMAuthenticationError` | `LLMRateLimitError` | `LLMTimeoutError` | `LLMContextLengthError`

---

## 6.22.11. Envelope-Level Message Tracking

**SDK**: Python (extended), Rust (basic)

The Python `ActivityBuffer` tracks individual envelopes beyond the spec-mandated
task-level entries (§10). This provides finer-grained observability.

### Extended ActivityRecord Fields

| Field | Type | Description |
|-------|------|-------------|
| `message_id` | string | Per-attempt message identifier |
| `direction` | string | `"in"` or `"out"` |
| `ack_stage` | int | Current ACK stage (see [ACK Lifecycle](../protocol/acks.md)) |
| `error_code` | int | Error code if applicable |
| `ack_note` | string | Human-readable ACK context |

The buffer indexes by `idempotency_token` for deduplication support per §11.2.

---

## 6.22.12. Extended Envelope Fields

**SDKs**: Python (implemented), JS/TS and Rust (added for parity)

These envelope fields extend the proto-defined `Envelope` message. They are
carried as SDK-level metadata until the proto is updated.

| Field | Type | Description |
|-------|------|-------------|
| `effective_policy_id` | string | ID of the effective policy governing the operation |
| `audit_proof` | bytes | Cryptographic proof for audit trail (hash, ZK-proof, or signature) |
| `audit_policy_id` | string | ID of the audit policy governing this envelope |

=== "Rust"
    ```rust
    use sw4rm_sdk::envelope::EnvelopeBuilder;

    let envelope = EnvelopeBuilder::new(/* ... */)
        .with_effective_policy_id("policy-abc".to_string())
        .with_audit_proof(proof_bytes)
        .with_audit_policy_id("audit-policy-1".to_string())
        .build();
    ```

=== "JavaScript/TypeScript"
    ```ts
    import { buildEnvelope } from '@sw4rm/js-sdk';

    const envelope = buildEnvelope({
      // ...standard fields...
      effective_policy_id: 'policy-abc',
      audit_proof: proofBytes,
      audit_policy_id: 'audit-policy-1',
    });
    ```

---

## 6.22.13. Voting / Aggregation Analytics

**SDKs**: Python, JS/TS, Rust

The `VotingAggregator` provides analytics on top of the four aggregation
strategies. The spec (§17.4) defines the strategies; the analytics layer is an
SDK extension. See [Voting Strategies](../protocol/voting-strategies.md) for
the protocol reference.

### Aggregation Strategies

| Strategy | Description |
|----------|-------------|
| `SimpleAverageAggregator` | Unweighted arithmetic mean |
| `ConfidenceWeightedAggregator` | POMDP-based confidence weighting |
| `MajorityVoteAggregator` | Binary pass/fail counting |
| `BordaCountAggregator` | Ranked voting |

### Analytics Methods (Python)

| Method | Description |
|--------|-------------|
| `compute_entropy(votes)` | Shannon entropy across 5 bins. Higher = more disagreement. |
| `detect_consensus(votes, threshold?)` | `True` if std_dev < 2.0 and agreement >= threshold (default 0.8). |
| `detect_polarization(votes)` | `True` if std_dev >= 3.0 with clustered extremes. |
| `compute_confidence_variance(votes)` | Variance in critic confidence values. |
| `get_vote_summary(votes)` | Full summary dict: entropy, consensus, polarization, confidence_variance, pass_rate. |

```python
from sw4rm.voting.aggregation import VotingAggregator
from sw4rm.voting.strategies import ConfidenceWeightedAggregator

aggregator = VotingAggregator(strategy=ConfidenceWeightedAggregator())
score = aggregator.aggregate(votes)
summary = aggregator.get_vote_summary(votes)

if aggregator.detect_polarization(votes):
    print("Votes are polarized — consider HITL escalation")
```

---

## 6.22.14. Persistence Backends

**SDKs**: Python, JS/TS, Rust

JSON file-based persistence for activity buffer, worktree bindings, and
configuration. The spec does not prescribe persistence mechanisms. See
[Persistence quickstart](../quickstart/persistence.md) for setup guidance.

### Backend Interface (Python)

| Method | Description |
|--------|-------------|
| `save_records(records, order)` | Persist activity records atomically (temp file + rename). |
| `load_records()` | Load records and ordering from storage. |
| `clear()` | Remove persisted data. |

### Implementations

| Backend | Description | SDK |
|---------|-------------|-----|
| `JSONFilePersistence` | Atomic JSON file writes, base64 for binary payloads. Default file: `sw4rm_activity.json`. | Python |
| `SQLitePersistence` | SQLite-backed storage (experimental). Default DB: `sw4rm_activity.sqlite3`. | Python |

```python
from sw4rm.persistence import JSONFilePersistence
from sw4rm.activity_buffer import ActivityBuffer

persistence = JSONFilePersistence("my_agent_activity.json")
buffer = ActivityBuffer(max_items=10000)

# Save buffer state
persistence.save_records(buffer.to_dict(), buffer.order())

# Restore on restart
records, order = persistence.load_records()
buffer.restore(records, order)
```

---

## 6.22.15. Inter-SW4RM Edge Semantics Hardening

**SDKs**: Python, JS/TS, Rust, Common Lisp

Python/JS/TS/Rust/Common Lisp delegation helpers share redirect/retry and
budget edge semantics for SW4-004/SW4-005 delegation flows.
Cancellation helper parity is implemented in Python/JS/TS/Rust/Common Lisp.
Gateway redirect-emitter parity is implemented in Python/JS/TS/Rust/Common Lisp.

### Redirect and Retry Semantics

- Redirect loop detection is deterministic across chained redirects (Python, JS/TS, Rust, Common Lisp).
- Redirect targets must be non-empty after trimming whitespace (Python, JS/TS, Rust, Common Lisp).
- Redirect follow depth uses `max_redirects`, with effective default `2` when unset.
- `OVERLOADED` retries consume wall time and obey deadline bounds before sleep
  (Python, JS/TS, Rust, Common Lisp).

### Deadline and Wall-Time Accounting

- Each send attempt decrements `budget.wall_time_remaining_ms` by observed elapsed time.
- Retry sleep also decrements `budget.wall_time_remaining_ms`.
- Python helper fallback mapping is deterministic: budget/deadline exhaustion maps to `ACK_TIMEOUT`, while non-`OVERLOADED`/non-`REDIRECT` rejections are returned unchanged.
- If wall-time or deadline is exhausted after an attempt, caller behavior fails
  fast with `ACK_TIMEOUT` instead of attempting another redirect/retry
  (Python, JS/TS, Rust, Common Lisp).

### Cancellation Safe-Points

- Python gateway/cancellation helpers provide:
- Gateways reject already-cancelled correlations before scheduling work.
- Gateways re-check cancellation immediately before accepting new work to block late cancellation races.
- Grace-period expiry remains enforceable through forced preemption.
- Python, JS/TS, Rust, and Common Lisp cancellation helpers provide cross-SDK parity for local cancellation state handling:
- parent/child cancellation cascade intent propagation,
- grace window clamping with minimum `5000ms`,
- forced-preemption signaling once grace expires, and
- normalized cancellation metadata (`reason`, `grace_period_ms`, plus normalized caller metadata fields).

### Peer Eligibility and Health Exclusion

- Python, JS/TS, Rust, and Common Lisp gateway redirect-emitter helpers now provide:
- Redirect candidates are restricted to `SWARM_GATEWAY` peers with matching capabilities.
- Non-serving peers (`INITIALIZING`, `FAILED_STATE`, `SHUTTING_DOWN`) are excluded.
- Stale and cooldown peers are excluded from redirect selection.
- Redirect responses use canonical `REDIRECT` shaping (`Gateway at capacity; redirect to peer gateway`) and fallback to `OVERLOADED` (`Gateway at capacity` + retry hint) when spillover routing is disabled or no eligible peer remains.

---

## 6.22.16. Cross-SDK Conformance Vector Harness v2

**SDKs**: Python, JS/TS, Rust, Common Lisp

The repository now includes shared SW4-004 and SW4-005 vector suites used by
all SDK test suites so the same cancellation and gateway/delegation
expectations are exercised with SDK-native adapters.

### Harness Layout

- Shared vectors:
  - `tests/conformance_vectors/sw4_005_delegation_vectors.json` (gateway/delegation)
  - `tests/conformance_vectors/sw4_004_cancellation_vectors.json` (cancellation)
- Harness guide: `tests/conformance_vectors/README.md`
- Python adapter: `sdks/py_sdk/tests/test_cross_sdk_conformance_vectors.py`
- JS/TS adapter: `sdks/js_sdk/test/conformanceVectors.test.ts`
- Rust adapters:
  - `sdks/rust_sdk/tests/integration_tests.rs` (`delegation_tests`)
  - `sdks/rust_sdk/tests/cancellation_tests.rs` (`shared_cancellation_conformance_vectors`)
- Common Lisp adapter: `sdks/cl_sdk/test/suite.lisp` (`client-stubs-suite`)

### Adding New Vectors

1. Add a new entry under `vectors` in the appropriate shared suite file.
2. Keep fields SDK-agnostic (`request`, `policy`, `redirect_map`, `expected`, etc.).
3. Re-run all four SDK suites (`py-test`, `test-js`, `test-rust`, `test-lisp`) so each adapter executes the new vector.
