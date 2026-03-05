defmodule Sw4rm.Cancellation do
  @moduledoc """
  Standalone functional cancellation manager for SW4-004 conformance.

  Pure functional module with immutable state — conformance vectors create
  fresh state per test, so a GenServer is unnecessary here.
  """

  @min_grace_period_ms 5000

  defmodule CancellationFlag do
    @moduledoc "A single cancellation flag with timing information."
    defstruct [:correlation_id, :cancel_time_ms, :grace_period_ms, :reason]
  end

  @type state :: %{
          flags: %{String.t() => CancellationFlag.t()},
          children: %{String.t() => [String.t()]},
          now_ms_fn: (-> integer())
        }

  @doc "Create a new cancellation state."
  @spec new(keyword()) :: state()
  def new(opts \\ []) do
    %{
      flags: %{},
      children: %{},
      now_ms_fn: Keyword.get(opts, :now_ms_fn, fn -> System.system_time(:millisecond) end)
    }
  end

  @doc "Register a child delegation under a parent correlation ID."
  @spec register_child_delegation(state(), String.t(), String.t()) :: state()
  def register_child_delegation(state, parent, child) do
    children = Map.update(state.children, parent, [child], &[child | &1])
    %{state | children: children}
  end

  @doc "Handle a cancel delegation request. Returns `{:ok, updated_state}`."
  @spec handle_cancel_delegation(state(), map()) :: {:ok, state()}
  def handle_cancel_delegation(state, request) do
    correlation_id = request.correlation_id
    reason = Map.get(request, :reason, "")
    requested_grace = Map.get(request, :grace_period_ms, 0)
    effective_grace = max(requested_grace, @min_grace_period_ms)
    now_ms = state.now_ms_fn.()

    all_ids = collect_tree(correlation_id, state.children)
    direct_children = Map.get(state.children, correlation_id, [])

    flags =
      Enum.reduce(all_ids, state.flags, fn id, acc ->
        # Children get grace clamped to parent's remaining grace
        child_grace =
          if id in direct_children do
            # If the parent was already cancelled, clamp child grace to parent's remaining
            case Map.get(acc, correlation_id) do
              %CancellationFlag{cancel_time_ms: parent_cancel, grace_period_ms: parent_grace} ->
                parent_remaining = max(0, parent_cancel + parent_grace - now_ms)
                min(effective_grace, parent_remaining)

              nil ->
                effective_grace
            end
          else
            effective_grace
          end

        flag = %CancellationFlag{
          correlation_id: id,
          cancel_time_ms: now_ms,
          grace_period_ms: child_grace,
          reason: reason
        }

        Map.put(acc, id, flag)
      end)

    {:ok, %{state | flags: flags}}
  end

  @doc "Check if a correlation ID has been cancelled."
  @spec is_cancelled?(state(), String.t()) :: boolean()
  def is_cancelled?(state, correlation_id) do
    Map.has_key?(state.flags, correlation_id)
  end

  @doc "Check if the grace period has expired for a cancelled correlation."
  @spec is_grace_expired?(state(), String.t(), integer() | nil) :: boolean()
  def is_grace_expired?(state, correlation_id, now_ms \\ nil) do
    case Map.get(state.flags, correlation_id) do
      nil ->
        false

      flag ->
        check_time = now_ms || state.now_ms_fn.()
        check_time >= flag.cancel_time_ms + flag.grace_period_ms
    end
  end

  @doc "Get the forced preemption error code for a correlation."
  @spec forced_preemption_error_code(state(), String.t(), integer() | nil) :: integer()
  def forced_preemption_error_code(state, correlation_id, now_ms \\ nil) do
    if is_grace_expired?(state, correlation_id, now_ms) do
      Sw4rm.ErrorCodes.forced_preemption()
    else
      Sw4rm.ErrorCodes.error_code_unspecified()
    end
  end

  @doc "Collect correlation IDs whose grace period has expired from a list of active correlations."
  @spec collect_forced_preemptions(state(), [String.t()], integer() | nil) :: [String.t()]
  def collect_forced_preemptions(state, active_correlations, now_ms \\ nil) do
    Enum.filter(active_correlations, fn corr_id ->
      is_cancelled?(state, corr_id) && is_grace_expired?(state, corr_id, now_ms)
    end)
  end

  @doc "Get the effective grace period for a cancelled correlation."
  @spec effective_grace_period_ms(state(), String.t()) :: integer() | nil
  def effective_grace_period_ms(state, correlation_id) do
    case Map.get(state.flags, correlation_id) do
      nil -> nil
      flag -> flag.grace_period_ms
    end
  end

  @doc "Return the minimum grace period constant."
  @spec min_grace_period_ms() :: non_neg_integer()
  def min_grace_period_ms, do: @min_grace_period_ms

  # -- Helpers --

  defp collect_tree(id, children_map) do
    direct = Map.get(children_map, id, [])
    nested = Enum.flat_map(direct, &collect_tree(&1, children_map))
    [id | direct ++ nested] |> Enum.uniq()
  end
end
