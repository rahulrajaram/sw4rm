defmodule Sw4rm.Transport.RetryTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Transport.Retry

  describe "with_retry/2" do
    test "returns ok on first success" do
      assert {:ok, :done} = Retry.with_retry(fn -> {:ok, :done} end)
    end

    test "returns error on non-retryable error" do
      assert {:error, :bad_request} = Retry.with_retry(fn -> {:error, :bad_request} end)
    end

    test "retries on RPCTimeout" do
      counter = :counters.new(1, [:atomics])

      result =
        Retry.with_retry([max_attempts: 3, backoff_ms: 1], fn ->
          attempt = :counters.get(counter, 1) + 1
          :counters.put(counter, 1, attempt)

          if attempt < 3 do
            {:error, Sw4rm.Error.RPCTimeout.exception(message: "timeout", timeout_ms: 100)}
          else
            {:ok, :recovered}
          end
        end)

      assert {:ok, :recovered} = result
      assert :counters.get(counter, 1) == 3
    end

    test "retries on RPCUnavailable" do
      counter = :counters.new(1, [:atomics])

      result =
        Retry.with_retry([max_attempts: 2, backoff_ms: 1], fn ->
          attempt = :counters.get(counter, 1) + 1
          :counters.put(counter, 1, attempt)

          if attempt < 2 do
            {:error, Sw4rm.Error.RPCUnavailable.exception(message: "unavail", endpoint: "host")}
          else
            {:ok, :back_up}
          end
        end)

      assert {:ok, :back_up} = result
    end

    test "gives up after max_attempts" do
      result =
        Retry.with_retry([max_attempts: 2, backoff_ms: 1], fn ->
          {:error, Sw4rm.Error.RPCTimeout.exception(message: "timeout", timeout_ms: 100)}
        end)

      assert {:error, %Sw4rm.Error.RPCTimeout{}} = result
    end
  end
end
