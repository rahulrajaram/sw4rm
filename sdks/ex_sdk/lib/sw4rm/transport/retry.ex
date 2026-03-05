defmodule Sw4rm.Transport.Retry do
  @moduledoc """
  Exponential backoff retry for gRPC calls.

  Retries on `RPCTimeout` and `RPCUnavailable` errors.
  """

  @default_opts [
    max_attempts: 3,
    backoff_ms: 100,
    backoff_multiplier: 2.0
  ]

  @doc """
  Execute `fun` with exponential backoff retry.

  Options:
  - `:max_attempts` - maximum attempts (default 3)
  - `:backoff_ms` - initial backoff in ms (default 100)
  - `:backoff_multiplier` - multiplier per retry (default 2.0)
  """
  @spec with_retry(keyword(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def with_retry(opts \\ [], fun) do
    opts = Keyword.merge(@default_opts, opts)
    max = Keyword.fetch!(opts, :max_attempts)
    backoff = Keyword.fetch!(opts, :backoff_ms)
    multiplier = Keyword.fetch!(opts, :backoff_multiplier)

    do_retry(fun, 1, max, backoff, multiplier)
  end

  defp do_retry(fun, attempt, max, _backoff, _multiplier) when attempt > max do
    fun.()
  end

  defp do_retry(fun, attempt, max, backoff, multiplier) do
    case fun.() do
      {:ok, _} = ok ->
        ok

      {:error, %Sw4rm.Error.RPCTimeout{}} when attempt < max ->
        Process.sleep(trunc(backoff))
        do_retry(fun, attempt + 1, max, backoff * multiplier, multiplier)

      {:error, %Sw4rm.Error.RPCUnavailable{}} when attempt < max ->
        Process.sleep(trunc(backoff))
        do_retry(fun, attempt + 1, max, backoff * multiplier, multiplier)

      other ->
        other
    end
  end
end
