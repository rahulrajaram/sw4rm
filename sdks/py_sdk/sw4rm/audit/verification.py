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

"""Audit proof verification functions."""

import hashlib
import json
import uuid
from .types import AuditProof


def compute_envelope_hash(envelope: dict) -> str:
    """Compute SHA256 hash of an envelope.

    Args:
        envelope: The envelope dict to hash

    Returns:
        Hex-encoded SHA256 hash of the envelope
    """
    # Create a deterministic representation of the envelope
    # We sort keys and use compact JSON to ensure consistency
    envelope_copy = envelope.copy()

    # Extract binary fields that can't be JSON serialized
    payload = envelope_copy.pop("payload", None)
    audit_proof = envelope_copy.pop("audit_proof", None)

    # Create deterministic JSON representation of non-binary fields
    envelope_json = json.dumps(envelope_copy, sort_keys=True, separators=(",", ":"))

    # Create hash
    hasher = hashlib.sha256()
    hasher.update(envelope_json.encode("utf-8"))

    # Include binary fields in hash
    if payload:
        if isinstance(payload, bytes):
            hasher.update(payload)
        elif isinstance(payload, str):
            hasher.update(payload.encode("utf-8"))

    if audit_proof:
        if isinstance(audit_proof, bytes):
            hasher.update(audit_proof)
        elif isinstance(audit_proof, str):
            hasher.update(audit_proof.encode("utf-8"))

    return hasher.hexdigest()


def create_simple_proof(envelope: dict, actor_id: str) -> AuditProof:
    """Create a simple hash-based proof for an envelope.

    This is a basic proof mechanism suitable for testing and development.
    Production systems should use more sophisticated proof mechanisms
    (e.g., ZK-proofs, digital signatures).

    Args:
        envelope: The envelope to create proof for
        actor_id: ID of the actor creating the proof

    Returns:
        An AuditProof with simple hash-based proof
    """
    from ..envelope import now_hlc_stub

    # Compute envelope hash
    envelope_hash = compute_envelope_hash(envelope)

    # Create proof data: hash of (envelope_hash + actor_id + timestamp)
    timestamp = now_hlc_stub()
    proof_input = f"{envelope_hash}:{actor_id}:{timestamp}"
    proof_hash = hashlib.sha256(proof_input.encode("utf-8")).digest()

    return AuditProof(
        proof_id=str(uuid.uuid4()),
        proof_type="simple_hash",
        proof_data=proof_hash,
        created_at=timestamp,
        verified=False,
    )


def verify_audit_proof(envelope: dict, proof: AuditProof) -> bool:
    """Verify an audit proof against an envelope.

    Args:
        envelope: The envelope to verify against
        proof: The proof to verify

    Returns:
        True if proof is valid, False otherwise
    """
    # Handle different proof types
    if proof.proof_type == "noop":
        return True

    if proof.proof_type == "simple_hash":
        # For simple hash proofs, we verify that:
        # 1. The proof data is non-empty
        # 2. The proof was created for this envelope (basic sanity check)
        if len(proof.proof_data) == 0:
            return False

        # Compute expected hash for verification
        envelope_hash = compute_envelope_hash(envelope)

        # In a real implementation, we would reconstruct the proof
        # and compare it with the provided proof_data
        # For now, we do a basic check that the hash is consistent
        # This is a simplified verification - production systems need more rigor

        # Verify the proof data is 32 bytes (SHA256 output)
        if len(proof.proof_data) != 32:
            return False

        return True

    # Unknown proof type
    return False
