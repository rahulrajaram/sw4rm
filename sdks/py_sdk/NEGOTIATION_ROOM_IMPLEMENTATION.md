# Negotiation Room Pattern - Phase 2.2 Implementation

## Overview

This document describes the implementation of Phase 2.2: Negotiation Room Pattern for the SW4RM Protocol Python SDK.

The Negotiation Room pattern enables multi-agent artifact approval workflows where:
1. **Producer agents** submit artifacts for review
2. **Critic agents** evaluate artifacts and submit votes
3. **Coordinator agents** aggregate votes and make final decisions

## Implementation Details

### Files Created

#### 1. `sw4rm/clients/negotiation_room.py`
**NegotiationRoomClient** - Client for managing negotiation rooms

**Key Methods:**
- `submit_proposal(proposal: NegotiationProposal) -> str`
  - Submits an artifact for review
  - Returns the artifact_id
  - Raises ValueError if duplicate proposal

- `submit_vote(vote: NegotiationVote) -> None`
  - Submits a critic's evaluation
  - Prevents duplicate votes from same critic
  - Raises ValueError if no proposal exists

- `get_votes(artifact_id: str) -> list[NegotiationVote]`
  - Retrieves all votes for an artifact
  - Returns empty list if no votes yet

- `get_decision(artifact_id: str) -> NegotiationDecision | None`
  - Retrieves the decision if available
  - Returns None if still under review

- `wait_for_decision(artifact_id: str, timeout_s: float) -> NegotiationDecision`
  - Polls for a decision until available or timeout
  - Raises TimeoutError if no decision within timeout
  - Useful for producer agents awaiting results

- `store_decision(decision: NegotiationDecision) -> None`
  - Internal method for coordinators to store decisions
  - Raises ValueError if decision already exists

- `get_proposal(artifact_id: str) -> NegotiationProposal | None`
  - Retrieves the original proposal

- `list_proposals(negotiation_room_id: str | None) -> list[NegotiationProposal]`
  - Lists all proposals, optionally filtered by room

**Storage:**
- In-memory implementation using dictionaries
- Future phases will integrate with persistent storage

#### 2. `sw4rm/negotiation_coordinator.py`
**NegotiationCoordinator** - Decision-making logic for negotiation rooms

**Key Methods:**
- `apply_policy(scores: AggregatedScore, policy: NegotiationPolicy) -> DecisionOutcome`
  - Applies policy thresholds to aggregated scores
  - Returns APPROVED, REVISION_REQUESTED, or ESCALATED_TO_HITL
  - Escalation takes precedence when variance is high

- `should_auto_approve(score: float, policy: NegotiationPolicy) -> bool`
  - Checks if score meets auto-approval threshold
  - Compares against normalized threshold (0-1 → 0-10 scale)

- `should_escalate(votes: list[NegotiationVote], policy: NegotiationPolicy) -> bool`
  - Detects conditions requiring human review:
    - Any critic marked artifact as failed
    - High variance in scores (disagreement)
    - Low average confidence (uncertainty)

- `generate_decision_reason(outcome, scores, votes, policy) -> str`
  - Creates human-readable explanation for decisions
  - Includes statistics and key factors

**Decision Logic:**
1. Check for high variance → ESCALATED_TO_HITL
2. Check if weighted_mean >= threshold → APPROVED
3. Otherwise → REVISION_REQUESTED

#### 3. `sw4rm/clients/__init__.py`
Updated to export `NegotiationRoomClient` along with other clients.

**Note:** Fixed incorrect `HITLClient` to `HitlClient` to match actual class name.

#### 4. `tests/test_negotiation_room.py`
Comprehensive test suite with 30 tests covering:

**NegotiationRoomClient Tests (14 tests):**
- Proposal submission (success, duplicates)
- Vote submission (success, validation, duplicates)
- Vote retrieval (empty, multiple)
- Decision storage and retrieval
- Wait for decision (success, timeout)
- Proposal listing (all, filtered)

**NegotiationCoordinator Tests (13 tests):**
- Policy application (approved, revision, escalation)
- Auto-approval logic
- Escalation detection (failed votes, low confidence, high variance)
- Decision reason generation

**Integration Tests (3 tests):**
- Complete approval workflow
- Complete revision workflow
- Complete escalation workflow

**All 30 tests pass successfully.**

#### 5. `sw4rm/examples/negotiation_room_example.py`
Demonstration script showing complete workflow:
- Producer submits Fibonacci code for review
- Three critics evaluate different aspects:
  - Quality critic (8.5/10, passed)
  - Performance critic (6.0/10, failed - notes inefficiency)
  - Security critic (9.0/10, passed)
- Coordinator aggregates and makes decision
- Displays detailed feedback and recommendations

## Usage Example

```python
from sw4rm.clients.negotiation_room import NegotiationRoomClient
from sw4rm.negotiation_coordinator import NegotiationCoordinator
from sw4rm.negotiation_types import (
    ArtifactType,
    NegotiationProposal,
    NegotiationVote,
    aggregate_votes,
)
from sw4rm.policy_types import NegotiationPolicy

# Initialize
client = NegotiationRoomClient()
coordinator = NegotiationCoordinator()
policy = NegotiationPolicy(score_threshold=0.8, diff_tolerance=0.1)

# Producer submits artifact
proposal = NegotiationProposal(
    artifact_type=ArtifactType.CODE,
    artifact_id="code-123",
    producer_id="producer-1",
    artifact=b"def hello(): pass",
    artifact_content_type="text/x-python",
    requested_critics=["critic-1", "critic-2"],
    negotiation_room_id="room-1",
)
artifact_id = client.submit_proposal(proposal)

# Critics submit votes
vote1 = NegotiationVote(
    artifact_id=artifact_id,
    critic_id="critic-1",
    score=8.5,
    confidence=0.9,
    passed=True,
    strengths=["Good structure"],
    weaknesses=[],
    recommendations=[],
    negotiation_room_id="room-1",
)
client.submit_vote(vote1)

# Coordinator makes decision
votes = client.get_votes(artifact_id)
aggregated = aggregate_votes(votes)
outcome = coordinator.apply_policy(aggregated, policy)
```

## Key Design Decisions

### 1. Score Normalization
- **NegotiationVote** uses 0-10 scale for scores (human-friendly)
- **NegotiationPolicy** uses 0-1 scale for thresholds (standard practice)
- **Coordinator** normalizes thresholds by multiplying by 10 when comparing

### 2. Escalation Logic
Escalation takes precedence to ensure conflicting or uncertain votes get human review:
- Any failed vote triggers escalation
- High variance (std_dev > threshold) triggers escalation
- Low average confidence (<0.5) triggers escalation

### 3. In-Memory Storage
Current implementation uses in-memory dictionaries:
- Simple and fast for Phase 2.2
- Easy to test without dependencies
- Future phases will add persistent storage

### 4. Vote Deduplication
Each critic can only vote once per artifact:
- Prevents vote manipulation
- Ensures fair aggregation
- Raises clear error if duplicate attempted

## Testing

Run tests with:
```bash
pytest tests/test_negotiation_room.py -v
```

All 30 tests pass:
- 14 NegotiationRoomClient tests
- 13 NegotiationCoordinator tests
- 3 Integration tests

Test coverage includes:
- Success paths
- Error handling
- Edge cases
- Thread safety (wait_for_decision)
- Complete workflows

## Dependencies

The implementation uses only existing types:
- `sw4rm.negotiation_types` (NegotiationProposal, NegotiationVote, etc.)
- `sw4rm.policy_types` (NegotiationPolicy)
- Standard library (time, typing)

No new external dependencies required.

## Future Enhancements

Phase 2.3+ may include:
- Persistent storage backend (database, Redis)
- gRPC service integration
- Real-time notifications for decision updates
- Metrics and analytics
- Policy versioning and migration
- Multi-room coordination

## Verification

All requirements from the specification are implemented:

✅ NegotiationRoomClient with all required methods
✅ NegotiationCoordinator with policy application
✅ Comprehensive test suite (30 tests, all passing)
✅ Proper error handling and validation
✅ Example demonstrating usage
✅ Documentation and docstrings
✅ Integration with existing types

## Files Modified/Created

**Created:**
- `sw4rm/clients/negotiation_room.py` (344 lines)
- `sw4rm/negotiation_coordinator.py` (317 lines)
- `sw4rm/clients/__init__.py` (48 lines)
- `tests/test_negotiation_room.py` (773 lines)
- `sw4rm/examples/negotiation_room_example.py` (216 lines)

**Total:** ~1,698 lines of production code and tests

---

*Implementation completed: Phase 2.2 - Negotiation Room Pattern*
