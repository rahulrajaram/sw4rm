defmodule Sw4rm.ConformanceVectorsTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Cancellation
  alias Sw4rm.Delegation
  alias Sw4rm.ErrorCodes

  # Load JSON vectors at compile time
  @cancellation_vectors Jason.decode!(
                          File.read!(
                            Path.join([
                              __DIR__,
                              "..",
                              "..",
                              "..",
                              "..",
                              "tests",
                              "conformance_vectors",
                              "sw4_004_cancellation_vectors.json"
                            ])
                          )
                        )

  @delegation_vectors Jason.decode!(
                        File.read!(
                          Path.join([
                            __DIR__,
                            "..",
                            "..",
                            "..",
                            "..",
                            "tests",
                            "conformance_vectors",
                            "sw4_005_delegation_vectors.json"
                          ])
                        )
                      )

  # -- SW4-004 Cancellation Vectors --

  for vector <- @cancellation_vectors["vectors"] do
    @vector vector

    test "SW4-004 cancellation: #{@vector["id"]}" do
      vector = @vector
      cancel_time = 100_000

      # Build state with injectable clock
      state = Cancellation.new(now_ms_fn: fn -> cancel_time end)

      # Register children
      state =
        Enum.reduce(vector["children"], state, fn child_def, acc ->
          Cancellation.register_child_delegation(acc, child_def["parent"], child_def["child"])
        end)

      # Handle cancel delegation
      request = %{
        correlation_id: vector["request"]["correlation_id"],
        reason: vector["request"]["reason"],
        grace_period_ms: vector["request"]["grace_period_ms"]
      }

      {:ok, state} = Cancellation.handle_cancel_delegation(state, request)

      expected = vector["expected"]

      # Check effective grace period
      assert Cancellation.effective_grace_period_ms(state, request.correlation_id) ==
               expected["effective_grace_period_ms"]

      # Check all expected correlations are cancelled
      for corr_id <- expected["cancelled"] do
        assert Cancellation.is_cancelled?(state, corr_id),
               "Expected #{corr_id} to be cancelled"
      end

      # Negative assertions: correlations outside the direct-children
      # cascade must remain active (R21).
      for corr_id <- Map.get(expected, "not_cancelled", []) do
        refute Cancellation.is_cancelled?(state, corr_id),
               "Expected #{corr_id} to remain uncancelled"
      end

      # Grace expiry checks
      effective_grace = expected["effective_grace_period_ms"]

      for check <- expected["grace_expiry_checks"] do
        check_time = cancel_time + effective_grace + check["offset_ms"]

        assert Cancellation.is_grace_expired?(state, check["correlation_id"], check_time) ==
                 check["expired"],
               "grace_expired check failed for #{check["correlation_id"]} at offset #{check["offset_ms"]}"
      end

      # Forced preemption checks
      for check <- expected["forced_preemption_checks"] do
        check_time = cancel_time + effective_grace + check["offset_ms"]
        expected_code = ErrorCodes.from_string(check["error_code"])

        assert Cancellation.forced_preemption_error_code(
                 state,
                 check["correlation_id"],
                 check_time
               ) == expected_code,
               "forced_preemption check failed for #{check["correlation_id"]} at offset #{check["offset_ms"]}"
      end

      # Collect forced preemptions
      collect = expected["collect_forced"]
      collect_time = cancel_time + effective_grace + collect["offset_ms"]

      forced =
        Cancellation.collect_forced_preemptions(
          state,
          collect["active_correlations"],
          collect_time
        )

      assert Enum.sort(forced) == Enum.sort(collect["expected"]),
             "collect_forced_preemptions mismatch: got #{inspect(forced)}, expected #{inspect(collect["expected"])}"
    end
  end

  # -- SW4-005 Delegation Vectors --

  for vector <- @delegation_vectors["vectors"] do
    @vector vector

    test "SW4-005 delegation: #{@vector["id"]}" do
      vector = @vector
      redirect_map = vector["redirect_map"]
      accept_agents = Map.get(vector, "accept_agents", [])

      send_handoff_fn = fn request ->
        cond do
          request.to_agent in accept_agents ->
            %{accepted: true, redirect_to_agent_id: ""}

          Map.has_key?(redirect_map, request.to_agent) ->
            %{
              accepted: false,
              rejection_code: ErrorCodes.redirect(),
              rejection_reason: "redirecting",
              redirect_to_agent_id: Map.fetch!(redirect_map, request.to_agent)
            }

          true ->
            %{accepted: true, redirect_to_agent_id: ""}
        end
      end

      # Exhaustion vectors inject a specific clock; everything else runs
      # shortly before the deadline so budget checks pass (R12).
      now_ms_fn = fn ->
        Map.get(
          vector,
          :now_ms_epoch_ms,
          vector["now_ms_epoch_ms"] ||
            vector["budget"]["deadline_epoch_ms"] - 1000
        )
      end

      result =
        Delegation.delegate_to_swarm(%{
          send_handoff_fn: send_handoff_fn,
          from_agent: vector["from_agent"],
          to_agent: vector["to_agent"],
          reason: vector["reason"],
          request_id: vector["request_id"],
          budget: %{
            deadline_epoch_ms: vector["budget"]["deadline_epoch_ms"],
            wall_time_remaining_ms: vector["budget"]["wall_time_remaining_ms"]
          },
          delegation_policy: %{
            allow_spillover_routing: vector["policy"]["allow_spillover_routing"],
            max_redirects: vector["policy"]["max_redirects"]
          },
          now_ms_fn: now_ms_fn
        })

      expected = vector["expected"]

      assert result.accepted == expected["accepted"],
             "accepted mismatch: got #{result.accepted}, expected #{expected["accepted"]}"

      expected_code =
        if expected["rejection_code"] == "NONE", do: 0, else: ErrorCodes.from_string(expected["rejection_code"])

      assert result.rejection_code == expected_code,
             "rejection_code mismatch: got #{result.rejection_code}, expected #{expected_code} (#{expected["rejection_code"]})"

      assert result.attempts == expected["attempts"],
             "attempts mismatch: got #{inspect(result.attempts)}, expected #{inspect(expected["attempts"])}"

      if expected["reason_contains"] do
        assert result.rejection_reason =~ expected["reason_contains"],
               "rejection_reason #{inspect(result.rejection_reason)} does not contain #{inspect(expected["reason_contains"])}"
      end

      if expected["redirect_to_agent_id"] do
        assert result.redirect_to_agent_id == expected["redirect_to_agent_id"],
               "redirect_to_agent_id mismatch: got #{result.redirect_to_agent_id}, expected #{expected["redirect_to_agent_id"]}"
      end
    end
  end
end
