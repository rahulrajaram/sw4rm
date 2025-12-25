"""Negotiation Room types for SW4RM.

This module provides dataclasses and enums for the Negotiation Room pattern,
enabling multi-agent artifact approval workflows. The pattern supports:
- Producer agents submitting artifacts for review
- Multiple critic agents evaluating artifacts against rubrics
- Coordinator agents aggregating scores and making approval decisions

Based on SPEC_REQUESTS.md section 6.1.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Any, Dict, List, Optional


class ArtifactType(Enum):
    """Type of artifact being negotiated.

    Maps to the artifact_type field in negotiation proposals to categorize
    what stage of the workflow the artifact belongs to.
    """
    ARTIFACT_TYPE_UNSPECIFIED = 0
    REQUIREMENTS = 1
    PLAN = 2
    CODE = 3
    DEPLOYMENT = 4


class DecisionOutcome(Enum):
    """Outcome of a negotiation decision.

    Represents the final decision made by the coordinator after aggregating
    critic votes and applying policy.
    """
    DECISION_OUTCOME_UNSPECIFIED = 0
    APPROVED = 1
    REVISION_REQUESTED = 2
    ESCALATED_TO_HITL = 3


@dataclass
class NegotiationProposal:
    """A proposal for artifact evaluation in a negotiation room.

    Submitted by a producer agent to request multi-agent review of an artifact.
    The proposal specifies which critics should evaluate the artifact and
    includes the artifact content for review.

    Attributes:
        artifact_type: Category of artifact (requirements, plan, code, deployment)
        artifact_id: Unique identifier for this artifact
        producer_id: Agent ID of the producer submitting the artifact
        artifact: Binary artifact content (e.g., serialized JSON, code files)
        artifact_content_type: MIME type or content type identifier
        requested_critics: List of critic agent IDs requested for evaluation
        negotiation_room_id: Identifier for the negotiation room session
        created_at: Timestamp when proposal was created (auto-set if None)
    """
    artifact_type: ArtifactType
    artifact_id: str
    producer_id: str
    artifact: bytes
    artifact_content_type: str
    requested_critics: List[str]
    negotiation_room_id: str
    created_at: Optional[datetime] = None

    def __post_init__(self) -> None:
        """Set created_at to now if not provided."""
        if self.created_at is None:
            object.__setattr__(self, "created_at", datetime.utcnow())

    def to_dict(self) -> Dict[str, Any]:
        """Convert proposal to dictionary representation.

        Returns:
            Dictionary with all proposal fields, suitable for JSON serialization.
            Binary artifact is base64-encoded, datetime is ISO-formatted.
        """
        import base64
        return {
            "artifact_type": self.artifact_type.name,
            "artifact_id": self.artifact_id,
            "producer_id": self.producer_id,
            "artifact": base64.b64encode(self.artifact).decode("utf-8"),
            "artifact_content_type": self.artifact_content_type,
            "requested_critics": self.requested_critics,
            "negotiation_room_id": self.negotiation_room_id,
            "created_at": self.created_at.isoformat() if self.created_at else None,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> NegotiationProposal:
        """Reconstruct proposal from dictionary representation.

        Args:
            data: Dictionary with proposal fields (from to_dict or similar source)

        Returns:
            NegotiationProposal instance
        """
        import base64
        artifact_type = ArtifactType[data["artifact_type"]]
        artifact = base64.b64decode(data["artifact"])
        created_at = datetime.fromisoformat(data["created_at"]) if data.get("created_at") else None

        return cls(
            artifact_type=artifact_type,
            artifact_id=data["artifact_id"],
            producer_id=data["producer_id"],
            artifact=artifact,
            artifact_content_type=data["artifact_content_type"],
            requested_critics=data["requested_critics"],
            negotiation_room_id=data["negotiation_room_id"],
            created_at=created_at,
        )


@dataclass
class NegotiationVote:
    """A critic's evaluation of an artifact.

    Represents a single critic's assessment including numerical scoring,
    qualitative feedback, and confidence level based on POMDP uncertainty.

    Attributes:
        artifact_id: Identifier of the artifact being evaluated
        critic_id: Agent ID of the critic providing this vote
        score: Numerical score from 0-10 (10 = excellent)
        confidence: Confidence level from 0-1 (based on POMDP research)
        passed: Boolean indicating if artifact meets minimum criteria
        strengths: List of identified strengths in the artifact
        weaknesses: List of identified weaknesses or concerns
        recommendations: List of suggestions for improvement
        negotiation_room_id: Identifier for the negotiation room session
        voted_at: Timestamp when vote was cast (auto-set if None)
    """
    artifact_id: str
    critic_id: str
    score: float
    confidence: float
    passed: bool
    strengths: List[str]
    weaknesses: List[str]
    recommendations: List[str]
    negotiation_room_id: str
    voted_at: Optional[datetime] = None

    def __post_init__(self) -> None:
        """Validate constraints and set voted_at if not provided."""
        if not (0.0 <= self.score <= 10.0):
            raise ValueError(f"score must be in range [0, 10], got {self.score}")
        if not (0.0 <= self.confidence <= 1.0):
            raise ValueError(f"confidence must be in range [0, 1], got {self.confidence}")
        if self.voted_at is None:
            object.__setattr__(self, "voted_at", datetime.utcnow())

    def to_dict(self) -> Dict[str, Any]:
        """Convert vote to dictionary representation.

        Returns:
            Dictionary with all vote fields, suitable for JSON serialization.
        """
        return {
            "artifact_id": self.artifact_id,
            "critic_id": self.critic_id,
            "score": self.score,
            "confidence": self.confidence,
            "passed": self.passed,
            "strengths": self.strengths,
            "weaknesses": self.weaknesses,
            "recommendations": self.recommendations,
            "negotiation_room_id": self.negotiation_room_id,
            "voted_at": self.voted_at.isoformat() if self.voted_at else None,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> NegotiationVote:
        """Reconstruct vote from dictionary representation.

        Args:
            data: Dictionary with vote fields (from to_dict or similar source)

        Returns:
            NegotiationVote instance
        """
        voted_at = datetime.fromisoformat(data["voted_at"]) if data.get("voted_at") else None

        return cls(
            artifact_id=data["artifact_id"],
            critic_id=data["critic_id"],
            score=data["score"],
            confidence=data["confidence"],
            passed=data["passed"],
            strengths=data["strengths"],
            weaknesses=data["weaknesses"],
            recommendations=data["recommendations"],
            negotiation_room_id=data["negotiation_room_id"],
            voted_at=voted_at,
        )


@dataclass
class AggregatedScore:
    """Statistical aggregation of multiple critic votes.

    Provides multiple views of the voting results including basic statistics
    and confidence-weighted metrics for decision making.

    Attributes:
        mean: Arithmetic mean of all scores
        min_score: Minimum score from any critic
        max_score: Maximum score from any critic
        std_dev: Standard deviation of scores (measures consensus)
        weighted_mean: Confidence-weighted mean (higher confidence votes weighted more)
        vote_count: Number of votes included in aggregation
    """
    mean: float
    min_score: float
    max_score: float
    std_dev: float
    weighted_mean: float
    vote_count: int

    def to_dict(self) -> Dict[str, Any]:
        """Convert aggregated score to dictionary representation.

        Returns:
            Dictionary with all aggregated score fields.
        """
        return {
            "mean": self.mean,
            "min_score": self.min_score,
            "max_score": self.max_score,
            "std_dev": self.std_dev,
            "weighted_mean": self.weighted_mean,
            "vote_count": self.vote_count,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> AggregatedScore:
        """Reconstruct aggregated score from dictionary representation.

        Args:
            data: Dictionary with aggregated score fields

        Returns:
            AggregatedScore instance
        """
        return cls(
            mean=data["mean"],
            min_score=data["min_score"],
            max_score=data["max_score"],
            std_dev=data["std_dev"],
            weighted_mean=data["weighted_mean"],
            vote_count=data["vote_count"],
        )


@dataclass
class NegotiationDecision:
    """Final decision on an artifact after critic evaluation.

    Represents the coordinator's decision after aggregating all critic votes
    and applying policy thresholds. Includes full audit trail of votes and
    reasoning.

    Attributes:
        artifact_id: Identifier of the artifact that was evaluated
        outcome: Final decision (approved, revision requested, escalated to HITL)
        votes: Complete list of all critic votes considered
        aggregated_score: Statistical summary of the votes
        policy_version: Version identifier of the policy used for decision
        reason: Human-readable explanation of the decision
        negotiation_room_id: Identifier for the negotiation room session
        decided_at: Timestamp when decision was made (auto-set if None)
    """
    artifact_id: str
    outcome: DecisionOutcome
    votes: List[NegotiationVote]
    aggregated_score: AggregatedScore
    policy_version: str
    reason: str
    negotiation_room_id: str
    decided_at: Optional[datetime] = None

    def __post_init__(self) -> None:
        """Set decided_at to now if not provided."""
        if self.decided_at is None:
            object.__setattr__(self, "decided_at", datetime.utcnow())

    def to_dict(self) -> Dict[str, Any]:
        """Convert decision to dictionary representation.

        Returns:
            Dictionary with all decision fields, suitable for JSON serialization.
        """
        return {
            "artifact_id": self.artifact_id,
            "outcome": self.outcome.name,
            "votes": [v.to_dict() for v in self.votes],
            "aggregated_score": self.aggregated_score.to_dict(),
            "policy_version": self.policy_version,
            "reason": self.reason,
            "negotiation_room_id": self.negotiation_room_id,
            "decided_at": self.decided_at.isoformat() if self.decided_at else None,
        }

    @classmethod
    def from_dict(cls, data: Dict[str, Any]) -> NegotiationDecision:
        """Reconstruct decision from dictionary representation.

        Args:
            data: Dictionary with decision fields (from to_dict or similar source)

        Returns:
            NegotiationDecision instance
        """
        outcome = DecisionOutcome[data["outcome"]]
        votes = [NegotiationVote.from_dict(v) for v in data["votes"]]
        aggregated_score = AggregatedScore.from_dict(data["aggregated_score"])
        decided_at = datetime.fromisoformat(data["decided_at"]) if data.get("decided_at") else None

        return cls(
            artifact_id=data["artifact_id"],
            outcome=outcome,
            votes=votes,
            aggregated_score=aggregated_score,
            policy_version=data["policy_version"],
            reason=data["reason"],
            negotiation_room_id=data["negotiation_room_id"],
            decided_at=decided_at,
        )


def aggregate_votes(votes: List[NegotiationVote]) -> AggregatedScore:
    """Aggregate multiple critic votes into statistical summary.

    Computes both basic statistics (mean, min, max, std dev) and a
    confidence-weighted mean that gives more weight to votes from critics
    with higher confidence levels.

    Args:
        votes: List of critic votes to aggregate

    Returns:
        AggregatedScore with statistical summary of votes

    Raises:
        ValueError: If votes list is empty
    """
    if not votes:
        raise ValueError("Cannot aggregate empty list of votes")

    scores = [v.score for v in votes]
    confidences = [v.confidence for v in votes]

    # Basic statistics
    mean = sum(scores) / len(scores)
    min_score = min(scores)
    max_score = max(scores)

    # Standard deviation
    variance = sum((s - mean) ** 2 for s in scores) / len(scores)
    std_dev = variance ** 0.5

    # Confidence-weighted mean
    # weight_i = confidence_i / sum(confidences)
    # weighted_mean = sum(score_i * weight_i)
    total_confidence = sum(confidences)
    if total_confidence > 0:
        weighted_mean = sum(s * c for s, c in zip(scores, confidences)) / total_confidence
    else:
        # Fallback to simple mean if all confidences are zero
        weighted_mean = mean

    return AggregatedScore(
        mean=mean,
        min_score=min_score,
        max_score=max_score,
        std_dev=std_dev,
        weighted_mean=weighted_mean,
        vote_count=len(votes),
    )
