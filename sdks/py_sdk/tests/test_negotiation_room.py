"""Tests for Negotiation Room pattern implementation.

This module tests the NegotiationRoomClient and NegotiationCoordinator classes
that implement the multi-agent artifact approval workflow described in
SPEC_REQUESTS.md section 6.1.
"""
import time
from threading import Thread

import pytest

from sw4rm.clients.negotiation_room import NegotiationRoomClient
from sw4rm.negotiation_coordinator import NegotiationCoordinator
from sw4rm.negotiation_types import (
    ArtifactType,
    DecisionOutcome,
    NegotiationProposal,
    NegotiationVote,
    NegotiationDecision,
    aggregate_votes,
)
from sw4rm.policy_types import NegotiationPolicy


# Test Fixtures


@pytest.fixture
def client():
    """Create a fresh NegotiationRoomClient for each test."""
    return NegotiationRoomClient()


@pytest.fixture
def coordinator():
    """Create a fresh NegotiationCoordinator for each test."""
    return NegotiationCoordinator()


@pytest.fixture
def sample_proposal():
    """Create a sample artifact proposal."""
    return NegotiationProposal(
        artifact_type=ArtifactType.CODE,
        artifact_id="code-123",
        producer_id="agent-producer",
        artifact=b"def hello(): return 'world'",
        artifact_content_type="text/x-python",
        requested_critics=["critic-1", "critic-2", "critic-3"],
        negotiation_room_id="room-1",
    )


@pytest.fixture
def sample_policy():
    """Create a sample negotiation policy."""
    return NegotiationPolicy(
        max_rounds=10,
        score_threshold=0.8,  # 0-1 scale (8.0 on 0-10 scale)
        diff_tolerance=0.1,   # 0-1 scale (1.0 on 0-10 scale)
        round_timeout_ms=30000,
    )


# NegotiationRoomClient Tests


class TestNegotiationRoomClient:
    """Tests for the NegotiationRoomClient class."""

    def test_submit_proposal_success(self, client, sample_proposal):
        """Test successful proposal submission."""
        artifact_id = client.submit_proposal(sample_proposal)
        assert artifact_id == "code-123"

        # Verify proposal is stored
        proposal = client.get_proposal("code-123")
        assert proposal is not None
        assert proposal.artifact_id == "code-123"
        assert proposal.producer_id == "agent-producer"

    def test_submit_proposal_duplicate_fails(self, client, sample_proposal):
        """Test that submitting duplicate proposal fails."""
        client.submit_proposal(sample_proposal)

        with pytest.raises(ValueError, match="already exists"):
            client.submit_proposal(sample_proposal)

    def test_submit_vote_success(self, client, sample_proposal):
        """Test successful vote submission."""
        client.submit_proposal(sample_proposal)

        vote = NegotiationVote(
            artifact_id="code-123",
            critic_id="critic-1",
            score=8.5,
            confidence=0.9,
            passed=True,
            strengths=["Well-structured", "Clear logic"],
            weaknesses=["Missing docstring"],
            recommendations=["Add type hints"],
            negotiation_room_id="room-1",
        )

        client.submit_vote(vote)

        # Verify vote is stored
        votes = client.get_votes("code-123")
        assert len(votes) == 1
        assert votes[0].critic_id == "critic-1"
        assert votes[0].score == 8.5

    def test_submit_vote_no_proposal_fails(self, client):
        """Test that voting without a proposal fails."""
        vote = NegotiationVote(
            artifact_id="nonexistent",
            critic_id="critic-1",
            score=8.5,
            confidence=0.9,
            passed=True,
            strengths=[],
            weaknesses=[],
            recommendations=[],
            negotiation_room_id="room-1",
        )

        with pytest.raises(ValueError, match="No proposal found"):
            client.submit_vote(vote)

    def test_submit_vote_duplicate_critic_fails(self, client, sample_proposal):
        """Test that a critic can only vote once."""
        client.submit_proposal(sample_proposal)

        vote1 = NegotiationVote(
            artifact_id="code-123",
            critic_id="critic-1",
            score=8.5,
            confidence=0.9,
            passed=True,
            strengths=[],
            weaknesses=[],
            recommendations=[],
            negotiation_room_id="room-1",
        )
        client.submit_vote(vote1)

        vote2 = NegotiationVote(
            artifact_id="code-123",
            critic_id="critic-1",  # Same critic
            score=9.0,
            confidence=0.95,
            passed=True,
            strengths=[],
            weaknesses=[],
            recommendations=[],
            negotiation_room_id="room-1",
        )

        with pytest.raises(ValueError, match="already voted"):
            client.submit_vote(vote2)

    def test_get_votes_empty(self, client, sample_proposal):
        """Test getting votes when none exist yet."""
        client.submit_proposal(sample_proposal)

        votes = client.get_votes("code-123")
        assert votes == []

    def test_get_votes_multiple(self, client, sample_proposal):
        """Test getting multiple votes."""
        client.submit_proposal(sample_proposal)

        for i, critic_id in enumerate(["critic-1", "critic-2", "critic-3"]):
            vote = NegotiationVote(
                artifact_id="code-123",
                critic_id=critic_id,
                score=8.0 + i * 0.5,
                confidence=0.9,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            )
            client.submit_vote(vote)

        votes = client.get_votes("code-123")
        assert len(votes) == 3
        assert {v.critic_id for v in votes} == {"critic-1", "critic-2", "critic-3"}

    def test_get_decision_none(self, client, sample_proposal):
        """Test getting decision when none exists."""
        client.submit_proposal(sample_proposal)

        decision = client.get_decision("code-123")
        assert decision is None

    def test_store_and_get_decision(self, client, sample_proposal):
        """Test storing and retrieving a decision."""
        client.submit_proposal(sample_proposal)

        votes = [
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-1",
                score=9.0,
                confidence=0.9,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            )
        ]

        aggregated = aggregate_votes(votes)
        decision = NegotiationDecision(
            artifact_id="code-123",
            outcome=DecisionOutcome.APPROVED,
            votes=votes,
            aggregated_score=aggregated,
            policy_version="1.0",
            reason="Meets all criteria",
            negotiation_room_id="room-1",
        )

        client.store_decision(decision)

        retrieved = client.get_decision("code-123")
        assert retrieved is not None
        assert retrieved.outcome == DecisionOutcome.APPROVED
        assert retrieved.artifact_id == "code-123"

    def test_store_decision_duplicate_fails(self, client, sample_proposal):
        """Test that storing duplicate decision fails."""
        client.submit_proposal(sample_proposal)

        votes = [
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-1",
                score=9.0,
                confidence=0.9,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            )
        ]

        aggregated = aggregate_votes(votes)
        decision = NegotiationDecision(
            artifact_id="code-123",
            outcome=DecisionOutcome.APPROVED,
            votes=votes,
            aggregated_score=aggregated,
            policy_version="1.0",
            reason="Meets all criteria",
            negotiation_room_id="room-1",
        )

        client.store_decision(decision)

        with pytest.raises(ValueError, match="Decision already exists"):
            client.store_decision(decision)

    def test_wait_for_decision_success(self, client, sample_proposal):
        """Test waiting for a decision that arrives."""
        client.submit_proposal(sample_proposal)

        votes = [
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-1",
                score=9.0,
                confidence=0.9,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            )
        ]

        aggregated = aggregate_votes(votes)
        decision = NegotiationDecision(
            artifact_id="code-123",
            outcome=DecisionOutcome.APPROVED,
            votes=votes,
            aggregated_score=aggregated,
            policy_version="1.0",
            reason="Meets all criteria",
            negotiation_room_id="room-1",
        )

        # Store decision in background after a short delay
        def store_later():
            time.sleep(0.2)
            client.store_decision(decision)

        thread = Thread(target=store_later)
        thread.start()

        # Wait for decision
        result = client.wait_for_decision("code-123", timeout_s=2.0)
        assert result.outcome == DecisionOutcome.APPROVED

        thread.join()

    def test_wait_for_decision_timeout(self, client, sample_proposal):
        """Test waiting for a decision that never arrives."""
        client.submit_proposal(sample_proposal)

        with pytest.raises(TimeoutError, match="No decision made"):
            client.wait_for_decision("code-123", timeout_s=0.3)

    def test_list_proposals_all(self, client):
        """Test listing all proposals."""
        proposal1 = NegotiationProposal(
            artifact_type=ArtifactType.CODE,
            artifact_id="code-1",
            producer_id="producer-1",
            artifact=b"code1",
            artifact_content_type="text/x-python",
            requested_critics=["critic-1"],
            negotiation_room_id="room-1",
        )
        proposal2 = NegotiationProposal(
            artifact_type=ArtifactType.PLAN,
            artifact_id="plan-1",
            producer_id="producer-2",
            artifact=b"plan1",
            artifact_content_type="text/plain",
            requested_critics=["critic-2"],
            negotiation_room_id="room-2",
        )

        client.submit_proposal(proposal1)
        client.submit_proposal(proposal2)

        proposals = client.list_proposals()
        assert len(proposals) == 2
        assert {p.artifact_id for p in proposals} == {"code-1", "plan-1"}

    def test_list_proposals_filtered(self, client):
        """Test listing proposals filtered by room."""
        proposal1 = NegotiationProposal(
            artifact_type=ArtifactType.CODE,
            artifact_id="code-1",
            producer_id="producer-1",
            artifact=b"code1",
            artifact_content_type="text/x-python",
            requested_critics=["critic-1"],
            negotiation_room_id="room-1",
        )
        proposal2 = NegotiationProposal(
            artifact_type=ArtifactType.PLAN,
            artifact_id="plan-1",
            producer_id="producer-2",
            artifact=b"plan1",
            artifact_content_type="text/plain",
            requested_critics=["critic-2"],
            negotiation_room_id="room-2",
        )

        client.submit_proposal(proposal1)
        client.submit_proposal(proposal2)

        room1_proposals = client.list_proposals(negotiation_room_id="room-1")
        assert len(room1_proposals) == 1
        assert room1_proposals[0].artifact_id == "code-1"


# NegotiationCoordinator Tests


class TestNegotiationCoordinator:
    """Tests for the NegotiationCoordinator class."""

    def test_apply_policy_approved(self, coordinator, sample_policy):
        """Test approval when score exceeds threshold."""
        from sw4rm.negotiation_types import AggregatedScore

        scores = AggregatedScore(
            mean=9.0,
            min_score=8.5,
            max_score=9.5,
            std_dev=0.5,  # Low variance
            weighted_mean=9.0,
            vote_count=3,
        )

        outcome = coordinator.apply_policy(scores, sample_policy)
        assert outcome == DecisionOutcome.APPROVED

    def test_apply_policy_revision_requested(self, coordinator, sample_policy):
        """Test revision request when score below threshold."""
        from sw4rm.negotiation_types import AggregatedScore

        scores = AggregatedScore(
            mean=6.0,
            min_score=5.5,
            max_score=6.5,
            std_dev=0.5,  # Low variance
            weighted_mean=6.0,
            vote_count=3,
        )

        outcome = coordinator.apply_policy(scores, sample_policy)
        assert outcome == DecisionOutcome.REVISION_REQUESTED

    def test_apply_policy_escalated_high_variance(self, coordinator, sample_policy):
        """Test escalation when variance is high."""
        from sw4rm.negotiation_types import AggregatedScore

        scores = AggregatedScore(
            mean=7.0,
            min_score=3.0,
            max_score=9.0,
            std_dev=2.5,  # High variance > diff_tolerance * 10
            weighted_mean=7.0,
            vote_count=3,
        )

        outcome = coordinator.apply_policy(scores, sample_policy)
        assert outcome == DecisionOutcome.ESCALATED_TO_HITL

    def test_should_auto_approve_true(self, coordinator, sample_policy):
        """Test auto-approval for high score."""
        assert coordinator.should_auto_approve(9.0, sample_policy) is True
        assert coordinator.should_auto_approve(8.0, sample_policy) is True

    def test_should_auto_approve_false(self, coordinator, sample_policy):
        """Test no auto-approval for low score."""
        assert coordinator.should_auto_approve(7.9, sample_policy) is False
        assert coordinator.should_auto_approve(5.0, sample_policy) is False

    def test_should_escalate_failed_vote(self, coordinator, sample_policy):
        """Test escalation when any critic fails the artifact."""
        votes = [
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-1",
                score=9.0,
                confidence=0.9,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            ),
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-2",
                score=3.0,
                confidence=0.9,
                passed=False,  # Failed
                strengths=[],
                weaknesses=["Major issues"],
                recommendations=[],
                negotiation_room_id="room-1",
            ),
        ]

        assert coordinator.should_escalate(votes, sample_policy) is True

    def test_should_escalate_low_confidence(self, coordinator, sample_policy):
        """Test escalation when confidence is low."""
        votes = [
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-1",
                score=8.0,
                confidence=0.3,  # Low confidence
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            ),
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-2",
                score=8.0,
                confidence=0.4,  # Low confidence
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            ),
        ]

        # Average confidence = 0.35 < 0.5
        assert coordinator.should_escalate(votes, sample_policy) is True

    def test_should_escalate_high_variance(self, coordinator, sample_policy):
        """Test escalation when vote variance is high."""
        votes = [
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-1",
                score=9.0,
                confidence=0.9,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            ),
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-2",
                score=3.0,  # Very different
                confidence=0.9,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            ),
        ]

        # Standard deviation will be high
        assert coordinator.should_escalate(votes, sample_policy) is True

    def test_should_escalate_no_votes(self, coordinator, sample_policy):
        """Test no escalation when there are no votes."""
        assert coordinator.should_escalate([], sample_policy) is False

    def test_should_escalate_all_good(self, coordinator, sample_policy):
        """Test no escalation when all conditions are good."""
        votes = [
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-1",
                score=8.5,
                confidence=0.9,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            ),
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-2",
                score=8.7,
                confidence=0.85,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            ),
        ]

        # Low variance, high confidence, all passed
        assert coordinator.should_escalate(votes, sample_policy) is False

    def test_generate_decision_reason_approved(self, coordinator, sample_policy):
        """Test reason generation for approval."""
        from sw4rm.negotiation_types import AggregatedScore

        scores = AggregatedScore(
            mean=9.0,
            min_score=8.5,
            max_score=9.5,
            std_dev=0.5,
            weighted_mean=9.0,
            vote_count=3,
        )

        reason = coordinator.generate_decision_reason(
            DecisionOutcome.APPROVED, scores, [], sample_policy
        )

        assert "APPROVED" in reason
        assert "9.00" in reason  # weighted mean
        assert "8.00" in reason  # threshold (0.8 * 10)

    def test_generate_decision_reason_revision(self, coordinator, sample_policy):
        """Test reason generation for revision request."""
        from sw4rm.negotiation_types import AggregatedScore

        scores = AggregatedScore(
            mean=6.0,
            min_score=5.5,
            max_score=6.5,
            std_dev=0.5,
            weighted_mean=6.0,
            vote_count=3,
        )

        votes = [
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-1",
                score=6.0,
                confidence=0.9,
                passed=False,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            )
        ]

        reason = coordinator.generate_decision_reason(
            DecisionOutcome.REVISION_REQUESTED, scores, votes, sample_policy
        )

        assert "REVISION_REQUESTED" in reason
        assert "6.00" in reason  # weighted mean
        assert "1 of 3" in reason or "1 of 1" in reason  # failed votes

    def test_generate_decision_reason_escalated(self, coordinator, sample_policy):
        """Test reason generation for escalation."""
        from sw4rm.negotiation_types import AggregatedScore

        scores = AggregatedScore(
            mean=7.0,
            min_score=3.0,
            max_score=9.0,
            std_dev=2.5,  # High variance
            weighted_mean=7.0,
            vote_count=2,
        )

        votes = [
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-1",
                score=9.0,
                confidence=0.9,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            ),
            NegotiationVote(
                artifact_id="code-123",
                critic_id="critic-2",
                score=3.0,
                confidence=0.9,
                passed=True,
                strengths=[],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            ),
        ]

        reason = coordinator.generate_decision_reason(
            DecisionOutcome.ESCALATED_TO_HITL, scores, votes, sample_policy
        )

        assert "ESCALATED_TO_HITL" in reason
        assert "variance" in reason or "high variance" in reason


# Integration Tests


class TestNegotiationRoomIntegration:
    """Integration tests combining client and coordinator."""

    def test_complete_approval_workflow(self, client, coordinator, sample_proposal, sample_policy):
        """Test complete workflow from proposal to approval."""
        # Producer submits proposal
        artifact_id = client.submit_proposal(sample_proposal)

        # Critics submit votes
        for i, critic_id in enumerate(["critic-1", "critic-2", "critic-3"]):
            vote = NegotiationVote(
                artifact_id=artifact_id,
                critic_id=critic_id,
                score=8.5 + i * 0.2,
                confidence=0.9,
                passed=True,
                strengths=["Well done"],
                weaknesses=[],
                recommendations=[],
                negotiation_room_id="room-1",
            )
            client.submit_vote(vote)

        # Coordinator aggregates votes and makes decision
        votes = client.get_votes(artifact_id)
        aggregated = aggregate_votes(votes)
        outcome = coordinator.apply_policy(aggregated, sample_policy)

        assert outcome == DecisionOutcome.APPROVED

        # Store decision
        reason = coordinator.generate_decision_reason(
            outcome, aggregated, votes, sample_policy
        )
        decision = NegotiationDecision(
            artifact_id=artifact_id,
            outcome=outcome,
            votes=votes,
            aggregated_score=aggregated,
            policy_version="1.0",
            reason=reason,
            negotiation_room_id="room-1",
        )
        client.store_decision(decision)

        # Verify decision is retrievable
        retrieved = client.get_decision(artifact_id)
        assert retrieved.outcome == DecisionOutcome.APPROVED

    def test_complete_revision_workflow(self, client, coordinator, sample_proposal, sample_policy):
        """Test complete workflow resulting in revision request."""
        # Producer submits proposal
        artifact_id = client.submit_proposal(sample_proposal)

        # Critics submit votes with low scores
        for i, critic_id in enumerate(["critic-1", "critic-2"]):
            vote = NegotiationVote(
                artifact_id=artifact_id,
                critic_id=critic_id,
                score=6.0 + i * 0.5,
                confidence=0.9,
                passed=False,
                strengths=[],
                weaknesses=["Needs improvement"],
                recommendations=["Add tests", "Improve docs"],
                negotiation_room_id="room-1",
            )
            client.submit_vote(vote)

        # Coordinator makes decision
        votes = client.get_votes(artifact_id)
        aggregated = aggregate_votes(votes)
        outcome = coordinator.apply_policy(aggregated, sample_policy)

        # Should be revision or escalation (due to failed votes)
        assert outcome in [DecisionOutcome.REVISION_REQUESTED, DecisionOutcome.ESCALATED_TO_HITL]

    def test_complete_escalation_workflow(self, client, coordinator, sample_proposal, sample_policy):
        """Test complete workflow resulting in escalation."""
        # Producer submits proposal
        artifact_id = client.submit_proposal(sample_proposal)

        # Critics submit conflicting votes
        vote1 = NegotiationVote(
            artifact_id=artifact_id,
            critic_id="critic-1",
            score=9.5,
            confidence=0.9,
            passed=True,
            strengths=["Excellent"],
            weaknesses=[],
            recommendations=[],
            negotiation_room_id="room-1",
        )
        vote2 = NegotiationVote(
            artifact_id=artifact_id,
            critic_id="critic-2",
            score=2.0,  # Very different score
            confidence=0.9,
            passed=False,
            strengths=[],
            weaknesses=["Poor quality"],
            recommendations=["Rewrite"],
            negotiation_room_id="room-1",
        )

        client.submit_vote(vote1)
        client.submit_vote(vote2)

        # Coordinator should escalate due to conflict
        votes = client.get_votes(artifact_id)
        should_escalate = coordinator.should_escalate(votes, sample_policy)
        assert should_escalate is True

        aggregated = aggregate_votes(votes)
        outcome = coordinator.apply_policy(aggregated, sample_policy)

        # Should be escalated due to high variance or failed vote
        assert outcome == DecisionOutcome.ESCALATED_TO_HITL
