defmodule Sw4rm.WorktreeState do
  @moduledoc """
  Worktree state machine per SW4RM spec S16.

  GenServer managing 5-state worktree binding FSM:
  unbound -> bound_home -> switch_pending -> bound_non_home, bind_failed
  """
  use GenServer

  @transition_matrix %{
    unbound: [:bound_home, :bind_failed],
    bound_home: [:switch_pending, :unbound],
    switch_pending: [:bound_non_home, :bound_home],
    bound_non_home: [:bound_home, :unbound],
    bind_failed: [:unbound, :bound_home]
  }

  defmodule BindingInfo do
    @moduledoc false
    defstruct [:worktree_id, :repo_id, :branch, :bound_at, :expires_at]
  end

  defmodule TransitionEntry do
    @moduledoc false
    defstruct [:from_state, :to_state, :timestamp, :metadata]
  end

  # -- Client API --

  @doc "Start the worktree state machine. Options: `:switch_ttl` (default 3600s)."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Return the current FSM state atom."
  def current_state(server), do: GenServer.call(server, :current_state)

  @doc "Bind to a worktree. Transitions unbound/bind_failed -> bound_home."
  def bind(server, worktree_id, repo_id, branch) do
    GenServer.call(server, {:bind, worktree_id, repo_id, branch})
  end

  @doc "Unbind from current worktree."
  def unbind(server), do: GenServer.call(server, :unbind)

  @doc "Request switch to non-home worktree. bound_home -> switch_pending."
  def request_switch(server, worktree_id, repo_id, branch) do
    GenServer.call(server, {:request_switch, worktree_id, repo_id, branch})
  end

  @doc "Approve pending switch. switch_pending -> bound_non_home."
  def approve_switch(server), do: GenServer.call(server, :approve_switch)

  @doc "Reject pending switch. switch_pending -> bound_home."
  def reject_switch(server), do: GenServer.call(server, :reject_switch)

  @doc "Revert from non-home to home binding."
  def revert_to_home(server), do: GenServer.call(server, :revert_to_home)

  @doc "Return the current `%BindingInfo{}` or `nil`."
  def get_current_binding(server), do: GenServer.call(server, :get_current_binding)

  @doc "Return the home `%BindingInfo{}` or `nil`."
  def get_home_binding(server), do: GenServer.call(server, :get_home_binding)

  @doc "Return the pending switch `%BindingInfo{}` or `nil`."
  def get_pending_switch(server), do: GenServer.call(server, :get_pending_switch)

  @doc "Return the list of `%TransitionEntry{}` records."
  def history(server), do: GenServer.call(server, :history)

  # -- Callbacks --

  @impl true
  def init(opts) do
    switch_ttl = Keyword.get(opts, :switch_ttl, 3600)

    {:ok,
     %{
       state: :unbound,
       home_binding: nil,
       current_binding: nil,
       pending_switch: nil,
       switch_ttl: switch_ttl,
       history: []
     }}
  end

  @impl true
  def handle_call(:current_state, _from, s), do: {:reply, s.state, s}

  def handle_call({:bind, wt_id, repo_id, branch}, _from, s) do
    if s.state in [:unbound, :bind_failed] do
      case do_transition(s, :bound_home) do
        {:ok, s} ->
          binding = %BindingInfo{
            worktree_id: wt_id,
            repo_id: repo_id,
            branch: branch,
            bound_at: System.system_time(:second)
          }

          {:reply, {:ok, :bound_home}, %{s | home_binding: binding, current_binding: binding}}

        {:error, _} = err ->
          {:reply, err, s}
      end
    else
      {:reply,
       {:error,
        Sw4rm.Error.Worktree.exception(
          message: "bind is only valid from unbound or bind_failed, current state: #{s.state}",
          worktree_id: (s.current_binding && s.current_binding.worktree_id) || "",
          state: s.state
        )}, s}
    end
  end

  def handle_call(:unbind, _from, s) do
    case do_transition(s, :unbound) do
      {:ok, s} ->
        {:reply, {:ok, :unbound}, %{s | current_binding: nil, pending_switch: nil}}

      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_call({:request_switch, wt_id, repo_id, branch}, _from, s) do
    case do_transition(s, :switch_pending) do
      {:ok, s} ->
        pending = %BindingInfo{worktree_id: wt_id, repo_id: repo_id, branch: branch}
        {:reply, {:ok, :switch_pending}, %{s | pending_switch: pending}}

      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_call(:approve_switch, _from, s) do
    case s.pending_switch do
      nil ->
        {:reply, {:error, :no_pending_switch}, s}

      pending ->
        case do_transition(s, :bound_non_home) do
          {:ok, s} ->
            now = System.system_time(:second)

            binding = %{
              pending
              | bound_at: now,
                expires_at: now + s.switch_ttl
            }

            {:reply, {:ok, :bound_non_home}, %{s | current_binding: binding, pending_switch: nil}}

          {:error, _} = err ->
            {:reply, err, s}
        end
    end
  end

  def handle_call(:reject_switch, _from, s) do
    case do_transition(s, :bound_home) do
      {:ok, s} ->
        {:reply, {:ok, :bound_home}, %{s | current_binding: s.home_binding, pending_switch: nil}}

      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_call(:revert_to_home, _from, s) do
    case do_transition(s, :bound_home) do
      {:ok, s} ->
        {:reply, {:ok, :bound_home}, %{s | current_binding: s.home_binding}}

      {:error, _} = err ->
        {:reply, err, s}
    end
  end

  def handle_call(:get_current_binding, _from, s), do: {:reply, s.current_binding, s}
  def handle_call(:get_home_binding, _from, s), do: {:reply, s.home_binding, s}
  def handle_call(:get_pending_switch, _from, s), do: {:reply, s.pending_switch, s}
  def handle_call(:history, _from, s), do: {:reply, s.history, s}

  # -- Helpers --

  defp do_transition(s, to_state) do
    allowed = Map.get(@transition_matrix, s.state, [])

    if to_state in allowed do
      entry = %TransitionEntry{
        from_state: s.state,
        to_state: to_state,
        timestamp: System.system_time(:second)
      }

      {:ok, %{s | state: to_state, history: [entry | s.history]}}
    else
      {:error,
       Sw4rm.Error.Worktree.exception(
         message: "Invalid worktree transition from #{s.state} to #{to_state}",
         worktree_id: (s.current_binding && s.current_binding.worktree_id) || "",
         state: s.state
       )}
    end
  end
end
