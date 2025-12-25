# SW4RM Voting Module

This module implements **Phase 3.4: Confidence-Weighted Voting** from the SW4RM Protocol specification, providing multiple aggregation strategies for combining critic votes in negotiation rooms.

## Overview

The voting module enables sophisticated aggregation of critic evaluations based on POMDP (Partially Observable Markov Decision Process) research, where critics express confidence levels alongside their scores. This allows for more nuanced decision-making in multi-agent artifact approval workflows.

## Components

### Aggregation Strategies

The module provides four aggregation strategies, each suitable for different scenarios:

#### 1. `SimpleAverageAggregator`
- **Use case**: Baseline comparison, equal weight to all critics
- **Method**: Arithmetic mean of all scores
- **Characteristics**:
  - Ignores confidence levels
  - Simple and transparent
  - Good for homogeneous critic teams

#### 2. `ConfidenceWeightedAggregator` (Recommended)
- **Use case**: Default strategy for most scenarios
- **Method**: Weight each vote by its confidence value
- **Formula**: `weighted_mean = sum(score_i * confidence_i) / sum(confidence_i)`
- **Characteristics**:
  - Based on POMDP research
  - Gives more influence to high-confidence critics
  - Accounts for uncertainty in evaluations
  - Falls back to simple mean if all confidences are zero

#### 3. `MajorityVoteAggregator`
- **Use case**: Binary approval decisions, ignore score nuances
- **Method**: Count passed vs failed votes
- **Score mapping**:
  - All passed: 10.0
  - Majority passed (>50%): 7.5
  - Tie: 5.0
  - Majority failed (>50%): 2.5
  - All failed: 0.0
- **Characteristics**:
  - Simple binary decision
  - Robust to score calibration differences
  - Good for go/no-go decisions

#### 4. `BordaCountAggregator`
- **Use case**: Resistant to strategic voting, reduce outlier impact
- **Method**: Ranked voting with position-based points
- **Algorithm**:
  1. Rank votes by score (highest to lowest)
  2. Assign points: highest gets n points, next gets n-1, etc.
  3. Normalize to 0-10 scale
- **Characteristics**:
  - Reduces impact of outliers
  - Resistant to strategic voting
  - Good for competitive evaluations

### VotingAggregator Class

The main aggregator class that wraps a strategy and provides analytical capabilities:

```python
from sw4rm.voting import VotingAggregator, ConfidenceWeightedAggregator

aggregator = VotingAggregator(ConfidenceWeightedAggregator())
result = aggregator.aggregate(votes)
```

#### Methods

- **`aggregate(votes)`**: Aggregate votes using configured strategy
- **`compute_entropy(votes)`**: Measure uncertainty/disagreement (Shannon entropy)
- **`detect_consensus(votes, threshold=0.8)`**: Detect if critics agree
- **`detect_polarization(votes)`**: Detect bimodal distribution (strong disagreement)
- **`compute_confidence_variance(votes)`**: Measure variation in critic confidence
- **`get_vote_summary(votes)`**: Get comprehensive analytical summary

## Usage Examples

### Basic Aggregation

```python
from sw4rm.negotiation_types import NegotiationVote
from sw4rm.voting import VotingAggregator, ConfidenceWeightedAggregator

# Create votes
votes = [
    NegotiationVote(
        artifact_id="art_123",
        critic_id="security_critic",
        score=8.5,
        confidence=0.9,
        passed=True,
        strengths=["Good auth"],
        weaknesses=["Missing rate limit"],
        recommendations=["Add rate limiting"],
        negotiation_room_id="room_001",
    ),
    # ... more votes
]

# Aggregate with confidence weighting
aggregator = VotingAggregator(ConfidenceWeightedAggregator())
result = aggregator.aggregate(votes)

print(f"Weighted mean: {result.weighted_mean}")
print(f"Standard deviation: {result.std_dev}")
```

### Detecting Consensus

```python
# Check if critics reached consensus
if aggregator.detect_consensus(votes, threshold=0.8):
    print("Strong consensus - can auto-approve")
else:
    print("No consensus - needs further review")
```

### Detecting Polarization

```python
# Check if critics are polarized (bimodal distribution)
if aggregator.detect_polarization(votes):
    print("Critics strongly disagree - escalate to HITL")
    # Trigger human-in-the-loop review
```

### Comprehensive Analysis

```python
# Get full analytical summary
summary = aggregator.get_vote_summary(votes)

print(f"Pass rate: {summary['pass_rate']:.1%}")
print(f"Entropy: {summary['entropy']:.3f} bits")
print(f"Consensus: {summary['consensus']}")
print(f"Polarization: {summary['polarization']}")
print(f"Confidence variance: {summary['confidence_variance']:.4f}")
```

### Strategy Comparison

```python
from sw4rm.voting import (
    SimpleAverageAggregator,
    ConfidenceWeightedAggregator,
    MajorityVoteAggregator,
    BordaCountAggregator,
)

strategies = [
    ("Simple Average", SimpleAverageAggregator()),
    ("Confidence Weighted", ConfidenceWeightedAggregator()),
    ("Majority Vote", MajorityVoteAggregator()),
    ("Borda Count", BordaCountAggregator()),
]

for name, strategy in strategies:
    aggregator = VotingAggregator(strategy)
    result = aggregator.aggregate(votes)
    print(f"{name}: {result.weighted_mean:.2f}")
```

## Decision Guidelines

### When to Use Each Strategy

| Scenario | Recommended Strategy | Rationale |
|----------|---------------------|-----------|
| General purpose | ConfidenceWeightedAggregator | Accounts for critic confidence |
| Binary approval | MajorityVoteAggregator | Simple pass/fail decision |
| Outlier resistance | BordaCountAggregator | Reduces extreme score impact |
| Baseline/comparison | SimpleAverageAggregator | Transparent and simple |

### Escalation Triggers

Consider escalating to human-in-the-loop (HITL) when:

1. **Polarization detected**: Critics strongly disagree
2. **Low consensus**: `detect_consensus(votes, threshold=0.8)` returns False
3. **High entropy**: `compute_entropy(votes) > 1.5` (significant disagreement)
4. **High confidence variance**: Critics have very different certainty levels
5. **Low pass rate with high scores**: Scores are high but many critics failed it

## Architecture

### Protocol-Based Design

The `AggregationStrategy` is defined as a Protocol (structural typing), allowing easy extension:

```python
from typing import Protocol
from sw4rm.negotiation_types import NegotiationVote, AggregatedScore

class AggregationStrategy(Protocol):
    def aggregate(self, votes: list[NegotiationVote]) -> AggregatedScore:
        ...
```

### Custom Strategies

You can implement custom strategies by following the protocol:

```python
class CustomWeightedAggregator:
    def aggregate(self, votes: list[NegotiationVote]) -> AggregatedScore:
        # Your custom logic here
        pass

# Use it with VotingAggregator
aggregator = VotingAggregator(CustomWeightedAggregator())
```

## Integration with Negotiation Room

The voting module integrates seamlessly with the existing negotiation types:

```python
from sw4rm.negotiation_types import NegotiationDecision, DecisionOutcome
from sw4rm.voting import VotingAggregator, ConfidenceWeightedAggregator

# Aggregate votes
aggregator = VotingAggregator(ConfidenceWeightedAggregator())
aggregated_score = aggregator.aggregate(votes)

# Make decision
if aggregator.detect_polarization(votes):
    outcome = DecisionOutcome.ESCALATED_TO_HITL
    reason = "Critics are polarized - human review required"
elif aggregated_score.weighted_mean >= 7.0 and aggregator.detect_consensus(votes):
    outcome = DecisionOutcome.APPROVED
    reason = "Strong consensus with high scores"
else:
    outcome = DecisionOutcome.REVISION_REQUESTED
    reason = f"Weighted score {aggregated_score.weighted_mean:.2f} below threshold"

# Create decision
decision = NegotiationDecision(
    artifact_id=votes[0].artifact_id,
    outcome=outcome,
    votes=votes,
    aggregated_score=aggregated_score,
    policy_version="1.0",
    reason=reason,
    negotiation_room_id=votes[0].negotiation_room_id,
)
```

## Testing

The module includes comprehensive tests covering:

- All aggregation strategies
- Edge cases (empty votes, single vote, all same score, ties)
- Entropy calculation
- Consensus detection
- Polarization detection
- Confidence variance
- Many votes (100+)
- Extreme scores (0 and 10)

Run tests with:

```bash
pytest tests/test_voting_aggregation.py -v
```

## References

- **SPEC_REQUESTS.md**: Phase 3.4 - Confidence-Weighted Voting
- **POMDP Research**: Confidence levels based on belief state certainty
- **Borda Count**: Classical ranked voting system
- **Shannon Entropy**: Information-theoretic measure of uncertainty

## See Also

- `sw4rm.negotiation_types`: Core negotiation room types
- `examples/voting_example.py`: Comprehensive usage examples
- `tests/test_voting_aggregation.py`: Test suite
