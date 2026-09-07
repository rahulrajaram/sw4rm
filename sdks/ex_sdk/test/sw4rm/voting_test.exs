defmodule Sw4rm.VotingTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Voting.{Vote, MajorityVote, SimpleAverage, BordaCount, ConfidenceWeighted}
  alias Sw4rm.Voting.ScoreSummary

  describe "aggregate_votes/1" do
    test "matches the shared score aggregation vectors" do
      path =
        Path.expand(
          "../../../../tests/conformance_vectors/score_aggregation_vectors.json",
          __DIR__
        )

      vectors = path |> File.read!() |> Jason.decode!() |> Map.fetch!("vectors")

      Enum.each(vectors, fn vector ->
        case Map.get(vector, "error") do
          "empty-votes" ->
            assert_raise ArgumentError, fn -> Sw4rm.Voting.aggregate_votes([]) end

          nil ->
            votes =
              Enum.map(Map.get(vector, "votes"), fn vote ->
                %{score: vote["score"], confidence: vote["confidence"]}
              end)

            expected = Map.fetch!(vector, "expected")
            result = Sw4rm.Voting.aggregate_votes(votes)
            assert_in_delta result.mean, expected["mean"], 0.000001
            assert result.min_score == expected["min_score"]
            assert result.max_score == expected["max_score"]
            assert_in_delta result.std_dev, expected["std_dev"], 0.000001
            assert_in_delta result.weighted_mean, expected["weighted_mean"], 0.000001
            assert result.vote_count == expected["vote_count"]
        end
      end)
    end

    test "computes arithmetic and confidence-weighted statistics" do
      result =
        Sw4rm.Voting.aggregate_votes([
          %{score: 2.0, confidence: 0.25},
          %{score: 8.0, confidence: 0.75}
        ])

      assert %ScoreSummary{
               mean: 5.0,
               min_score: 2.0,
               max_score: 8.0,
               weighted_mean: 6.5,
               vote_count: 2
             } = result

      assert_in_delta result.std_dev, 3.0, 0.0001
    end

    test "falls back to arithmetic mean when confidence is all zero" do
      result =
        Sw4rm.Voting.aggregate_votes([
          %{score: 2.0, confidence: 0.0},
          %{score: 8.0, confidence: 0.0}
        ])

      assert result.mean == 5.0
      assert result.weighted_mean == 5.0
    end

    test "handles a single vote" do
      result = Sw4rm.Voting.aggregate_votes([%{score: 7, confidence: 1.0}])
      assert result.mean == 7.0
      assert result.min_score == 7
      assert result.max_score == 7
      assert result.std_dev == 0.0
      assert result.weighted_mean == 7.0
    end

    test "rejects empty votes" do
      assert_raise ArgumentError, "Cannot aggregate empty list of votes", fn ->
        Sw4rm.Voting.aggregate_votes([])
      end
    end
  end

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
