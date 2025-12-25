#!/usr/bin/env python3
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

"""Example demonstrating SW4RM workflow orchestration.

This example shows how to build and execute a multi-agent workflow
with dependencies, data passing, and parallel execution.
"""

from sw4rm.workflow import (
    WorkflowBuilder,
    WorkflowEngine,
    NodeStatus,
    TriggerType,
)


def example_basic_workflow():
    """Example: Create and execute a simple linear workflow."""
    print("\n=== Example 1: Basic Linear Workflow ===\n")

    # Build a simple data processing pipeline
    builder = WorkflowBuilder("data_pipeline")
    builder.add_node("fetch", "fetcher_agent")
    builder.add_node("process", "processor_agent")
    builder.add_node("store", "storage_agent")
    builder.add_dependency("fetch", "process")
    builder.add_dependency("process", "store")

    workflow = builder.build()
    print(f"Created workflow: {workflow.workflow_id}")
    print(f"Nodes: {list(workflow.nodes.keys())}")
    print(f"Root nodes: {workflow.get_root_nodes()}")
    print(f"Leaf nodes: {workflow.get_leaf_nodes()}")

    # Define a simple executor
    def simple_executor(node, input_data):
        print(f"  Executing node: {node.node_id} (agent: {node.agent_id})")
        return {"result": f"completed_{node.node_id}"}

    # Execute the workflow
    engine = WorkflowEngine(workflow, executor=simple_executor)

    print("\nExecution plan (parallel stages):")
    for i, stage in enumerate(engine.get_execution_plan()):
        print(f"  Stage {i}: {stage}")

    print("\nExecuting workflow:")
    state = engine.execute()

    print("\nExecution results:")
    for node_id, node_state in state.node_states.items():
        print(f"  {node_id}: {node_state.status.value} (duration: {node_state.duration_ms}ms)")


def example_parallel_workflow():
    """Example: Create a workflow with parallel execution."""
    print("\n=== Example 2: Parallel Workflow ===\n")

    # Build a diamond-shaped DAG with parallel execution
    builder = WorkflowBuilder("parallel_pipeline")
    builder.add_node("start", "starter_agent")
    builder.add_node("analyze_a", "analyzer_agent_a")
    builder.add_node("analyze_b", "analyzer_agent_b")
    builder.add_node("combine", "combiner_agent")

    # Create diamond structure: start -> [analyze_a, analyze_b] -> combine
    builder.add_dependency("start", "analyze_a")
    builder.add_dependency("start", "analyze_b")
    builder.add_dependency("analyze_a", "combine")
    builder.add_dependency("analyze_b", "combine")

    workflow = builder.build()
    print(f"Created workflow: {workflow.workflow_id}")

    def parallel_executor(node, input_data):
        print(f"  Executing node: {node.node_id}")
        return {"result": f"processed_by_{node.node_id}"}

    engine = WorkflowEngine(workflow, executor=parallel_executor)

    print("\nExecution plan (showing parallelism):")
    for i, stage in enumerate(engine.get_execution_plan()):
        print(f"  Stage {i}: {stage}")
        if len(stage) > 1:
            print(f"    -> Can execute in parallel!")

    print("\nExecuting workflow:")
    state = engine.execute()

    print(f"\nCompleted: {state.is_completed()}")
    print(f"Has failures: {state.has_failures()}")


def example_data_passing():
    """Example: Workflow with data passing between nodes."""
    print("\n=== Example 3: Data Passing Between Nodes ===\n")

    # Build a workflow with data flow
    builder = WorkflowBuilder("data_flow")
    builder.add_node("fetch_data", "fetcher_agent")
    builder.add_node("transform_data", "transformer_agent")
    builder.add_node("validate_data", "validator_agent")

    builder.add_dependency("fetch_data", "transform_data")
    builder.add_dependency("transform_data", "validate_data")

    # Configure data mappings
    builder.set_output_mapping("fetch_data", {"raw_data": "fetched_data"})
    builder.set_input_mapping("transform_data", {"input": "fetched_data"})
    builder.set_output_mapping("transform_data", {"clean_data": "transformed_data"})
    builder.set_input_mapping("validate_data", {"data_to_check": "transformed_data"})

    workflow = builder.build()

    # Executor that demonstrates data passing
    def data_executor(node, input_data):
        print(f"  Executing: {node.node_id}")
        print(f"    Input: {input_data}")

        if node.node_id == "fetch_data":
            return {"raw_data": [1, 2, 3, 4, 5]}
        elif node.node_id == "transform_data":
            raw = input_data.get("input", [])
            transformed = [x * 2 for x in raw]
            return {"clean_data": transformed}
        elif node.node_id == "validate_data":
            data = input_data.get("data_to_check", [])
            is_valid = all(x > 0 for x in data)
            return {"valid": is_valid}
        return {}

    engine = WorkflowEngine(workflow, executor=data_executor)
    state = engine.execute()

    print("\nShared data after execution:")
    for key, value in state.shared_data.items():
        print(f"  {key}: {value}")


def example_complex_workflow():
    """Example: Complex workflow with multiple patterns."""
    print("\n=== Example 4: Complex Multi-Agent Workflow ===\n")

    # Build a complex workflow
    builder = WorkflowBuilder("ml_pipeline")

    # Data ingestion stage
    builder.add_node("ingest_train", "ingestion_agent")
    builder.add_node("ingest_test", "ingestion_agent")

    # Preprocessing stage
    builder.add_node("preprocess_train", "preprocessing_agent")
    builder.add_node("preprocess_test", "preprocessing_agent")

    # Training stage
    builder.add_node("train_model", "training_agent")

    # Evaluation stage
    builder.add_node("evaluate", "evaluation_agent")

    # Dependencies
    builder.add_dependency("ingest_train", "preprocess_train")
    builder.add_dependency("ingest_test", "preprocess_test")
    builder.add_dependency("preprocess_train", "train_model")
    builder.add_dependencies(["train_model", "preprocess_test"], "evaluate")

    # Set metadata
    builder.set_node_metadata("train_model", {
        "timeout_ms": 300000,
        "retry_count": 3
    })
    builder.set_workflow_metadata({
        "version": "1.0",
        "description": "ML training pipeline"
    })

    workflow = builder.build()

    print(f"Workflow: {workflow.workflow_id}")
    print(f"Metadata: {workflow.metadata}")
    print(f"Total nodes: {len(workflow.nodes)}")

    engine = WorkflowEngine(workflow)

    print("\nExecution plan:")
    for i, stage in enumerate(engine.get_execution_plan()):
        print(f"  Stage {i}: {stage}")

    print("\nTopological order:")
    print(f"  {' -> '.join(engine.topological_sort())}")


def example_checkpoint_resume():
    """Example: Checkpoint and resume functionality."""
    print("\n=== Example 5: Checkpoint and Resume ===\n")

    builder = WorkflowBuilder("resumable_workflow")
    builder.add_node("step1", "agent1")
    builder.add_node("step2", "agent2")
    builder.add_node("step3", "agent3")
    builder.add_dependency("step1", "step2")
    builder.add_dependency("step2", "step3")

    workflow = builder.build()

    # Simulate a checkpoint after step1
    from sw4rm.workflow.types import WorkflowState, NodeState, NodeStatus

    checkpoint = WorkflowState(workflow_id=workflow.workflow_id)
    checkpoint.node_states["step1"] = NodeState(
        node_id="step1",
        status=NodeStatus.COMPLETED,
        result={"data": "checkpoint_data"}
    )
    checkpoint.node_states["step2"] = NodeState(node_id="step2")
    checkpoint.node_states["step3"] = NodeState(node_id="step3")
    checkpoint.shared_data["checkpoint_data"] = "saved_state"

    print("Starting from checkpoint (step1 already completed)...")

    executed_nodes = []

    def resume_executor(node, input_data):
        executed_nodes.append(node.node_id)
        print(f"  Executing: {node.node_id}")
        return {"result": f"completed_{node.node_id}"}

    engine = WorkflowEngine(workflow, executor=resume_executor)
    final_state = engine.resume_from_checkpoint(checkpoint)

    print(f"\nNodes executed: {executed_nodes}")
    print(f"Nodes skipped: {['step1']}")
    print(f"Completed: {final_state.is_completed()}")


if __name__ == "__main__":
    """Run all examples."""
    print("=" * 60)
    print("SW4RM Workflow Orchestration Examples")
    print("=" * 60)

    example_basic_workflow()
    example_parallel_workflow()
    example_data_passing()
    example_complex_workflow()
    example_checkpoint_resume()

    print("\n" + "=" * 60)
    print("All examples completed successfully!")
    print("=" * 60)
