defmodule Sw4rm.LLM.RateLimiter do
  @moduledoc """
  Token-bucket rate limiter for LLM API requests.

  Provides proactive rate limiting to avoid 429 errors. Multiple LLM
  clients in the same application can share a single named instance.

  ## Adaptive throttling

  When `record_rate_limit/1` is called (after receiving a 429), the budget
  is reduced by `reduction_factor` (default 0.7). After a cooldown period
  and `successes_for_recovery` consecutive successful requests, the budget
  recovers by `recovery_factor` (default 1.1) up to the original base TPM.

  ## Configuration via environment variables

    * `LLM_RATE_LIMIT_ENABLED`   -- `"1"` (default) or `"0"`
    * `LLM_RATE_LIMIT_TOKENS_PER_MIN` -- default `250000` (Groq free tier)
    * `LLM_RATE_LIMIT_ADAPTIVE`  -- `"1"` (default) or `"0"`

  ## Usage

      {:ok, _pid} = Sw4rm.LLM.RateLimiter.start_link(name: :llm_limiter)
      :ok = Sw4rm.LLM.RateLimiter.acquire(:llm_limiter, 500)
      :ok = Sw4rm.LLM.RateLimiter.record_success(:llm_limiter)
  """

  use GenServer

  require Logger

  # -- Types -----------------------------------------------------------------

  @type config :: %{
          tokens_per_minute: pos_integer(),
          burst_allowance: float(),
          min_tokens_per_request: pos_integer(),
          max_wait_ms: pos_integer(),
          enabled: boolean(),
          adaptive_enabled: boolean(),
          reduction_factor: float(),
          recovery_factor: float(),
          cooldown_ms: pos_integer(),
          successes_for_recovery: pos_integer()
        }

  # -- Client API ------------------------------------------------------------

  @doc """
  Start a rate limiter process.

  ## Options

    * `:name`                  -- GenServer name (default `__MODULE__`)
    * `:tokens_per_minute`     -- base TPM budget (default from env or 250_000)
    * `:burst_allowance`       -- max burst as fraction of TPM (default 1.0)
    * `:min_tokens_per_request`-- floor per request (default 100)
    * `:max_wait_ms`           -- max blocking wait in ms (default 120_000)
    * `:enabled`               -- enable/disable (default from env or true)
    * `:adaptive_enabled`      -- enable adaptive throttling (default from env or true)
    * `:reduction_factor`      -- multiplier on 429 (default 0.7)
    * `:recovery_factor`       -- multiplier on recovery (default 1.1)
    * `:cooldown_ms`           -- ms before recovery starts (default 30_000)
    * `:successes_for_recovery`-- required successes before recovery (default 20)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Acquire `estimated_tokens` from the bucket.

  Blocks (via `:timer.sleep/1` loop) until tokens are available or the
  `max_wait_ms` deadline is exceeded. Returns `:ok` on success or
  `{:error, :timeout}` if the deadline is reached.

  When the limiter is disabled, returns `:ok` immediately.
  """
  @spec acquire(GenServer.server(), pos_integer()) :: :ok | {:error, :timeout}
  def acquire(server, estimated_tokens) do
    GenServer.call(server, {:acquire, estimated_tokens}, :infinity)
  end

  @doc """
  Record a 429 rate-limit event. Adaptively reduces the token budget.
  """
  @spec record_rate_limit(GenServer.server()) :: :ok
  def record_rate_limit(server) do
    GenServer.cast(server, :record_rate_limit)
  end

  @doc """
  Record a successful request. Contributes toward adaptive recovery.
  """
  @spec record_success(GenServer.server()) :: :ok
  def record_success(server) do
    GenServer.cast(server, :record_success)
  end

  @doc """
  Return a snapshot of the limiter state for diagnostics.
  """
  @spec status(GenServer.server()) :: map()
  def status(server) do
    GenServer.call(server, :status)
  end

  # -- Callbacks -------------------------------------------------------------

  @impl true
  def init(opts) do
    config = build_config(opts)

    state = %{
      config: config,
      base_tpm: config.tokens_per_minute * 1.0,
      current_tpm: config.tokens_per_minute * 1.0,
      min_tpm: max(1000.0, config.tokens_per_minute * 0.25),
      tokens: config.tokens_per_minute * 1.0,
      last_refill: System.monotonic_time(:millisecond),
      last_rate_limit_time: nil,
      successes_since_limit: 0
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:acquire, estimated_tokens}, from, state) do
    if not state.config.enabled do
      {:reply, :ok, state}
    else
      tokens_needed = max(estimated_tokens, state.config.min_tokens_per_request)
      state = refill(state)
      attempt_acquire(state, tokens_needed, from, System.monotonic_time(:millisecond))
    end
  end

  @impl true
  def handle_call(:status, _from, state) do
    info = %{
      enabled: state.config.enabled,
      adaptive_enabled: state.config.adaptive_enabled,
      base_tpm: state.base_tpm,
      current_tpm: state.current_tpm,
      available_tokens: state.tokens,
      successes_since_limit: state.successes_since_limit
    }

    {:reply, info, state}
  end

  @impl true
  def handle_cast(:record_rate_limit, state) do
    if not (state.config.enabled and state.config.adaptive_enabled) do
      {:noreply, state}
    else
      now = System.monotonic_time(:millisecond)
      new_tpm = max(state.min_tpm, state.current_tpm * state.config.reduction_factor)

      if new_tpm < state.current_tpm do
        Logger.warning("LLM rate limiter reduced to #{round(new_tpm)} tokens/min")

        {:noreply,
         %{
           state
           | current_tpm: new_tpm,
             tokens: min(state.tokens, new_tpm),
             last_rate_limit_time: now,
             successes_since_limit: 0
         }}
      else
        {:noreply, %{state | last_rate_limit_time: now, successes_since_limit: 0}}
      end
    end
  end

  @impl true
  def handle_cast(:record_success, state) do
    if not (state.config.enabled and state.config.adaptive_enabled) do
      {:noreply, state}
    else
      {:noreply, %{state | successes_since_limit: state.successes_since_limit + 1}}
    end
  end

  @impl true
  def handle_info({:retry_acquire, tokens_needed, from, start_time}, state) do
    state = refill(state)
    attempt_acquire(state, tokens_needed, from, start_time)
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # -- Private ---------------------------------------------------------------

  defp attempt_acquire(state, tokens_needed, from, start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if state.tokens >= tokens_needed do
      GenServer.reply(from, :ok)
      {:noreply, %{state | tokens: state.tokens - tokens_needed}}
    else
      if elapsed >= state.config.max_wait_ms do
        GenServer.reply(from, {:error, :timeout})
        {:noreply, state}
      else
        # Schedule a retry after 250ms
        Process.send_after(self(), {:retry_acquire, tokens_needed, from, start_time}, 250)
        {:noreply, state}
      end
    end
  end

  defp refill(state) do
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - state.last_refill
    refill_amount = elapsed_ms / 60_000.0 * state.current_tpm
    max_tokens = state.current_tpm * state.config.burst_allowance
    new_tokens = min(state.tokens + refill_amount, max_tokens)

    state = %{state | tokens: new_tokens, last_refill: now}
    maybe_recover(state, now)
  end

  defp maybe_recover(state, now) do
    cond do
      not state.config.adaptive_enabled ->
        state

      state.current_tpm >= state.base_tpm ->
        state

      is_nil(state.last_rate_limit_time) ->
        state

      now - state.last_rate_limit_time < state.config.cooldown_ms ->
        state

      state.successes_since_limit < state.config.successes_for_recovery ->
        state

      true ->
        new_tpm = min(state.base_tpm, state.current_tpm * state.config.recovery_factor)

        if new_tpm > state.current_tpm do
          Logger.info("LLM rate limiter recovered to #{round(new_tpm)} tokens/min")
          %{state | current_tpm: new_tpm, successes_since_limit: 0}
        else
          state
        end
    end
  end

  defp build_config(opts) do
    %{
      tokens_per_minute:
        Keyword.get(opts, :tokens_per_minute, env_int("LLM_RATE_LIMIT_TOKENS_PER_MIN", 250_000)),
      burst_allowance: Keyword.get(opts, :burst_allowance, 1.0),
      min_tokens_per_request: Keyword.get(opts, :min_tokens_per_request, 100),
      max_wait_ms: Keyword.get(opts, :max_wait_ms, 120_000),
      enabled: Keyword.get(opts, :enabled, env_bool("LLM_RATE_LIMIT_ENABLED", true)),
      adaptive_enabled:
        Keyword.get(opts, :adaptive_enabled, env_bool("LLM_RATE_LIMIT_ADAPTIVE", true)),
      reduction_factor: Keyword.get(opts, :reduction_factor, 0.7),
      recovery_factor: Keyword.get(opts, :recovery_factor, 1.1),
      cooldown_ms: Keyword.get(opts, :cooldown_ms, 30_000),
      successes_for_recovery: Keyword.get(opts, :successes_for_recovery, 20)
    }
  end

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      val -> String.to_integer(val)
    end
  end

  defp env_bool(key, default) do
    case System.get_env(key) do
      nil -> default
      val -> val not in ["0", "false", "no"]
    end
  end
end
