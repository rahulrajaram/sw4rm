# SW4RM Elixir SDK — Workflow Orchestration Example
#
# Demonstrates the local DAG-based workflow engine:
# - Defining a multi-node DAG (lint -> test -> build -> deploy)
# - Submitting and tracking workflow progress
# - Advancing through ready nodes
# - Handling node failure and workflow cancellation
# - Status reporting
#
# Run: mix run examples/workflow.exs

alias Sw4rm.Workflow
alias Sw4rm.Workflow.{Node, Edge}

IO.puts("=== SW4RM Workflow Orchestration Example ===\n")

# ──────────────────────────────────────────────
# 1. Start the Workflow Engine
# ──────────────────────────────────────────────
IO.puts("--- 1. Start Workflow Engine ---")

{:ok, engine} = Workflow.start_link()
IO.puts("  Workflow engine started")

# ──────────────────────────────────────────────
# 2. Define a CI/CD Pipeline DAG
# ──────────────────────────────────────────────
IO.puts("\n--- 2. Define CI/CD Pipeline ---")
IO.puts("  DAG: lint ──┐")
IO.puts("               ├──> build ──> deploy")
IO.puts("       test ──┘")

pipeline = %{
  name: "ci-cd-pipeline",
  nodes: [
    %{
      node_id: "lint",
      agent_id: "lint-agent",
      task_type: "lint",
      params: %{strict: true}
    },
    %{
      node_id: "test",
      agent_id: "test-agent",
      task_type: "test",
      params: %{suite: "unit"}
    },
    %{
      node_id: "build",
      agent_id: "build-agent",
      task_type: "build",
      params: %{target: "release"}
    },
    %{
      node_id: "deploy",
      agent_id: "deploy-agent",
      task_type: "deploy",
      params: %{env: "staging"}
    }
  ],
  edges: [
    %{from_node: "lint", to_node: "build"},
    %{from_node: "test", to_node: "build"},
    %{from_node: "build", to_node: "deploy"}
  ]
}

{:ok, wf_id} = Workflow.submit(engine, pipeline)
IO.puts("  Submitted workflow: #{wf_id}")

# ──────────────────────────────────────────────
# 3. Execute the Workflow
# ──────────────────────────────────────────────
IO.puts("\n--- 3. Execute Workflow ---")

# Check initial ready nodes (lint and test have no dependencies)
{:ok, ready} = Workflow.ready_nodes(engine, wf_id)
ready_ids = Enum.map(ready, & &1.node_id) |> Enum.sort()
IO.puts("  Ready nodes: #{inspect(ready_ids)}")

# Complete lint
:ok = Workflow.update_node(engine, wf_id, "lint", :completed, "No lint errors")
IO.puts("  lint: completed (no lint errors)")

# Complete test
:ok = Workflow.update_node(engine, wf_id, "test", :completed, "42 tests passed")
IO.puts("  test: completed (42 tests passed)")

# Now build should be ready
{:ok, ready} = Workflow.ready_nodes(engine, wf_id)
ready_ids = Enum.map(ready, & &1.node_id)
IO.puts("  Ready nodes: #{inspect(ready_ids)}")

# Complete build
:ok = Workflow.update_node(engine, wf_id, "build", :completed, "Artifact v1.2.3 built")
IO.puts("  build: completed (artifact v1.2.3)")

# Deploy should now be ready
{:ok, ready} = Workflow.ready_nodes(engine, wf_id)
ready_ids = Enum.map(ready, & &1.node_id)
IO.puts("  Ready nodes: #{inspect(ready_ids)}")

# Complete deploy
:ok = Workflow.update_node(engine, wf_id, "deploy", :completed, "Deployed to staging")
IO.puts("  deploy: completed (staging)")

# Check final status
{:ok, status} = Workflow.status(engine, wf_id)
IO.puts("\n  Final status: #{status.status}")
IO.puts("    Total nodes: #{status.total_nodes}")
IO.puts("    Completed:   #{status.completed}")
IO.puts("    Pending:     #{status.pending}")
IO.puts("    Failed:      #{status.failed}")

# ──────────────────────────────────────────────
# 4. Failure and Cancellation
# ──────────────────────────────────────────────
IO.puts("\n--- 4. Failure and Cancellation ---")

failure_pipeline = %{
  name: "failing-pipeline",
  nodes: [
    %{node_id: "check", agent_id: "check-agent", task_type: "check", params: %{}},
    %{node_id: "release", agent_id: "release-agent", task_type: "release", params: %{}}
  ],
  edges: [
    %{from_node: "check", to_node: "release"}
  ]
}

{:ok, fail_id} = Workflow.submit(engine, failure_pipeline)
IO.puts("  Submitted failing workflow: #{fail_id}")

# Fail the check node
:ok = Workflow.update_node(engine, fail_id, "check", :failed, "Security scan failed")
IO.puts("  check: failed (security scan)")

{:ok, status} = Workflow.status(engine, fail_id)
IO.puts("  Workflow status after failure: #{status.status}")

# No nodes should be ready since the dependency failed
{:ok, ready} = Workflow.ready_nodes(engine, fail_id)
IO.puts("  Ready nodes after failure: #{inspect(Enum.map(ready, & &1.node_id))}")

# Demonstrate explicit cancellation
cancel_pipeline = %{
  name: "cancel-demo",
  nodes: [
    %{node_id: "step-a", agent_id: "a", task_type: "work", params: %{}},
    %{node_id: "step-b", agent_id: "b", task_type: "work", params: %{}}
  ],
  edges: [
    %{from_node: "step-a", to_node: "step-b"}
  ]
}

{:ok, cancel_id} = Workflow.submit(engine, cancel_pipeline)
:ok = Workflow.cancel(engine, cancel_id)
{:ok, status} = Workflow.status(engine, cancel_id)
IO.puts("\n  Cancellation demo:")
IO.puts("    Submitted and immediately cancelled")
IO.puts("    Status: #{status.status}")

# ──────────────────────────────────────────────
# 5. Listing Workflows
# ──────────────────────────────────────────────
IO.puts("\n--- 5. Listing Workflows ---")

all = Workflow.list(engine)
IO.puts("  Total workflows: #{length(all)}")

for wf <- all do
  IO.puts("    #{wf.name}: #{wf.status} (#{wf.completed}/#{wf.total_nodes} completed)")
end

# ──────────────────────────────────────────────
IO.puts("\n=== Workflow Orchestration Example Complete ===")
IO.puts("\nKey concepts covered:")
IO.puts("  1. DAG-based workflow definition with nodes and edges")
IO.puts("  2. Dependency-aware execution (ready_nodes)")
IO.puts("  3. Node status progression: pending -> completed/failed")
IO.puts("  4. Workflow-level status derived from node statuses")
IO.puts("  5. Explicit cancellation support")
