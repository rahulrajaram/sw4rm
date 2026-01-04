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

"""
SW4RM Coordination Services.

This package provides gRPC server implementations for the three in-memory
coordination services:

- HandoffService: Agent-to-agent task handoff coordination
- WorkflowService: DAG-based workflow orchestration
- NegotiationRoomService: Multi-agent artifact approval workflows

These services maintain centralized state that can be shared across
distributed agent deployments. All three SDKs (Python, Rust, TypeScript)
can connect to these services as gRPC clients.

Typical deployment:
    python -m reference_services.coordination.server --port 50060

Environment variables:
    COORDINATION_PORT: gRPC server port (default: 50060)
"""

from .handoff_service import HandoffServiceImpl
from .workflow_service import WorkflowServiceImpl
from .negotiation_room_service import NegotiationRoomServiceImpl

__all__ = [
    "HandoffServiceImpl",
    "WorkflowServiceImpl",
    "NegotiationRoomServiceImpl",
]
