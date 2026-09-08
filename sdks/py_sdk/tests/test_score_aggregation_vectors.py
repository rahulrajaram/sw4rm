"""The same numeric contract is consumed by all five SDK suites."""
from dataclasses import asdict
import json
from pathlib import Path

import pytest
from sw4rm_policies.aggregation import aggregate_votes

VECTORS = json.loads((Path(__file__).resolve().parents[3] / 'tests/conformance_vectors/score_aggregation_vectors.json').read_text())['vectors']


@pytest.mark.parametrize('vector', VECTORS, ids=lambda vector: vector['id'])
def test_score_summary_shared_contract(vector):
    if 'error' in vector:
        with pytest.raises(ValueError):
            aggregate_votes(vector['votes'])
    else:
        assert asdict(aggregate_votes(vector['votes'])) == pytest.approx(vector['expected'])
