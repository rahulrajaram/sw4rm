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

"""SW4RM Agentic Protocol — Reference Python SDK (experimental).

This package provides a lightweight runtime, clients, and helpers for building
agents that speak the SW4RM Agentic Protocol specified in the local .proto files.
"""

__all__ = [
    "config",
    "activity_buffer",
    "persistence",
    "worktree_state",
    "worktree_policies",
    "ack_integration",
    "envelope",
    "acks",
    "constants",
    "error_mapping",
    "buffer_strategy",
    "metrics",
    "content_types",
    "shared_context",
    # Cross-cutting concerns (Phase 3.6)
    "logging",
    "tracing",
    "feature_flags",
    # Clients
    "clients",
    # Workflow orchestration
    "workflow",
    # Handoff
    "handoff",
]

__version__ = "0.4.0"
