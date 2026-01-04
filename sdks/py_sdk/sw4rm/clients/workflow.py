"""Workflow client for SW4RM.

This module re-exports WorkflowEngine as WorkflowClient for API consistency
with Rust and JS SDKs. The workflow engine provides local DAG-based workflow
orchestration for multi-agent systems.

Note: WorkflowClient is an alias for WorkflowEngine. The workflow module
provides local orchestration, not a remote service client. In the future,
this may be replaced by a true gRPC client when the WorkflowService backend
is implemented.

Example:
    >>> from sw4rm.clients import WorkflowClient
    >>> client = WorkflowClient()
    >>> # Or use the builder pattern:
    >>> from sw4rm.workflow import WorkflowBuilder
    >>> builder = WorkflowBuilder("my_workflow")
    >>> builder.add_node("step1", "agent1")
    >>> workflow = builder.build()
"""

from sw4rm.workflow.engine import WorkflowEngine
from sw4rm.workflow.types import (
    NodeStatus,
    TriggerType,
    WorkflowNode,
    WorkflowDefinition,
    WorkflowState,
    NodeState,
)

# Alias for SDK parity with Rust and JS
WorkflowClient = WorkflowEngine

__all__ = [
    "WorkflowClient",
    "WorkflowEngine",
    "NodeStatus",
    "TriggerType",
    "WorkflowNode",
    "WorkflowDefinition",
    "WorkflowState",
    "NodeState",
]
