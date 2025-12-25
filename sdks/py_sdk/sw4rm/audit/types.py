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

"""Types for audit proof extension."""

from dataclasses import dataclass
from typing import Optional


@dataclass
class AuditProof:
    """Represents a cryptographic or logical proof for an audit event.

    Attributes:
        proof_id: Unique identifier for this proof
        proof_type: Type of proof (e.g., "simple_hash", "zk_proof", "signature")
        proof_data: The actual proof data as bytes
        created_at: Timestamp when the proof was created (HLC or unix ms)
        verified: Whether this proof has been verified
    """
    proof_id: str
    proof_type: str
    proof_data: bytes
    created_at: str
    verified: bool = False


@dataclass
class AuditPolicy:
    """Defines audit requirements for envelope processing.

    Attributes:
        policy_id: Unique identifier for this policy
        require_proof: Whether proof is required for this policy
        verification_level: Level of verification required (e.g., "none", "basic", "strict")
        retention_days: How many days to retain audit records
    """
    policy_id: str
    require_proof: bool
    verification_level: str
    retention_days: int


@dataclass
class AuditRecord:
    """Represents a complete audit record for an envelope action.

    Attributes:
        record_id: Unique identifier for this audit record
        envelope_id: The message_id of the envelope being audited
        action: The action performed (e.g., "send", "receive", "process")
        actor_id: ID of the agent/component that performed the action
        timestamp: When the action occurred (HLC or unix ms)
        proof: Optional proof associated with this action
    """
    record_id: str
    envelope_id: str
    action: str
    actor_id: str
    timestamp: str
    proof: Optional[AuditProof] = None
