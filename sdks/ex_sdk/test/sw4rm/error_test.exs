defmodule Sw4rm.ErrorTest do
  use ExUnit.Case, async: true

  describe "exception structs" do
    test "Sw4rm.Error" do
      err = Sw4rm.Error.exception(message: "base error")
      assert Exception.message(err) == "base error"
    end

    test "Sw4rm.Error.RPC" do
      err = Sw4rm.Error.RPC.exception(message: "rpc fail", status_code: 13, details: "router")
      assert err.status_code == 13
      assert err.details == "router"
    end

    test "Sw4rm.Error.RPCTimeout" do
      err = Sw4rm.Error.RPCTimeout.exception(message: "timeout", timeout_ms: 5000)
      assert err.timeout_ms == 5000
    end

    test "Sw4rm.Error.RPCUnavailable" do
      err =
        Sw4rm.Error.RPCUnavailable.exception(message: "unavailable", endpoint: "localhost:50051")

      assert err.endpoint == "localhost:50051"
    end

    test "Sw4rm.Error.Validation" do
      err =
        Sw4rm.Error.Validation.exception(message: "bad", field: "name", constraint: "required")

      assert err.field == "name"
      assert err.constraint == "required"
    end

    test "Sw4rm.Error.StateTransition" do
      err =
        Sw4rm.Error.StateTransition.exception(
          message: "invalid",
          from_state: :running,
          to_state: :initializing,
          allowed_transitions: [:waiting, :completed]
        )

      assert err.from_state == :running
      assert err.to_state == :initializing
      assert err.allowed_transitions == [:waiting, :completed]
    end

    test "Sw4rm.Error.BufferFull" do
      err = Sw4rm.Error.BufferFull.exception(message: "full", current_size: 100, max_size: 100)
      assert err.current_size == 100
      assert err.max_size == 100
    end

    test "Sw4rm.Error.Worktree" do
      err =
        Sw4rm.Error.Worktree.exception(message: "wt err", worktree_id: "wt-1", state: :unbound)

      assert err.worktree_id == "wt-1"
    end

    test "Sw4rm.Error.DuplicateDetected" do
      err =
        Sw4rm.Error.DuplicateDetected.exception(
          message: "dup",
          idempotency_token: "token-1"
        )

      assert err.idempotency_token == "token-1"
    end
  end
end
