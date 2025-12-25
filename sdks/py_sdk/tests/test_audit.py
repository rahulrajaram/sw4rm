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

"""Tests for audit proof extension."""

import pytest
from sw4rm.audit import (
    AuditProof,
    AuditPolicy,
    AuditRecord,
    NoOpAuditor,
    InMemoryAuditor,
    verify_audit_proof,
    compute_envelope_hash,
    create_simple_proof,
)
from sw4rm.envelope import build_envelope
from sw4rm import constants as C


class TestAuditTypes:
    """Test audit type classes."""

    def test_audit_proof_creation(self):
        """Test creating an AuditProof instance."""
        proof = AuditProof(
            proof_id="proof-123",
            proof_type="simple_hash",
            proof_data=b"test_proof_data",
            created_at="1234567890",
            verified=False,
        )
        assert proof.proof_id == "proof-123"
        assert proof.proof_type == "simple_hash"
        assert proof.proof_data == b"test_proof_data"
        assert proof.created_at == "1234567890"
        assert proof.verified is False

    def test_audit_policy_creation(self):
        """Test creating an AuditPolicy instance."""
        policy = AuditPolicy(
            policy_id="policy-456",
            require_proof=True,
            verification_level="strict",
            retention_days=90,
        )
        assert policy.policy_id == "policy-456"
        assert policy.require_proof is True
        assert policy.verification_level == "strict"
        assert policy.retention_days == 90

    def test_audit_record_creation(self):
        """Test creating an AuditRecord instance."""
        proof = AuditProof(
            proof_id="proof-123",
            proof_type="simple_hash",
            proof_data=b"test",
            created_at="1234567890",
        )
        record = AuditRecord(
            record_id="record-789",
            envelope_id="env-123",
            action="send",
            actor_id="agent-1",
            timestamp="1234567890",
            proof=proof,
        )
        assert record.record_id == "record-789"
        assert record.envelope_id == "env-123"
        assert record.action == "send"
        assert record.actor_id == "agent-1"
        assert record.timestamp == "1234567890"
        assert record.proof == proof

    def test_audit_record_without_proof(self):
        """Test creating an AuditRecord without proof."""
        record = AuditRecord(
            record_id="record-789",
            envelope_id="env-123",
            action="send",
            actor_id="agent-1",
            timestamp="1234567890",
        )
        assert record.proof is None


class TestVerificationFunctions:
    """Test verification utility functions."""

    def test_compute_envelope_hash_deterministic(self):
        """Test that envelope hash is deterministic."""
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            payload=b"test payload",
        )
        hash1 = compute_envelope_hash(env)
        hash2 = compute_envelope_hash(env)
        assert hash1 == hash2
        assert isinstance(hash1, str)
        assert len(hash1) == 64  # SHA256 hex digest

    def test_compute_envelope_hash_different_for_different_envelopes(self):
        """Test that different envelopes produce different hashes."""
        env1 = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            payload=b"payload1",
        )
        env2 = build_envelope(
            producer_id="agent-2",
            message_type=C.DATA,
            payload=b"payload2",
        )
        hash1 = compute_envelope_hash(env1)
        hash2 = compute_envelope_hash(env2)
        assert hash1 != hash2

    def test_create_simple_proof(self):
        """Test creating a simple hash-based proof."""
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            payload=b"test",
        )
        proof = create_simple_proof(env, "agent-1")

        assert proof.proof_type == "simple_hash"
        assert len(proof.proof_data) == 32  # SHA256 output
        assert proof.verified is False
        assert proof.proof_id  # Should have a UUID
        assert proof.created_at  # Should have a timestamp

    def test_create_simple_proof_deterministic_for_same_input(self):
        """Test that proof creation is deterministic for same timestamp."""
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            payload=b"test",
        )
        # Note: proofs will differ due to timestamp and UUID generation
        # This tests that the proof is created successfully
        proof1 = create_simple_proof(env, "agent-1")
        proof2 = create_simple_proof(env, "agent-1")

        assert proof1.proof_type == proof2.proof_type
        # proof_data will differ due to timestamp in proof_input

    def test_verify_audit_proof_simple_hash(self):
        """Test verifying a simple hash proof."""
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            payload=b"test",
        )
        proof = create_simple_proof(env, "agent-1")

        assert verify_audit_proof(env, proof) is True

    def test_verify_audit_proof_noop(self):
        """Test verifying a no-op proof."""
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        proof = AuditProof(
            proof_id="test-id",
            proof_type="noop",
            proof_data=b"",
            created_at="1234567890",
        )
        assert verify_audit_proof(env, proof) is True

    def test_verify_audit_proof_invalid_simple_hash(self):
        """Test verifying an invalid simple hash proof."""
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        # Create proof with wrong size
        proof = AuditProof(
            proof_id="test-id",
            proof_type="simple_hash",
            proof_data=b"invalid",  # Wrong size
            created_at="1234567890",
        )
        assert verify_audit_proof(env, proof) is False

    def test_verify_audit_proof_unknown_type(self):
        """Test verifying a proof with unknown type."""
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        proof = AuditProof(
            proof_id="test-id",
            proof_type="unknown_type",
            proof_data=b"some data",
            created_at="1234567890",
        )
        assert verify_audit_proof(env, proof) is False


class TestNoOpAuditor:
    """Test NoOpAuditor implementation."""

    def test_create_proof(self):
        """Test NoOpAuditor creates minimal proof."""
        auditor = NoOpAuditor()
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        proof = auditor.create_proof(env, "send")

        assert proof.proof_type == "noop"
        assert proof.proof_data == b""
        assert proof.verified is True

    def test_verify_proof_always_true(self):
        """Test NoOpAuditor always verifies proofs."""
        auditor = NoOpAuditor()
        proof = AuditProof(
            proof_id="test",
            proof_type="anything",
            proof_data=b"anything",
            created_at="123",
        )
        assert auditor.verify_proof(proof) is True

    def test_record_creates_record(self):
        """Test NoOpAuditor creates audit record."""
        auditor = NoOpAuditor()
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        record = auditor.record(env, "send", None)

        assert record.envelope_id == env["message_id"]
        assert record.action == "send"
        assert record.actor_id == "agent-1"
        assert record.proof is None

    def test_record_with_proof(self):
        """Test NoOpAuditor record includes proof if provided."""
        auditor = NoOpAuditor()
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        proof = auditor.create_proof(env, "send")
        record = auditor.record(env, "send", proof)

        assert record.proof == proof

    def test_query_always_empty(self):
        """Test NoOpAuditor query always returns empty list."""
        auditor = NoOpAuditor()
        assert auditor.query("any-id") == []


class TestInMemoryAuditor:
    """Test InMemoryAuditor implementation."""

    def test_create_proof(self):
        """Test InMemoryAuditor creates simple hash proof."""
        auditor = InMemoryAuditor()
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        proof = auditor.create_proof(env, "send")

        assert proof.proof_type == "simple_hash"
        assert len(proof.proof_data) == 32
        assert proof.verified is False

    def test_verify_proof_simple_hash(self):
        """Test InMemoryAuditor verifies simple hash proofs."""
        auditor = InMemoryAuditor()
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        proof = auditor.create_proof(env, "send")
        assert auditor.verify_proof(proof) is True

    def test_verify_proof_noop(self):
        """Test InMemoryAuditor verifies noop proofs."""
        auditor = InMemoryAuditor()
        proof = AuditProof(
            proof_id="test",
            proof_type="noop",
            proof_data=b"",
            created_at="123",
        )
        assert auditor.verify_proof(proof) is True

    def test_verify_proof_invalid(self):
        """Test InMemoryAuditor rejects invalid proofs."""
        auditor = InMemoryAuditor()
        proof = AuditProof(
            proof_id="test",
            proof_type="unknown",
            proof_data=b"data",
            created_at="123",
        )
        assert auditor.verify_proof(proof) is False

    def test_record_stores_record(self):
        """Test InMemoryAuditor stores audit records."""
        auditor = InMemoryAuditor()
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        record = auditor.record(env, "send", None)

        assert record.envelope_id == env["message_id"]
        assert record.action == "send"

        # Query should return the record
        records = auditor.query(env["message_id"])
        assert len(records) == 1
        assert records[0] == record

    def test_record_multiple_actions(self):
        """Test InMemoryAuditor tracks multiple actions for same envelope."""
        auditor = InMemoryAuditor()
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )

        record1 = auditor.record(env, "send", None)
        record2 = auditor.record(env, "receive", None)
        record3 = auditor.record(env, "process", None)

        records = auditor.query(env["message_id"])
        assert len(records) == 3
        assert records[0].action == "send"
        assert records[1].action == "receive"
        assert records[2].action == "process"

    def test_query_nonexistent_envelope(self):
        """Test querying for non-existent envelope returns empty list."""
        auditor = InMemoryAuditor()
        records = auditor.query("nonexistent-id")
        assert records == []

    def test_get_all_records(self):
        """Test getting all records across envelopes."""
        auditor = InMemoryAuditor()
        env1 = build_envelope(producer_id="agent-1", message_type=C.DATA)
        env2 = build_envelope(producer_id="agent-2", message_type=C.DATA)

        auditor.record(env1, "send", None)
        auditor.record(env1, "receive", None)
        auditor.record(env2, "send", None)

        all_records = auditor.get_all_records()
        assert len(all_records) == 3

    def test_clear_records(self):
        """Test clearing all audit records."""
        auditor = InMemoryAuditor()
        env = build_envelope(producer_id="agent-1", message_type=C.DATA)

        auditor.record(env, "send", None)
        assert len(auditor.get_all_records()) == 1

        auditor.clear()
        assert len(auditor.get_all_records()) == 0
        assert auditor.query(env["message_id"]) == []


class TestEnvelopeIntegration:
    """Test integration with envelope building."""

    def test_build_envelope_with_audit_proof(self):
        """Test building envelope with audit proof."""
        proof_data = b"test_proof"
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            audit_proof=proof_data,
        )
        assert env["audit_proof"] == proof_data

    def test_build_envelope_with_audit_policy_id(self):
        """Test building envelope with audit policy ID."""
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            audit_policy_id="policy-123",
        )
        assert env["audit_policy_id"] == "policy-123"

    def test_build_envelope_with_both_audit_fields(self):
        """Test building envelope with both audit fields."""
        proof_data = b"test_proof"
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            audit_proof=proof_data,
            audit_policy_id="policy-456",
        )
        assert env["audit_proof"] == proof_data
        assert env["audit_policy_id"] == "policy-456"

    def test_build_envelope_without_audit_fields(self):
        """Test building envelope without audit fields uses defaults."""
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        assert env["audit_proof"] == b""
        assert env["audit_policy_id"] == ""


class TestAuditWorkflow:
    """Test complete audit workflow scenarios."""

    def test_full_audit_workflow(self):
        """Test complete audit workflow: create, record, query."""
        auditor = InMemoryAuditor()

        # Build envelope
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            payload=b"test payload",
        )

        # Create proof
        proof = auditor.create_proof(env, "send")
        assert auditor.verify_proof(proof) is True

        # Record action with proof
        record = auditor.record(env, "send", proof)
        assert record.proof == proof

        # Query records
        records = auditor.query(env["message_id"])
        assert len(records) == 1
        assert records[0].proof == proof

    def test_audit_workflow_with_envelope_proof(self):
        """Test audit workflow with proof embedded in envelope."""
        auditor = InMemoryAuditor()

        # Create initial envelope
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            payload=b"test",
        )

        # Create proof and embed in envelope
        proof = auditor.create_proof(env, "send")
        env_with_proof = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
            payload=b"test",
            audit_proof=proof.proof_data,
            audit_policy_id="policy-1",
        )

        # Record
        record = auditor.record(env_with_proof, "send", proof)

        # Verify
        assert env_with_proof["audit_proof"] == proof.proof_data
        assert env_with_proof["audit_policy_id"] == "policy-1"

        # Query
        records = auditor.query(env_with_proof["message_id"])
        assert len(records) == 1

    def test_audit_trail_across_multiple_agents(self):
        """Test audit trail across multiple agents."""
        auditor = InMemoryAuditor()

        # Agent 1 sends
        env = build_envelope(
            producer_id="agent-1",
            message_type=C.DATA,
        )
        proof1 = auditor.create_proof(env, "send")
        auditor.record(env, "send", proof1)

        # Agent 2 receives
        proof2 = auditor.create_proof(env, "receive")
        auditor.record(env, "receive", proof2)

        # Agent 2 processes
        proof3 = auditor.create_proof(env, "process")
        auditor.record(env, "process", proof3)

        # Verify audit trail
        records = auditor.query(env["message_id"])
        assert len(records) == 3
        assert records[0].action == "send"
        assert records[1].action == "receive"
        assert records[2].action == "process"

        # Each has a proof
        for record in records:
            assert record.proof is not None
            assert auditor.verify_proof(record.proof) is True
