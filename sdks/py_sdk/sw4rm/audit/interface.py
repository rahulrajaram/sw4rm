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

"""Auditor interface and implementations."""

import uuid
from typing import Protocol, Optional
from .types import AuditProof, AuditRecord


class Auditor(Protocol):
    """Protocol defining the interface for audit implementations.

    Implementations can range from no-op (for development) to full
    ZK-proof based systems (for production).
    """

    def create_proof(self, envelope: dict, action: str) -> AuditProof:
        """Create a proof for an envelope action.

        Args:
            envelope: The envelope dict to create proof for
            action: The action being performed (e.g., "send", "receive")

        Returns:
            An AuditProof instance
        """
        ...

    def verify_proof(self, proof: AuditProof) -> bool:
        """Verify the validity of a proof.

        Args:
            proof: The proof to verify

        Returns:
            True if proof is valid, False otherwise
        """
        ...

    def record(
        self, envelope: dict, action: str, proof: Optional[AuditProof] = None
    ) -> AuditRecord:
        """Record an audit event.

        Args:
            envelope: The envelope being audited
            action: The action being performed
            proof: Optional proof to attach to the record

        Returns:
            The created AuditRecord
        """
        ...

    def query(self, envelope_id: str) -> list[AuditRecord]:
        """Query audit records for a specific envelope.

        Args:
            envelope_id: The message_id of the envelope to query

        Returns:
            List of AuditRecords for this envelope
        """
        ...


class NoOpAuditor:
    """No-op auditor that does nothing.

    Useful for development and when audit trail is not required.
    """

    def create_proof(self, envelope: dict, action: str) -> AuditProof:
        """Create a minimal no-op proof."""
        from ..envelope import now_hlc_stub
        return AuditProof(
            proof_id=str(uuid.uuid4()),
            proof_type="noop",
            proof_data=b"",
            created_at=now_hlc_stub(),
            verified=True,
        )

    def verify_proof(self, proof: AuditProof) -> bool:
        """Always returns True for no-op proofs."""
        return True

    def record(
        self, envelope: dict, action: str, proof: Optional[AuditProof] = None
    ) -> AuditRecord:
        """Create a minimal audit record without storing it."""
        from ..envelope import now_hlc_stub
        return AuditRecord(
            record_id=str(uuid.uuid4()),
            envelope_id=envelope.get("message_id", "unknown"),
            action=action,
            actor_id=envelope.get("producer_id", "unknown"),
            timestamp=now_hlc_stub(),
            proof=proof,
        )

    def query(self, envelope_id: str) -> list[AuditRecord]:
        """Always returns empty list."""
        return []


class InMemoryAuditor:
    """In-memory auditor for testing and development.

    Stores audit records in memory and supports basic querying.
    Not suitable for production use.
    """

    def __init__(self) -> None:
        """Initialize with empty record storage."""
        self._records: dict[str, list[AuditRecord]] = {}

    def create_proof(self, envelope: dict, action: str) -> AuditProof:
        """Create a simple hash-based proof."""
        from .verification import create_simple_proof
        return create_simple_proof(
            envelope, envelope.get("producer_id", "unknown")
        )

    def verify_proof(self, proof: AuditProof) -> bool:
        """Verify a proof using the verification module."""
        # Handle different proof types
        if proof.proof_type == "noop":
            return True

        # For simple hash proofs, check that the proof_data is non-empty
        if proof.proof_type == "simple_hash":
            return len(proof.proof_data) > 0

        # Unknown proof types are not verified
        return False

    def record(
        self, envelope: dict, action: str, proof: Optional[AuditProof] = None
    ) -> AuditRecord:
        """Create and store an audit record."""
        from ..envelope import now_hlc_stub

        record = AuditRecord(
            record_id=str(uuid.uuid4()),
            envelope_id=envelope.get("message_id", "unknown"),
            action=action,
            actor_id=envelope.get("producer_id", "unknown"),
            timestamp=now_hlc_stub(),
            proof=proof,
        )

        # Store the record
        envelope_id = record.envelope_id
        if envelope_id not in self._records:
            self._records[envelope_id] = []
        self._records[envelope_id].append(record)

        return record

    def query(self, envelope_id: str) -> list[AuditRecord]:
        """Query all audit records for a specific envelope."""
        return self._records.get(envelope_id, [])

    def get_all_records(self) -> list[AuditRecord]:
        """Get all audit records (useful for testing)."""
        all_records = []
        for records in self._records.values():
            all_records.extend(records)
        return all_records

    def clear(self) -> None:
        """Clear all stored records (useful for testing)."""
        self._records.clear()
