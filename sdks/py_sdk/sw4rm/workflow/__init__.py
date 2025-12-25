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

"""SW4RM Workflow orchestration for multi-agent systems.

This module provides workflow graph primitives for defining and executing
complex multi-agent workflows as directed acyclic graphs (DAGs). Inspired by
CrewAI Flows, it enables sophisticated coordination patterns with dependencies,
triggers, and state management.

Core Components:
    - WorkflowBuilder: Fluent API for building workflow definitions
    - WorkflowEngine: Execution engine with DAG validation and orchestration
    - WorkflowDefinition: Immutable workflow structure
    - WorkflowState: Mutable runtime execution state

Example:
    >>> from sw4rm.workflow import WorkflowBuilder, WorkflowEngine, TriggerType
    >>>
    >>> # Build a workflow
    >>> builder = WorkflowBuilder("data_pipeline")
    >>> builder.add_node("fetch", "fetcher_agent")
    >>>        .add_node("process", "processor_agent")
    >>>        .add_node("store", "storage_agent")
    >>>        .add_dependency("fetch", "process")
    >>>        .add_dependency("process", "store")
    >>>
    >>> workflow = builder.build()
    >>>
    >>> # Execute the workflow
    >>> engine = WorkflowEngine(workflow, executor=my_executor_func)
    >>> final_state = engine.execute(initial_data={"input": "data"})
"""

from .types import (
    NodeStatus,
    TriggerType,
    WorkflowNode,
    WorkflowDefinition,
    WorkflowState,
    NodeState,
)
from .engine import (
    WorkflowEngine,
    WorkflowEngineError,
    CycleDetectedError,
    WorkflowValidationError,
)
from .builder import (
    WorkflowBuilder,
    WorkflowBuilderError,
)

__all__ = [
    # Types
    "NodeStatus",
    "TriggerType",
    "WorkflowNode",
    "WorkflowDefinition",
    "WorkflowState",
    "NodeState",
    # Engine
    "WorkflowEngine",
    "WorkflowEngineError",
    "CycleDetectedError",
    "WorkflowValidationError",
    # Builder
    "WorkflowBuilder",
    "WorkflowBuilderError",
]
