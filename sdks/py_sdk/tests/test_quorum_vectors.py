"""Cross-SDK threshold and failure-action contract."""
import json
from pathlib import Path

import pytest
from sw4rm_policies.quorum import (
    DecidedWithAbstains, DecidedWithAvailable, EscalateHitl,
    MinimumVotes, MinimumFraction, RequireAll, QuorumPolicy, evaluate,
)

VECTORS = json.loads((Path(__file__).resolve().parents[3] / 'tests/conformance_vectors/quorum_vectors.json').read_text())['vectors']


@pytest.mark.parametrize('vector', VECTORS, ids=lambda vector: vector['id'])
def test_quorum_shared_contract(vector):
    constructors = {'minimum_votes': MinimumVotes, 'minimum_fraction': MinimumFraction, 'require_all': RequireAll}
    rule = constructors[vector['rule']['kind']](vector['rule']['value'])
    outcome = evaluate(vector['votes'], vector['requested'], QuorumPolicy(rule, vector['on_failure']))
    action_names = {type(None): 'none', EscalateHitl: 'escalate_hitl', DecidedWithAbstains: 'decided_with_abstains', DecidedWithAvailable: 'decided_with_available'}
    injected = outcome.action.injected_votes if isinstance(outcome.action, DecidedWithAbstains) else []
    assert {
        'met': outcome.met, 'received': outcome.votes_received, 'expected': outcome.votes_expected,
        'threshold': outcome.threshold, 'action': action_names[type(outcome.action)],
        'injected': [v['critic_id'] for v in injected], 'all_vote_count': len(outcome.all_votes),
    } == vector['expected']
    assert all(v['score'] == 0 and v['confidence'] == 0 and v['abstain'] and not v['passed'] for v in injected)
