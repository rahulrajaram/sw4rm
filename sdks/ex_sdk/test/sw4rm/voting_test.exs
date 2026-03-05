defmodule Sw4rm.VotingTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Voting.{Vote, MajorityVote, SimpleAverage, BordaCount, ConfidenceWeighted}

  describe "MajorityVote" do
    test "empty votes" do
      assert %{winner: nil, count: 0} = MajorityVote.aggregate([])
    end

    test "single winner" do
      votes = [
        Vote.new(choice: :a, agent_id: "a1"),
        Vote.new(choice: :a, agent_id: "a2"),
        Vote.new(choice: :b, agent_id: "a3")
      ]

      result = MajorityVote.aggregate(votes)
      assert result.winner == :a
      assert result.count == 2
      assert result.total == 3
    end

    test "strategy_name" do
      assert MajorityVote.strategy_name() == "majority-vote"
    end
  end

  describe "SimpleAverage" do
    test "empty votes" do
      assert %{average: nil} = SimpleAverage.aggregate([])
    end

    test "computes average and stats" do
      votes = [
        Vote.new(choice: 10, agent_id: "a1"),
        Vote.new(choice: 20, agent_id: "a2"),
        Vote.new(choice: 30, agent_id: "a3")
      ]

      result = SimpleAverage.aggregate(votes)
      assert result.average == 20.0
      assert result.count == 3
      assert result.min == 10
      assert result.max == 30
      assert is_float(result.stddev)
    end

    test "strategy_name" do
      assert SimpleAverage.strategy_name() == "simple-average"
    end
  end

  describe "BordaCount" do
    test "empty votes" do
      assert %{winner: nil} = BordaCount.aggregate([])
    end

    test "scores ranked preferences" do
      votes = [
        Vote.new(choice: [:a, :b, :c], agent_id: "a1"),
        Vote.new(choice: [:b, :a, :c], agent_id: "a2"),
        Vote.new(choice: [:a, :c, :b], agent_id: "a3")
      ]

      result = BordaCount.aggregate(votes)
      assert result.winner == :a
      assert result.total_votes == 3
      assert result.scores[:a] > result.scores[:c]
    end

    test "strategy_name" do
      assert BordaCount.strategy_name() == "borda-count"
    end
  end

  describe "ConfidenceWeighted" do
    test "empty votes" do
      assert %{winner: nil, total_weight: +0.0} = ConfidenceWeighted.aggregate([])
    end

    test "weights by confidence" do
      votes = [
        Vote.new(choice: :a, confidence: 0.9, agent_id: "a1"),
        Vote.new(choice: :b, confidence: 0.1, agent_id: "a2"),
        Vote.new(choice: :b, confidence: 0.1, agent_id: "a3")
      ]

      result = ConfidenceWeighted.aggregate(votes)
      assert result.winner == :a
      assert_in_delta result.total_weight, 1.1, 0.01
    end

    test "defaults confidence to 1.0" do
      votes = [
        Vote.new(choice: :a, agent_id: "a1"),
        Vote.new(choice: :a, agent_id: "a2")
      ]

      result = ConfidenceWeighted.aggregate(votes)
      assert result.winner == :a
      assert_in_delta result.total_weight, 2.0, 0.01
    end

    test "strategy_name" do
      assert ConfidenceWeighted.strategy_name() == "confidence-weighted"
    end
  end
end
