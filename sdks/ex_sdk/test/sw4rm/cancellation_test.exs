defmodule Sw4rm.CancellationTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Cancellation
  alias Sw4rm.Cancellation.CancellationFlag

  describe "new/1" do
    test "creates empty state" do
      state = Cancellation.new()
      assert state.flags == %{}
      assert state.children == %{}
    end

    test "accepts injectable now_ms_fn" do
      state = Cancellation.new(now_ms_fn: fn -> 42_000 end)
      assert state.now_ms_fn.() == 42_000
    end
  end

  describe "register_child_delegation/3" do
    test "registers parent-child relationship" do
      state = Cancellation.new()
      state = Cancellation.register_child_delegation(state, "parent", "child-a")
      state = Cancellation.register_child_delegation(state, "parent", "child-b")
      assert "child-a" in state.children["parent"]
      assert "child-b" in state.children["parent"]
    end
  end

  describe "handle_cancel_delegation/2" do
    test "cancels the target correlation" do
      state = Cancellation.new(now_ms_fn: fn -> 10_000 end)

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "corr-1",
          reason: "stop",
          grace_period_ms: 0
        })

      assert Cancellation.is_cancelled?(state, "corr-1")
    end

    test "clamps grace period to minimum 5000ms" do
      state = Cancellation.new(now_ms_fn: fn -> 10_000 end)

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "corr-1",
          reason: "stop",
          grace_period_ms: 0
        })

      assert Cancellation.effective_grace_period_ms(state, "corr-1") == 5000
    end

    test "preserves grace period when above minimum" do
      state = Cancellation.new(now_ms_fn: fn -> 10_000 end)

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "corr-1",
          reason: "stop",
          grace_period_ms: 10_000
        })

      assert Cancellation.effective_grace_period_ms(state, "corr-1") == 10_000
    end

    test "cascades to registered children" do
      state =
        Cancellation.new(now_ms_fn: fn -> 10_000 end)
        |> Cancellation.register_child_delegation("parent", "child-a")
        |> Cancellation.register_child_delegation("parent", "child-b")

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "parent",
          reason: "abort",
          grace_period_ms: 10_000
        })

      assert Cancellation.is_cancelled?(state, "parent")
      assert Cancellation.is_cancelled?(state, "child-a")
      assert Cancellation.is_cancelled?(state, "child-b")
    end

    test "children inherit parent's grace period" do
      state =
        Cancellation.new(now_ms_fn: fn -> 10_000 end)
        |> Cancellation.register_child_delegation("parent", "child")

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "parent",
          reason: "abort",
          grace_period_ms: 8_000
        })

      assert Cancellation.effective_grace_period_ms(state, "child") == 8_000
    end
  end

  describe "is_grace_expired?/3" do
    test "false before expiry" do
      cancel_time = 10_000
      grace = 5_000
      state = Cancellation.new(now_ms_fn: fn -> cancel_time end)

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "corr-1",
          reason: "stop",
          grace_period_ms: 0
        })

      refute Cancellation.is_grace_expired?(state, "corr-1", cancel_time + grace - 1)
    end

    test "true at expiry boundary" do
      cancel_time = 10_000
      grace = 5_000
      state = Cancellation.new(now_ms_fn: fn -> cancel_time end)

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "corr-1",
          reason: "stop",
          grace_period_ms: 0
        })

      assert Cancellation.is_grace_expired?(state, "corr-1", cancel_time + grace)
    end

    test "false for non-cancelled correlation" do
      state = Cancellation.new()
      refute Cancellation.is_grace_expired?(state, "not-cancelled", 999_999)
    end
  end

  describe "forced_preemption_error_code/3" do
    test "returns 0 before grace expiry" do
      state = Cancellation.new(now_ms_fn: fn -> 10_000 end)

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "corr-1",
          reason: "stop",
          grace_period_ms: 0
        })

      assert Cancellation.forced_preemption_error_code(state, "corr-1", 14_999) == 0
    end

    test "returns 12 after grace expiry" do
      state = Cancellation.new(now_ms_fn: fn -> 10_000 end)

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "corr-1",
          reason: "stop",
          grace_period_ms: 0
        })

      assert Cancellation.forced_preemption_error_code(state, "corr-1", 15_000) == 12
    end
  end

  describe "collect_forced_preemptions/3" do
    test "filters to cancelled correlations past grace period" do
      state = Cancellation.new(now_ms_fn: fn -> 10_000 end)

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "corr-1",
          reason: "stop",
          grace_period_ms: 0
        })

      result =
        Cancellation.collect_forced_preemptions(
          state,
          ["corr-1", "not-cancelled"],
          15_000
        )

      assert result == ["corr-1"]
    end

    test "returns empty when no grace expired" do
      state = Cancellation.new(now_ms_fn: fn -> 10_000 end)

      {:ok, state} =
        Cancellation.handle_cancel_delegation(state, %{
          correlation_id: "corr-1",
          reason: "stop",
          grace_period_ms: 0
        })

      result =
        Cancellation.collect_forced_preemptions(
          state,
          ["corr-1"],
          14_999
        )

      assert result == []
    end
  end

  describe "CancellationFlag struct" do
    test "has expected fields" do
      flag = %CancellationFlag{
        correlation_id: "c1",
        cancel_time_ms: 1000,
        grace_period_ms: 5000,
        reason: "test"
      }

      assert flag.correlation_id == "c1"
      assert flag.cancel_time_ms == 1000
      assert flag.grace_period_ms == 5000
      assert flag.reason == "test"
    end
  end
end
