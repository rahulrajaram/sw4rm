"""Policy-related dataclasses for the SchedulerPolicyService.

This module defines Python dataclasses for all policy-related types used
in the SW4RM scheduler policy service. These types correspond to the protobuf
definitions in policy.proto and scheduler_policy.proto.
"""

from __future__ import annotations

from dataclasses import dataclass, field, asdict
from typing import Any, Optional


@dataclass
class ScoringConfig:
    """Configuration for scoring during negotiation.

    Defines how proposals are scored and weighted during the negotiation process.

    Attributes:
        weights: Mapping of scoring dimension names to their weights.
        normalization: Normalization strategy (e.g., 'minmax', 'zscore', 'none').
    """

    weights: dict[str, float] = field(default_factory=dict)
    normalization: str = "none"

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> ScoringConfig:
        """Create from dictionary."""
        return cls(
            weights=data.get("weights", {}),
            normalization=data.get("normalization", "none"),
        )


@dataclass
class AgentPreferences:
    """Per-agent policy preferences.

    Advisory preferences that an agent can specify. The scheduler
    clamps these to the guardrails defined by the effective policy.

    Attributes:
        agent_id: Unique identifier for the agent.
        weight_overrides: Agent-specific weight overrides for scoring dimensions.
    """

    agent_id: str = ""
    weight_overrides: dict[str, float] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> AgentPreferences:
        """Create from dictionary."""
        return cls(
            agent_id=data.get("agent_id", ""),
            weight_overrides=data.get("weight_overrides", {}),
        )


@dataclass
class NegotiationPolicy:
    """Policy governing negotiation behavior.

    Defines the constraints and parameters for the negotiation process
    between agents.

    Attributes:
        max_rounds: Maximum number of negotiation rounds allowed.
        score_threshold: Minimum score (0..1) required for acceptance.
        diff_tolerance: Maximum allowed difference (0..1) between proposals.
        round_timeout_ms: Timeout in milliseconds for each round.
        token_budget_per_round: Maximum tokens allowed per round.
        total_token_budget: Total token budget for entire negotiation (None=unlimited).
        oscillation_limit: Maximum allowed proposal oscillations before termination.
        hitl_mode: Human-in-the-loop mode ('None', 'PauseBetweenRounds', 'PauseOnFinalAccept').
        scoring: Optional scoring configuration.
        agent_preferences: List of per-agent preferences.
    """

    max_rounds: int = 10
    score_threshold: float = 0.8
    diff_tolerance: float = 0.1
    round_timeout_ms: int = 30000
    token_budget_per_round: int = 4000
    total_token_budget: Optional[int] = None
    oscillation_limit: int = 3
    hitl_mode: str = "None"
    scoring: Optional[ScoringConfig] = None
    agent_preferences: list[AgentPreferences] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "max_rounds": self.max_rounds,
            "score_threshold": self.score_threshold,
            "diff_tolerance": self.diff_tolerance,
            "round_timeout_ms": self.round_timeout_ms,
            "token_budget_per_round": self.token_budget_per_round,
            "total_token_budget": self.total_token_budget,
            "oscillation_limit": self.oscillation_limit,
            "hitl_mode": self.hitl_mode,
            "scoring": self.scoring.to_dict() if self.scoring else None,
            "agent_preferences": [p.to_dict() for p in self.agent_preferences],
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> NegotiationPolicy:
        """Create from dictionary."""
        scoring_data = data.get("scoring")
        prefs_data = data.get("agent_preferences", [])

        return cls(
            max_rounds=data.get("max_rounds", 10),
            score_threshold=data.get("score_threshold", 0.8),
            diff_tolerance=data.get("diff_tolerance", 0.1),
            round_timeout_ms=data.get("round_timeout_ms", 30000),
            token_budget_per_round=data.get("token_budget_per_round", 4000),
            total_token_budget=data.get("total_token_budget"),
            oscillation_limit=data.get("oscillation_limit", 3),
            hitl_mode=data.get("hitl_mode", "None"),
            scoring=ScoringConfig.from_dict(scoring_data) if scoring_data else None,
            agent_preferences=[AgentPreferences.from_dict(p) for p in prefs_data],
        )


@dataclass
class ExecutionPolicy:
    """Policy governing task execution.

    Defines constraints and resource limits for executing tasks.

    Attributes:
        timeout_ms: Maximum execution time in milliseconds.
        max_retries: Maximum number of retry attempts.
        backoff: Backoff strategy (e.g., 'none', 'linear', 'exponential').
        worktree_required: Whether a worktree binding is required for execution.
        network_policy: Network access policy (e.g., 'none', 'restricted', 'full').
        privilege_level: Required privilege level (e.g., 'standard', 'elevated').
        budget_cpu_ms: CPU time budget in milliseconds.
        budget_wall_ms: Wall clock time budget in milliseconds.
    """

    timeout_ms: int = 60000
    max_retries: int = 3
    backoff: str = "exponential"
    worktree_required: bool = False
    network_policy: str = "restricted"
    privilege_level: str = "standard"
    budget_cpu_ms: int = 30000
    budget_wall_ms: int = 60000

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> ExecutionPolicy:
        """Create from dictionary."""
        return cls(
            timeout_ms=data.get("timeout_ms", 60000),
            max_retries=data.get("max_retries", 3),
            backoff=data.get("backoff", "exponential"),
            worktree_required=data.get("worktree_required", False),
            network_policy=data.get("network_policy", "restricted"),
            privilege_level=data.get("privilege_level", "standard"),
            budget_cpu_ms=data.get("budget_cpu_ms", 30000),
            budget_wall_ms=data.get("budget_wall_ms", 60000),
        )


@dataclass
class EscalationPolicy:
    """Policy governing escalation behavior.

    Defines when and how negotiations should be escalated.

    Attributes:
        auto_escalate_on_deadlock: Whether to automatically escalate when deadlock is detected.
        deadlock_rounds: Number of rounds without progress before declaring deadlock.
        escalation_reasons: List of valid reasons for escalation.
    """

    auto_escalate_on_deadlock: bool = True
    deadlock_rounds: int = 3
    escalation_reasons: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> EscalationPolicy:
        """Create from dictionary."""
        return cls(
            auto_escalate_on_deadlock=data.get("auto_escalate_on_deadlock", True),
            deadlock_rounds=data.get("deadlock_rounds", 3),
            escalation_reasons=data.get("escalation_reasons", []),
        )


@dataclass
class EffectivePolicy:
    """The authoritative policy derived for a negotiation.

    Combines base policy with any profile and agent overrides to produce
    the final effective policy used during negotiation.

    Attributes:
        policy_id: Unique identifier for this policy instance.
        version: Version string for the policy.
        negotiation: Negotiation policy settings.
        execution: Execution policy settings.
        escalation: Escalation policy settings.
    """

    policy_id: str = ""
    version: str = "1.0"
    negotiation: NegotiationPolicy = field(default_factory=NegotiationPolicy)
    execution: ExecutionPolicy = field(default_factory=ExecutionPolicy)
    escalation: EscalationPolicy = field(default_factory=EscalationPolicy)

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "policy_id": self.policy_id,
            "version": self.version,
            "negotiation": self.negotiation.to_dict(),
            "execution": self.execution.to_dict(),
            "escalation": self.escalation.to_dict(),
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> EffectivePolicy:
        """Create from dictionary."""
        return cls(
            policy_id=data.get("policy_id", ""),
            version=data.get("version", "1.0"),
            negotiation=NegotiationPolicy.from_dict(data.get("negotiation", {})),
            execution=ExecutionPolicy.from_dict(data.get("execution", {})),
            escalation=EscalationPolicy.from_dict(data.get("escalation", {})),
        )


@dataclass
class PolicyProfile:
    """A named policy profile.

    Represents a pre-configured policy profile that can be selected
    by name (e.g., LOW, MEDIUM, HIGH).

    Attributes:
        profile_id: Unique identifier for the profile.
        name: Human-readable name for the profile.
        description: Description of when to use this profile.
        policy: The effective policy for this profile.
        is_default: Whether this is the default profile.
    """

    profile_id: str = ""
    name: str = ""
    description: str = ""
    policy: EffectivePolicy = field(default_factory=EffectivePolicy)
    is_default: bool = False

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "profile_id": self.profile_id,
            "name": self.name,
            "description": self.description,
            "policy": self.policy.to_dict(),
            "is_default": self.is_default,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> PolicyProfile:
        """Create from dictionary."""
        return cls(
            profile_id=data.get("profile_id", ""),
            name=data.get("name", ""),
            description=data.get("description", ""),
            policy=EffectivePolicy.from_dict(data.get("policy", {})),
            is_default=data.get("is_default", False),
        )


@dataclass
class DeltaSummary:
    """Summary of changes between proposal versions.

    Tracks what changed between two versions of a proposal.

    Attributes:
        field_path: Dot-separated path to the changed field.
        old_value: Previous value as string.
        new_value: New value as string.
    """

    field_path: str = ""
    old_value: str = ""
    new_value: str = ""

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> DeltaSummary:
        """Create from dictionary."""
        return cls(
            field_path=data.get("field_path", ""),
            old_value=data.get("old_value", ""),
            new_value=data.get("new_value", ""),
        )


@dataclass
class EvaluationReport:
    """Report from evaluating a proposal.

    Contains the evaluation results from an agent reviewing a proposal.

    Attributes:
        negotiation_id: ID of the negotiation this evaluation belongs to.
        round_number: The round number when this evaluation was made.
        scores: Mapping of scoring dimension names to scores.
        summary: Human-readable summary of the evaluation.
        deltas: List of changes from previous version.
    """

    negotiation_id: str = ""
    round_number: int = 0
    scores: dict[str, float] = field(default_factory=dict)
    summary: str = ""
    deltas: list[DeltaSummary] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return {
            "negotiation_id": self.negotiation_id,
            "round_number": self.round_number,
            "scores": self.scores,
            "summary": self.summary,
            "deltas": [d.to_dict() for d in self.deltas],
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> EvaluationReport:
        """Create from dictionary."""
        deltas_data = data.get("deltas", [])
        return cls(
            negotiation_id=data.get("negotiation_id", ""),
            round_number=data.get("round_number", 0),
            scores=data.get("scores", {}),
            summary=data.get("summary", ""),
            deltas=[DeltaSummary.from_dict(d) for d in deltas_data],
        )


@dataclass
class DecisionReport:
    """Report of the final decision for a negotiation.

    Contains the outcome and rationale for ending a negotiation.

    Attributes:
        negotiation_id: ID of the negotiation this decision belongs to.
        outcome: The decision outcome (e.g., 'accepted', 'rejected', 'escalated').
        rationale: Explanation for the decision.
        policy_version: Version of the policy used for this decision.
    """

    negotiation_id: str = ""
    outcome: str = ""
    rationale: str = ""
    policy_version: str = ""

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for serialization."""
        return asdict(self)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> DecisionReport:
        """Create from dictionary."""
        return cls(
            negotiation_id=data.get("negotiation_id", ""),
            outcome=data.get("outcome", ""),
            rationale=data.get("rationale", ""),
            policy_version=data.get("policy_version", ""),
        )
