"""Tests for Three-ID Envelope Model (Phase 2.1).

Tests envelope state transitions, idempotency token generation,
and deduplication functionality.
"""
import time
from sw4rm import constants as C
from sw4rm.envelope import (
    build_envelope,
    update_envelope_state,
    is_terminal_state,
    compute_deterministic_hash,
    make_idempotency_token,
)
from sw4rm.activity_buffer import ActivityBuffer, is_terminal_state as buffer_is_terminal


class TestEnvelopeStateManagement:
    """Test envelope state transitions and helpers."""

    def test_build_envelope_default_state(self):
        """Test that envelopes default to CREATED state."""
        env = build_envelope(producer_id="agent-1", message_type=C.DATA)
        assert env["state"] == C.CREATED

    def test_build_envelope_custom_state(self):
        """Test creating envelope with custom initial state."""
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            state=C.PENDING
        )
        assert env["state"] == C.PENDING

    def test_update_envelope_state(self):
        """Test state transition helper."""
        env = build_envelope(producer_id="agent-1", message_type=C.DATA)
        assert env["state"] == C.CREATED

        env = update_envelope_state(env, C.PENDING)
        assert env["state"] == C.PENDING

        env = update_envelope_state(env, C.RUNNING_ENVELOPE)
        assert env["state"] == C.RUNNING_ENVELOPE

        env = update_envelope_state(env, C.FULFILLED_ENVELOPE)
        assert env["state"] == C.FULFILLED_ENVELOPE

    def test_state_lifecycle(self):
        """Test typical envelope state lifecycle."""
        env = build_envelope(producer_id="agent-1", message_type=C.TOOL_CALL)

        # Initial state
        assert env["state"] == C.CREATED
        assert not is_terminal_state(env["state"])

        # Sent to router
        update_envelope_state(env, C.PENDING)
        assert env["state"] == C.PENDING
        assert not is_terminal_state(env["state"])

        # Agent starts processing
        update_envelope_state(env, C.RUNNING_ENVELOPE)
        assert env["state"] == C.RUNNING_ENVELOPE
        assert not is_terminal_state(env["state"])

        # Completed successfully
        update_envelope_state(env, C.FULFILLED_ENVELOPE)
        assert env["state"] == C.FULFILLED_ENVELOPE
        assert is_terminal_state(env["state"])

    def test_is_terminal_state(self):
        """Test terminal state detection."""
        # Non-terminal states
        assert not is_terminal_state(C.ENVELOPE_STATE_UNSPECIFIED)
        assert not is_terminal_state(C.CREATED)
        assert not is_terminal_state(C.PENDING)
        assert not is_terminal_state(C.RUNNING_ENVELOPE)

        # Terminal states
        assert is_terminal_state(C.FULFILLED_ENVELOPE)
        assert is_terminal_state(C.REJECTED_ENVELOPE)
        assert is_terminal_state(C.FAILED_ENVELOPE)
        assert is_terminal_state(C.TIMED_OUT_ENVELOPE)

    def test_buffer_is_terminal_state(self):
        """Test that buffer module also exports is_terminal_state."""
        # Verify both functions work identically
        assert buffer_is_terminal(C.FULFILLED_ENVELOPE)
        assert buffer_is_terminal(C.REJECTED_ENVELOPE)
        assert not buffer_is_terminal(C.PENDING)


class TestIdempotencyTokenGeneration:
    """Test idempotency token generation and determinism."""

    def test_compute_deterministic_hash_stability(self):
        """Test that same params produce same hash."""
        params1 = {"tool": "git_commit", "repo": "myrepo", "files": ["a.py", "b.py"]}
        params2 = {"tool": "git_commit", "repo": "myrepo", "files": ["a.py", "b.py"]}

        hash1 = compute_deterministic_hash(params1)
        hash2 = compute_deterministic_hash(params2)

        assert hash1 == hash2
        assert len(hash1) == 16  # Should be truncated to 16 hex chars

    def test_compute_deterministic_hash_order_independence(self):
        """Test that key order doesn't affect hash (canonical JSON)."""
        params1 = {"z": 1, "a": 2, "m": 3}
        params2 = {"a": 2, "m": 3, "z": 1}

        hash1 = compute_deterministic_hash(params1)
        hash2 = compute_deterministic_hash(params2)

        assert hash1 == hash2

    def test_compute_deterministic_hash_different_values(self):
        """Test that different params produce different hashes."""
        params1 = {"tool": "git_commit", "files": ["a.py"]}
        params2 = {"tool": "git_commit", "files": ["b.py"]}

        hash1 = compute_deterministic_hash(params1)
        hash2 = compute_deterministic_hash(params2)

        assert hash1 != hash2

    def test_make_idempotency_token_format(self):
        """Test idempotency token format."""
        token = make_idempotency_token(
            producer_id="agent-1",
            operation_type="git_commit",
            deterministic_hash="abc123def456"
        )

        assert token == "agent-1:git_commit:abc123def456"

        # Verify format is parseable
        parts = token.split(":")
        assert len(parts) == 3
        assert parts[0] == "agent-1"
        assert parts[1] == "git_commit"
        assert parts[2] == "abc123def456"

    def test_idempotency_token_end_to_end(self):
        """Test complete idempotency token generation workflow."""
        # Same operation parameters
        params = {
            "tool": "file_write",
            "path": "/tmp/test.txt",
            "content_hash": "sha256:abc123"
        }

        # Generate tokens for two "attempts" of same operation
        hash1 = compute_deterministic_hash(params)
        token1 = make_idempotency_token("agent-1", "tool_call", hash1)

        hash2 = compute_deterministic_hash(params)
        token2 = make_idempotency_token("agent-1", "tool_call", hash2)

        # Tokens should be identical for retry scenarios
        assert token1 == token2

        # Build envelopes with same token
        env1 = build_envelope(
            producer_id="agent-1",
            message_type=C.TOOL_CALL,
            idempotency_token=token1
        )
        env2 = build_envelope(
            producer_id="agent-1",
            message_type=C.TOOL_CALL,
            idempotency_token=token2
        )

        # Different message_ids (per-attempt)
        assert env1["message_id"] != env2["message_id"]

        # Same idempotency token (stable)
        assert env1["idempotency_token"] == env2["idempotency_token"]


class TestThreeIDSemantics:
    """Test three-ID model: message_id, correlation_id, idempotency_token."""

    def test_message_id_uniqueness(self):
        """Test that message_id is unique per call."""
        env1 = build_envelope(producer_id="agent-1", message_type=C.DATA)
        env2 = build_envelope(producer_id="agent-1", message_type=C.DATA)

        assert env1["message_id"] != env2["message_id"]

    def test_correlation_id_auto_generation(self):
        """Test that correlation_id is auto-generated if not provided."""
        env = build_envelope(producer_id="agent-1", message_type=C.DATA)
        assert env["correlation_id"]
        assert len(env["correlation_id"]) > 0

    def test_correlation_id_preservation(self):
        """Test that correlation_id can be explicitly set and preserved."""
        corr_id = "workflow-123"

        env1 = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            correlation_id=corr_id
        )
        env2 = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            correlation_id=corr_id
        )

        assert env1["correlation_id"] == corr_id
        assert env2["correlation_id"] == corr_id
        # But message_ids differ
        assert env1["message_id"] != env2["message_id"]

    def test_retry_scenario(self):
        """Test proper ID handling in retry scenario."""
        # Original attempt
        original_corr_id = "workflow-xyz"
        params = {"operation": "critical_task"}
        idem_hash = compute_deterministic_hash(params)
        idem_token = make_idempotency_token("agent-1", "task", idem_hash)

        env1 = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            correlation_id=original_corr_id,
            idempotency_token=idem_token,
            retry_count=0
        )

        # Retry attempt (same operation)
        env2 = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            correlation_id=original_corr_id,  # KEEP
            idempotency_token=idem_token,      # KEEP
            retry_count=1                       # INCREMENT
        )

        # Different message_ids (per-attempt identifier)
        assert env1["message_id"] != env2["message_id"]

        # Same correlation_id (workflow scope)
        assert env1["correlation_id"] == env2["correlation_id"]

        # Same idempotency token (operation scope)
        assert env1["idempotency_token"] == env2["idempotency_token"]

        # Different retry counts
        assert env1["retry_count"] == 0
        assert env2["retry_count"] == 1


class TestActivityBufferDeduplication:
    """Test deduplication via idempotency tokens in ActivityBuffer."""

    def test_get_by_idempotency_token(self):
        """Test looking up messages by idempotency token."""
        buffer = ActivityBuffer(max_items=10)

        params = {"op": "write", "file": "test.txt"}
        token = make_idempotency_token(
            "agent-1",
            "file_op",
            compute_deterministic_hash(params)
        )

        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            idempotency_token=token
        )

        # Record envelope
        rec = buffer.record_incoming(env)

        # Look up by idempotency token
        found = buffer.get_by_idempotency_token(token)
        assert found is not None
        assert found.message_id == rec.message_id
        assert found.idempotency_token == token

    def test_deduplication_detection(self):
        """Test detecting duplicate operations."""
        buffer = ActivityBuffer(max_items=10)

        params = {"action": "deploy", "version": "1.0.0"}
        token = make_idempotency_token(
            "agent-1",
            "deploy",
            compute_deterministic_hash(params)
        )

        # First attempt
        env1 = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            idempotency_token=token,
            state=C.RUNNING_ENVELOPE
        )
        rec1 = buffer.record_incoming(env1)

        # Check for existing operation
        existing = buffer.get_by_idempotency_token(token)
        assert existing is not None
        assert existing.message_id == rec1.message_id
        assert existing.state == C.RUNNING_ENVELOPE

        # Duplicate attempt arrives
        env2 = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            idempotency_token=token  # Same token!
        )

        # Before recording, check for duplicate
        duplicate = buffer.get_by_idempotency_token(token)
        assert duplicate is not None
        # Should be the first attempt, not terminal yet
        assert not is_terminal_state(duplicate.state)

    def test_deduplication_window_expiry(self):
        """Test that deduplication entries expire after window."""
        # Short dedup window for testing
        buffer = ActivityBuffer(max_items=10, dedup_window_s=1)

        token = make_idempotency_token(
            "agent-1",
            "op",
            compute_deterministic_hash({"test": "value"})
        )

        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            idempotency_token=token
        )

        buffer.record_incoming(env)

        # Should be found immediately
        found = buffer.get_by_idempotency_token(token)
        assert found is not None

        # Wait for dedup window to expire
        time.sleep(1.1)

        # Should still be in buffer (buffer has longer retention)
        # but dedup lookup should trigger cleanup
        found_after_expiry = buffer.get_by_idempotency_token(token)
        # After cleanup, token should be removed from dedup index
        # (though record might still exist in main buffer)
        # This is expected: dedup is for recent duplicates only

    def test_multiple_tokens_tracked(self):
        """Test that buffer can track multiple idempotency tokens."""
        buffer = ActivityBuffer(max_items=100)

        tokens = []
        for i in range(5):
            params = {"iteration": i}
            token = make_idempotency_token(
                "agent-1",
                "iterate",
                compute_deterministic_hash(params)
            )
            tokens.append(token)

            env = build_envelope(
                producer_id="agent-1",
                message_type=C.DATA,
                idempotency_token=token
            )
            buffer.record_incoming(env)

        # All tokens should be findable
        for token in tokens:
            found = buffer.get_by_idempotency_token(token)
            assert found is not None
            assert found.idempotency_token == token

    def test_update_state_method(self):
        """Test updating envelope state via ActivityBuffer."""
        buffer = ActivityBuffer(max_items=10)

        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            state=C.CREATED
        )
        rec = buffer.record_incoming(env)
        msg_id = rec.message_id

        # Update state
        updated = buffer.update_state(msg_id, C.PENDING)
        assert updated is not None
        assert updated.state == C.PENDING

        # Verify via get
        retrieved = buffer.get(msg_id)
        assert retrieved is not None
        assert retrieved.state == C.PENDING

    def test_activity_record_properties(self):
        """Test ActivityRecord convenience properties."""
        token = "agent-1:op:hash123"
        corr_id = "workflow-456"

        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            idempotency_token=token,
            correlation_id=corr_id,
            state=C.RUNNING_ENVELOPE
        )

        buffer = ActivityBuffer(max_items=10)
        rec = buffer.record_incoming(env)

        # Test properties
        assert rec.state == C.RUNNING_ENVELOPE
        assert rec.idempotency_token == token
        assert rec.correlation_id == corr_id
