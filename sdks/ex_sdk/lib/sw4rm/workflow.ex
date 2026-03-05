defmodule Sw4rm.Workflow do
  @moduledoc """
  Local DAG-based workflow orchestration.

  Manages multi-step, multi-agent execution graphs with dependencies,
  parallel execution, and status tracking.
  """
  use GenServer

  defmodule Node do
    @moduledoc "A single node in a workflow DAG."
    @type t :: %__MODULE__{}
    defstruct [
      :node_id,
      :agent_id,
      :task_type,
      :params,
      trigger: :automatic,
      status: :pending,
      result: nil
    ]
  end

  defmodule Edge do
    @moduledoc "A dependency edge between two nodes."
    @type t :: %__MODULE__{}
    defstruct [:from_node, :to_node, :condition]
  end

  # -- Client API --

  @doc "Start the workflow engine."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Submit a workflow DAG."
  def submit(server, workflow_def), do: GenServer.call(server, {:submit, workflow_def})

  @doc "Get workflow status."
  def status(server, workflow_id), do: GenServer.call(server, {:status, workflow_id})

  @doc "Update a node's status."
  def update_node(server, workflow_id, node_id, status, result \\ nil) do
    GenServer.call(server, {:update_node, workflow_id, node_id, status, result})
  end

  @doc "Get nodes ready for execution (all dependencies met)."
  def ready_nodes(server, workflow_id), do: GenServer.call(server, {:ready_nodes, workflow_id})

  @doc "Cancel a workflow."
  def cancel(server, workflow_id), do: GenServer.call(server, {:cancel, workflow_id})

  @doc "List all workflows."
  def list(server), do: GenServer.call(server, :list)

  # -- Callbacks --

  @impl true
  def init(_opts), do: {:ok, %{workflows: %{}}}

  @impl true
  def handle_call({:submit, def_}, _from, s) do
    wf_id = Map.get(def_, :workflow_id, Sw4rm.Envelope.generate_uuid())

    nodes =
      def_
      |> Map.get(:nodes, [])
      |> Enum.into(%{}, fn n ->
        node = struct(Node, n)
        {node.node_id, node}
      end)

    edges =
      def_
      |> Map.get(:edges, [])
      |> Enum.map(&struct(Edge, &1))

    # Validate no cycles (simple DFS)
    case validate_dag(nodes, edges) do
      :ok ->
        workflow = %{
          workflow_id: wf_id,
          name: Map.get(def_, :name),
          nodes: nodes,
          edges: edges,
          status: :running,
          created_at: System.system_time(:second),
          metadata: Map.get(def_, :metadata, %{})
        }

        {:reply, {:ok, wf_id}, %{s | workflows: Map.put(s.workflows, wf_id, workflow)}}

      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_call({:status, wf_id}, _from, s) do
    case Map.get(s.workflows, wf_id) do
      nil -> {:reply, {:error, :not_found}, s}
      wf -> {:reply, {:ok, workflow_summary(wf)}, s}
    end
  end

  def handle_call({:update_node, wf_id, node_id, status, result}, _from, s) do
    case Map.get(s.workflows, wf_id) do
      nil ->
        {:reply, {:error, :not_found}, s}

      wf ->
        case Map.get(wf.nodes, node_id) do
          nil ->
            {:reply, {:error, :node_not_found}, s}

          node ->
            updated_node = %{node | status: status, result: result}
            nodes = Map.put(wf.nodes, node_id, updated_node)
            wf_status = compute_workflow_status(nodes)
            wf = %{wf | nodes: nodes, status: wf_status}
            {:reply, :ok, %{s | workflows: Map.put(s.workflows, wf_id, wf)}}
        end
    end
  end

  def handle_call({:ready_nodes, wf_id}, _from, s) do
    case Map.get(s.workflows, wf_id) do
      nil ->
        {:reply, {:error, :not_found}, s}

      wf ->
        ready =
          wf.nodes
          |> Map.values()
          |> Enum.filter(fn node ->
            node.status == :pending and all_deps_complete?(node.node_id, wf.edges, wf.nodes)
          end)

        {:reply, {:ok, ready}, s}
    end
  end

  def handle_call({:cancel, wf_id}, _from, s) do
    case Map.get(s.workflows, wf_id) do
      nil ->
        {:reply, {:error, :not_found}, s}

      wf ->
        {:reply, :ok, %{s | workflows: Map.put(s.workflows, wf_id, %{wf | status: :cancelled})}}
    end
  end

  def handle_call(:list, _from, s) do
    summaries = Enum.map(s.workflows, fn {_id, wf} -> workflow_summary(wf) end)
    {:reply, summaries, s}
  end

  # -- Helpers --

  defp all_deps_complete?(node_id, edges, nodes) do
    edges
    |> Enum.filter(&(&1.to_node == node_id))
    |> Enum.all?(fn edge ->
      case Map.get(nodes, edge.from_node) do
        nil -> true
        dep -> dep.status == :completed
      end
    end)
  end

  defp compute_workflow_status(nodes) do
    statuses = nodes |> Map.values() |> Enum.map(& &1.status)

    cond do
      Enum.any?(statuses, &(&1 == :failed)) -> :failed
      Enum.all?(statuses, &(&1 == :completed)) -> :completed
      true -> :running
    end
  end

  defp workflow_summary(wf) do
    nodes = Map.values(wf.nodes)

    %{
      workflow_id: wf.workflow_id,
      name: wf.name,
      status: wf.status,
      total_nodes: length(nodes),
      completed: Enum.count(nodes, &(&1.status == :completed)),
      pending: Enum.count(nodes, &(&1.status == :pending)),
      failed: Enum.count(nodes, &(&1.status == :failed)),
      running: Enum.count(nodes, &(&1.status == :running))
    }
  end

  defp validate_dag(nodes, edges) do
    # Simple cycle detection via topological sort (Kahn's algorithm)
    node_ids = Map.keys(nodes)

    in_degree =
      Enum.reduce(node_ids, %{}, fn id, acc -> Map.put(acc, id, 0) end)
      |> then(fn deg ->
        Enum.reduce(edges, deg, fn edge, acc ->
          Map.update(acc, edge.to_node, 1, &(&1 + 1))
        end)
      end)

    queue = Enum.filter(node_ids, fn id -> Map.get(in_degree, id, 0) == 0 end)
    do_topo_sort(queue, edges, in_degree, 0, length(node_ids))
  end

  defp do_topo_sort([], _edges, _in_degree, count, total) do
    if count == total, do: :ok, else: {:error, :cycle_detected}
  end

  defp do_topo_sort([node | rest], edges, in_degree, count, total) do
    {new_queue, new_in_degree} =
      edges
      |> Enum.filter(&(&1.from_node == node))
      |> Enum.reduce({rest, in_degree}, fn edge, {q, deg} ->
        new_deg = Map.update!(deg, edge.to_node, &(&1 - 1))

        if Map.get(new_deg, edge.to_node) == 0 do
          {q ++ [edge.to_node], new_deg}
        else
          {q, new_deg}
        end
      end)

    do_topo_sort(new_queue, edges, new_in_degree, count + 1, total)
  end
end
