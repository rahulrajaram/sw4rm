defmodule Sw4rm.LLM.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Sw4rm.LLM.RateLimiter

  setup do
    # Start a fresh rate limiter per test with a unique name
    name = :"test_limiter_#{:erlang.unique_integer([:positive])}"

    {:ok, pid} =
      RateLimiter.start_link(
        name: name,
        tokens_per_minute: 10_000,
        max_wait_ms: 1_000,
        cooldown_ms: 100,
        successes_for_recovery: 3
      )

    on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid)
    end)

    %{limiter: name}
  end

  describe "acquire/2" do
    test "succeeds when tokens are available", %{limiter: limiter} do
      assert :ok = RateLimiter.acquire(limiter, 100)
    end

    test "succeeds for small requests without waiting", %{limiter: limiter} do
      # The bucket starts full at 10,000 tokens
      assert :ok = RateLimiter.acquire(limiter, 5_000)
      assert :ok = RateLimiter.acquire(limiter, 4_000)
    end
  end

  describe "status/1" do
    test "returns diagnostic info", %{limiter: limiter} do
      status = RateLimiter.status(limiter)
      assert status.enabled == true
      assert status.adaptive_enabled == true
      assert status.base_tpm == 10_000.0
      assert status.current_tpm == 10_000.0
      assert is_float(status.available_tokens)
    end
  end

  describe "disabled limiter" do
    test "always returns :ok immediately" do
      name = :"disabled_limiter_#{:erlang.unique_integer([:positive])}"

      {:ok, pid} =
        RateLimiter.start_link(
          name: name,
          enabled: false,
          tokens_per_minute: 1
        )

      # Even requesting more tokens than exist should succeed
      assert :ok = RateLimiter.acquire(name, 1_000_000)

      GenServer.stop(pid)
    end
  end

  describe "record_rate_limit/1" do
    test "reduces current TPM", %{limiter: limiter} do
      initial = RateLimiter.status(limiter)
      RateLimiter.record_rate_limit(limiter)
      # Cast is async, give it a moment
      Process.sleep(50)
      after_limit = RateLimiter.status(limiter)
      assert after_limit.current_tpm < initial.current_tpm
    end
  end

  describe "record_success/1" do
    test "increments success counter", %{limiter: limiter} do
      RateLimiter.record_success(limiter)
      RateLimiter.record_success(limiter)
      Process.sleep(50)
      status = RateLimiter.status(limiter)
      assert status.successes_since_limit == 2
    end
  end

  describe "adaptive recovery" do
    test "recovers TPM after cooldown and sufficient successes", %{limiter: limiter} do
      # First, trigger a rate limit to reduce TPM
      RateLimiter.record_rate_limit(limiter)
      Process.sleep(50)

      reduced = RateLimiter.status(limiter)
      assert reduced.current_tpm < reduced.base_tpm

      # Record enough successes
      for _ <- 1..3 do
        RateLimiter.record_success(limiter)
      end

      Process.sleep(50)

      # Wait for cooldown (100ms configured above)
      Process.sleep(150)

      # Trigger a refill cycle via acquire to run recovery logic
      RateLimiter.acquire(limiter, 1)
      Process.sleep(50)

      recovered = RateLimiter.status(limiter)
      assert recovered.current_tpm > reduced.current_tpm
    end
  end
end
