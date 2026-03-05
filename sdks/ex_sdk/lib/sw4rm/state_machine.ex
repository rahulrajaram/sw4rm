defmodule Sw4rm.StateMachine do
  @moduledoc """
  Agent lifecycle state machine per SW4RM spec S8.

  GenServer managing state transitions with before/after hooks and history.
  """
  use GenServer

  @type state ::
          :initializing
          | :runnable
          | :scheduled
          | :running
          | :waiting
          | :waiting_resources
          | :suspended
          | :resumed
          | :completed
          | :failed
          | :shutting_down
          | :recovering

  @transition_matrix %{
    initializing: [:runnable, :failed],
    runnable: [:scheduled],
    scheduled: [:running],
    running: [:waiting, :waiting_resources, :suspended, :completed, :failed, :shutting_down],
    waiting: [:running],
    waiting_resources: [:running, :failed],
    suspended: [:resumed, :failed],
    resumed: [:running],
    completed: [:runnable],
    failed: [:recovering],
    shutting_down: [:failed],
    recovering: [:runnable, :shutting_down, :failed]
  }

  defmodule HistoryEntry do
    @moduledoc false
    defstruct [:from_state, :to_state, :timestamp, :metadata]
  end

  # -- Client API --

  @doc "Start the state machine. Options: `:initial_state` (default `:initializing`), `:max_history` (default 100)."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Return the current lifecycle state."
  @spec current_state(GenServer.server()) :: state()
  def current_state(server), do: GenServer.call(server, :current_state)

  @doc "Attempt a state transition. Returns `{:ok, new_state}` or `{:error, %StateTransition{}}`."
  @spec transition(GenServer.server(), state(), keyword()) ::
          {:ok, state()} | {:error, Sw4rm.Error.StateTransition.t()}
  def transition(server, to_state, metadata \\ []) do
    GenServer.call(server, {:transition, to_state, metadata})
  end

  @doc "Check whether a transition to `to_state` is allowed from the current state."
  @spec can_transition?(GenServer.server(), state()) :: boolean()
  def can_transition?(server, to_state), do: GenServer.call(server, {:can_transition?, to_state})

  @doc "List the states reachable from the current state."
  @spec valid_transitions(GenServer.server()) :: [state()]
  def valid_transitions(server), do: GenServer.call(server, :valid_transitions)

  @doc "Return transition history, optionally limited to the most recent `limit` entries."
  @spec history(GenServer.server(), non_neg_integer() | nil) :: [HistoryEntry.t()]
  def history(server, limit \\ nil), do: GenServer.call(server, {:history, limit})

  @doc "Register a hook called before each transition: `fn(from, to, timestamp, metadata) -> any`."
  @spec add_before_hook(GenServer.server(), (state(), state(), integer(), keyword() -> any())) ::
          :ok
  def add_before_hook(server, hook), do: GenServer.call(server, {:add_before_hook, hook})

  @doc "Register a hook called after each transition: `fn(from, to, timestamp, metadata) -> any`."
  @spec add_after_hook(GenServer.server(), (state(), state(), integer(), keyword() -> any())) ::
          :ok
  def add_after_hook(server, hook), do: GenServer.call(server, {:add_after_hook, hook})

  # -- Callbacks --

  @impl true
  def init(opts) do
    initial = Keyword.get(opts, :initial_state, :initializing)
    max_history = Keyword.get(opts, :max_history, 100)
    now = System.system_time(:second)

    {:ok,
     %{
       state: initial,
       before_hooks: [],
       after_hooks: [],
       history: [%HistoryEntry{from_state: nil, to_state: initial, timestamp: now, metadata: []}],
       max_history: max_history
     }}
  end

  @impl true
  def handle_call(:current_state, _from, %{state: state} = s), do: {:reply, state, s}

  def handle_call({:transition, to_state, metadata}, _from, s) do
    allowed = Map.get(@transition_matrix, s.state, [])

    if to_state in allowed do
      now = System.system_time(:second)

      Enum.each(s.before_hooks, fn hook -> hook.(s.state, to_state, now, metadata) end)

      entry = %HistoryEntry{
        from_state: s.state,
        to_state: to_state,
        timestamp: now,
        metadata: metadata
      }

      history = Enum.take([entry | s.history], s.max_history)

      new_s = %{s | state: to_state, history: history}

      Enum.each(s.after_hooks, fn hook -> hook.(s.state, to_state, now, metadata) end)

      {:reply, {:ok, to_state}, new_s}
    else
      error =
        Sw4rm.Error.StateTransition.exception(
          message: "No valid transition from #{s.state} to #{to_state}",
          from_state: s.state,
          to_state: to_state,
          allowed_transitions: allowed
        )

      {:reply, {:error, error}, s}
    end
  end

  def handle_call({:can_transition?, to_state}, _from, s) do
    allowed = Map.get(@transition_matrix, s.state, [])
    {:reply, to_state in allowed, s}
  end

  def handle_call(:valid_transitions, _from, s) do
    {:reply, Map.get(@transition_matrix, s.state, []), s}
  end

  def handle_call({:history, nil}, _from, s), do: {:reply, s.history, s}

  def handle_call({:history, limit}, _from, s) do
    {:reply, Enum.take(s.history, limit), s}
  end

  def handle_call({:add_before_hook, hook}, _from, s) do
    {:reply, :ok, %{s | before_hooks: [hook | s.before_hooks]}}
  end

  def handle_call({:add_after_hook, hook}, _from, s) do
    {:reply, :ok, %{s | after_hooks: [hook | s.after_hooks]}}
  end

  # -- Pure helpers --

  @doc "Get valid transitions from a state (no GenServer needed)."
  @spec transitions_for(state()) :: [state()]
  def transitions_for(state), do: Map.get(@transition_matrix, state, [])
end
