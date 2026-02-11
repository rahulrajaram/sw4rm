# Voting Strategies

Voting strategies aggregate `NegotiationVote` inputs into an `AggregatedScore`
for Negotiation Room decisions and other consensus workflows. Pair a strategy
with `VotingAggregator` to compute statistics and produce a weighted outcome.

**Source:** `sdks/py_sdk/sw4rm/voting/strategies.py`

## Strategy Summary

| Strategy | Algorithm | Use case |
|----------|-----------|----------|
| `SimpleAverageAggregator` | Arithmetic mean of scores | Transparent baseline |
| `ConfidenceWeightedAggregator` | Confidence-weighted mean | Default for mixed certainty |
| `MajorityVoteAggregator` | Pass/fail majority mapping | Binary approval gates |
| `BordaCountAggregator` | Rank-based points, normalized | Reduce outlier impact |

## AggregationStrategy Protocol

All strategies implement a shared protocol:

```python
from typing import Protocol
from sw4rm.negotiation_types import AggregatedScore, NegotiationVote

class AggregationStrategy(Protocol):
    def aggregate(self, votes: list[NegotiationVote]) -> AggregatedScore:
        ...
```

All implementations raise `ValueError` when `votes` is empty.

## Strategy Details

### SimpleAverageAggregator

- **Constructor:** `SimpleAverageAggregator()`

- **`aggregate(votes)` behavior:** Computes mean, min, max, std dev from scores and
  sets `weighted_mean` to the same value as `mean`.

- **Edge cases:** Empty vote lists raise `ValueError`.

### ConfidenceWeightedAggregator

- **Constructor:** `ConfidenceWeightedAggregator()`

- **`aggregate(votes)` behavior:** Computes the unweighted statistics and sets
  `weighted_mean = sum(score_i * confidence_i) / sum(confidence_i)`.

- **Edge cases:** If the total confidence is zero, `weighted_mean` falls back to
  the simple mean. Empty vote lists raise `ValueError`.

### MajorityVoteAggregator

- **Constructor:** `MajorityVoteAggregator()`

- **`aggregate(votes)` behavior:** Uses the pass/fail majority to set
  `weighted_mean` and still computes the unweighted statistics from scores.

- **Score mapping:**

  - All passed: `10.0`

  - Majority passed (>50%): `7.5`

  - Tie: `5.0`

  - Majority failed (>50%): `2.5`

  - All failed: `0.0`

- **Edge cases:** Empty vote lists raise `ValueError`.

### BordaCountAggregator

- **Constructor:** `BordaCountAggregator()`

- **`aggregate(votes)` behavior:** Ranks scores from highest to lowest, assigns
  points `n..1`, averages the points per vote, and normalizes to a `0..10`
  `weighted_mean`. Unweighted statistics are still computed from scores.

- **Edge cases:** Empty vote lists raise `ValueError`. Ties are resolved by the
  input order of votes during ranking.

## Using Strategies in a Negotiation Room

```python
from sw4rm.negotiation_types import DecisionOutcome, NegotiationDecision, NegotiationVote
from sw4rm.voting import VotingAggregator, ConfidenceWeightedAggregator

votes = [
    NegotiationVote(
        artifact_id="artifact-123",
        critic_id="critic-1",
        score=8.5,
        confidence=0.9,
        passed=True,
        strengths=["Clear intent"],
        weaknesses=["Missing tests"],
        recommendations=["Add unit tests"],
        negotiation_room_id="room-1",
    ),
    NegotiationVote(
        artifact_id="artifact-123",
        critic_id="critic-2",
        score=6.5,
        confidence=0.6,
        passed=False,
        strengths=["Readable code"],
        weaknesses=["No validation"],
        recommendations=["Add input checks"],
        negotiation_room_id="room-1",
    ),
]

aggregator = VotingAggregator(ConfidenceWeightedAggregator())
aggregated = aggregator.aggregate(votes)

if aggregated.weighted_mean >= 7.0 and aggregator.detect_consensus(votes):
    outcome = DecisionOutcome.APPROVED
    reason = "High confidence consensus"
else:
    outcome = DecisionOutcome.REVISION_REQUESTED
    reason = "Consensus threshold not met"

decision = NegotiationDecision(
    artifact_id="artifact-123",
    outcome=outcome,
    votes=votes,
    aggregated_score=aggregated,
    policy_version="1.0",
    reason=reason,
    negotiation_room_id="room-1",
)
```

## Strategy Selection Guide

| Scenario | Recommended strategy |
|----------|----------------------|
| General purpose | `ConfidenceWeightedAggregator` |
| Binary approval | `MajorityVoteAggregator` |
| Outlier resistance | `BordaCountAggregator` |
| Baseline comparison | `SimpleAverageAggregator` |

## Related Documentation

- [Negotiation Room Client](../clients/negotiation-room.md)
- [Advanced Patterns](advanced-patterns.md)
