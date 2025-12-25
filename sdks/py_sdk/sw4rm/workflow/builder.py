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

"""Fluent API for building workflow definitions.

This module provides the WorkflowBuilder class with a chainable fluent API
for constructing workflow DAGs programmatically with validation.
"""

from __future__ import annotations

from typing import Any, Optional

from .types import (
    WorkflowDefinition,
    WorkflowNode,
    TriggerType,
)
from .engine import WorkflowEngine, CycleDetectedError


class WorkflowBuilderError(Exception):
    """Base exception for workflow builder errors."""
    pass


class WorkflowBuilder:
    """Fluent API builder for constructing workflow definitions.

    Provides a chainable interface for building workflows step by step with
    validation. Supports adding nodes, dependencies, triggers, and I/O mappings.

    Example:
        builder = WorkflowBuilder("my_workflow")
        builder.add_node("fetch", "fetcher_agent")
               .add_node("process", "processor_agent")
               .add_dependency("fetch", "process")
               .set_input_mapping("process", {"data": "fetch_output"})
               .build()
    """

    def __init__(self, workflow_id: str):
        """Initialize a new workflow builder.

        Args:
            workflow_id: Unique identifier for the workflow
        """
        if not workflow_id or not workflow_id.strip():
            raise WorkflowBuilderError("workflow_id must be a non-empty string")

        self.workflow_id = workflow_id
        self._nodes: dict[str, dict[str, Any]] = {}
        self._metadata: dict[str, Any] = {}

    def add_node(
        self,
        node_id: str,
        agent_id: str,
        trigger_type: TriggerType = TriggerType.EVENT
    ) -> WorkflowBuilder:
        """Add a node to the workflow.

        Args:
            node_id: Unique identifier for the node
            agent_id: Identifier of the agent that executes this node
            trigger_type: How the node is triggered (default: EVENT)

        Returns:
            Self for method chaining

        Raises:
            WorkflowBuilderError: If node_id already exists or is invalid
        """
        if not node_id or not node_id.strip():
            raise WorkflowBuilderError("node_id must be a non-empty string")
        if not agent_id or not agent_id.strip():
            raise WorkflowBuilderError("agent_id must be a non-empty string")
        if node_id in self._nodes:
            raise WorkflowBuilderError(f"node {node_id} already exists")

        self._nodes[node_id] = {
            "agent_id": agent_id,
            "depends_on": set(),
            "trigger_type": trigger_type,
            "input_mapping": {},
            "output_mapping": {},
            "metadata": {},
        }
        return self

    def add_dependency(self, from_node: str, to_node: str) -> WorkflowBuilder:
        """Add a dependency edge between nodes.

        The to_node will depend on from_node, meaning from_node must complete
        before to_node can execute.

        Args:
            from_node: Node that must execute first
            to_node: Node that depends on from_node

        Returns:
            Self for method chaining

        Raises:
            WorkflowBuilderError: If either node doesn't exist or dependency is invalid
        """
        if from_node not in self._nodes:
            raise WorkflowBuilderError(f"from_node {from_node} does not exist")
        if to_node not in self._nodes:
            raise WorkflowBuilderError(f"to_node {to_node} does not exist")
        if from_node == to_node:
            raise WorkflowBuilderError(f"node {from_node} cannot depend on itself")

        self._nodes[to_node]["depends_on"].add(from_node)
        return self

    def add_dependencies(self, from_nodes: list[str], to_node: str) -> WorkflowBuilder:
        """Add multiple dependency edges to a single node.

        Convenience method for adding multiple dependencies at once.

        Args:
            from_nodes: List of nodes that must execute first
            to_node: Node that depends on all from_nodes

        Returns:
            Self for method chaining

        Raises:
            WorkflowBuilderError: If any node doesn't exist or dependencies are invalid
        """
        for from_node in from_nodes:
            self.add_dependency(from_node, to_node)
        return self

    def set_trigger(self, node_id: str, trigger_type: TriggerType) -> WorkflowBuilder:
        """Set the trigger type for a node.

        Args:
            node_id: The node to update
            trigger_type: The trigger type to set

        Returns:
            Self for method chaining

        Raises:
            WorkflowBuilderError: If node doesn't exist
        """
        if node_id not in self._nodes:
            raise WorkflowBuilderError(f"node {node_id} does not exist")

        self._nodes[node_id]["trigger_type"] = trigger_type
        return self

    def set_input_mapping(
        self,
        node_id: str,
        input_mapping: dict[str, str]
    ) -> WorkflowBuilder:
        """Set input mapping for a node.

        Maps workflow state keys to node input parameters.

        Args:
            node_id: The node to update
            input_mapping: Dictionary mapping parameter names to state keys

        Returns:
            Self for method chaining

        Raises:
            WorkflowBuilderError: If node doesn't exist
        """
        if node_id not in self._nodes:
            raise WorkflowBuilderError(f"node {node_id} does not exist")

        self._nodes[node_id]["input_mapping"] = input_mapping.copy()
        return self

    def set_output_mapping(
        self,
        node_id: str,
        output_mapping: dict[str, str]
    ) -> WorkflowBuilder:
        """Set output mapping for a node.

        Maps node output keys to workflow state keys.

        Args:
            node_id: The node to update
            output_mapping: Dictionary mapping output keys to state keys

        Returns:
            Self for method chaining

        Raises:
            WorkflowBuilderError: If node doesn't exist
        """
        if node_id not in self._nodes:
            raise WorkflowBuilderError(f"node {node_id} does not exist")

        self._nodes[node_id]["output_mapping"] = output_mapping.copy()
        return self

    def set_node_metadata(
        self,
        node_id: str,
        metadata: dict[str, Any]
    ) -> WorkflowBuilder:
        """Set metadata for a node.

        Args:
            node_id: The node to update
            metadata: Metadata dictionary

        Returns:
            Self for method chaining

        Raises:
            WorkflowBuilderError: If node doesn't exist
        """
        if node_id not in self._nodes:
            raise WorkflowBuilderError(f"node {node_id} does not exist")

        self._nodes[node_id]["metadata"] = metadata.copy()
        return self

    def set_workflow_metadata(self, metadata: dict[str, Any]) -> WorkflowBuilder:
        """Set metadata for the workflow.

        Args:
            metadata: Metadata dictionary

        Returns:
            Self for method chaining
        """
        self._metadata = metadata.copy()
        return self

    def remove_node(self, node_id: str) -> WorkflowBuilder:
        """Remove a node from the workflow.

        Also removes all dependencies involving this node.

        Args:
            node_id: The node to remove

        Returns:
            Self for method chaining

        Raises:
            WorkflowBuilderError: If node doesn't exist
        """
        if node_id not in self._nodes:
            raise WorkflowBuilderError(f"node {node_id} does not exist")

        # Remove the node
        del self._nodes[node_id]

        # Remove all dependencies involving this node
        for node_data in self._nodes.values():
            node_data["depends_on"].discard(node_id)

        return self

    def build(self, validate: bool = True) -> WorkflowDefinition:
        """Build and validate the workflow definition.

        Args:
            validate: Whether to validate the DAG structure (default: True)

        Returns:
            Immutable WorkflowDefinition instance

        Raises:
            WorkflowBuilderError: If workflow is invalid
            CycleDetectedError: If a cycle is detected in the DAG
        """
        if not self._nodes:
            raise WorkflowBuilderError("workflow must contain at least one node")

        # Convert internal representation to WorkflowNode instances
        nodes = {}
        for node_id, node_data in self._nodes.items():
            nodes[node_id] = WorkflowNode(
                node_id=node_id,
                agent_id=node_data["agent_id"],
                depends_on=frozenset(node_data["depends_on"]),
                trigger_type=node_data["trigger_type"],
                input_mapping=node_data["input_mapping"],
                output_mapping=node_data["output_mapping"],
                metadata=node_data["metadata"],
            )

        # Create workflow definition
        workflow = WorkflowDefinition(
            workflow_id=self.workflow_id,
            nodes=nodes,
            metadata=self._metadata,
        )

        # Validate DAG structure if requested
        if validate:
            try:
                # Validation happens in the engine constructor
                WorkflowEngine(workflow, executor=None)
            except CycleDetectedError as e:
                raise WorkflowBuilderError(f"Workflow validation failed: {e}") from e

        return workflow

    def clone(self) -> WorkflowBuilder:
        """Create a deep copy of this builder.

        Returns:
            New WorkflowBuilder with the same configuration
        """
        new_builder = WorkflowBuilder(self.workflow_id)
        new_builder._metadata = self._metadata.copy()

        # Deep copy nodes
        for node_id, node_data in self._nodes.items():
            new_builder._nodes[node_id] = {
                "agent_id": node_data["agent_id"],
                "depends_on": node_data["depends_on"].copy(),
                "trigger_type": node_data["trigger_type"],
                "input_mapping": node_data["input_mapping"].copy(),
                "output_mapping": node_data["output_mapping"].copy(),
                "metadata": node_data["metadata"].copy(),
            }

        return new_builder

    def get_node_count(self) -> int:
        """Get the number of nodes in the workflow.

        Returns:
            Number of nodes
        """
        return len(self._nodes)

    def has_node(self, node_id: str) -> bool:
        """Check if a node exists.

        Args:
            node_id: The node to check

        Returns:
            True if the node exists, False otherwise
        """
        return node_id in self._nodes

    def get_node_dependencies(self, node_id: str) -> set[str]:
        """Get the dependencies of a node.

        Args:
            node_id: The node to query

        Returns:
            Set of node_ids that this node depends on

        Raises:
            WorkflowBuilderError: If node doesn't exist
        """
        if node_id not in self._nodes:
            raise WorkflowBuilderError(f"node {node_id} does not exist")

        return self._nodes[node_id]["depends_on"].copy()
