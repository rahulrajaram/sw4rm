defmodule Sw4rm.Handoff do
  @moduledoc """
  SW4-004 inter-swarm delegation with budget envelopes, depth tracking,
  and cascading cancellation.
  """
  use GenServer

  @default_delegation_policy %{
    max_retries_on_overloaded: 2,
    initial_backoff_ms: 250,
    backoff_multiplier: 2.0,
    max_backoff_ms: 2000,
    allow_spillover_routing: false,
    max_redirects: 0
  }
  @min_cancel_grace_period_ms 5000

  defmodule BudgetEnvelope do
    @moduledoc "Resource budget for delegated tasks (matches handoff.proto BudgetEnvelope)."
    @type t :: %__MODULE__{}
    defstruct [
      :token_budget_remaining,
      :wall_time_remaining_ms,
      :deadline_epoch_ms,
      :max_delegation_depth,
      current_depth: 0
    ]
  end

  defmodule HandoffRecord do
    @moduledoc false
    defstruct [
      :handoff_id,
      :from_agent,
      :to_agent,
      :correlation_id,
      :budget,
      :delegation_policy,
      :status,
      :created_at,
      :accepted_at,
      :completed_at,
      :result,
      :rejection_reason
    ]
  end

  # -- Client API --

  @doc "Start the handoff manager."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Request a handoff to another agent."
  def request_handoff(server, request), do: GenServer.call(server, {:request, request})

  @doc "Accept a pending handoff."
  def accept(server, handoff_id), do: GenServer.call(server, {:accept, handoff_id})

  @doc "Reject a pending handoff."
  def reject(server, handoff_id, reason \\ nil) do
    GenServer.call(server, {:reject, handoff_id, reason})
  end

  @doc "Get all pending handoffs for a given agent."
  def get_pending(server, agent_id), do: GenServer.call(server, {:get_pending, agent_id})

  @doc "Complete a handoff with result."
  def complete(server, handoff_id, result),
    do: GenServer.call(server, {:complete, handoff_id, result})

  @doc "Cancel a delegation and cascade to child delegations."
  def cancel_delegation(server, correlation_id, grace_period_ms \\ nil) do
    if grace_period_ms do
      GenServer.call(server, {:cancel, correlation_id, grace_period_ms})
    else
      GenServer.call(server, {:cancel, correlation_id})
    end
  end

  @doc "Register a child delegation under a parent correlation ID."
  def register_child(server, parent_correlation_id, child_correlation_id) do
    GenServer.call(server, {:register_child, parent_correlation_id, child_correlation_id})
  end

  @doc "Get a handoff record."
  def get(server, handoff_id), do: GenServer.call(server, {:get, handoff_id})

  # -- Callbacks --

  @impl true
  def init(_opts) do
    {:ok,
     %{
       handoffs: %{},
       pending_by_agent: %{},
       children: %{},
       cancellation_flags: MapSet.new()
     }}
  end

  @impl true
  def handle_call({:request, req}, _from, s) do
    handoff_id = Map.get(req, :handoff_id, Sw4rm.Envelope.generate_uuid())
    from_agent = Map.fetch!(req, :from_agent)
    to_agent = Map.fetch!(req, :to_agent)
    correlation_id = Map.get(req, :correlation_id, Sw4rm.Envelope.generate_uuid())
    budget = Map.get(req, :budget)
    policy = Map.merge(@default_delegation_policy, Map.get(req, :delegation_policy, %{}))

    # Check depth budget
    if budget && budget.max_delegation_depth &&
         budget.current_depth >= budget.max_delegation_depth do
      {:reply, {:error, :depth_exceeded}, s}
    else
      record = %HandoffRecord{
        handoff_id: handoff_id,
        from_agent: from_agent,
        to_agent: to_agent,
        correlation_id: correlation_id,
        budget: budget,
        delegation_policy: policy,
        status: :pending,
        created_at: System.system_time(:millisecond)
      }

      pending = Map.update(s.pending_by_agent, to_agent, [handoff_id], &[handoff_id | &1])

      {:reply, {:ok, handoff_id},
       %{s | handoffs: Map.put(s.handoffs, handoff_id, record), pending_by_agent: pending}}
    end
  end

  def handle_call({:accept, handoff_id}, _from, s) do
    case Map.get(s.handoffs, handoff_id) do
      nil ->
        {:reply, {:error, :not_found}, s}

      %{status: :pending} = record ->
        updated = %{record | status: :accepted, accepted_at: System.system_time(:millisecond)}
        pending = remove_from_pending(s.pending_by_agent, record.to_agent, handoff_id)

        {:reply, {:ok, updated},
         %{s | handoffs: Map.put(s.handoffs, handoff_id, updated), pending_by_agent: pending}}

      _ ->
        {:reply, {:error, :not_pending}, s}
    end
  end

  def handle_call({:reject, handoff_id, reason}, _from, s) do
    case Map.get(s.handoffs, handoff_id) do
      nil ->
        {:reply, {:error, :not_found}, s}

      %{status: :pending} = record ->
        updated = %{record | status: :rejected, rejection_reason: reason}
        pending = remove_from_pending(s.pending_by_agent, record.to_agent, handoff_id)

        {:reply, {:ok, updated},
         %{s | handoffs: Map.put(s.handoffs, handoff_id, updated), pending_by_agent: pending}}

      _ ->
        {:reply, {:error, :not_pending}, s}
    end
  end

  def handle_call({:get_pending, agent_id}, _from, s) do
    ids = Map.get(s.pending_by_agent, agent_id, [])
    records = Enum.map(ids, &Map.get(s.handoffs, &1)) |> Enum.reject(&is_nil/1)
    {:reply, records, s}
  end

  def handle_call({:complete, handoff_id, result}, _from, s) do
    case Map.get(s.handoffs, handoff_id) do
      nil ->
        {:reply, {:error, :not_found}, s}

      record ->
        updated = %{
          record
          | status: :completed,
            result: result,
            completed_at: System.system_time(:millisecond)
        }

        {:reply, :ok, %{s | handoffs: Map.put(s.handoffs, handoff_id, updated)}}
    end
  end

  def handle_call({:cancel, correlation_id}, _from, s) do
    handle_cancel(correlation_id, @min_cancel_grace_period_ms, s)
  end

  def handle_call({:cancel, correlation_id, grace_period_ms}, _from, s) do
    clamped_grace = max(grace_period_ms, @min_cancel_grace_period_ms)
    handle_cancel(correlation_id, clamped_grace, s)
  end

  def handle_call({:register_child, parent, child}, _from, s) do
    children = Map.update(s.children, parent, [child], &[child | &1])
    {:reply, :ok, %{s | children: children}}
  end

  def handle_call({:get, handoff_id}, _from, s) do
    {:reply, Map.get(s.handoffs, handoff_id), s}
  end

  defp handle_cancel(correlation_id, _grace_period_ms, s) do
    # Mark this and all child correlations as cancelled
    to_cancel = collect_children(correlation_id, s.children)
    flags = Enum.reduce(to_cancel, s.cancellation_flags, &MapSet.put(&2, &1))

    # Update handoff statuses
    handoffs =
      Enum.reduce(s.handoffs, s.handoffs, fn {id, record}, acc ->
        if record.correlation_id in to_cancel and record.status in [:pending, :accepted] do
          Map.put(acc, id, %{record | status: :cancelled})
        else
          acc
        end
      end)

    {:reply, {:ok, MapSet.size(flags)}, %{s | handoffs: handoffs, cancellation_flags: flags}}
  end

  # -- Helpers --

  defp remove_from_pending(pending_by_agent, agent_id, handoff_id) do
    case Map.get(pending_by_agent, agent_id) do
      nil -> pending_by_agent
      ids -> Map.put(pending_by_agent, agent_id, List.delete(ids, handoff_id))
    end
  end

  defp collect_children(correlation_id, children_map) do
    direct = Map.get(children_map, correlation_id, [])
    nested = Enum.flat_map(direct, &collect_children(&1, children_map))
    [correlation_id | direct ++ nested] |> Enum.uniq()
  end
end
