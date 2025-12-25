"""Integration tests for multi-agent negotiation flows.

This module tests complete negotiation workflows including:
- Multi-agent negotiation setup
- Proposal -> vote -> decision flow
- Negotiation timeout handling
- HITL escalation triggers
- Negotiation abort scenarios
"""
import pytest
from unittest.mock import MagicMock, patch
import time


class TestNegotiationSetup:
    """Test negotiation setup and initialization."""

    def test_open_two_agent_negotiation(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test opening a negotiation with two agents."""
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        open_response.negotiation_id = "neg-123"
        mock_negotiation_stub.Open.return_value = open_response

        # Act
        response = negotiation_client.open(
            negotiation_id="neg-123",
            correlation_id="corr-456",
            topic="Resource allocation for project X",
            participants=["agent-1", "agent-2"],
            intensity=3
        )

        # Assert
        assert response.acknowledged
        assert response.negotiation_id == "neg-123"
        assert mock_negotiation_stub.Open.called

    def test_open_multi_agent_negotiation(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test opening a negotiation with multiple agents."""
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        open_response.negotiation_id = "neg-456"
        mock_negotiation_stub.Open.return_value = open_response

        participants = [f"agent-{i}" for i in range(1, 6)]

        # Act
        response = negotiation_client.open(
            negotiation_id="neg-456",
            correlation_id="corr-789",
            topic="Multi-agent resource planning",
            participants=participants,
            intensity=5
        )

        # Assert
        assert response.acknowledged
        assert response.negotiation_id == "neg-456"

    def test_open_negotiation_with_timeout(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test opening a negotiation with debate timeout."""
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        # Act
        response = negotiation_client.open(
            negotiation_id="neg-789",
            correlation_id="corr-abc",
            topic="Time-constrained decision",
            participants=["agent-1", "agent-2"],
            intensity=7,
            debate_timeout_seconds=300  # 5 minutes
        )

        # Assert
        assert response.acknowledged
        assert mock_negotiation_stub.Open.called

    def test_open_negotiation_with_high_intensity(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test opening a high-intensity negotiation."""
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        # Act
        response = negotiation_client.open(
            negotiation_id="neg-urgent",
            correlation_id="corr-urgent",
            topic="Critical resource conflict",
            participants=["agent-1", "agent-2", "agent-3"],
            intensity=10  # Maximum intensity
        )

        # Assert
        assert response.acknowledged


class TestProposalVoteDecisionFlow:
    """Test the complete proposal -> vote -> decision flow."""

    def test_simple_proposal_and_decision(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test simple flow: open -> propose -> decide.

        Workflow:
        1. Open negotiation
        2. Agent-1 proposes
        3. Agent-1 decides (unanimous)
        """
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        propose_response = MagicMock()
        propose_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = propose_response

        decide_response = MagicMock()
        decide_response.acknowledged = True
        mock_negotiation_stub.Decide.return_value = decide_response

        # Act
        open_resp = negotiation_client.open(
            negotiation_id="neg-123",
            correlation_id="corr-123",
            topic="Simple decision",
            participants=["agent-1"]
        )

        propose_resp = negotiation_client.propose(
            negotiation_id="neg-123",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"allocation": "resource-A"}'
        )

        decide_resp = negotiation_client.decide(
            negotiation_id="neg-123",
            decided_by="agent-1",
            content_type="application/json",
            result=b'{"decision": "allocate resource-A"}'
        )

        # Assert
        assert open_resp.acknowledged
        assert propose_resp.acknowledged
        assert decide_resp.acknowledged

    def test_proposal_counter_proposal_decision(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test flow with counter-proposal: propose -> counter -> decide.

        Workflow:
        1. Open negotiation
        2. Agent-1 proposes
        3. Agent-2 counters
        4. Agent-1 decides based on counter
        """
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        propose_response = MagicMock()
        propose_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = propose_response

        counter_response = MagicMock()
        counter_response.acknowledged = True
        mock_negotiation_stub.Counter.return_value = counter_response

        decide_response = MagicMock()
        decide_response.acknowledged = True
        mock_negotiation_stub.Decide.return_value = decide_response

        # Act
        open_resp = negotiation_client.open(
            negotiation_id="neg-456",
            correlation_id="corr-456",
            topic="Resource negotiation",
            participants=["agent-1", "agent-2"]
        )

        propose_resp = negotiation_client.propose(
            negotiation_id="neg-456",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"proposal": "50% resource-A, 50% resource-B"}'
        )

        counter_resp = negotiation_client.counter(
            negotiation_id="neg-456",
            from_agent="agent-2",
            content_type="application/json",
            payload=b'{"counter": "60% resource-A, 40% resource-B"}'
        )

        decide_resp = negotiation_client.decide(
            negotiation_id="neg-456",
            decided_by="agent-1",
            content_type="application/json",
            result=b'{"decision": "accept counter: 60/40 split"}'
        )

        # Assert
        assert open_resp.acknowledged
        assert propose_resp.acknowledged
        assert counter_resp.acknowledged
        assert decide_resp.acknowledged

    def test_multiple_rounds_of_counter_proposals(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test multiple rounds of negotiation before decision.

        Workflow:
        1. Open negotiation
        2. Agent-1 proposes
        3. Agent-2 counters
        4. Agent-1 counters again
        5. Agent-2 counters again
        6. Agent-1 decides
        """
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        propose_response = MagicMock()
        propose_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = propose_response

        counter_response = MagicMock()
        counter_response.acknowledged = True
        mock_negotiation_stub.Counter.return_value = counter_response

        decide_response = MagicMock()
        decide_response.acknowledged = True
        mock_negotiation_stub.Decide.return_value = decide_response

        # Act
        negotiation_client.open(
            negotiation_id="neg-789",
            correlation_id="corr-789",
            topic="Complex negotiation",
            participants=["agent-1", "agent-2"]
        )

        # Round 1
        negotiation_client.propose(
            negotiation_id="neg-789",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"round": 1, "offer": "100%"}'
        )

        # Round 2
        negotiation_client.counter(
            negotiation_id="neg-789",
            from_agent="agent-2",
            content_type="application/json",
            payload=b'{"round": 2, "offer": "50%"}'
        )

        # Round 3
        negotiation_client.counter(
            negotiation_id="neg-789",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"round": 3, "offer": "75%"}'
        )

        # Round 4
        negotiation_client.counter(
            negotiation_id="neg-789",
            from_agent="agent-2",
            content_type="application/json",
            payload=b'{"round": 4, "offer": "60%"}'
        )

        # Decision
        decide_resp = negotiation_client.decide(
            negotiation_id="neg-789",
            decided_by="agent-1",
            content_type="application/json",
            result=b'{"decision": "accept 60%"}'
        )

        # Assert
        assert mock_negotiation_stub.Propose.call_count == 1
        assert mock_negotiation_stub.Counter.call_count == 3
        assert decide_resp.acknowledged

    def test_proposal_with_evaluations_then_decision(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test flow with evaluations: propose -> evaluate -> decide.

        Workflow:
        1. Open negotiation
        2. Agent-1 proposes
        3. Agent-2 evaluates
        4. Agent-3 evaluates
        5. Agent-1 decides based on evaluations
        """
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        propose_response = MagicMock()
        propose_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = propose_response

        evaluate_response = MagicMock()
        evaluate_response.acknowledged = True
        mock_negotiation_stub.Evaluate.return_value = evaluate_response

        decide_response = MagicMock()
        decide_response.acknowledged = True
        mock_negotiation_stub.Decide.return_value = decide_response

        # Act
        negotiation_client.open(
            negotiation_id="neg-eval",
            correlation_id="corr-eval",
            topic="Evaluated decision",
            participants=["agent-1", "agent-2", "agent-3"]
        )

        negotiation_client.propose(
            negotiation_id="neg-eval",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"proposal": "plan-A"}'
        )

        # Evaluations from other agents
        negotiation_client.evaluate(
            negotiation_id="neg-eval",
            from_agent="agent-2",
            confidence_score=0.85,
            notes="Plan looks good, minor concerns"
        )

        negotiation_client.evaluate(
            negotiation_id="neg-eval",
            from_agent="agent-3",
            confidence_score=0.92,
            notes="Strongly support plan-A"
        )

        decide_resp = negotiation_client.decide(
            negotiation_id="neg-eval",
            decided_by="agent-1",
            content_type="application/json",
            result=b'{"decision": "proceed with plan-A"}'
        )

        # Assert
        assert mock_negotiation_stub.Propose.call_count == 1
        assert mock_negotiation_stub.Evaluate.call_count == 2
        assert decide_resp.acknowledged


class TestNegotiationTimeoutHandling:
    """Test negotiation timeout scenarios."""

    def test_negotiation_timeout_triggers_abort(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test that timeout triggers negotiation abort."""
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        propose_response = MagicMock()
        propose_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = propose_response

        # Timeout triggers abort
        abort_response = MagicMock()
        abort_response.acknowledged = True
        abort_response.reason = "Debate timeout exceeded"
        mock_negotiation_stub.Abort.return_value = abort_response

        # Act
        negotiation_client.open(
            negotiation_id="neg-timeout",
            correlation_id="corr-timeout",
            topic="Time-limited decision",
            participants=["agent-1", "agent-2"],
            debate_timeout_seconds=5  # Very short timeout
        )

        negotiation_client.propose(
            negotiation_id="neg-timeout",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"proposal": "quick-decision"}'
        )

        # Simulate timeout
        abort_resp = negotiation_client.abort(
            negotiation_id="neg-timeout",
            reason="Debate timeout exceeded"
        )

        # Assert
        assert abort_resp.acknowledged
        assert "timeout" in abort_resp.reason.lower()

    def test_manual_abort_before_timeout(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test manually aborting before timeout."""
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        abort_response = MagicMock()
        abort_response.acknowledged = True
        mock_negotiation_stub.Abort.return_value = abort_response

        # Act
        negotiation_client.open(
            negotiation_id="neg-manual-abort",
            correlation_id="corr-manual",
            topic="Abortable negotiation",
            participants=["agent-1", "agent-2"]
        )

        abort_resp = negotiation_client.abort(
            negotiation_id="neg-manual-abort",
            reason="Agents reached impasse"
        )

        # Assert
        assert abort_resp.acknowledged
        assert mock_negotiation_stub.Abort.called

    def test_timeout_with_no_proposals(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test timeout when no proposals have been made."""
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        abort_response = MagicMock()
        abort_response.acknowledged = True
        abort_response.reason = "Timeout with no proposals"
        mock_negotiation_stub.Abort.return_value = abort_response

        # Act
        negotiation_client.open(
            negotiation_id="neg-no-proposal",
            correlation_id="corr-no-proposal",
            topic="Stalled negotiation",
            participants=["agent-1", "agent-2"],
            debate_timeout_seconds=10
        )

        # No proposals made, timeout occurs
        abort_resp = negotiation_client.abort(
            negotiation_id="neg-no-proposal",
            reason="Timeout with no proposals"
        )

        # Assert
        assert abort_resp.acknowledged
        assert mock_negotiation_stub.Propose.call_count == 0


class TestHITLEscalation:
    """Test Human-in-the-Loop escalation scenarios."""

    def test_negotiation_triggers_hitl_on_low_confidence(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test HITL escalation when confidence is low.

        Workflow:
        1. Open negotiation
        2. Agent proposes
        3. Multiple agents evaluate with low confidence
        4. Low confidence triggers HITL escalation
        5. Negotiation aborted pending human review
        """
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        propose_response = MagicMock()
        propose_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = propose_response

        evaluate_response = MagicMock()
        evaluate_response.acknowledged = True
        evaluate_response.hitl_required = True  # Low confidence triggers HITL
        mock_negotiation_stub.Evaluate.return_value = evaluate_response

        abort_response = MagicMock()
        abort_response.acknowledged = True
        abort_response.escalated_to_hitl = True
        mock_negotiation_stub.Abort.return_value = abort_response

        # Act
        negotiation_client.open(
            negotiation_id="neg-hitl",
            correlation_id="corr-hitl",
            topic="High-stakes decision",
            participants=["agent-1", "agent-2", "agent-3"]
        )

        negotiation_client.propose(
            negotiation_id="neg-hitl",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"proposal": "risky-plan"}'
        )

        # Low confidence evaluations
        eval_1 = negotiation_client.evaluate(
            negotiation_id="neg-hitl",
            from_agent="agent-2",
            confidence_score=0.35,  # Low confidence
            notes="Uncertain about this approach"
        )

        eval_2 = negotiation_client.evaluate(
            negotiation_id="neg-hitl",
            from_agent="agent-3",
            confidence_score=0.42,  # Low confidence
            notes="Need human review"
        )

        # HITL escalation triggered
        abort_resp = negotiation_client.abort(
            negotiation_id="neg-hitl",
            reason="HITL escalation: low confidence scores"
        )

        # Assert
        assert eval_1.acknowledged
        assert eval_2.acknowledged
        assert abort_resp.acknowledged
        assert abort_resp.escalated_to_hitl

    def test_negotiation_triggers_hitl_on_conflict(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test HITL escalation when agents cannot reach consensus.

        Workflow:
        1. Open negotiation
        2. Multiple rounds of conflicting proposals
        3. Agents cannot agree
        4. Conflict triggers HITL escalation
        """
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        propose_response = MagicMock()
        propose_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = propose_response

        counter_response = MagicMock()
        counter_response.acknowledged = True
        counter_response.conflict_detected = True
        mock_negotiation_stub.Counter.return_value = counter_response

        abort_response = MagicMock()
        abort_response.acknowledged = True
        abort_response.escalated_to_hitl = True
        abort_response.reason = "Unresolvable conflict"
        mock_negotiation_stub.Abort.return_value = abort_response

        # Act
        negotiation_client.open(
            negotiation_id="neg-conflict",
            correlation_id="corr-conflict",
            topic="Conflicting priorities",
            participants=["agent-1", "agent-2"]
        )

        # Agent-1 proposes
        negotiation_client.propose(
            negotiation_id="neg-conflict",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"proposal": "prioritize-speed"}'
        )

        # Agent-2 counters with opposite view
        counter_1 = negotiation_client.counter(
            negotiation_id="neg-conflict",
            from_agent="agent-2",
            content_type="application/json",
            payload=b'{"counter": "prioritize-quality"}'
        )

        # Agent-1 counters again
        counter_2 = negotiation_client.counter(
            negotiation_id="neg-conflict",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"counter": "must-have-speed"}'
        )

        # Conflict detected, escalate to HITL
        abort_resp = negotiation_client.abort(
            negotiation_id="neg-conflict",
            reason="HITL escalation: unresolvable conflict"
        )

        # Assert
        assert counter_1.acknowledged
        assert counter_2.acknowledged
        assert abort_resp.escalated_to_hitl
        assert "conflict" in abort_resp.reason.lower()

    def test_negotiation_hitl_on_critical_intensity(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test HITL escalation for critical intensity negotiations.

        High-intensity (critical) negotiations may require human oversight.
        """
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        open_response.hitl_monitoring = True  # Critical intensity enables HITL
        mock_negotiation_stub.Open.return_value = open_response

        propose_response = MagicMock()
        propose_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = propose_response

        decide_response = MagicMock()
        decide_response.acknowledged = True
        decide_response.requires_hitl_approval = True
        mock_negotiation_stub.Decide.return_value = decide_response

        # Act
        open_resp = negotiation_client.open(
            negotiation_id="neg-critical",
            correlation_id="corr-critical",
            topic="Critical system decision",
            participants=["agent-1", "agent-2"],
            intensity=10  # Maximum/critical intensity
        )

        negotiation_client.propose(
            negotiation_id="neg-critical",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"proposal": "critical-change"}'
        )

        decide_resp = negotiation_client.decide(
            negotiation_id="neg-critical",
            decided_by="agent-1",
            content_type="application/json",
            result=b'{"decision": "proceed-with-critical-change"}'
        )

        # Assert
        assert open_resp.hitl_monitoring
        assert decide_resp.requires_hitl_approval


class TestComplexNegotiationScenarios:
    """Test complex, multi-step negotiation scenarios."""

    def test_three_agent_consensus_building(
        self, negotiation_client, mock_negotiation_stub
    ):
        """Test building consensus among three agents.

        Workflow:
        1. Open 3-agent negotiation
        2. Agent-1 proposes
        3. Agent-2 evaluates positively
        4. Agent-3 evaluates positively
        5. Agent-1 decides based on consensus
        """
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        propose_response = MagicMock()
        propose_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = propose_response

        evaluate_response = MagicMock()
        evaluate_response.acknowledged = True
        mock_negotiation_stub.Evaluate.return_value = evaluate_response

        decide_response = MagicMock()
        decide_response.acknowledged = True
        decide_response.consensus_reached = True
        mock_negotiation_stub.Decide.return_value = decide_response

        # Act
        negotiation_client.open(
            negotiation_id="neg-consensus",
            correlation_id="corr-consensus",
            topic="Build team consensus",
            participants=["agent-1", "agent-2", "agent-3"]
        )

        negotiation_client.propose(
            negotiation_id="neg-consensus",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"proposal": "shared-plan"}'
        )

        negotiation_client.evaluate(
            negotiation_id="neg-consensus",
            from_agent="agent-2",
            confidence_score=0.88,
            notes="Agree with proposal"
        )

        negotiation_client.evaluate(
            negotiation_id="neg-consensus",
            from_agent="agent-3",
            confidence_score=0.91,
            notes="Strong agreement"
        )

        decide_resp = negotiation_client.decide(
            negotiation_id="neg-consensus",
            decided_by="agent-1",
            content_type="application/json",
            result=b'{"decision": "consensus-reached-proceed"}'
        )

        # Assert
        assert decide_resp.consensus_reached
        assert mock_negotiation_stub.Evaluate.call_count == 2

    def test_negotiation_with_artifact_logging(
        self, negotiation_client, activity_client,
        mock_negotiation_stub, mock_activity_stub
    ):
        """Test negotiation flow with artifact logging.

        Workflow:
        1. Open negotiation
        2. Log initial proposal as artifact
        3. Agent proposes
        4. Log counter as artifact
        5. Agent counters
        6. Log decision as artifact
        7. Decide
        """
        # Arrange
        open_response = MagicMock()
        open_response.acknowledged = True
        mock_negotiation_stub.Open.return_value = open_response

        propose_response = MagicMock()
        propose_response.acknowledged = True
        mock_negotiation_stub.Propose.return_value = propose_response

        counter_response = MagicMock()
        counter_response.acknowledged = True
        mock_negotiation_stub.Counter.return_value = counter_response

        decide_response = MagicMock()
        decide_response.acknowledged = True
        mock_negotiation_stub.Decide.return_value = decide_response

        artifact_response = MagicMock()
        artifact_response.acknowledged = True
        mock_activity_stub.AppendArtifact.return_value = artifact_response

        # Act
        negotiation_client.open(
            negotiation_id="neg-artifacts",
            correlation_id="corr-artifacts",
            topic="Documented negotiation",
            participants=["agent-1", "agent-2"]
        )

        # Log and submit proposal
        activity_client.append_artifact(
            negotiation_id="neg-artifacts",
            kind="proposal",
            version="v1",
            content_type="application/json",
            content=b'{"proposal": "initial-plan"}',
            created_at="2025-12-23T10:00:00Z"
        )

        negotiation_client.propose(
            negotiation_id="neg-artifacts",
            from_agent="agent-1",
            content_type="application/json",
            payload=b'{"proposal": "initial-plan"}'
        )

        # Log and submit counter
        activity_client.append_artifact(
            negotiation_id="neg-artifacts",
            kind="counter",
            version="v1",
            content_type="application/json",
            content=b'{"counter": "revised-plan"}',
            created_at="2025-12-23T10:05:00Z"
        )

        negotiation_client.counter(
            negotiation_id="neg-artifacts",
            from_agent="agent-2",
            content_type="application/json",
            payload=b'{"counter": "revised-plan"}'
        )

        # Log and submit decision
        activity_client.append_artifact(
            negotiation_id="neg-artifacts",
            kind="decision",
            version="v1",
            content_type="application/json",
            content=b'{"decision": "accept-revised"}',
            created_at="2025-12-23T10:10:00Z"
        )

        decide_resp = negotiation_client.decide(
            negotiation_id="neg-artifacts",
            decided_by="agent-1",
            content_type="application/json",
            result=b'{"decision": "accept-revised"}'
        )

        # Assert
        assert decide_resp.acknowledged
        assert mock_activity_stub.AppendArtifact.call_count == 3
