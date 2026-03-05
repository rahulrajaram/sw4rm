defmodule Sw4rm.QuorumPolicyTest do
  use ExUnit.Case, async: true

  alias Sw4rm.QuorumPolicy

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
