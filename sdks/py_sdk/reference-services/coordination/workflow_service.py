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
Workflow Service gRPC Server Implementation.

This module provides the gRPC server implementation for the WorkflowService,
enabling distributed DAG-based workflow orchestration with centralized state.

The service maintains:
- Workflow definitions indexed by workflow_id
- Workflow instances (running workflows) indexed by workflow_id
- Node states within each workflow instance

Example usage:
    from coordination.workflow_service import WorkflowServiceImpl
    from sw4rm.protos import workflow_pb2_grpc

    server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
    workflow_pb2_grpc.add_WorkflowServiceServicer_to_server(
        WorkflowServiceImpl(), server
    )
"""

import logging
import threading
from typing import Dict, Set, Optional

import grpc
from google.protobuf import timestamp_pb2

from sw4rm.protos import workflow_pb2, workflow_pb2_grpc

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s'
)
logger = logging.getLogger(__name__)


def _current_timestamp() -> timestamp_pb2.Timestamp:
    """Get current time as a protobuf Timestamp."""
    ts = timestamp_pb2.Timestamp()
    ts.GetCurrentTime()
    return ts


class WorkflowServiceImpl(workflow_pb2_grpc.WorkflowServiceServicer):
    """
    gRPC server implementation for WorkflowService.

    Provides centralized workflow orchestration for distributed agent deployments.
    Thread-safe implementation using RLock for all state mutations.

    State storage:
    - definitions: Dict[workflow_id, WorkflowDefinition] - workflow definitions
    - instances: Dict[workflow_id, WorkflowState] - running workflow instances
    """

    def __init__(self):
        """Initialize the workflow service with empty state."""
        self._lock = threading.RLock()
        self._definitions: Dict[str, workflow_pb2.WorkflowDefinition] = {}
        self._instances: Dict[str, workflow_pb2.WorkflowState] = {}
        logger.info("WorkflowService initialized")

    def _validate_dag(self, definition: workflow_pb2.WorkflowDefinition) -> Optional[str]:
        """
        Validate that the workflow DAG has no cycles.

        Uses DFS-based cycle detection.

        Args:
            definition: WorkflowDefinition to validate

        Returns:
            Error message if cycle detected, None if valid
        """
        nodes = definition.nodes
        visited: Set[str] = set()
        rec_stack: Set[str] = set()

        def has_cycle(node_id: str) -> bool:
            visited.add(node_id)
            rec_stack.add(node_id)

            node = nodes.get(node_id)
            if node:
                for dep in node.dependencies:
                    if dep not in visited:
                        if has_cycle(dep):
                            return True
                    elif dep in rec_stack:
                        return True

            rec_stack.discard(node_id)
            return False

        for node_id in nodes:
            if node_id not in visited:
                if has_cycle(node_id):
                    return f"Cycle detected in workflow starting from node '{node_id}'"

        return None

    def _validate_dependencies(self, definition: workflow_pb2.WorkflowDefinition) -> Optional[str]:
        """
        Validate that all dependencies reference existing nodes.

        Args:
            definition: WorkflowDefinition to validate

        Returns:
            Error message if invalid dependencies found, None if valid
        """
        node_ids = set(definition.nodes.keys())

        for node_id, node in definition.nodes.items():
            for dep in node.dependencies:
                if dep not in node_ids:
                    return f"Node '{node_id}' has dependency '{dep}' which does not exist"

        return None

    def CreateWorkflow(
        self,
        request: workflow_pb2.CreateWorkflowRequest,
        context: grpc.ServicerContext
    ) -> workflow_pb2.CreateWorkflowResponse:
        """
        Create a new workflow from a definition.

        Validates the workflow DAG for cycles and missing dependencies,
        then stores the definition for later execution.

        Args:
            request: CreateWorkflowRequest containing WorkflowDefinition
            context: gRPC context

        Returns:
            CreateWorkflowResponse with workflow_id, success flag, and error
        """
        definition = request.definition
        workflow_id = definition.workflow_id

        # Validate required fields
        if not workflow_id:
            return workflow_pb2.CreateWorkflowResponse(
                workflow_id="",
                success=False,
                error="workflow_id is required"
            )

        if not definition.nodes:
            return workflow_pb2.CreateWorkflowResponse(
                workflow_id=workflow_id,
                success=False,
                error="workflow must contain at least one node"
            )

        # Validate dependencies
        dep_error = self._validate_dependencies(definition)
        if dep_error:
            return workflow_pb2.CreateWorkflowResponse(
                workflow_id=workflow_id,
                success=False,
                error=dep_error
            )

        # Validate DAG (no cycles)
        cycle_error = self._validate_dag(definition)
        if cycle_error:
            return workflow_pb2.CreateWorkflowResponse(
                workflow_id=workflow_id,
                success=False,
                error=cycle_error
            )

        with self._lock:
            if workflow_id in self._definitions:
                return workflow_pb2.CreateWorkflowResponse(
                    workflow_id=workflow_id,
                    success=False,
                    error=f"Workflow with id '{workflow_id}' already exists"
                )

            # Set created_at if not provided
            if not definition.created_at.ByteSize():
                definition.created_at.CopyFrom(_current_timestamp())

            self._definitions[workflow_id] = definition
            logger.info(f"Workflow created: {workflow_id} with {len(definition.nodes)} nodes")

        return workflow_pb2.CreateWorkflowResponse(
            workflow_id=workflow_id,
            success=True,
            error=""
        )

    def StartWorkflow(
        self,
        request: workflow_pb2.StartWorkflowRequest,
        context: grpc.ServicerContext
    ) -> workflow_pb2.StartWorkflowResponse:
        """
        Start a new instance of a workflow.

        Creates a new workflow state and initializes all node states based
        on their dependencies. Nodes with no dependencies start as READY,
        others start as PENDING.

        Args:
            request: StartWorkflowRequest with workflow_id and optional initial data
            context: gRPC context

        Returns:
            StartWorkflowResponse with workflow_id, state, success flag, and error
        """
        workflow_id = request.workflow_id

        with self._lock:
            if workflow_id not in self._definitions:
                return workflow_pb2.StartWorkflowResponse(
                    workflow_id=workflow_id,
                    state=None,
                    success=False,
                    error=f"Workflow '{workflow_id}' not found"
                )

            if workflow_id in self._instances:
                return workflow_pb2.StartWorkflowResponse(
                    workflow_id=workflow_id,
                    state=None,
                    success=False,
                    error=f"Workflow '{workflow_id}' is already running"
                )

            definition = self._definitions[workflow_id]

            # Initialize node states
            node_states: Dict[str, workflow_pb2.NodeState] = {}
            for node_id, node in definition.nodes.items():
                # Nodes with no dependencies start as READY, others as PENDING
                if len(node.dependencies) == 0:
                    status = workflow_pb2.NodeStatus.READY
                else:
                    status = workflow_pb2.NodeStatus.PENDING

                node_states[node_id] = workflow_pb2.NodeState(
                    node_id=node_id,
                    status=status,
                    output="",
                    error=""
                )

            # Create workflow state
            state = workflow_pb2.WorkflowState(
                workflow_id=workflow_id,
                workflow_data=request.workflow_data or "{}",
                started_at=_current_timestamp()
            )
            state.node_states.update(node_states)
            state.metadata.update(request.metadata)

            self._instances[workflow_id] = state
            logger.info(f"Workflow started: {workflow_id}")

        return workflow_pb2.StartWorkflowResponse(
            workflow_id=workflow_id,
            state=state,
            success=True,
            error=""
        )

    def GetWorkflowState(
        self,
        request: workflow_pb2.GetWorkflowStateRequest,
        context: grpc.ServicerContext
    ) -> workflow_pb2.GetWorkflowStateResponse:
        """
        Get the current state of a workflow instance.

        Args:
            request: GetWorkflowStateRequest with workflow_id
            context: gRPC context

        Returns:
            GetWorkflowStateResponse with current state, success flag, and error
        """
        workflow_id = request.workflow_id

        with self._lock:
            if workflow_id not in self._instances:
                # Check if definition exists but not started
                if workflow_id in self._definitions:
                    return workflow_pb2.GetWorkflowStateResponse(
                        state=None,
                        success=False,
                        error=f"Workflow '{workflow_id}' exists but is not started"
                    )
                return workflow_pb2.GetWorkflowStateResponse(
                    state=None,
                    success=False,
                    error=f"Workflow '{workflow_id}' not found"
                )

            state = self._instances[workflow_id]
            logger.debug(f"GetWorkflowState: {workflow_id}")

        return workflow_pb2.GetWorkflowStateResponse(
            state=state,
            success=True,
            error=""
        )

    def ResumeWorkflow(
        self,
        request: workflow_pb2.ResumeWorkflowRequest,
        context: grpc.ServicerContext
    ) -> workflow_pb2.ResumeWorkflowResponse:
        """
        Resume a workflow by completing a node.

        Updates the specified node's state and propagates changes to
        dependent nodes. If all dependencies of a node are COMPLETED,
        that node becomes READY.

        Args:
            request: ResumeWorkflowRequest with workflow_id, node_id,
                    optional workflow_data, and metadata
            context: gRPC context

        Returns:
            ResumeWorkflowResponse with updated state, success flag, and error
        """
        workflow_id = request.workflow_id
        node_id = request.node_id

        with self._lock:
            if workflow_id not in self._instances:
                return workflow_pb2.ResumeWorkflowResponse(
                    workflow_id=workflow_id,
                    state=None,
                    success=False,
                    error=f"Workflow '{workflow_id}' not found or not started"
                )

            if workflow_id not in self._definitions:
                return workflow_pb2.ResumeWorkflowResponse(
                    workflow_id=workflow_id,
                    state=None,
                    success=False,
                    error=f"Workflow definition '{workflow_id}' not found"
                )

            state = self._instances[workflow_id]
            definition = self._definitions[workflow_id]

            if node_id not in state.node_states:
                return workflow_pb2.ResumeWorkflowResponse(
                    workflow_id=workflow_id,
                    state=state,
                    success=False,
                    error=f"Node '{node_id}' not found in workflow"
                )

            # Update the node to COMPLETED
            node_state = state.node_states[node_id]
            node_state.status = workflow_pb2.NodeStatus.COMPLETED
            node_state.completed_at.CopyFrom(_current_timestamp())

            # Update workflow data if provided
            if request.workflow_data:
                state.workflow_data = request.workflow_data

            # Update metadata
            state.metadata.update(request.metadata)

            # Check and update dependent nodes
            self._update_dependent_nodes(state, definition, node_id)

            # Check if workflow is complete
            self._check_workflow_completion(state)

            logger.info(f"Workflow resumed: {workflow_id}, node {node_id} completed")

        return workflow_pb2.ResumeWorkflowResponse(
            workflow_id=workflow_id,
            state=state,
            success=True,
            error=""
        )

    def _update_dependent_nodes(
        self,
        state: workflow_pb2.WorkflowState,
        definition: workflow_pb2.WorkflowDefinition,
        completed_node_id: str
    ) -> None:
        """
        Update nodes that depend on a completed node.

        If all dependencies of a node are now COMPLETED, mark it as READY.
        """
        for node_id, node in definition.nodes.items():
            if completed_node_id in node.dependencies:
                node_state = state.node_states.get(node_id)
                if node_state and node_state.status == workflow_pb2.NodeStatus.PENDING:
                    # Check if all dependencies are complete
                    all_deps_complete = all(
                        state.node_states.get(dep) and
                        state.node_states[dep].status == workflow_pb2.NodeStatus.COMPLETED
                        for dep in node.dependencies
                    )
                    if all_deps_complete:
                        node_state.status = workflow_pb2.NodeStatus.READY

    def _check_workflow_completion(self, state: workflow_pb2.WorkflowState) -> None:
        """Check if all nodes are in terminal states and mark workflow complete."""
        terminal_statuses = {
            workflow_pb2.NodeStatus.COMPLETED,
            workflow_pb2.NodeStatus.FAILED,
            workflow_pb2.NodeStatus.SKIPPED
        }

        all_terminal = all(
            node_state.status in terminal_statuses
            for node_state in state.node_states.values()
        )

        if all_terminal and not state.completed_at.ByteSize():
            state.completed_at.CopyFrom(_current_timestamp())

    # Additional helper methods for service management

    def update_node_state(
        self,
        workflow_id: str,
        node_id: str,
        status: int,
        output: str = "",
        error: str = ""
    ) -> bool:
        """
        Update a node's state (internal use for testing/management).

        Args:
            workflow_id: ID of the workflow
            node_id: ID of the node to update
            status: New NodeStatus value
            output: Optional output data
            error: Optional error message

        Returns:
            True if update succeeded, False otherwise
        """
        with self._lock:
            if workflow_id not in self._instances:
                return False

            state = self._instances[workflow_id]
            if node_id not in state.node_states:
                return False

            node_state = state.node_states[node_id]
            node_state.status = status

            if output:
                node_state.output = output
            if error:
                node_state.error = error

            if status == workflow_pb2.NodeStatus.RUNNING:
                node_state.started_at.CopyFrom(_current_timestamp())
            elif status in (
                workflow_pb2.NodeStatus.COMPLETED,
                workflow_pb2.NodeStatus.FAILED,
                workflow_pb2.NodeStatus.SKIPPED
            ):
                node_state.completed_at.CopyFrom(_current_timestamp())

            # Update dependent nodes if completed
            if status == workflow_pb2.NodeStatus.COMPLETED:
                definition = self._definitions.get(workflow_id)
                if definition:
                    self._update_dependent_nodes(state, definition, node_id)

            self._check_workflow_completion(state)
            return True

    def get_definition(self, workflow_id: str) -> Optional[workflow_pb2.WorkflowDefinition]:
        """Get a workflow definition (internal use)."""
        with self._lock:
            return self._definitions.get(workflow_id)

    def clear_all(self) -> None:
        """Clear all workflow data (for testing)."""
        with self._lock:
            self._definitions.clear()
            self._instances.clear()
            logger.info("WorkflowService state cleared")
