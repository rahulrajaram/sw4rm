defmodule Sw4rm.PolicyStore do
  @moduledoc """
  Policy storage behaviour with pluggable backends.
  """

  defmodule Policy do
    @moduledoc "A policy defining rules or constraints."
    @type t :: %__MODULE__{}
    defstruct [
      :policy_id,
      :name,
      :description,
      rules: [],
      enabled: true,
      created_at: nil,
      updated_at: nil,
      metadata: %{}
    ]

    def new(opts \\ []) do
      now = System.system_time(:second)

      %__MODULE__{
        policy_id: Keyword.get(opts, :policy_id, "policy-#{now}-#{:rand.uniform(1_000_000)}"),
        name: Keyword.get(opts, :name),
        description: Keyword.get(opts, :description),
        rules: Keyword.get(opts, :rules, []),
        enabled: Keyword.get(opts, :enabled, true),
        created_at: now,
        updated_at: now,
        metadata: Keyword.get(opts, :metadata, %{})
      }
    end
  end

  @callback get_policy(store :: term(), policy_id :: String.t()) :: Policy.t() | nil
  @callback set_policy(store :: term(), policy :: Policy.t()) :: String.t()
  @callback delete_policy(store :: term(), policy_id :: String.t()) :: boolean()
  @callback list_policies(store :: term(), opts :: keyword()) :: [Policy.t()]
end

defmodule Sw4rm.PolicyStore.InMemory do
  @moduledoc "In-memory policy store (GenServer)."
  @behaviour Sw4rm.PolicyStore
  use GenServer

  alias Sw4rm.PolicyStore.Policy

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @impl Sw4rm.PolicyStore
  def get_policy(server, policy_id), do: GenServer.call(server, {:get, policy_id})

  @impl Sw4rm.PolicyStore
  def set_policy(server, %Policy{} = policy), do: GenServer.call(server, {:set, policy})

  @impl Sw4rm.PolicyStore
  def delete_policy(server, policy_id), do: GenServer.call(server, {:delete, policy_id})

  @impl Sw4rm.PolicyStore
  def list_policies(server, opts \\ []), do: GenServer.call(server, {:list, opts})

  def clear(server), do: GenServer.call(server, :clear)

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:get, id}, _from, s), do: {:reply, Map.get(s, id), s}

  def handle_call({:set, policy}, _from, s) do
    policy =
      if policy.policy_id do
        %{policy | updated_at: System.system_time(:second)}
      else
        now = System.system_time(:second)
        %{policy | policy_id: "policy-#{now}-#{:rand.uniform(1_000_000)}", updated_at: now}
      end

    {:reply, policy.policy_id, Map.put(s, policy.policy_id, policy)}
  end

  def handle_call({:delete, id}, _from, s) do
    if Map.has_key?(s, id) do
      {:reply, true, Map.delete(s, id)}
    else
      {:reply, false, s}
    end
  end

  def handle_call({:list, opts}, _from, s) do
    enabled_only = Keyword.get(opts, :enabled_only, false)

    result =
      s
      |> Map.values()
      |> then(fn policies ->
        if enabled_only, do: Enum.filter(policies, & &1.enabled), else: policies
      end)

    {:reply, result, s}
  end

  def handle_call(:clear, _from, s) do
    {:reply, map_size(s), %{}}
  end
end
