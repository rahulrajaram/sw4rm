# 6.14. Negotiation Room Client

The Negotiation Room Client implements the producer-critic-coordinator pattern for multi-agent artifact approval. Use it to:

- Submit artifacts for review.
- Collect critic votes.
- Aggregate votes and store final decisions.
- Wait for decisions or inspect proposals.

The client is SDK-local and backed by a pluggable `NegotiationRoomStore`. Python and JS/TS default to a shared in-memory store per process, while Rust `new()` creates an isolated store. For multi-process deployments, use a persistent store from `colony` or implement the store interface.

## 6.14.1. Data Model

Field names are snake_case in Python/Rust and camelCase in JS/TS.

### ArtifactType values

| Value | Description |
|-------|-------------|
| `ARTIFACT_TYPE_UNSPECIFIED` | Unspecified artifact type |
| `REQUIREMENTS` | Requirements documentation |
| `PLAN` | Planning artifacts |
| `CODE` | Code artifacts |
| `DEPLOYMENT` | Deployment artifacts |

### DecisionOutcome values

| Value | Description |
|-------|-------------|
| `DECISION_OUTCOME_UNSPECIFIED` | Unspecified outcome |
| `APPROVED` | Artifact approved |
| `REVISION_REQUESTED` | Revision requested |
| `ESCALATED_TO_HITL` | Escalated to human-in-the-loop |

### NegotiationProposal fields

| Field | Type | Description |
|-------|------|-------------|
| `artifact_type` | enum | Artifact category (`ArtifactType`) |
| `artifact_id` | string | Unique artifact identifier |
| `producer_id` | string | Agent ID of the producer |
| `artifact` | bytes | Binary artifact payload |
| `artifact_content_type` | string | MIME/content type |
| `requested_critics` | list[string] | Critic agent IDs |
| `negotiation_room_id` | string | Negotiation room identifier |
| `created_at` | datetime | Creation timestamp (auto-set if omitted) |

### NegotiationVote fields

| Field | Type | Description |
|-------|------|-------------|
| `artifact_id` | string | Artifact identifier |
| `critic_id` | string | Critic agent ID |
| `score` | float | Score (0.0-10.0) |
| `confidence` | float | Confidence (0.0-1.0) |
| `passed` | bool | Whether artifact meets minimum criteria |
| `strengths` | list[string] | Strengths noted by critic |
| `weaknesses` | list[string] | Weaknesses noted by critic |
| `recommendations` | list[string] | Suggestions for improvement |
| `negotiation_room_id` | string | Negotiation room identifier |
| `voted_at` | datetime | Vote timestamp (auto-set if omitted) |

### AggregatedScore fields

| Field | Type | Description |
|-------|------|-------------|
| `mean` | float | Arithmetic mean score |
| `min_score` | float | Minimum score |
| `max_score` | float | Maximum score |
| `std_dev` | float | Standard deviation |
| `weighted_mean` | float | Confidence-weighted mean |
| `vote_count` | int | Number of votes |

### NegotiationDecision fields

| Field | Type | Description |
|-------|------|-------------|
| `artifact_id` | string | Artifact identifier |
| `outcome` | enum | Final decision (`DecisionOutcome`) |
| `votes` | list[NegotiationVote] | Full vote list |
| `aggregated_score` | AggregatedScore | Statistical summary |
| `policy_version` | string | Policy version used |
| `reason` | string | Human-readable rationale |
| `negotiation_room_id` | string | Negotiation room identifier |
| `decided_at` | datetime | Decision timestamp (auto-set if omitted) |

## 6.14.2. Constructors

### Python

`NegotiationRoomClient(store: NegotiationRoomStore | None = None)`

- `store`: Optional storage backend. If omitted, uses a shared in-memory store within the process.

### JavaScript/TypeScript

`new NegotiationRoomClient(options?: { store?: NegotiationRoomStore })`

- `options.store`: Optional storage backend. If omitted, uses a shared in-memory store within the process.

### Rust

`NegotiationRoomClient::new() -> NegotiationRoomClient`

- Creates a new client with an isolated in-memory store.

`NegotiationRoomClient::with_store(store: Arc<dyn NegotiationRoomStore>) -> NegotiationRoomClient`

- Uses a shared store for producer/critic/coordinator coordination.

## 6.14.3. Key Methods

### `submit_proposal` / `submitProposal`

**Python**
`submit_proposal(proposal: NegotiationProposal) -> str`

**JavaScript/TypeScript**
`submitProposal(proposal: NegotiationProposal): Promise<string>`

**Rust**
`submit_proposal(&self, proposal: NegotiationProposal) -> Result<String>`

### `submit_vote` / `submitVote`

**Python**
`submit_vote(vote: NegotiationVote) -> None`

**JavaScript/TypeScript**
`submitVote(vote: NegotiationVote): Promise<void>`

**Rust**
`submit_vote(&self, vote: NegotiationVote) -> Result<()>`

### `get_votes` / `getVotes`

**Python**
`get_votes(artifact_id: str) -> list[NegotiationVote]`

**JavaScript/TypeScript**
`getVotes(artifactId: string): Promise<NegotiationVote[]>`

**Rust**
`get_votes(&self, artifact_id: &str) -> Result<Vec<NegotiationVote>>`

### `get_decision` / `getDecision`

**Python**
`get_decision(artifact_id: str) -> NegotiationDecision | None`

**JavaScript/TypeScript**
`getDecision(artifactId: string): Promise<NegotiationDecision | null>`

**Rust**
`get_decision(&self, artifact_id: &str) -> Result<Option<NegotiationDecision>>`

### `store_decision` / `storeDecision`

**Python**
`store_decision(decision: NegotiationDecision) -> None`

**JavaScript/TypeScript**
`storeDecision(decision: NegotiationDecision): Promise<void>`

**Rust**
`store_decision(&self, decision: NegotiationDecision) -> Result<()>`

### `wait_for_decision` / `waitForDecision`

**Python**
`wait_for_decision(artifact_id: str, timeout_s: float = 30.0, poll_interval_s: float = 0.1) -> NegotiationDecision`

**JavaScript/TypeScript**
`waitForDecision(artifactId: string, timeoutMs: number = 30000, pollIntervalMs: number = 100): Promise<NegotiationDecision>`

**Rust**
`wait_for_decision(&self, artifact_id: &str, timeout: Duration) -> Result<NegotiationDecision>`

### `get_proposal` / `getProposal`

**Python**
`get_proposal(artifact_id: str) -> NegotiationProposal | None`

**JavaScript/TypeScript**
`getProposal(artifactId: string): Promise<NegotiationProposal | null>`

**Rust**
`get_proposal(&self, artifact_id: &str) -> Result<Option<NegotiationProposal>>`

### `list_proposals` / `listProposals`

**Python**
`list_proposals(negotiation_room_id: str | None = None) -> list[NegotiationProposal]`

**JavaScript/TypeScript**
`listProposals(negotiationRoomId?: string): Promise<NegotiationProposal[]>`

**Rust**
`list_proposals(&self, negotiation_room_id: Option<&str>) -> Result<Vec<NegotiationProposal>>`

## 6.14.4. Custom Coordinator Guide

Coordinator agents typically:

- Fetch all votes for an artifact.
- Aggregate scores to apply a decision policy.
- Store the final decision for producers to retrieve.

Python example:

```python
from sw4rm.clients import NegotiationRoomClient
from sw4rm.negotiation_types import (
    DecisionOutcome,
    NegotiationDecision,
    aggregate_votes,
)

client = NegotiationRoomClient()
votes = client.get_votes("artifact-123")
aggregated = aggregate_votes(votes)

decision = NegotiationDecision(
    artifact_id="artifact-123",
    outcome=DecisionOutcome.APPROVED,
    votes=votes,
    aggregated_score=aggregated,
    policy_version="policy-1",
    reason="Meets approval threshold",
    negotiation_room_id="room-1",
)

client.store_decision(decision)
```

For advanced policies, use the voting strategies in `sw4rm.voting` (Python) or `sw4rm_sdk::voting` (Rust) before storing a decision.

## 6.14.5. Usage Examples

=== "Python"
    ```python
    from sw4rm.clients import NegotiationRoomClient
    from sw4rm.negotiation_types import (
        NegotiationProposal,
        NegotiationVote,
        ArtifactType,
    )

    client = NegotiationRoomClient()

    proposal = NegotiationProposal(
        artifact_type=ArtifactType.CODE,
        artifact_id="code-123",
        producer_id="agent-producer",
        artifact=b"def hello(): pass",
        artifact_content_type="text/x-python",
        requested_critics=["critic-1", "critic-2"],
        negotiation_room_id="room-1",
    )

    client.submit_proposal(proposal)

    vote = NegotiationVote(
        artifact_id="code-123",
        critic_id="critic-1",
        score=8.5,
        confidence=0.9,
        passed=True,
        strengths=["Clean structure"],
        weaknesses=["Missing tests"],
        recommendations=["Add unit tests"],
        negotiation_room_id="room-1",
    )

    client.submit_vote(vote)
    decision = client.wait_for_decision("code-123", timeout_s=10.0)
    ```

=== "JavaScript/TypeScript"
    ```ts
    import {
      NegotiationRoomClient,
      ArtifactType,
    } from '@sw4rm/js-sdk';

    const client = new NegotiationRoomClient();

    await client.submitProposal({
      artifactType: ArtifactType.CODE,
      artifactId: 'code-123',
      producerId: 'agent-producer',
      artifact: new TextEncoder().encode('def hello(): pass'),
      artifactContentType: 'text/x-python',
      requestedCritics: ['critic-1', 'critic-2'],
      negotiationRoomId: 'room-1',
    });

    await client.submitVote({
      artifactId: 'code-123',
      criticId: 'critic-1',
      score: 8.5,
      confidence: 0.9,
      passed: true,
      strengths: ['Clean structure'],
      weaknesses: ['Missing tests'],
      recommendations: ['Add unit tests'],
      negotiationRoomId: 'room-1',
    });

    const decision = await client.waitForDecision('code-123', 10000);
    console.log(decision.outcome);
    ```

=== "Rust"
    ```rust
    use sw4rm_sdk::clients::negotiation_room_store::InMemoryNegotiationRoomStore;
    use sw4rm_sdk::clients::{NegotiationRoomClient, NegotiationProposal, NegotiationVote};
    use sw4rm_sdk::clients::negotiation_room::{ArtifactType};
    use std::sync::Arc;
    use std::time::Duration;

    let store = Arc::new(InMemoryNegotiationRoomStore::new());
    let producer = NegotiationRoomClient::with_store(store.clone());
    let critic = NegotiationRoomClient::with_store(store.clone());

    let proposal = NegotiationProposal::new(
        ArtifactType::Code,
        "code-123".to_string(),
        "agent-producer".to_string(),
        b"def hello(): pass".to_vec(),
        "text/x-python".to_string(),
        vec!["critic-1".to_string(), "critic-2".to_string()],
        "room-1".to_string(),
    );

    producer.submit_proposal(proposal)?;

    let vote = NegotiationVote::new(
        "code-123".to_string(),
        "critic-1".to_string(),
        8.5,
        0.9,
        true,
        vec!["Clean structure".to_string()],
        vec!["Missing tests".to_string()],
        vec!["Add unit tests".to_string()],
        "room-1".to_string(),
    );

    critic.submit_vote(vote)?;
    let decision = producer.wait_for_decision("code-123", Duration::from_secs(10))?;
    println!("{:?}", decision.outcome);
    ```
