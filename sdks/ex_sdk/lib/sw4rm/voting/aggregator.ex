defmodule Sw4rm.Voting.Aggregator do
  @moduledoc """
  GenServer for stateful multi-round voting with history.
  """
  use GenServer

  alias Sw4rm.Voting.Vote

  defmodule Round do
    @moduledoc false
    defstruct [:round_id, :timestamp, :strategy_name, :votes, :result]
  end

  # -- Client API --

  @doc "Start the aggregator. Options: `:strategy` (module, default `MajorityVote`), `:max_history` (default 100)."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec set_strategy(GenServer.server(), module()) :: :ok
  def set_strategy(server, strategy_mod),
    do: GenServer.call(server, {:set_strategy, strategy_mod})

  @spec run_vote(GenServer.server(), [Vote.t()], keyword()) :: map()
  def run_vote(server, votes, opts \\ []) do
    GenServer.call(server, {:run_vote, votes, opts})
  end

  @spec history(GenServer.server(), non_neg_integer() | nil) :: [Round.t()]
  def history(server, limit \\ nil), do: GenServer.call(server, {:history, limit})

  @spec clear_history(GenServer.server()) :: :ok
  def clear_history(server), do: GenServer.call(server, :clear_history)

  # -- Callbacks --

  @impl true
  def init(opts) do
    strategy = Keyword.get(opts, :strategy, Sw4rm.Voting.MajorityVote)
    max_history = Keyword.get(opts, :max_history, 100)
    {:ok, %{strategy: strategy, history: [], max_history: max_history}}
  end

  @impl true
  def handle_call({:set_strategy, mod}, _from, s), do: {:reply, :ok, %{s | strategy: mod}}

  def handle_call({:run_vote, votes, opts}, _from, s) do
    result = s.strategy.aggregate(votes)

    round = %Round{
      round_id: Keyword.get(opts, :round_id),
      timestamp: System.system_time(:second),
      strategy_name: s.strategy.strategy_name(),
      votes: votes,
      result: result
    }

    history = Enum.take([round | s.history], s.max_history)
    {:reply, result, %{s | history: history}}
  end

  def handle_call({:history, nil}, _from, s), do: {:reply, s.history, s}
  def handle_call({:history, limit}, _from, s), do: {:reply, Enum.take(s.history, limit), s}
  def handle_call(:clear_history, _from, s), do: {:reply, :ok, %{s | history: []}}
end
