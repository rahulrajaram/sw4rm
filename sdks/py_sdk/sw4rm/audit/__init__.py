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

"""Audit proof extension for SW4RM protocol.

This module provides audit trail capabilities with optional proof generation
and verification, inspired by ZK-MCP research.
"""

from .types import AuditProof, AuditPolicy, AuditRecord
from .interface import Auditor, NoOpAuditor, InMemoryAuditor
from .verification import (
    verify_audit_proof,
    compute_envelope_hash,
    create_simple_proof,
)

__all__ = [
    "AuditProof",
    "AuditPolicy",
    "AuditRecord",
    "Auditor",
    "NoOpAuditor",
    "InMemoryAuditor",
    "verify_audit_proof",
    "compute_envelope_hash",
    "create_simple_proof",
]
