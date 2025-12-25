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

"""Workflow execution engine with DAG validation and orchestration.

This module provides the core WorkflowEngine class that validates workflow DAGs,
detects cycles, computes execution order, and orchestrates multi-agent workflows
with support for parallel execution and checkpoint/resume.
"""

from __future__ import annotations

import time
from typing import Callable, Optional, Any

from .types import (
    WorkflowDefinition,
    WorkflowState,
    NodeState,
    NodeStatus,
    WorkflowNode,
)


class WorkflowEngineError(Exception):
    """Base exception for workflow engine errors."""
    pass


class CycleDetectedError(WorkflowEngineError):
    """Raised when a cycle is detected in the workflow DAG."""
    def __init__(self, cycle_path: list[str]):
        self.cycle_path = cycle_path
        super().__init__(f"Cycle detected in workflow: {' -> '.join(cycle_path)}")


class WorkflowValidationError(WorkflowEngineError):
    """Raised when workflow validation fails."""
    pass


class WorkflowEngine:
    """Execution engine for workflow DAGs.

    Validates workflow structure, detects cycles, computes execution order,
    and orchestrates workflow execution with support for parallel node execution
    and checkpoint/resume for long-running workflows.

    Attributes:
        workflow: The workflow definition to execute
        executor: Optional callable that executes individual nodes
    """

    def __init__(
        self,
        workflow: WorkflowDefinition,
        executor: Optional[Callable[[WorkflowNode, dict[str, Any]], dict[str, Any]]] = None
    ):
        """Initialize the workflow engine.

        Args:
            workflow: The workflow definition to execute
            executor: Optional function that executes a node with input data and returns output.
                     Signature: (node: WorkflowNode, input_data: dict) -> dict
                     If not provided, nodes will be marked as completed without execution.

        Raises:
            WorkflowValidationError: If workflow validation fails
            CycleDetectedError: If a cycle is detected in the DAG
        """
        self.workflow = workflow
        self.executor = executor
        self._validate_dag()

    def _validate_dag(self) -> None:
        """Validate the workflow DAG structure.

        Checks for cycles using depth-first search with cycle detection.

        Raises:
            CycleDetectedError: If a cycle is detected
        """
        # Use DFS to detect cycles
        visited = set()
        rec_stack = set()
        path = []

        def visit(node_id: str) -> None:
            if node_id in rec_stack:
                # Cycle detected - find the cycle path
                cycle_start = path.index(node_id)
                cycle_path = path[cycle_start:] + [node_id]
                raise CycleDetectedError(cycle_path)

            if node_id in visited:
                return

            visited.add(node_id)
            rec_stack.add(node_id)
            path.append(node_id)

            node = self.workflow.nodes[node_id]
            for dep in node.depends_on:
                visit(dep)

            path.pop()
            rec_stack.remove(node_id)

        # Visit all nodes to ensure we catch disconnected components
        for node_id in self.workflow.nodes:
            if node_id not in visited:
                visit(node_id)

    def topological_sort(self) -> list[str]:
        """Compute topological ordering of workflow nodes.

        Uses Kahn's algorithm to produce a valid execution order where all
        dependencies are satisfied before each node.

        Returns:
            List of node_ids in topological order

        Raises:
            WorkflowValidationError: If topological sort fails (shouldn't happen after validation)
        """
        # Calculate in-degree for each node
        in_degree = {node_id: 0 for node_id in self.workflow.nodes}
        for node in self.workflow.nodes.values():
            for dep in node.depends_on:
                in_degree[node.node_id] += 1

        # Queue of nodes with no dependencies
        queue = [node_id for node_id, degree in in_degree.items() if degree == 0]
        result = []

        while queue:
            # Process nodes with no remaining dependencies
            # Sort for deterministic ordering
            queue.sort()
            node_id = queue.pop(0)
            result.append(node_id)

            # Reduce in-degree for dependent nodes
            for other_id, other_node in self.workflow.nodes.items():
                if node_id in other_node.depends_on:
                    in_degree[other_id] -= 1
                    if in_degree[other_id] == 0:
                        queue.append(other_id)

        if len(result) != len(self.workflow.nodes):
            raise WorkflowValidationError(
                f"Topological sort failed: processed {len(result)} of {len(self.workflow.nodes)} nodes"
            )

        return result

    def is_node_ready(self, node_id: str, state: WorkflowState) -> bool:
        """Check if a node is ready to execute.

        A node is ready if all its dependencies have completed successfully.

        Args:
            node_id: The node to check
            state: Current workflow execution state

        Returns:
            True if the node is ready to execute, False otherwise
        """
        node = self.workflow.nodes.get(node_id)
        if not node:
            return False

        # Check node status
        node_state = state.get_node_state(node_id)
        if not node_state or node_state.status != NodeStatus.PENDING:
            return False

        # Check all dependencies are completed
        for dep_id in node.depends_on:
            dep_state = state.get_node_state(dep_id)
            if not dep_state or dep_state.status != NodeStatus.COMPLETED:
                return False

        return True

    def get_runnable_nodes(self, state: WorkflowState) -> list[str]:
        """Get all nodes ready for parallel execution.

        Returns nodes that have all dependencies satisfied and are in PENDING status.

        Args:
            state: Current workflow execution state

        Returns:
            List of node_ids that can be executed in parallel
        """
        runnable = []
        for node_id in self.workflow.nodes:
            if self.is_node_ready(node_id, state):
                runnable.append(node_id)
        return runnable

    def _prepare_node_input(self, node: WorkflowNode, state: WorkflowState) -> dict[str, Any]:
        """Prepare input data for node execution using input_mapping.

        Args:
            node: The node to prepare input for
            state: Current workflow state containing shared data

        Returns:
            Dictionary of input parameters for the node
        """
        input_data = {}
        for param_name, state_key in node.input_mapping.items():
            if state_key in state.shared_data:
                input_data[param_name] = state.shared_data[state_key]
        return input_data

    def _store_node_output(
        self,
        node: WorkflowNode,
        output: dict[str, Any],
        state: WorkflowState
    ) -> None:
        """Store node output in workflow state using output_mapping.

        Args:
            node: The node that produced output
            output: The output data from node execution
            state: Workflow state to update
        """
        for output_key, state_key in node.output_mapping.items():
            if output_key in output:
                state.shared_data[state_key] = output[output_key]

    def _execute_node(self, node_id: str, state: WorkflowState) -> None:
        """Execute a single node and update state.

        Args:
            node_id: The node to execute
            state: Workflow state to update

        Raises:
            Exception: If node execution fails
        """
        node = self.workflow.nodes[node_id]
        node_state = state.get_node_state(node_id)
        if not node_state:
            return

        # Mark as running
        node_state.status = NodeStatus.RUNNING
        node_state.start_time = int(time.time() * 1000)

        try:
            # Prepare input data
            input_data = self._prepare_node_input(node, state)

            # Execute node if executor is provided
            if self.executor:
                output = self.executor(node, input_data)
                node_state.result = output
                self._store_node_output(node, output, state)
            else:
                # No executor - just mark as completed
                node_state.result = {}

            # Mark as completed
            node_state.status = NodeStatus.COMPLETED
            node_state.end_time = int(time.time() * 1000)

        except Exception as e:
            # Mark as failed
            node_state.status = NodeStatus.FAILED
            node_state.error = str(e)
            node_state.end_time = int(time.time() * 1000)
            raise

    def execute(
        self,
        initial_data: Optional[dict[str, Any]] = None,
        checkpoint_interval: Optional[int] = None
    ) -> WorkflowState:
        """Execute the workflow from start to completion.

        Executes nodes in topological order, supporting parallel execution of
        independent nodes. Optionally supports checkpointing for long-running workflows.

        Args:
            initial_data: Initial data to populate workflow state shared_data
            checkpoint_interval: Optional interval in seconds to create checkpoints
                                (not implemented in this basic version)

        Returns:
            Final WorkflowState with execution results

        Raises:
            Exception: If any node execution fails
        """
        # Initialize workflow state
        state = WorkflowState(workflow_id=self.workflow.workflow_id)
        if initial_data:
            state.shared_data.update(initial_data)

        # Initialize node states
        for node_id in self.workflow.nodes:
            state.node_states[node_id] = NodeState(node_id=node_id)

        # Execute nodes in topological order
        # This simple implementation executes sequentially
        # A more advanced version would execute runnable nodes in parallel
        order = self.topological_sort()

        for node_id in order:
            self._execute_node(node_id, state)

            # Optional: checkpoint logic could go here
            # if checkpoint_interval and should_checkpoint():
            #     self._create_checkpoint(state)

        return state

    def resume_from_checkpoint(self, state: WorkflowState) -> WorkflowState:
        """Resume workflow execution from a checkpoint.

        Continues execution from a previously checkpointed state,
        skipping completed nodes.

        Args:
            state: Previously checkpointed workflow state

        Returns:
            Updated WorkflowState with execution results

        Raises:
            Exception: If any node execution fails
        """
        # Get topological order
        order = self.topological_sort()

        # Resume from first non-completed node
        for node_id in order:
            node_state = state.get_node_state(node_id)
            if node_state and node_state.status == NodeStatus.COMPLETED:
                continue

            # Ensure node state exists
            if not node_state:
                state.node_states[node_id] = NodeState(node_id=node_id)

            # Execute node if ready
            if self.is_node_ready(node_id, state):
                self._execute_node(node_id, state)

        return state

    def get_execution_plan(self) -> list[set[str]]:
        """Get the execution plan showing parallelizable stages.

        Returns a list of sets, where each set contains nodes that can be
        executed in parallel (same stage).

        Returns:
            List of sets of node_ids, ordered by execution stage
        """
        # Calculate in-degree and depth for each node
        in_degree = {node_id: 0 for node_id in self.workflow.nodes}
        for node in self.workflow.nodes.values():
            for dep in node.depends_on:
                in_degree[node.node_id] += 1

        # Build execution plan level by level
        plan = []
        processed = set()

        while len(processed) < len(self.workflow.nodes):
            # Find all nodes with satisfied dependencies
            current_level = set()
            for node_id in self.workflow.nodes:
                if node_id in processed:
                    continue

                node = self.workflow.nodes[node_id]
                if all(dep in processed for dep in node.depends_on):
                    current_level.add(node_id)

            if not current_level:
                # This shouldn't happen if DAG is valid
                raise WorkflowValidationError("Failed to compute execution plan")

            plan.append(current_level)
            processed.update(current_level)

        return plan
