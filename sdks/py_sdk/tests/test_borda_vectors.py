"""Cross-SDK Borda count conformance vectors (R22).

Pins identical score-derived Borda outputs across the Python, JavaScript,
and Rust SDKs. The Lisp and Elixir SDKs implement classic Borda over ranked
preference lists (a distinct input format) and are intentionally not part
of this scored-vote corpus.
"""
import json
from pathlib import Path

import pytest

from sw4rm.negotiation_types import NegotiationVote
from sw4rm.voting.strategies import BordaCountAggregator

VECTORS = json.loads(
    (Path(__file__).resolve().parents[3] / "tests/conformance_vectors/borda_vectors.json")
    .read_text()
)["vectors"]


def _vote(entry: dict) -> NegotiationVote:
    return NegotiationVote(
        artifact_id="conformance",
        critic_id=entry["critic_id"],
        score=entry["score"],
        confidence=1.0,
        passed=True,
        strengths=[],
        weaknesses=[],
        recommendations=[],
        negotiation_room_id="conformance",
    )


@pytest.mark.parametrize("vector", VECTORS, ids=lambda vector: vector["id"])
def test_borda_vectors(vector):
    outcome = BordaCountAggregator().aggregate([_vote(v) for v in vector["votes"]])
    expected = vector["expected"]
    assert outcome.weighted_mean == pytest.approx(expected["weighted_mean"], abs=1e-9)
    assert outcome.mean == pytest.approx(expected["mean"], abs=1e-9)
    assert outcome.std_dev == pytest.approx(expected["std_dev"], abs=1e-9)
    assert outcome.min_score == expected["min_score"]
    assert outcome.max_score == expected["max_score"]
    assert outcome.vote_count == expected["vote_count"]


def test_borda_output_depends_on_scores_not_just_count():
    """Same vote count, different scores -> different output (R22 regression)."""
    aggregator = BordaCountAggregator()
    by_scores = {}
    for scores in ([9.0, 9.0, 9.0], [1.0, 1.0, 1.0]):
        outcome = aggregator.aggregate([_vote({"critic_id": f"c{i}", "score": s})
                                       for i, s in enumerate(scores)])
        by_scores[tuple(scores)] = outcome.weighted_mean
    assert by_scores[(9.0, 9.0, 9.0)] != by_scores[(1.0, 1.0, 1.0)]
