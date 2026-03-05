defmodule Sw4rm.WorkflowTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Workflow

  setup do
    {:ok, wf} = Workflow.start_link()
    %{wf: wf}
  end

  describe "submit/2" do
    test "creates workflow from DAG definition", %{wf: wf} do
      def_ = %{
        name: "test-wf",
        nodes: [
          %{node_id: "n1", agent_id: "a1", task_type: :code},
          %{node_id: "n2", agent_id: "a2", task_type: :review}
        ],
        edges: [%{from_node: "n1", to_node: "n2"}]
      }

      assert {:ok, wf_id} = Workflow.submit(wf, def_)
      assert is_binary(wf_id)
    end

    test "rejects cyclic graph", %{wf: wf} do
      def_ = %{
        nodes: [
          %{node_id: "n1", agent_id: "a1", task_type: :code},
          %{node_id: "n2", agent_id: "a2", task_type: :review}
        ],
        edges: [
          %{from_node: "n1", to_node: "n2"},
          %{from_node: "n2", to_node: "n1"}
        ]
      }

      assert {:error, :cycle_detected} = Workflow.submit(wf, def_)
    end

    test "accepts custom workflow_id", %{wf: wf} do
      def_ = %{
        workflow_id: "custom-id",
        nodes: [%{node_id: "n1", agent_id: "a1", task_type: :t}],
        edges: []
      }

      assert {:ok, "custom-id"} = Workflow.submit(wf, def_)
    end
  end

  describe "status/2" do
    test "returns workflow summary", %{wf: wf} do
      def_ = %{
        name: "test",
        nodes: [%{node_id: "n1", agent_id: "a1", task_type: :code}],
        edges: []
      }

      {:ok, wf_id} = Workflow.submit(wf, def_)
      assert {:ok, summary} = Workflow.status(wf, wf_id)
      assert summary.name == "test"
      assert summary.status == :running
      assert summary.total_nodes == 1
      assert summary.pending == 1
    end

    test "returns error for missing workflow", %{wf: wf} do
      assert {:error, :not_found} = Workflow.status(wf, "nope")
    end
  end

  describe "update_node/5" do
    test "updates node status", %{wf: wf} do
      def_ = %{nodes: [%{node_id: "n1", agent_id: "a1", task_type: :t}], edges: []}
      {:ok, wf_id} = Workflow.submit(wf, def_)

      assert :ok = Workflow.update_node(wf, wf_id, "n1", :completed, "done")
      {:ok, summary} = Workflow.status(wf, wf_id)
      assert summary.completed == 1
      assert summary.status == :completed
    end

    test "workflow becomes failed if any node fails", %{wf: wf} do
      def_ = %{
        nodes: [
          %{node_id: "n1", agent_id: "a1", task_type: :t},
          %{node_id: "n2", agent_id: "a2", task_type: :t}
        ],
        edges: []
      }

      {:ok, wf_id} = Workflow.submit(wf, def_)
      Workflow.update_node(wf, wf_id, "n1", :failed, "error")

      {:ok, summary} = Workflow.status(wf, wf_id)
      assert summary.status == :failed
    end

    test "returns error for missing node", %{wf: wf} do
      def_ = %{nodes: [%{node_id: "n1", agent_id: "a1", task_type: :t}], edges: []}
      {:ok, wf_id} = Workflow.submit(wf, def_)

      assert {:error, :node_not_found} = Workflow.update_node(wf, wf_id, "nope", :completed)
    end
  end

  describe "ready_nodes/2" do
    test "returns nodes with all deps met", %{wf: wf} do
      def_ = %{
        nodes: [
          %{node_id: "n1", agent_id: "a1", task_type: :t},
          %{node_id: "n2", agent_id: "a2", task_type: :t},
          %{node_id: "n3", agent_id: "a3", task_type: :t}
        ],
        edges: [
          %{from_node: "n1", to_node: "n2"},
          %{from_node: "n2", to_node: "n3"}
        ]
      }

      {:ok, wf_id} = Workflow.submit(wf, def_)

      # Only n1 should be ready initially
      {:ok, ready} = Workflow.ready_nodes(wf, wf_id)
      assert length(ready) == 1
      assert hd(ready).node_id == "n1"

      # Complete n1, now n2 should be ready
      Workflow.update_node(wf, wf_id, "n1", :completed)
      {:ok, ready} = Workflow.ready_nodes(wf, wf_id)
      assert length(ready) == 1
      assert hd(ready).node_id == "n2"
    end

    test "parallel nodes are all ready", %{wf: wf} do
      def_ = %{
        nodes: [
          %{node_id: "n1", agent_id: "a1", task_type: :t},
          %{node_id: "n2", agent_id: "a2", task_type: :t}
        ],
        edges: []
      }

      {:ok, wf_id} = Workflow.submit(wf, def_)
      {:ok, ready} = Workflow.ready_nodes(wf, wf_id)
      assert length(ready) == 2
    end
  end

  describe "cancel/2" do
    test "cancels a workflow", %{wf: wf} do
      def_ = %{nodes: [%{node_id: "n1", agent_id: "a1", task_type: :t}], edges: []}
      {:ok, wf_id} = Workflow.submit(wf, def_)

      assert :ok = Workflow.cancel(wf, wf_id)
      {:ok, summary} = Workflow.status(wf, wf_id)
      assert summary.status == :cancelled
    end
  end

  describe "list/1" do
    test "returns all workflow summaries", %{wf: wf} do
      Workflow.submit(wf, %{nodes: [%{node_id: "n1", agent_id: "a1", task_type: :t}], edges: []})
      Workflow.submit(wf, %{nodes: [%{node_id: "n2", agent_id: "a2", task_type: :t}], edges: []})

      summaries = Workflow.list(wf)
      assert length(summaries) == 2
    end
  end
end
