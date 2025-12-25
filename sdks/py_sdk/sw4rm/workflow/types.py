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

"""Workflow type definitions for SW4RM agent orchestration.

This module provides the core type system for defining and executing workflows
as directed acyclic graphs (DAGs) of agent nodes. Inspired by CrewAI Flows,
this enables complex multi-agent coordination with dependencies, triggers, and
state management.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Optional


class NodeStatus(str, Enum):
    """Execution status of a workflow node.

    Tracks the lifecycle state of individual nodes during workflow execution.
    """
    PENDING = "pending"      # Node waiting for dependencies
    RUNNING = "running"      # Node currently executing
    COMPLETED = "completed"  # Node finished successfully
    FAILED = "failed"        # Node encountered an error
    SKIPPED = "skipped"      # Node skipped due to conditional logic


class TriggerType(str, Enum):
    """Trigger mechanism for node execution.

    Defines how and when a node should be activated within the workflow.
    """
    EVENT = "event"          # Triggered by specific events
    SCHEDULE = "schedule"    # Triggered on a schedule (cron-like)
    MANUAL = "manual"        # Triggered by explicit user action


@dataclass(frozen=True)
class WorkflowNode:
    """A single node in a workflow DAG.

    Represents an agent or operation with dependencies, triggers, and I/O mappings.
    Nodes are immutable once created to ensure workflow definition integrity.

    Attributes:
        node_id: Unique identifier for this node within the workflow
        agent_id: Identifier of the agent that executes this node
        depends_on: Set of node_ids that must complete before this node runs
        trigger_type: How this node is triggered (default: EVENT)
        input_mapping: Maps workflow state keys to node input parameters
        output_mapping: Maps node output keys to workflow state keys
        metadata: Additional node configuration and context
    """
    node_id: str
    agent_id: str
    depends_on: frozenset[str] = field(default_factory=frozenset)
    trigger_type: TriggerType = TriggerType.EVENT
    input_mapping: dict[str, str] = field(default_factory=dict)
    output_mapping: dict[str, str] = field(default_factory=dict)
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        """Validate node configuration."""
        if not self.node_id or not self.node_id.strip():
            raise ValueError("node_id must be a non-empty string")
        if not self.agent_id or not self.agent_id.strip():
            raise ValueError("agent_id must be a non-empty string")
        if self.node_id in self.depends_on:
            raise ValueError(f"node {self.node_id} cannot depend on itself")


@dataclass(frozen=True)
class WorkflowDefinition:
    """Immutable workflow definition as a DAG of nodes.

    Defines the complete structure of a multi-agent workflow including all nodes,
    their dependencies, and metadata. Once created, workflows are immutable to
    ensure execution consistency.

    Attributes:
        workflow_id: Unique identifier for this workflow
        nodes: Dictionary mapping node_id to WorkflowNode instances
        metadata: Workflow-level configuration and context
    """
    workflow_id: str
    nodes: dict[str, WorkflowNode]
    metadata: dict[str, Any] = field(default_factory=dict)

    def __post_init__(self) -> None:
        """Validate workflow structure."""
        if not self.workflow_id or not self.workflow_id.strip():
            raise ValueError("workflow_id must be a non-empty string")
        if not self.nodes:
            raise ValueError("workflow must contain at least one node")

        # Validate all dependency references exist
        all_node_ids = set(self.nodes.keys())
        for node in self.nodes.values():
            invalid_deps = node.depends_on - all_node_ids
            if invalid_deps:
                raise ValueError(
                    f"node {node.node_id} has invalid dependencies: {invalid_deps}"
                )

    def get_node(self, node_id: str) -> Optional[WorkflowNode]:
        """Get a node by ID.

        Args:
            node_id: The node identifier

        Returns:
            The WorkflowNode if found, None otherwise
        """
        return self.nodes.get(node_id)

    def get_root_nodes(self) -> set[str]:
        """Get all nodes with no dependencies (entry points).

        Returns:
            Set of node_ids that have no dependencies
        """
        return {node_id for node_id, node in self.nodes.items() if not node.depends_on}

    def get_leaf_nodes(self) -> set[str]:
        """Get all nodes that no other nodes depend on (exit points).

        Returns:
            Set of node_ids that are not dependencies of any other node
        """
        all_deps = set()
        for node in self.nodes.values():
            all_deps.update(node.depends_on)
        return set(self.nodes.keys()) - all_deps


@dataclass
class NodeState:
    """Runtime state of a single workflow node.

    Tracks the execution state, results, and errors for a node during workflow
    execution. Mutable to allow state updates.

    Attributes:
        node_id: The node this state belongs to
        status: Current execution status
        result: Output data from node execution (if completed)
        error: Error information if node failed
        start_time: When node execution started (milliseconds since epoch)
        end_time: When node execution completed (milliseconds since epoch)
    """
    node_id: str
    status: NodeStatus = NodeStatus.PENDING
    result: Optional[dict[str, Any]] = None
    error: Optional[str] = None
    start_time: Optional[int] = None
    end_time: Optional[int] = None

    @property
    def is_terminal(self) -> bool:
        """Check if node is in a terminal state (completed, failed, or skipped)."""
        return self.status in {NodeStatus.COMPLETED, NodeStatus.FAILED, NodeStatus.SKIPPED}

    @property
    def duration_ms(self) -> Optional[int]:
        """Calculate execution duration in milliseconds."""
        if self.start_time and self.end_time:
            return self.end_time - self.start_time
        return None


@dataclass
class WorkflowState:
    """Runtime state for an executing workflow.

    Maintains the execution state for all nodes and shared workflow data.
    This is the mutable counterpart to WorkflowDefinition.

    Attributes:
        workflow_id: Identifier of the workflow being executed
        node_states: Map of node_id to NodeState for tracking execution
        shared_data: Shared key-value store for inter-node data passing
        checkpoint_data: Data for checkpoint/resume functionality
        metadata: Additional runtime metadata
    """
    workflow_id: str
    node_states: dict[str, NodeState] = field(default_factory=dict)
    shared_data: dict[str, Any] = field(default_factory=dict)
    checkpoint_data: dict[str, Any] = field(default_factory=dict)
    metadata: dict[str, Any] = field(default_factory=dict)

    def get_node_state(self, node_id: str) -> Optional[NodeState]:
        """Get the state of a specific node.

        Args:
            node_id: The node identifier

        Returns:
            NodeState if found, None otherwise
        """
        return self.node_states.get(node_id)

    def is_completed(self) -> bool:
        """Check if all nodes are in terminal states.

        Returns:
            True if workflow execution is complete
        """
        return all(state.is_terminal for state in self.node_states.values())

    def has_failures(self) -> bool:
        """Check if any nodes failed.

        Returns:
            True if any node has FAILED status
        """
        return any(state.status == NodeStatus.FAILED for state in self.node_states.values())

    def get_completed_nodes(self) -> set[str]:
        """Get all successfully completed node IDs.

        Returns:
            Set of node_ids that have completed successfully
        """
        return {
            node_id for node_id, state in self.node_states.items()
            if state.status == NodeStatus.COMPLETED
        }

    def get_failed_nodes(self) -> set[str]:
        """Get all failed node IDs.

        Returns:
            Set of node_ids that have failed
        """
        return {
            node_id for node_id, state in self.node_states.items()
            if state.status == NodeStatus.FAILED
        }
