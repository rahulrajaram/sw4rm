# SW4-001: Failure Semantics Extension

**Status:** Draft
**Version:** 0.1.0
**Date:** 2026-01-10
**Extends:** Core Spec §17.5 (Negotiation Room Pattern)

## Abstract

This extension defines normative failure semantics for SW4RM coordination primitives, specifically addressing quorum rules, partition handling, and timeout behavior for the Negotiation Room pattern. These semantics are OPTIONAL for implementations but REQUIRED for production deployments requiring deterministic behavior under partial failure.

## Motivation

The core specification (§17.5) defines the Negotiation Room pattern but leaves failure behavior undefined:

- What happens when a requested critic is unreachable?
- How long does the Coordinator wait for votes before deciding?
- What constitutes a valid decision when not all critics respond?
- How should implementations handle network partitions?

Without answers, implementations exhibit nondeterministic behavior under real-world conditions.

## Terminology

**Quorum**: The minimum number of votes required to render a valid decision.

**Vote Collection Window**: The maximum duration the Coordinator waits for votes after proposal submission.

**Abstain**: A synthetic vote indicating a critic did not respond within the collection window.

**Fail-Closed**: Behavior where insufficient votes result in automatic rejection/escalation rather than proceeding with partial information.

**Fail-Open**: Behavior where insufficient votes result in proceeding with available votes (not recommended for production).

## 1. Quorum Semantics

### 1.1. Quorum Configuration

Implementations conforming to this extension MUST support configurable quorum rules per negotiation room:

```protobuf
message QuorumPolicy {
  oneof rule {
    uint32 minimum_votes = 1;      // Absolute minimum vote count
    float minimum_fraction = 2;    // Fraction of requested critics (0.0-1.0)
    bool require_all = 3;          // All requested critics must vote
  }
  QuorumFailureAction on_failure = 4;
}

enum QuorumFailureAction {
  QUORUM_FAIL_CLOSED = 0;         // Escalate to HITL if quorum not met
  QUORUM_FAIL_WITH_ABSTAIN = 1;   // Treat missing votes as abstain (score=0, confidence=0)
  QUORUM_FAIL_WITH_AVAILABLE = 2; // Decide with available votes (fail-open, NOT RECOMMENDED)
}
```

### 1.2. Default Quorum Behavior

Implementations MUST default to:

- `minimum_fraction = 0.5` (majority of requested critics)
- `on_failure = QUORUM_FAIL_CLOSED`

### 1.3. Quorum Evaluation

The Coordinator MUST evaluate quorum after the vote collection window closes:

1. Count received votes from requested critics
2. Compare against quorum threshold
3. If quorum met: proceed to decision
4. If quorum not met: apply `QuorumFailureAction`

## 2. Vote Collection Timeout

### 2.1. Collection Window Configuration

Implementations MUST support a configurable vote collection window:

```protobuf
message NegotiationProposal {
  // ... existing fields ...

  // Extension fields (SW4-001)
  uint32 vote_collection_timeout_s = 100;  // Default: 300 (5 minutes)
  QuorumPolicy quorum_policy = 101;
}
```

### 2.2. Timeout Behavior

When the vote collection window expires:

1. The Coordinator MUST stop accepting new votes for the proposal
2. The Coordinator MUST evaluate quorum with votes received
3. Late-arriving votes MUST be logged but NOT included in the decision
4. The decision MUST include `collection_timeout_reached = true` if window expired

### 2.3. Recommended Timeout Values

| Artifact Type | Recommended Timeout | Rationale |
|---------------|---------------------|-----------|
| REQUIREMENTS  | 600s (10 min)       | Complex review, multiple stakeholders |
| PLAN          | 600s (10 min)       | Architectural review requires thought |
| CODE          | 300s (5 min)        | Automated analysis + human spot-check |
| DEPLOYMENT    | 180s (3 min)        | Often automated validation |

## 3. Partition Handling

### 3.1. Critic Unavailability Detection

Implementations MUST detect critic unavailability through:

1. **Registration check**: Critic not registered in Registry
2. **Health check failure**: Critic registered but unhealthy
3. **Vote timeout**: Critic registered and healthy but did not respond

### 3.2. Unavailability Response

For each unavailable critic, the Coordinator MUST:

1. Log the unavailability with reason and timestamp
2. Apply the configured `QuorumFailureAction`
3. Include unavailability details in the decision audit trail

### 3.3. Partition Recovery

If a critic becomes available after collection window closes:

1. The critic MAY submit a vote (for audit purposes)
2. The vote MUST NOT affect the rendered decision
3. The vote SHOULD be logged as `late_vote` for post-hoc analysis

## 4. Decision Consistency Guarantees

### 4.1. Coordinator Guarantees

The Coordinator MUST provide the following consistency guarantees:

1. **At-most-once decision**: Each proposal receives at most one decision
2. **Decision immutability**: Once rendered, a decision MUST NOT change
3. **Vote inclusion**: All votes received before collection window close MUST be included
4. **Audit completeness**: The decision record MUST include all inputs and the decision rationale

### 4.2. Decision Record Extension

```protobuf
message NegotiationDecision {
  // ... existing fields ...

  // Extension fields (SW4-001)
  bool quorum_met = 100;
  uint32 votes_received = 101;
  uint32 votes_expected = 102;
  bool collection_timeout_reached = 103;
  repeated string unavailable_critics = 104;
  repeated LateVote late_votes = 105;
}

message LateVote {
  string critic_id = 1;
  NegotiationVote vote = 2;
  google.protobuf.Timestamp received_at = 3;
}
```

## 5. Implementation Requirements

### 5.1. MUST Requirements

Implementations conforming to SW4-001 MUST:

1. Support configurable quorum policies
2. Enforce vote collection timeouts
3. Detect and handle critic unavailability
4. Provide complete audit trails for decisions
5. Default to fail-closed behavior

### 5.2. SHOULD Requirements

Implementations SHOULD:

1. Expose metrics for quorum success/failure rates
2. Alert operators when quorum failures exceed thresholds
3. Support dynamic quorum adjustment based on critic availability
4. Provide health endpoints indicating coordination readiness

### 5.3. MAY Requirements

Implementations MAY:

1. Support weighted quorum (some critics' votes count more)
2. Implement optimistic early decision (if quorum met before timeout)
3. Support hierarchical escalation (fail to senior critic before HITL)

## 6. Compatibility

This extension is backward-compatible with core spec §17.5. Implementations not conforming to SW4-001:

- Will exhibit undefined behavior under partial failure
- SHOULD document their failure behavior explicitly
- MUST NOT claim SW4-001 conformance

## 7. Security Considerations

Quorum manipulation attacks:

- Malicious actors could attempt to prevent quorum by DoS-ing critics
- Implementations SHOULD monitor for availability patterns indicating attack
- Fail-closed behavior limits damage from quorum manipulation

## 8. References

- Core Spec §17.5: Negotiation Room Pattern
- Core Spec §6: Identity and Security
- Core Spec §15: Human-In-The-Loop

---

*This extension is part of the SW4RM protocol extension series.*
