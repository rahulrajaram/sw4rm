# SW4RM Voting Module - Quick Start Guide

## Installation

The voting module is part of the SW4RM Python SDK. No additional installation needed.

## Basic Usage

### 1. Simple Aggregation

```python
from sw4rm.negotiation_types import NegotiationVote
from sw4rm.voting import VotingAggregator, ConfidenceWeightedAggregator

# Create votes (from critics)
votes = [
    NegotiationVote(
        artifact_id="art_123",
        critic_id="critic_1",
        score=8.5,
        confidence=0.9,
        passed=True,
        strengths=["Good security"],
        weaknesses=["Minor issues"],
        recommendations=["Fix edge cases"],
        negotiation_room_id="room_001",
    ),
    # ... more votes
]

# Aggregate
aggregator = VotingAggregator(ConfidenceWeightedAggregator())
result = aggregator.aggregate(votes)

print(f"Final score: {result.weighted_mean:.2f}")
```

### 2. Decision Making

```python
# Make approval decision
if aggregator.detect_polarization(votes):
    decision = "ESCALATE_TO_HITL"  # Critics disagree
elif result.weighted_mean >= 7.0 and aggregator.detect_consensus(votes):
    decision = "APPROVED"
else:
    decision = "REVISION_REQUESTED"
```

### 3. Compare Strategies

```python
from sw4rm.voting import (
    SimpleAverageAggregator,
    MajorityVoteAggregator,
    BordaCountAggregator,
)

strategies = {
    "Simple": SimpleAverageAggregator(),
    "Confidence": ConfidenceWeightedAggregator(),
    "Majority": MajorityVoteAggregator(),
    "Borda": BordaCountAggregator(),
}

for name, strategy in strategies.items():
    agg = VotingAggregator(strategy)
    result = agg.aggregate(votes)
    print(f"{name}: {result.weighted_mean:.2f}")
```

## Common Patterns

### Pattern 1: Consensus Check

```python
if aggregator.detect_consensus(votes, threshold=0.8):
    # 80%+ critics agree - safe to proceed
    auto_approve()
else:
    # Need more review
    request_additional_critics()
```

### Pattern 2: Polarization Alert

```python
if aggregator.detect_polarization(votes):
    # Critics strongly disagree
    escalate_to_human_review()
```

### Pattern 3: Full Analysis

```python
summary = aggregator.get_vote_summary(votes)

if summary['polarization']:
    action = "ESCALATE"
elif summary['consensus'] and summary['pass_rate'] > 0.8:
    action = "APPROVE"
elif summary['entropy'] > 1.5:
    action = "REQUEST_MORE_VOTES"
else:
    action = "REVISION"
```

## Strategy Selection

| Use Case | Strategy | Why |
|----------|----------|-----|
| General purpose | `ConfidenceWeightedAggregator` | Accounts for critic confidence |
| Yes/No decision | `MajorityVoteAggregator` | Simple binary voting |
| Avoid outliers | `BordaCountAggregator` | Rank-based, outlier-resistant |
| Baseline | `SimpleAverageAggregator` | Simple, transparent |

## Key Metrics

### Entropy
```python
entropy = aggregator.compute_entropy(votes)
# 0.0 = perfect agreement
# 2.3 = maximum disagreement (uniform distribution)
```

### Consensus
```python
consensus = aggregator.detect_consensus(votes, threshold=0.8)
# True = 80%+ critics agree on pass/fail AND low variance
# False = significant disagreement
```

### Polarization
```python
polarization = aggregator.detect_polarization(votes)
# True = votes clustered at extremes (bimodal)
# False = normal distribution
```

## Complete Example

```python
from sw4rm.negotiation_types import NegotiationVote, NegotiationDecision, DecisionOutcome
from sw4rm.voting import VotingAggregator, ConfidenceWeightedAggregator

# Collect votes from critics
votes = [...]  # List of NegotiationVote

# Create aggregator
aggregator = VotingAggregator(ConfidenceWeightedAggregator())

# Aggregate scores
score = aggregator.aggregate(votes)

# Analyze vote distribution
summary = aggregator.get_vote_summary(votes)

# Make decision
if summary['polarization']:
    outcome = DecisionOutcome.ESCALATED_TO_HITL
    reason = "Critics are polarized - human review required"
elif score.weighted_mean >= 7.0 and summary['consensus']:
    outcome = DecisionOutcome.APPROVED
    reason = f"Strong consensus with score {score.weighted_mean:.2f}"
elif score.weighted_mean >= 6.0:
    outcome = DecisionOutcome.REVISION_REQUESTED
    reason = f"Score {score.weighted_mean:.2f} needs improvement"
else:
    outcome = DecisionOutcome.REVISION_REQUESTED
    reason = f"Score {score.weighted_mean:.2f} below threshold"

# Create decision record
decision = NegotiationDecision(
    artifact_id=votes[0].artifact_id,
    outcome=outcome,
    votes=votes,
    aggregated_score=score,
    policy_version="1.0",
    reason=reason,
    negotiation_room_id=votes[0].negotiation_room_id,
)
```

## Thresholds

Common threshold values:

```python
# Consensus threshold
consensus = aggregator.detect_consensus(votes, threshold=0.8)  # 80% agreement

# Approval threshold
if score.weighted_mean >= 7.0:  # 7/10 minimum
    approve()

# Entropy threshold
if aggregator.compute_entropy(votes) > 1.5:  # High disagreement
    request_more_reviews()
```

## Error Handling

```python
from sw4rm.voting import VotingAggregator, ConfidenceWeightedAggregator

aggregator = VotingAggregator(ConfidenceWeightedAggregator())

try:
    result = aggregator.aggregate(votes)
except ValueError as e:
    # Raised when votes list is empty
    print(f"Cannot aggregate: {e}")
```

## Testing

Run the test suite:

```bash
# All voting tests
pytest tests/test_voting_aggregation.py -v

# Specific test class
pytest tests/test_voting_aggregation.py::TestConfidenceWeightedAggregator -v

# Run example
python examples/voting_example.py
```

## Next Steps

- Read [README.md](README.md) for detailed documentation
- See [examples/voting_example.py](../../examples/voting_example.py) for complete examples
- Check [PHASE_3_4_IMPLEMENTATION.md](../../PHASE_3_4_IMPLEMENTATION.md) for implementation details

## Support

For issues or questions:
- Review test cases in `tests/test_voting_aggregation.py`
- Check module docstrings for detailed API documentation
- See SPEC_REQUESTS.md Phase 3.4 for requirements
