# Copyright 2025 Rahul Rajaram
# Licensed under the Apache License, Version 2.0.
"""Runtime-neutral vote aggregation primitives."""
from dataclasses import dataclass
from collections.abc import Mapping
from typing import Any, Sequence


@dataclass(frozen=True)
class ScoreSummary:
    """Immutable descriptive and confidence-weighted vote statistics."""

    mean: float
    min_score: float
    max_score: float
    std_dev: float
    weighted_mean: float
    vote_count: int


def _value(vote: Any, name: str) -> Any:
    return vote[name] if isinstance(vote, Mapping) else getattr(vote, name)


def aggregate_votes(votes: Sequence[Any]) -> ScoreSummary:
    """Aggregate non-empty votes using scores and confidence weights."""
    if not votes:
        raise ValueError("Cannot aggregate empty list of votes")
    scores = [_value(v, "score") for v in votes]
    confidences = [_value(v, "confidence") for v in votes]
    mean = sum(scores) / len(scores)
    std_dev = _population_stddev(scores)
    total = sum(confidences)
    weighted_mean = (
        sum(s * c for s, c in zip(scores, confidences)) / total if total > 0 else mean
    )
    return ScoreSummary(
        mean, min(scores), max(scores), std_dev, weighted_mean, len(votes)
    )


def _population_stddev(values: Sequence[float]) -> float:
    """Return population standard deviation, or zero for empty values."""
    if not values:
        return 0.0
    mean = sum(values) / len(values)
    variance = sum((value - mean) ** 2 for value in values) / len(values)
    return variance**0.5


__all__ = ["ScoreSummary", "aggregate_votes"]
