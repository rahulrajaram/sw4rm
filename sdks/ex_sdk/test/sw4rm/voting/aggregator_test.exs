defmodule Sw4rm.Voting.AggregatorTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Voting.{Aggregator, Vote, SimpleAverage}

  setup do
    {:ok, agg} = Aggregator.start_link()
    %{agg: agg}
  end

  describe "run_vote/3" do
    test "aggregates votes with default strategy (MajorityVote)", %{agg: agg} do
      votes = [
        Vote.new(choice: :a, agent_id: "a1"),
        Vote.new(choice: :a, agent_id: "a2"),
        Vote.new(choice: :b, agent_id: "a3")
      ]

      result = Aggregator.run_vote(agg, votes)
      assert result.winner == :a
    end

    test "records round in history", %{agg: agg} do
      votes = [Vote.new(choice: :x, agent_id: "a1")]
      Aggregator.run_vote(agg, votes)

      history = Aggregator.history(agg)
      assert length(history) == 1
      assert hd(history).strategy_name == "majority-vote"
    end
  end

  describe "set_strategy/2" do
    test "changes strategy module", %{agg: agg} do
      Aggregator.set_strategy(agg, SimpleAverage)

      votes = [
        Vote.new(choice: 10, agent_id: "a1"),
        Vote.new(choice: 20, agent_id: "a2")
      ]

      result = Aggregator.run_vote(agg, votes)
      assert result.average == 15.0
    end
  end

  describe "history/2" do
    test "returns all rounds", %{agg: agg} do
      for i <- 1..3 do
        Aggregator.run_vote(agg, [Vote.new(choice: i, agent_id: "a1")], round_id: "r#{i}")
      end

      assert length(Aggregator.history(agg)) == 3
    end

    test "respects limit", %{agg: agg} do
      for i <- 1..5 do
        Aggregator.run_vote(agg, [Vote.new(choice: i, agent_id: "a1")])
      end

      assert length(Aggregator.history(agg, 2)) == 2
    end
  end

  describe "clear_history/1" do
    test "removes all history", %{agg: agg} do
      Aggregator.run_vote(agg, [Vote.new(choice: :a, agent_id: "a1")])
      Aggregator.clear_history(agg)
      assert Aggregator.history(agg) == []
    end
  end
end
