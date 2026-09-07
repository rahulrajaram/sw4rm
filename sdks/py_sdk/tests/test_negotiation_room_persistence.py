"""NegotiationRoom durability tests (campaign crash-conformance S1 family).

Invariants:
- S1: a proposal plus the votes accepted before a process kill survive the
  kill; after restart, vote submission continues and the decision is
  computed from surviving votes — never from a silently empty room.
- Write-through: an RPC that returned success has its row on disk.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

pytest.importorskip("grpc")

sys.path.insert(0, str(Path(__file__).parent.parent / "reference-services" / "coordination"))

from sw4rm.protos import negotiation_room_pb2  # noqa: E402
from negotiation_room_state_store import NegotiationRoomStateStore  # noqa: E402


def _db(tmp_path: Path) -> str:
    return str(tmp_path / "negotiation_room.sqlite3")


def _make_room(tmp_path: Path):
    from negotiation_room_service import NegotiationRoomServiceImpl

    return NegotiationRoomServiceImpl(db_path=_db(tmp_path))


def _proposal(artifact_id: str):
    return negotiation_room_pb2.NegotiationProposal(
        artifact_id=artifact_id,
        negotiation_room_id="room-1",
        producer_id="producer-1",
    )


def _vote(artifact_id: str, critic_id: str, score: float = 8.0, confidence: float = 0.9):
    return negotiation_room_pb2.NegotiationVote(
        artifact_id=artifact_id,
        critic_id=critic_id,
        score=score,
        confidence=confidence,
    )


class _Ctx:
    """Minimal ServicerContext stand-in that records gRPC errors."""

    def __init__(self):
        self.code = None
        self.details = None

    def set_code(self, code):
        self.code = code

    def set_details(self, details):
        self.details = details


def test_s1_state_survives_kill_mid_vote_collection(tmp_path: Path) -> None:
    room = _make_room(tmp_path)
    ctx = _Ctx()

    resp = room.SubmitProposal(
        negotiation_room_pb2.SubmitProposalRequest(proposal=_proposal("art-1")), ctx
    )
    assert resp.artifact_id == "art-1"

    # Two critics vote before the "kill".
    for critic in ("critic-1", "critic-2"):
        r = room.SubmitVote(
            negotiation_room_pb2.SubmitVoteRequest(
                vote=_vote("art-1", critic)
            ),
            ctx,
        )
        assert r.artifact_id == "art-1"

    del room  # SIGKILL equivalent: nothing flushed explicitly, WAL committed

    # New process: state replays from the store.
    room2 = _make_room(tmp_path)
    ctx2 = _Ctx()

    # The proposal is visible.
    got = room2.get_proposal("art-1")
    assert got is not None and got.artifact_id == "art-1"

    # Both pre-kill votes survived.
    votes = room2.GetVotes(
        negotiation_room_pb2.GetVotesRequest(artifact_id="art-1"), ctx2
    )
    assert {v.critic_id for v in votes.votes} == {"critic-1", "critic-2"}

    # The pre-kill duplicate-vote guard still holds across restart.
    dup = room2.SubmitVote(
        negotiation_room_pb2.SubmitVoteRequest(vote=_vote("art-1", "critic-1")),
        ctx2,
    )
    assert ctx2.code is not None  # ALREADY_EXISTS

    # A third critic votes post-restart; decision work continues normally.
    ctx3 = _Ctx()
    r = room2.SubmitVote(
        negotiation_room_pb2.SubmitVoteRequest(vote=_vote("art-1", "critic-3")),
        ctx3,
    )
    assert r.artifact_id == "art-1" and ctx3.code is None

    # Decision storage works on the replayed state.
    assert room2.store_decision(
        negotiation_room_pb2.NegotiationDecision(
            artifact_id="art-1",
            outcome=negotiation_room_pb2.APPROVED,
        )
    )
    d = room2.GetDecision(
        negotiation_room_pb2.GetDecisionRequest(artifact_id="art-1"), _Ctx()
    )
    assert d.decision.outcome == negotiation_room_pb2.APPROVED


def test_write_through_rows_are_on_disk_after_rpc_returns(tmp_path: Path) -> None:
    """The store file holds rows immediately after successful RPCs."""
    room = _make_room(tmp_path)
    room.SubmitProposal(
        negotiation_room_pb2.SubmitProposalRequest(proposal=_proposal("art-2")), _Ctx()
    )
    room.SubmitVote(
        negotiation_room_pb2.SubmitVoteRequest(vote=_vote("art-2", "critic-9")), _Ctx()
    )

    store = NegotiationRoomStateStore(_db(tmp_path))
    assert "art-2" in store.load_proposals()
    votes = store.load_votes()
    assert [c for c, _ in votes.get("art-2", [])] == ["critic-9"]
    assert store.load_decisions() == {}


def test_clear_all_clears_persistence(tmp_path: Path) -> None:
    room = _make_room(tmp_path)
    room.SubmitProposal(
        negotiation_room_pb2.SubmitProposalRequest(proposal=_proposal("art-3")), _Ctx()
    )
    room.clear_all()
    store = NegotiationRoomStateStore(_db(tmp_path))
    assert store.load_proposals() == {}
    assert store.load_votes() == {}
