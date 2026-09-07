# Copyright 2025 Rahul Rajaram
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Parity tests for the Python quorum-policy port (SW4-001).

Mirrors the semantics of sdks/ex_sdk/lib/sw4rm/quorum_policy.ex so that
a Python fleet and an Elixir fleet reach the same decision on identical
vote sets.
"""

from __future__ import annotations

import math
import os
import subprocess
import sys

import pytest

from sw4rm.negotiation_types import NegotiationVote
from sw4rm.quorum_policy import (
    DecidedWithAbstains,
    DecidedWithAvailable,
    EscalateHitl,
    MinimumFraction,
    MinimumVotes,
    QuorumPolicy,
    RequireAll,
    default_policy,
    evaluate,
)


def test_runtime_neutral_package_accepts_mapping_without_sw4rm_dependency() -> None:
    from sw4rm_policies.quorum import MinimumVotes, QuorumPolicy, evaluate

    outcome = evaluate(
        [{"critic_id": "a"}], ["a", "b"], QuorumPolicy(MinimumVotes(1), "fail_closed")
    )
    assert outcome.met and outcome.votes_received == 1


def test_runtime_neutral_import_is_clean_interpreter() -> None:
    code = (
        "import sys; from sw4rm_policies import evaluate, default_policy; "
        "assert evaluate([{'critic_id': 'a'}], ['a'], default_policy()).met; "
        "assert not any(name == 'sw4rm' or name.startswith('sw4rm.') for name in sys.modules)"
    )
    env = dict(os.environ)
    env["PYTHONPATH"] = os.path.join(os.path.dirname(__file__), "..")
    subprocess.run([sys.executable, "-c", code], check=True, env=env)


def _vote(critic_id: str, score: float = 8.0, confidence: float = 0.9):
    return NegotiationVote(
        artifact_id="art-1",
        critic_id=critic_id,
        score=score,
        confidence=confidence,
        passed=score >= 5.0,
        strengths=[],
        weaknesses=[],
        recommendations=[],
        negotiation_room_id="room-1",
    )


CRITICS = ["critic-1", "critic-2", "critic-3", "critic-4"]


def test_default_policy_is_majority_fail_closed() -> None:
    policy = default_policy()
    assert policy.on_failure == "fail_closed"
    assert isinstance(policy.rule, MinimumFraction)
    assert policy.rule.fraction == 0.5


def test_minimum_votes_threshold() -> None:
    policy = QuorumPolicy(rule=MinimumVotes(2), on_failure="fail_closed")
    outcome = evaluate([_vote("critic-1"), _vote("critic-2")], CRITICS, policy)
    assert outcome.met and outcome.threshold == 2

    outcome = evaluate([_vote("critic-1")], CRITICS, policy)
    assert not outcome.met
    assert isinstance(outcome.action, EscalateHitl)


def test_minimum_fraction_threshold_is_ceiled() -> None:
    policy = QuorumPolicy(rule=MinimumFraction(0.5), on_failure="fail_closed")
    # 4 critics * 0.5 = 2.0 -> threshold 2
    outcome = evaluate([_vote("critic-1"), _vote("critic-2")], CRITICS, policy)
    assert outcome.met and outcome.threshold == 2

    # 3 critics * 0.5 = 1.5 -> ceil = 2
    outcome = evaluate([_vote("critic-1")], CRITICS[:3], policy)
    assert not outcome.met and outcome.threshold == 2


def test_require_all() -> None:
    policy_all = QuorumPolicy(rule=RequireAll(True), on_failure="fail_closed")
    assert evaluate([_vote(c) for c in CRITICS], CRITICS, policy_all).met
    assert not evaluate([_vote(c) for c in CRITICS[:3]], CRITICS, policy_all).met

    policy_off = QuorumPolicy(rule=RequireAll(False), on_failure="fail_closed")
    assert evaluate([], CRITICS, policy_off).met  # threshold 0


def test_votes_outside_requested_critics_do_not_count() -> None:
    policy = QuorumPolicy(rule=MinimumVotes(2), on_failure="fail_closed")
    votes = [_vote("critic-1"), _vote("unrequested-critic")]
    outcome = evaluate(votes, ["critic-1", "critic-2"], policy)
    assert not outcome.met
    assert outcome.votes_received == 1


def test_fail_closed_action() -> None:
    policy = QuorumPolicy(rule=MinimumVotes(3), on_failure="fail_closed")
    outcome = evaluate([_vote("critic-1")], CRITICS, policy)
    assert not outcome.met
    assert isinstance(outcome.action, EscalateHitl)
    assert "HITL" in outcome.action.reason


def test_fail_with_abstain_injects_missing_critics() -> None:
    policy = QuorumPolicy(rule=MinimumVotes(4), on_failure="fail_with_abstain")
    votes = [_vote("critic-1"), _vote("critic-2")]
    outcome = evaluate(votes, CRITICS, policy)
    assert not outcome.met
    assert isinstance(outcome.action, DecidedWithAbstains)
    injected = outcome.action.injected_votes
    assert {v["critic_id"] for v in injected} == {"critic-3", "critic-4"}
    assert all(v["abstain"] and v["score"] == 0.0 for v in injected)
    # all_votes carries received + abstains for downstream aggregation
    assert outcome.all_votes == votes + injected
    assert len(outcome.all_votes) == 4


def test_fail_with_available_decides_on_received() -> None:
    policy = QuorumPolicy(rule=MinimumVotes(4), on_failure="fail_with_available")
    votes = [_vote("critic-1"), _vote("critic-2")]
    outcome = evaluate(votes, CRITICS, policy)
    assert not outcome.met
    assert isinstance(outcome.action, DecidedWithAvailable)
    assert outcome.all_votes == votes


def test_unknown_rule_and_action_raise() -> None:
    policy = QuorumPolicy(rule=object(), on_failure="fail_closed")
    with pytest.raises(ValueError):
        evaluate([_vote("critic-1")], CRITICS, policy)
    # R44: the failure action is validated eagerly at construction now, not
    # only when the quorum is missed.
    with pytest.raises(ValueError):
        QuorumPolicy(rule=MinimumVotes(1), on_failure="bogus")
    with pytest.raises(ValueError):
        QuorumPolicy(rule=MinimumVotes(1), on_failure=None)
