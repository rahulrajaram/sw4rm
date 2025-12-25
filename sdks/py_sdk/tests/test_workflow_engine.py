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

"""Tests for SW4RM workflow engine and builder.

Comprehensive test suite covering:
- DAG validation and cycle detection
- Topological sort
- Parallel node identification
- Workflow execution
- Builder fluent API
- Checkpoint/resume functionality
"""

import pytest
from sw4rm.workflow import (
    WorkflowBuilder,
    WorkflowEngine,
    WorkflowDefinition,
    WorkflowNode,
    NodeStatus,
    TriggerType,
    CycleDetectedError,
    WorkflowBuilderError,
    WorkflowValidationError,
)


class TestWorkflowBuilder:
    """Tests for the WorkflowBuilder fluent API."""

    def test_basic_workflow_creation(self):
        """Test creating a simple linear workflow."""
        builder = WorkflowBuilder("test_workflow")
        builder.add_node("node1", "agent1")
        builder.add_node("node2", "agent2")
        builder.add_dependency("node1", "node2")

        workflow = builder.build()

        assert workflow.workflow_id == "test_workflow"
        assert len(workflow.nodes) == 2
        assert "node1" in workflow.nodes
        assert "node2" in workflow.nodes
        assert "node1" in workflow.nodes["node2"].depends_on

    def test_fluent_api_chaining(self):
        """Test that builder methods can be chained."""
        workflow = (
            WorkflowBuilder("chained")
            .add_node("a", "agent_a")
            .add_node("b", "agent_b")
            .add_node("c", "agent_c")
            .add_dependency("a", "b")
            .add_dependency("b", "c")
            .build()
        )

        assert len(workflow.nodes) == 3
        assert workflow.nodes["c"].depends_on == frozenset(["b"])

    def test_multiple_dependencies(self):
        """Test adding multiple dependencies to a single node."""
        builder = WorkflowBuilder("multi_dep")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_dependencies(["a", "b"], "c")

        workflow = builder.build()

        assert workflow.nodes["c"].depends_on == frozenset(["a", "b"])

    def test_input_output_mapping(self):
        """Test setting input and output mappings."""
        builder = WorkflowBuilder("mapping_test")
        builder.add_node("fetch", "fetcher")
        builder.add_node("process", "processor")
        builder.set_output_mapping("fetch", {"result": "fetch_data"})
        builder.set_input_mapping("process", {"input": "fetch_data"})

        workflow = builder.build()

        assert workflow.nodes["fetch"].output_mapping == {"result": "fetch_data"}
        assert workflow.nodes["process"].input_mapping == {"input": "fetch_data"}

    def test_trigger_type_setting(self):
        """Test setting trigger types on nodes."""
        builder = WorkflowBuilder("trigger_test")
        builder.add_node("manual_node", "agent1", TriggerType.MANUAL)
        builder.add_node("scheduled_node", "agent2")
        builder.set_trigger("scheduled_node", TriggerType.SCHEDULE)

        workflow = builder.build()

        assert workflow.nodes["manual_node"].trigger_type == TriggerType.MANUAL
        assert workflow.nodes["scheduled_node"].trigger_type == TriggerType.SCHEDULE

    def test_node_metadata(self):
        """Test setting node and workflow metadata."""
        builder = WorkflowBuilder("metadata_test")
        builder.add_node("node1", "agent1")
        builder.set_node_metadata("node1", {"timeout": 3000, "retries": 3})
        builder.set_workflow_metadata({"version": "1.0", "author": "test"})

        workflow = builder.build()

        assert workflow.nodes["node1"].metadata == {"timeout": 3000, "retries": 3}
        assert workflow.metadata == {"version": "1.0", "author": "test"}

    def test_remove_node(self):
        """Test removing nodes and their dependencies."""
        builder = WorkflowBuilder("remove_test")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_dependency("a", "b")
        builder.add_dependency("b", "c")
        builder.remove_node("b")

        workflow = builder.build()

        assert len(workflow.nodes) == 2
        assert "b" not in workflow.nodes
        assert len(workflow.nodes["c"].depends_on) == 0

    def test_clone_builder(self):
        """Test cloning a builder."""
        builder1 = WorkflowBuilder("original")
        builder1.add_node("a", "agent_a")
        builder1.add_node("b", "agent_b")

        builder2 = builder1.clone()
        builder2.add_node("c", "agent_c")

        assert builder1.get_node_count() == 2
        assert builder2.get_node_count() == 3

    def test_empty_workflow_error(self):
        """Test that building an empty workflow raises an error."""
        builder = WorkflowBuilder("empty")
        with pytest.raises(WorkflowBuilderError, match="at least one node"):
            builder.build()

    def test_duplicate_node_error(self):
        """Test that adding duplicate nodes raises an error."""
        builder = WorkflowBuilder("duplicate")
        builder.add_node("node1", "agent1")
        with pytest.raises(WorkflowBuilderError, match="already exists"):
            builder.add_node("node1", "agent2")

    def test_invalid_dependency_error(self):
        """Test that invalid dependencies raise errors."""
        builder = WorkflowBuilder("invalid_dep")
        builder.add_node("a", "agent_a")

        with pytest.raises(WorkflowBuilderError, match="does not exist"):
            builder.add_dependency("a", "nonexistent")

        with pytest.raises(WorkflowBuilderError, match="does not exist"):
            builder.add_dependency("nonexistent", "a")

    def test_self_dependency_error(self):
        """Test that self-dependencies raise an error."""
        builder = WorkflowBuilder("self_dep")
        builder.add_node("a", "agent_a")
        with pytest.raises(WorkflowBuilderError, match="cannot depend on itself"):
            builder.add_dependency("a", "a")


class TestDAGValidation:
    """Tests for DAG validation and cycle detection."""

    def test_simple_cycle_detection(self):
        """Test detection of a simple 2-node cycle."""
        builder = WorkflowBuilder("simple_cycle")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_dependency("a", "b")
        builder.add_dependency("b", "a")

        with pytest.raises(WorkflowBuilderError, match="Cycle detected"):
            builder.build()

    def test_complex_cycle_detection(self):
        """Test detection of a cycle in a larger graph."""
        builder = WorkflowBuilder("complex_cycle")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_node("d", "agent_d")
        builder.add_dependency("a", "b")
        builder.add_dependency("b", "c")
        builder.add_dependency("c", "d")
        builder.add_dependency("d", "b")  # Creates cycle: b -> c -> d -> b

        with pytest.raises(WorkflowBuilderError, match="Cycle detected"):
            builder.build()

    def test_self_loop_detection(self):
        """Test detection of self-loops."""
        # Self-loops are caught during node creation
        with pytest.raises(ValueError, match="cannot depend on itself"):
            WorkflowNode(
                node_id="self_loop",
                agent_id="agent",
                depends_on=frozenset(["self_loop"])
            )

    def test_acyclic_graph_validation(self):
        """Test that valid DAGs pass validation."""
        builder = WorkflowBuilder("valid_dag")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_node("d", "agent_d")
        builder.add_dependency("a", "b")
        builder.add_dependency("a", "c")
        builder.add_dependency("b", "d")
        builder.add_dependency("c", "d")

        # Should not raise
        workflow = builder.build()
        assert len(workflow.nodes) == 4


class TestTopologicalSort:
    """Tests for topological sort algorithm."""

    def test_linear_chain_sort(self):
        """Test topological sort of a linear chain."""
        builder = WorkflowBuilder("linear")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_dependency("a", "b")
        builder.add_dependency("b", "c")

        workflow = builder.build()
        engine = WorkflowEngine(workflow)
        order = engine.topological_sort()

        assert order.index("a") < order.index("b")
        assert order.index("b") < order.index("c")

    def test_diamond_graph_sort(self):
        """Test topological sort of a diamond-shaped DAG."""
        builder = WorkflowBuilder("diamond")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_node("d", "agent_d")
        builder.add_dependency("a", "b")
        builder.add_dependency("a", "c")
        builder.add_dependency("b", "d")
        builder.add_dependency("c", "d")

        workflow = builder.build()
        engine = WorkflowEngine(workflow)
        order = engine.topological_sort()

        # a must come first, d must come last
        assert order[0] == "a"
        assert order[-1] == "d"
        # b and c must come after a and before d
        assert order.index("a") < order.index("b")
        assert order.index("a") < order.index("c")
        assert order.index("b") < order.index("d")
        assert order.index("c") < order.index("d")

    def test_complex_dag_sort(self):
        """Test topological sort preserves all dependencies."""
        builder = WorkflowBuilder("complex")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_node("d", "agent_d")
        builder.add_node("e", "agent_e")
        builder.add_dependency("a", "c")
        builder.add_dependency("b", "c")
        builder.add_dependency("c", "d")
        builder.add_dependency("d", "e")

        workflow = builder.build()
        engine = WorkflowEngine(workflow)
        order = engine.topological_sort()

        # Verify all dependencies are respected
        for node_id, node in workflow.nodes.items():
            node_idx = order.index(node_id)
            for dep in node.depends_on:
                dep_idx = order.index(dep)
                assert dep_idx < node_idx, f"{dep} should come before {node_id}"


class TestParallelNodeIdentification:
    """Tests for identifying nodes that can run in parallel."""

    def test_get_runnable_nodes_initial(self):
        """Test getting runnable nodes at workflow start."""
        builder = WorkflowBuilder("parallel_initial")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_dependency("a", "c")
        builder.add_dependency("b", "c")

        workflow = builder.build()
        engine = WorkflowEngine(workflow)

        # Create initial state
        from sw4rm.workflow.types import WorkflowState, NodeState
        state = WorkflowState(workflow_id=workflow.workflow_id)
        for node_id in workflow.nodes:
            state.node_states[node_id] = NodeState(node_id=node_id)

        runnable = engine.get_runnable_nodes(state)

        # a and b should be runnable initially
        assert set(runnable) == {"a", "b"}

    def test_execution_plan_stages(self):
        """Test getting execution plan with parallel stages."""
        builder = WorkflowBuilder("stages")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_node("d", "agent_d")
        builder.add_dependency("a", "c")
        builder.add_dependency("b", "c")
        builder.add_dependency("c", "d")

        workflow = builder.build()
        engine = WorkflowEngine(workflow)
        plan = engine.get_execution_plan()

        # Should have 3 stages: [a,b], [c], [d]
        assert len(plan) == 3
        assert set(plan[0]) == {"a", "b"}
        assert set(plan[1]) == {"c"}
        assert set(plan[2]) == {"d"}

    def test_is_node_ready(self):
        """Test checking if a node is ready to execute."""
        builder = WorkflowBuilder("ready_check")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_dependency("a", "b")

        workflow = builder.build()
        engine = WorkflowEngine(workflow)

        from sw4rm.workflow.types import WorkflowState, NodeState, NodeStatus
        state = WorkflowState(workflow_id=workflow.workflow_id)
        state.node_states["a"] = NodeState(node_id="a", status=NodeStatus.PENDING)
        state.node_states["b"] = NodeState(node_id="b", status=NodeStatus.PENDING)

        # b is not ready because a is not completed
        assert not engine.is_node_ready("b", state)

        # Mark a as completed
        state.node_states["a"].status = NodeStatus.COMPLETED

        # Now b should be ready
        assert engine.is_node_ready("b", state)


class TestWorkflowExecution:
    """Tests for workflow execution."""

    def test_simple_execution(self):
        """Test executing a simple workflow."""
        builder = WorkflowBuilder("simple_exec")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_dependency("a", "b")

        workflow = builder.build()

        # Simple executor that just marks completion
        def simple_executor(node, input_data):
            return {"result": f"executed_{node.node_id}"}

        engine = WorkflowEngine(workflow, executor=simple_executor)
        state = engine.execute()

        # Both nodes should be completed
        assert state.node_states["a"].status == NodeStatus.COMPLETED
        assert state.node_states["b"].status == NodeStatus.COMPLETED
        assert state.is_completed()
        assert not state.has_failures()

    def test_execution_with_data_passing(self):
        """Test data passing between nodes via input/output mappings."""
        builder = WorkflowBuilder("data_passing")
        builder.add_node("producer", "agent_p")
        builder.add_node("consumer", "agent_c")
        builder.add_dependency("producer", "consumer")
        builder.set_output_mapping("producer", {"data": "shared_data"})
        builder.set_input_mapping("consumer", {"input": "shared_data"})

        workflow = builder.build()

        # Executor that produces and consumes data
        def data_executor(node, input_data):
            if node.node_id == "producer":
                return {"data": "test_value"}
            elif node.node_id == "consumer":
                assert input_data.get("input") == "test_value"
                return {"processed": True}
            return {}

        engine = WorkflowEngine(workflow, executor=data_executor)
        state = engine.execute()

        # Verify data was passed correctly
        assert state.shared_data["shared_data"] == "test_value"
        assert state.node_states["consumer"].result["processed"] is True

    def test_execution_with_failure(self):
        """Test workflow execution when a node fails."""
        builder = WorkflowBuilder("failure_test")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_dependency("a", "b")

        workflow = builder.build()

        # Executor that fails on node b
        def failing_executor(node, input_data):
            if node.node_id == "b":
                raise RuntimeError("Simulated failure")
            return {"result": "ok"}

        engine = WorkflowEngine(workflow, executor=failing_executor)

        with pytest.raises(RuntimeError, match="Simulated failure"):
            engine.execute()

    def test_execution_with_initial_data(self):
        """Test workflow execution with initial data."""
        builder = WorkflowBuilder("initial_data")
        builder.add_node("processor", "agent_p")
        builder.set_input_mapping("processor", {"config": "initial_config"})

        workflow = builder.build()

        def config_executor(node, input_data):
            assert input_data.get("config") == "test_config"
            return {"processed": True}

        engine = WorkflowEngine(workflow, executor=config_executor)
        state = engine.execute(initial_data={"initial_config": "test_config"})

        assert state.is_completed()

    def test_execution_order_respected(self):
        """Test that execution order respects dependencies."""
        builder = WorkflowBuilder("order_test")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_dependency("a", "b")
        builder.add_dependency("b", "c")

        workflow = builder.build()

        execution_order = []

        def tracking_executor(node, input_data):
            execution_order.append(node.node_id)
            return {}

        engine = WorkflowEngine(workflow, executor=tracking_executor)
        engine.execute()

        # Verify execution order
        assert execution_order.index("a") < execution_order.index("b")
        assert execution_order.index("b") < execution_order.index("c")


class TestCheckpointResume:
    """Tests for checkpoint and resume functionality."""

    def test_resume_from_checkpoint(self):
        """Test resuming workflow from a checkpoint."""
        builder = WorkflowBuilder("resume_test")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_dependency("a", "b")
        builder.add_dependency("b", "c")

        workflow = builder.build()

        # Create a checkpoint state with 'a' completed
        from sw4rm.workflow.types import WorkflowState, NodeState, NodeStatus
        checkpoint_state = WorkflowState(workflow_id=workflow.workflow_id)
        checkpoint_state.node_states["a"] = NodeState(
            node_id="a",
            status=NodeStatus.COMPLETED,
            result={"data": "from_a"}
        )
        checkpoint_state.node_states["b"] = NodeState(node_id="b")
        checkpoint_state.node_states["c"] = NodeState(node_id="c")

        executed = []

        def resume_executor(node, input_data):
            executed.append(node.node_id)
            return {"result": f"executed_{node.node_id}"}

        engine = WorkflowEngine(workflow, executor=resume_executor)
        final_state = engine.resume_from_checkpoint(checkpoint_state)

        # Only b and c should have been executed
        assert "a" not in executed
        assert "b" in executed
        assert "c" in executed
        assert final_state.is_completed()


class TestWorkflowDefinition:
    """Tests for WorkflowDefinition helper methods."""

    def test_get_root_nodes(self):
        """Test getting root nodes (no dependencies)."""
        builder = WorkflowBuilder("roots")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_dependency("a", "c")
        builder.add_dependency("b", "c")

        workflow = builder.build()
        roots = workflow.get_root_nodes()

        assert roots == {"a", "b"}

    def test_get_leaf_nodes(self):
        """Test getting leaf nodes (not depended upon)."""
        builder = WorkflowBuilder("leaves")
        builder.add_node("a", "agent_a")
        builder.add_node("b", "agent_b")
        builder.add_node("c", "agent_c")
        builder.add_dependency("a", "b")
        builder.add_dependency("a", "c")

        workflow = builder.build()
        leaves = workflow.get_leaf_nodes()

        assert leaves == {"b", "c"}

    def test_get_node(self):
        """Test getting a node by ID."""
        builder = WorkflowBuilder("get_node")
        builder.add_node("test", "agent_test")

        workflow = builder.build()
        node = workflow.get_node("test")

        assert node is not None
        assert node.node_id == "test"
        assert node.agent_id == "agent_test"

        assert workflow.get_node("nonexistent") is None


class TestNodeState:
    """Tests for NodeState helper methods."""

    def test_is_terminal(self):
        """Test checking if node is in terminal state."""
        from sw4rm.workflow.types import NodeState, NodeStatus

        pending = NodeState(node_id="test", status=NodeStatus.PENDING)
        assert not pending.is_terminal

        running = NodeState(node_id="test", status=NodeStatus.RUNNING)
        assert not running.is_terminal

        completed = NodeState(node_id="test", status=NodeStatus.COMPLETED)
        assert completed.is_terminal

        failed = NodeState(node_id="test", status=NodeStatus.FAILED)
        assert failed.is_terminal

        skipped = NodeState(node_id="test", status=NodeStatus.SKIPPED)
        assert skipped.is_terminal

    def test_duration_calculation(self):
        """Test calculating node execution duration."""
        from sw4rm.workflow.types import NodeState

        state = NodeState(node_id="test")
        assert state.duration_ms is None

        state.start_time = 1000
        assert state.duration_ms is None

        state.end_time = 3500
        assert state.duration_ms == 2500
