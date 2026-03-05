defmodule Sw4rm.DelegationTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Delegation

  defp make_redirect_fn(redirect_map) do
    fn request ->
      case Map.get(redirect_map, request.to_agent) do
        nil ->
          %{accepted: true, redirect_to_agent_id: ""}

        target ->
          %{
            accepted: false,
            rejection_code: 20,
            rejection_reason: "redirecting",
            redirect_to_agent_id: target
          }
      end
    end
  end

  describe "delegate_to_swarm/1" do
    test "direct acceptance (no redirect)" do
      send_fn = fn _req -> %{accepted: true, redirect_to_agent_id: ""} end

      result =
        Delegation.delegate_to_swarm(%{
          send_handoff_fn: send_fn,
          to_agent: "gateway-a",
          from_agent: "parent",
          request_id: "req-1"
        })

      assert result.accepted == true
      assert result.attempts == ["gateway-a"]
    end

    test "redirect loop detected" do
      send_fn =
        make_redirect_fn(%{
          "gateway-a" => "gateway-b",
          "gateway-b" => "gateway-a"
        })

      result =
        Delegation.delegate_to_swarm(%{
          send_handoff_fn: send_fn,
          to_agent: "gateway-a",
          from_agent: "parent",
          request_id: "req-loop",
          delegation_policy: %{allow_spillover_routing: true, max_redirects: 4}
        })

      assert result.accepted == false
      assert result.rejection_code == 6
      assert result.rejection_reason =~ "loop"
      assert result.attempts == ["gateway-a", "gateway-b"]
    end

    test "default redirect bound applied (max_redirects=0 -> 2)" do
      send_fn =
        make_redirect_fn(%{
          "gateway-a" => "gateway-b",
          "gateway-b" => "gateway-c",
          "gateway-c" => "gateway-d"
        })

      result =
        Delegation.delegate_to_swarm(%{
          send_handoff_fn: send_fn,
          to_agent: "gateway-a",
          from_agent: "parent",
          request_id: "req-bound",
          delegation_policy: %{allow_spillover_routing: true, max_redirects: 0}
        })

      assert result.accepted == false
      assert result.rejection_code == 20
      assert result.attempts == ["gateway-a", "gateway-b", "gateway-c"]
    end

    test "spillover disabled returns original redirect as-is" do
      send_fn =
        make_redirect_fn(%{
          "gateway-a" => "gateway-b"
        })

      result =
        Delegation.delegate_to_swarm(%{
          send_handoff_fn: send_fn,
          to_agent: "gateway-a",
          from_agent: "parent",
          request_id: "req-no-spillover",
          delegation_policy: %{allow_spillover_routing: false, max_redirects: 5}
        })

      assert result.accepted == false
      assert result.rejection_code == 20
      assert result.redirect_to_agent_id == "gateway-b"
      assert result.attempts == ["gateway-a"]
    end

    test "blank redirect target is validation error" do
      send_fn = fn request ->
        case request.to_agent do
          "gateway-a" ->
            %{
              accepted: false,
              rejection_code: 20,
              rejection_reason: "redirect",
              redirect_to_agent_id: "gateway-b"
            }

          "gateway-b" ->
            %{
              accepted: false,
              rejection_code: 20,
              rejection_reason: "redirect",
              redirect_to_agent_id: "   "
            }
        end
      end

      result =
        Delegation.delegate_to_swarm(%{
          send_handoff_fn: send_fn,
          to_agent: "gateway-a",
          from_agent: "parent",
          request_id: "req-blank",
          delegation_policy: %{allow_spillover_routing: true, max_redirects: 5}
        })

      assert result.accepted == false
      assert result.rejection_code == 6
      assert result.rejection_reason =~ "non-empty"
      assert result.attempts == ["gateway-a", "gateway-b"]
    end

    test "wall-time is deducted per redirect hop" do
      # Track budgets seen by the send function
      budgets = :ets.new(:budgets, [:set, :public])

      send_fn = fn request ->
        :ets.insert(budgets, {request.to_agent, request.budget})

        case request.to_agent do
          "gateway-a" ->
            %{
              accepted: false,
              rejection_code: 20,
              rejection_reason: "redirect",
              redirect_to_agent_id: "gateway-b"
            }

          "gateway-b" ->
            %{accepted: true, redirect_to_agent_id: ""}
        end
      end

      # Use a clock that advances 100ms per call
      clock = :counters.new(1, [])

      now_ms_fn = fn ->
        :counters.add(clock, 1, 100)
        :counters.get(clock, 1)
      end

      result =
        Delegation.delegate_to_swarm(%{
          send_handoff_fn: send_fn,
          to_agent: "gateway-a",
          from_agent: "parent",
          request_id: "req-budget",
          budget: %{wall_time_remaining_ms: 10_000},
          delegation_policy: %{allow_spillover_routing: true, max_redirects: 3},
          now_ms_fn: now_ms_fn
        })

      assert result.accepted == true
      assert result.attempts == ["gateway-a", "gateway-b"]

      # The second hop should see reduced wall_time_remaining_ms
      [{_, budget_b}] = :ets.lookup(budgets, "gateway-b")
      assert budget_b.wall_time_remaining_ms < 10_000
      :ets.delete(budgets)
    end

    test "explicit max_redirects is used when non-zero" do
      send_fn =
        make_redirect_fn(%{
          "a" => "b",
          "b" => "c",
          "c" => "d",
          "d" => "e"
        })

      result =
        Delegation.delegate_to_swarm(%{
          send_handoff_fn: send_fn,
          to_agent: "a",
          from_agent: "parent",
          request_id: "req-explicit",
          delegation_policy: %{allow_spillover_routing: true, max_redirects: 1}
        })

      assert result.accepted == false
      assert result.attempts == ["a", "b"]
    end
  end
end
