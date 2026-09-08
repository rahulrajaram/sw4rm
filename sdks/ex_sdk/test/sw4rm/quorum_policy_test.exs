defmodule Sw4rm.QuorumPolicyTest do
  use ExUnit.Case, async: true

  alias Sw4rm.QuorumPolicy

  test "matches shared quorum vectors" do
    path = Path.expand("../../../../tests/conformance_vectors/quorum_vectors.json", __DIR__)
    vectors = path |> File.read!() |> Jason.decode!() |> Map.fetch!("vectors")

    Enum.each(vectors, fn vector ->
      rule = Map.fetch!(vector, "rule")
      rule_value = Map.fetch!(rule, "value")

      rule_tuple =
        case Map.fetch!(rule, "kind") do
          "minimum_votes" -> {:minimum_votes, rule_value}
          "minimum_fraction" -> {:minimum_fraction, rule_value}
          "require_all" -> {:require_all, rule_value}
        end

      policy = %{rule: rule_tuple, on_failure: String.to_atom(Map.fetch!(vector, "on_failure"))}
      votes = Enum.map(Map.fetch!(vector, "votes"), &%{critic_id: Map.fetch!(&1, "critic_id")})
      result = QuorumPolicy.evaluate(votes, Map.fetch!(vector, "requested"), policy)
      expected = Map.fetch!(vector, "expected")
      met = Map.fetch!(expected, "met")
      expected_status = if met, do: :quorum_met, else: :quorum_not_met
      assert {^expected_status, _} = result
      {_status, details} = result
      assert details.votes_received == expected["received"]
      assert details.votes_expected == expected["expected"]
      assert details.threshold == expected["threshold"]
      assert length(details.all_votes) == expected["all_vote_count"]

      action =
        cond do
          met -> "none"
          policy.on_failure == :fail_closed -> "escalate_hitl"
          policy.on_failure == :fail_with_available -> "decided_with_available"
          true -> "decided_with_abstains"
        end

      assert action == expected["action"]
    end)
  end

  defp vote(critic_id), do: %{critic_id: critic_id, score: 8.0, confidence: 0.9, passed: true}

  describe "default_policy/0" do
    test "returns majority fraction with fail-closed" do
      policy = QuorumPolicy.default_policy()
      assert policy.rule == {:minimum_fraction, 0.5}
      assert policy.on_failure == :fail_closed
    end
  end

  describe "evaluate/3 with minimum_votes" do
    test "quorum met when enough votes" do
      votes = [vote("c1"), vote("c2")]
      requested = ["c1", "c2", "c3"]
      policy = %{rule: {:minimum_votes, 2}, on_failure: :fail_closed}

      assert {:quorum_met, details} = QuorumPolicy.evaluate(votes, requested, policy)
      assert details.votes_received == 2
      assert details.votes_expected == 3
    end

    test "quorum not met when insufficient votes" do
      votes = [vote("c1")]
      requested = ["c1", "c2", "c3"]
      policy = %{rule: {:minimum_votes, 2}, on_failure: :fail_closed}

      assert {:quorum_not_met, details} = QuorumPolicy.evaluate(votes, requested, policy)
      assert details.votes_received == 1
    end
  end

  describe "evaluate/3 with minimum_fraction" do
    test "quorum met with majority" do
      votes = [vote("c1"), vote("c2")]
      requested = ["c1", "c2", "c3"]
      policy = %{rule: {:minimum_fraction, 0.5}, on_failure: :fail_closed}

      assert {:quorum_met, _} = QuorumPolicy.evaluate(votes, requested, policy)
    end

    test "quorum not met below fraction" do
      votes = [vote("c1")]
      requested = ["c1", "c2", "c3", "c4"]
      policy = %{rule: {:minimum_fraction, 0.5}, on_failure: :fail_closed}

      assert {:quorum_not_met, _} = QuorumPolicy.evaluate(votes, requested, policy)
    end
  end

  describe "evaluate/3 with require_all" do
    test "quorum met when all voted" do
      votes = [vote("c1"), vote("c2")]
      requested = ["c1", "c2"]
      policy = %{rule: {:require_all, true}, on_failure: :fail_closed}

      assert {:quorum_met, _} = QuorumPolicy.evaluate(votes, requested, policy)
    end

    test "quorum not met when missing one" do
      votes = [vote("c1")]
      requested = ["c1", "c2"]
      policy = %{rule: {:require_all, true}, on_failure: :fail_closed}

      assert {:quorum_not_met, _} = QuorumPolicy.evaluate(votes, requested, policy)
    end
  end

  describe "fail-closed action" do
    test "returns escalate_hitl" do
      votes = [vote("c1")]
      requested = ["c1", "c2", "c3"]
      policy = %{rule: {:minimum_votes, 3}, on_failure: :fail_closed}

      assert {:quorum_not_met, details} = QuorumPolicy.evaluate(votes, requested, policy)
      assert {:escalate_hitl, _reason} = details.action
    end
  end

  describe "fail-with-abstain action" do
    test "injects zero-score abstain votes for missing critics" do
      votes = [vote("c1")]
      requested = ["c1", "c2", "c3"]
      policy = %{rule: {:minimum_votes, 3}, on_failure: :fail_with_abstain}

      assert {:quorum_not_met, details} = QuorumPolicy.evaluate(votes, requested, policy)
      assert details.action == :decided_with_abstains
      assert length(details.injected_votes) == 2

      for v <- details.injected_votes do
        assert v.score == 0.0
        assert v.confidence == 0.0
        assert v.abstain == true
      end

      assert length(details.all_votes) == 3
    end
  end

  describe "fail-with-available action" do
    test "decides with available votes only" do
      votes = [vote("c1")]
      requested = ["c1", "c2", "c3"]
      policy = %{rule: {:minimum_votes, 3}, on_failure: :fail_with_available}

      assert {:quorum_not_met, details} = QuorumPolicy.evaluate(votes, requested, policy)
      assert details.action == :decided_with_available
      assert length(details.all_votes) == 1
    end
  end
end
