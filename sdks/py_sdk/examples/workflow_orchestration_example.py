#!/usr/bin/env python3
"""
Workflow Orchestration Example for SW4RM Protocol.

This example demonstrates:
- DAG-based workflow using WorkflowEngine
- WorkflowBuilder DSL for defining workflows
- Node dependencies and parallel execution
- Context passing between nodes
- Execution planning and visualization

Prerequisites:
  - Generate protobuf stubs: `make protos`
  - Install deps: `python -m pip install -e ".[dev]"`

Run:
  python examples/workflow_orchestration_example.py
"""
from __future__ import annotations

import json
import time
from typing import Any, Optional

# SW4RM SDK imports
from sw4rm.workflow.builder import WorkflowBuilder, WorkflowBuilderError
from sw4rm.workflow.engine import (
    WorkflowEngine,
    CycleDetectedError,
    WorkflowValidationError,
)
from sw4rm.workflow.types import (
    WorkflowDefinition,
    WorkflowNode,
    WorkflowState,
    NodeState,
    NodeStatus,
    TriggerType,
)


# ---------------------------------------------------------------------------
# Node Executor Functions
# ---------------------------------------------------------------------------

def fetch_data_executor(node: WorkflowNode, input_data: dict[str, Any]) -> dict[str, Any]:
    """Executor for data fetching node.

    Args:
        node: The workflow node being executed
        input_data: Input parameters from workflow state

    Returns:
        Output data to be stored in workflow state
    """
    source = input_data.get("source", "default_source")
    print(f"  [Fetch] Fetching data from '{source}'...")
    time.sleep(0.1)  # Simulate network delay

    # Simulate fetched data
    data = {
        "records": [
            {"id": 1, "value": 100, "category": "A"},
            {"id": 2, "value": 200, "category": "B"},
            {"id": 3, "value": 150, "category": "A"},
            {"id": 4, "value": 300, "category": "C"},
        ],
        "fetch_timestamp": int(time.time()),
        "source": source
    }

    print(f"  [Fetch] Retrieved {len(data['records'])} records")
    return {"fetched_data": data}


def validate_data_executor(node: WorkflowNode, input_data: dict[str, Any]) -> dict[str, Any]:
    """Executor for data validation node.

    Args:
        node: The workflow node being executed
        input_data: Input parameters including data to validate

    Returns:
        Validation results
    """
    data = input_data.get("data", {})
    records = data.get("records", [])

    print(f"  [Validate] Validating {len(records)} records...")
    time.sleep(0.05)

    # Simulate validation
    valid_records = []
    invalid_records = []

    for record in records:
        if record.get("value", 0) > 0 and record.get("category"):
            valid_records.append(record)
        else:
            invalid_records.append(record)

    result = {
        "valid_count": len(valid_records),
        "invalid_count": len(invalid_records),
        "valid_records": valid_records,
        "validation_passed": len(invalid_records) == 0
    }

    print(f"  [Validate] Valid: {result['valid_count']}, Invalid: {result['invalid_count']}")
    return {"validation_result": result}


def transform_data_executor(node: WorkflowNode, input_data: dict[str, Any]) -> dict[str, Any]:
    """Executor for data transformation node.

    Args:
        node: The workflow node being executed
        input_data: Input parameters including validated data

    Returns:
        Transformed data
    """
    validation_result = input_data.get("validation", {})
    records = validation_result.get("valid_records", [])

    print(f"  [Transform] Transforming {len(records)} records...")
    time.sleep(0.08)

    # Aggregate by category
    aggregates = {}
    for record in records:
        category = record.get("category", "unknown")
        value = record.get("value", 0)

        if category not in aggregates:
            aggregates[category] = {"count": 0, "total": 0}

        aggregates[category]["count"] += 1
        aggregates[category]["total"] += value

    # Calculate averages
    for cat in aggregates:
        aggregates[cat]["average"] = aggregates[cat]["total"] / aggregates[cat]["count"]

    print(f"  [Transform] Created {len(aggregates)} category aggregates")
    return {"transformed_data": aggregates}


def enrich_data_executor(node: WorkflowNode, input_data: dict[str, Any]) -> dict[str, Any]:
    """Executor for data enrichment node (runs in parallel with transform).

    Args:
        node: The workflow node being executed
        input_data: Input parameters

    Returns:
        Enrichment data
    """
    validation_result = input_data.get("validation", {})
    records = validation_result.get("valid_records", [])

    print(f"  [Enrich] Enriching {len(records)} records with metadata...")
    time.sleep(0.1)  # Simulate external API call

    # Simulate enrichment with external data
    enrichment = {
        "category_labels": {
            "A": "High Priority",
            "B": "Medium Priority",
            "C": "Low Priority"
        },
        "data_quality_score": 0.95,
        "enrichment_source": "metadata-service"
    }

    print(f"  [Enrich] Added labels for {len(enrichment['category_labels'])} categories")
    return {"enrichment_data": enrichment}


def merge_results_executor(node: WorkflowNode, input_data: dict[str, Any]) -> dict[str, Any]:
    """Executor for merging results from parallel nodes.

    Args:
        node: The workflow node being executed
        input_data: Input from both transform and enrich nodes

    Returns:
        Merged final results
    """
    transformed = input_data.get("transformed", {})
    enrichment = input_data.get("enrichment", {})

    print("  [Merge] Merging transformed data with enrichment...")
    time.sleep(0.05)

    # Merge enrichment labels into transformed data
    final_results = {}
    labels = enrichment.get("category_labels", {})

    for category, stats in transformed.items():
        final_results[category] = {
            **stats,
            "label": labels.get(category, "Unknown"),
        }

    result = {
        "final_data": final_results,
        "data_quality": enrichment.get("data_quality_score", 0),
        "processed_at": int(time.time())
    }

    print(f"  [Merge] Final result has {len(final_results)} categories")
    return {"merged_result": result}


def store_results_executor(node: WorkflowNode, input_data: dict[str, Any]) -> dict[str, Any]:
    """Executor for storing final results.

    Args:
        node: The workflow node being executed
        input_data: Merged results to store

    Returns:
        Storage confirmation
    """
    merged = input_data.get("merged", {})

    print("  [Store] Storing results to database...")
    time.sleep(0.05)

    # Simulate storage
    storage_result = {
        "storage_id": f"result-{int(time.time())}",
        "records_stored": len(merged.get("final_data", {})),
        "storage_timestamp": int(time.time()),
        "status": "success"
    }

    print(f"  [Store] Stored with ID: {storage_result['storage_id']}")
    return {"storage_confirmation": storage_result}


# ---------------------------------------------------------------------------
# Workflow Builder Examples
# ---------------------------------------------------------------------------

def build_data_pipeline_workflow() -> WorkflowDefinition:
    """Build a data processing pipeline workflow using WorkflowBuilder.

    This creates a DAG with the following structure:

        [fetch] --> [validate] --> [transform] ---|
                                                   |--> [merge] --> [store]
                               --> [enrich]   ----|

    Returns:
        The workflow definition
    """
    print("\n" + "=" * 60)
    print("BUILDING WORKFLOW: Data Processing Pipeline")
    print("=" * 60)

    builder = WorkflowBuilder("data_pipeline_v1")

    # Add nodes
    builder.add_node("fetch", "fetch-agent", TriggerType.MANUAL)
    builder.add_node("validate", "validator-agent", TriggerType.EVENT)
    builder.add_node("transform", "transformer-agent", TriggerType.EVENT)
    builder.add_node("enrich", "enricher-agent", TriggerType.EVENT)
    builder.add_node("merge", "merger-agent", TriggerType.EVENT)
    builder.add_node("store", "storage-agent", TriggerType.EVENT)

    # Define dependencies (edges in the DAG)
    # validate depends on fetch
    builder.add_dependency("fetch", "validate")

    # transform and enrich both depend on validate (can run in parallel)
    builder.add_dependency("validate", "transform")
    builder.add_dependency("validate", "enrich")

    # merge depends on both transform and enrich
    builder.add_dependencies(["transform", "enrich"], "merge")

    # store depends on merge
    builder.add_dependency("merge", "store")

    # Set input/output mappings for data flow
    builder.set_input_mapping("fetch", {"source": "data_source"})
    builder.set_output_mapping("fetch", {"fetched_data": "raw_data"})

    builder.set_input_mapping("validate", {"data": "raw_data"})
    builder.set_output_mapping("validate", {"validation_result": "validated_data"})

    builder.set_input_mapping("transform", {"validation": "validated_data"})
    builder.set_output_mapping("transform", {"transformed_data": "aggregates"})

    builder.set_input_mapping("enrich", {"validation": "validated_data"})
    builder.set_output_mapping("enrich", {"enrichment_data": "metadata"})

    builder.set_input_mapping("merge", {
        "transformed": "aggregates",
        "enrichment": "metadata"
    })
    builder.set_output_mapping("merge", {"merged_result": "final_output"})

    builder.set_input_mapping("store", {"merged": "final_output"})
    builder.set_output_mapping("store", {"storage_confirmation": "storage_status"})

    # Set workflow metadata
    builder.set_workflow_metadata({
        "description": "Data processing pipeline with validation, transformation, and enrichment",
        "version": "1.0.0",
        "owner": "data-team"
    })

    # Build and validate
    workflow = builder.build(validate=True)

    print(f"\nWorkflow created: {workflow.workflow_id}")
    print(f"  Nodes: {len(workflow.nodes)}")
    print(f"  Root nodes: {workflow.get_root_nodes()}")
    print(f"  Leaf nodes: {workflow.get_leaf_nodes()}")

    return workflow


def visualize_execution_plan(engine: WorkflowEngine) -> None:
    """Visualize the execution plan showing parallel stages.

    Args:
        engine: The workflow engine with a validated workflow
    """
    print("\n" + "-" * 40)
    print("EXECUTION PLAN (Parallel Stages)")
    print("-" * 40)

    plan = engine.get_execution_plan()

    for stage_idx, nodes in enumerate(plan):
        nodes_str = ", ".join(sorted(nodes))
        parallel_note = " (parallel)" if len(nodes) > 1 else ""
        print(f"  Stage {stage_idx + 1}: [{nodes_str}]{parallel_note}")


def run_workflow(workflow: WorkflowDefinition) -> WorkflowState:
    """Execute a workflow with custom executors.

    Args:
        workflow: The workflow to execute

    Returns:
        Final workflow state
    """
    print("\n" + "=" * 60)
    print("EXECUTING WORKFLOW")
    print("=" * 60)

    # Map node agent_ids to executor functions
    executors = {
        "fetch-agent": fetch_data_executor,
        "validator-agent": validate_data_executor,
        "transformer-agent": transform_data_executor,
        "enricher-agent": enrich_data_executor,
        "merger-agent": merge_results_executor,
        "storage-agent": store_results_executor,
    }

    def executor(node: WorkflowNode, input_data: dict[str, Any]) -> dict[str, Any]:
        """Dispatch to the appropriate executor based on agent_id."""
        exec_fn = executors.get(node.agent_id)
        if exec_fn:
            print(f"\nExecuting node: {node.node_id} (agent: {node.agent_id})")
            return exec_fn(node, input_data)
        else:
            print(f"\nNo executor for node: {node.node_id}")
            return {}

    # Create engine and show execution plan
    engine = WorkflowEngine(workflow, executor=executor)
    visualize_execution_plan(engine)

    # Execute with initial data
    print("\n" + "-" * 40)
    print("EXECUTION LOG")
    print("-" * 40)

    initial_data = {
        "data_source": "production_database"
    }

    start_time = time.time()
    state = engine.execute(initial_data=initial_data)
    elapsed = time.time() - start_time

    return state, elapsed


def show_execution_results(state: WorkflowState, elapsed: float) -> None:
    """Display execution results.

    Args:
        state: Final workflow state
        elapsed: Execution time in seconds
    """
    print("\n" + "=" * 60)
    print("EXECUTION RESULTS")
    print("=" * 60)

    print(f"\nWorkflow: {state.workflow_id}")
    print(f"Execution time: {elapsed:.3f}s")
    print(f"Completed: {state.is_completed()}")
    print(f"Has failures: {state.has_failures()}")

    print("\nNode Results:")
    for node_id, node_state in state.node_states.items():
        duration = node_state.duration_ms
        duration_str = f"{duration}ms" if duration else "N/A"
        print(f"  {node_id}:")
        print(f"    Status: {node_state.status.value}")
        print(f"    Duration: {duration_str}")
        if node_state.error:
            print(f"    Error: {node_state.error}")

    # Show final output
    if "storage_status" in state.shared_data:
        storage = state.shared_data["storage_status"]
        print(f"\nFinal Output:")
        print(f"  Storage ID: {storage.get('storage_id')}")
        print(f"  Records stored: {storage.get('records_stored')}")
        print(f"  Status: {storage.get('status')}")


def demo_cycle_detection():
    """Demonstrate cycle detection in workflow DAGs."""
    print("\n" + "=" * 60)
    print("DEMO: Cycle Detection")
    print("=" * 60)

    print("\nAttempting to create a workflow with a cycle...")

    builder = WorkflowBuilder("cyclic_workflow")
    builder.add_node("A", "agent-a")
    builder.add_node("B", "agent-b")
    builder.add_node("C", "agent-c")

    # Create cycle: A -> B -> C -> A
    builder.add_dependency("A", "B")
    builder.add_dependency("B", "C")
    builder.add_dependency("C", "A")  # This creates a cycle!

    try:
        workflow = builder.build(validate=True)
        print("  ERROR: Cycle was not detected!")
    except WorkflowBuilderError as e:
        print(f"  Caught expected error: {e}")


def demo_workflow_resumption():
    """Demonstrate checkpoint and resumption of workflows."""
    print("\n" + "=" * 60)
    print("DEMO: Workflow Resumption")
    print("=" * 60)

    # Build a simple workflow
    builder = WorkflowBuilder("resumable_workflow")
    builder.add_node("step1", "agent-1")
    builder.add_node("step2", "agent-2")
    builder.add_node("step3", "agent-3")
    builder.add_dependency("step1", "step2")
    builder.add_dependency("step2", "step3")

    workflow = builder.build()

    # Create engine with a simple executor
    call_count = {"count": 0}

    def counting_executor(node: WorkflowNode, input_data: dict) -> dict:
        call_count["count"] += 1
        print(f"  Executing: {node.node_id} (call #{call_count['count']})")
        return {"output": f"result_from_{node.node_id}"}

    engine = WorkflowEngine(workflow, executor=counting_executor)

    # Simulate partial execution (first 2 nodes)
    print("\nSimulating partial execution (first 2 nodes completed)...")
    state = WorkflowState(workflow_id=workflow.workflow_id)

    # Manually set step1 and step2 as completed
    state.node_states["step1"] = NodeState(
        node_id="step1",
        status=NodeStatus.COMPLETED,
        result={"output": "result_from_step1"}
    )
    state.node_states["step2"] = NodeState(
        node_id="step2",
        status=NodeStatus.COMPLETED,
        result={"output": "result_from_step2"}
    )
    state.node_states["step3"] = NodeState(node_id="step3")

    print(f"  Completed nodes: {state.get_completed_nodes()}")

    # Resume from checkpoint
    print("\nResuming from checkpoint...")
    call_count["count"] = 0
    resumed_state = engine.resume_from_checkpoint(state)

    print(f"\nResumption complete:")
    print(f"  Executor calls: {call_count['count']} (only step3 should have been executed)")
    print(f"  All completed: {resumed_state.is_completed()}")


def main() -> int:
    """Run all workflow orchestration examples."""
    print("\nSW4RM Workflow Orchestration Example")
    print("=" * 60)
    print("This demonstrates DAG-based workflow execution with the WorkflowEngine\n")

    # Build and execute the main workflow
    workflow = build_data_pipeline_workflow()
    state, elapsed = run_workflow(workflow)
    show_execution_results(state, elapsed)

    # Demo cycle detection
    demo_cycle_detection()

    # Demo workflow resumption
    demo_workflow_resumption()

    print("\n" + "=" * 60)
    print("ALL WORKFLOW SCENARIOS COMPLETED")
    print("=" * 60)
    print("\nKey takeaways:")
    print("1. Use WorkflowBuilder for fluent DAG construction")
    print("2. Define dependencies with add_dependency() to control execution order")
    print("3. Nodes without dependencies can execute in parallel")
    print("4. Use input/output mapping for data flow between nodes")
    print("5. WorkflowEngine validates DAG structure (no cycles)")
    print("6. Use resume_from_checkpoint() for long-running workflows")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
