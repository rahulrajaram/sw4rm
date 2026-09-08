"""Identical operation bytes must produce the same token in every SDK."""
import json
from pathlib import Path

import pytest
from sw4rm.envelope import compute_idempotency_token

VECTORS = json.loads((Path(__file__).resolve().parents[3]
                     / 'tests/conformance_vectors/idempotency_vectors.json').read_text())['vectors']


@pytest.mark.parametrize('vector', VECTORS, ids=lambda v: v['id'])
def test_portable_idempotency(vector):
    if vector.get('rejected'):
        # R43: LF in producer/operation must be rejected, not hashed.
        with pytest.raises(ValueError):
            compute_idempotency_token(vector['producer_id'], vector['operation'],
                                      bytes.fromhex(vector['canonical_hex']))
        return
    assert compute_idempotency_token(vector['producer_id'], vector['operation'],
                                     bytes.fromhex(vector['canonical_hex'])) == vector['token']
