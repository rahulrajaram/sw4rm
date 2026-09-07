defmodule Sw4rm.Voting do
  @moduledoc """
  Voting aggregation strategies for multi-agent decision making.

  Behaviour for pluggable strategies plus four built-in implementations.
  """

  defmodule Vote do
    @moduledoc "A single vote from an agent."
    @type t :: %__MODULE__{}
    defstruct [:agent_id, :choice, :confidence, :timestamp, :metadata]

    @doc "Build a vote from keyword options. Required: `:choice`."
    def new(opts) do
      %__MODULE__{
        agent_id: Keyword.get(opts, :agent_id),
        choice: Keyword.fetch!(opts, :choice),
        confidence: Keyword.get(opts, :confidence),
        timestamp: Keyword.get(opts, :timestamp, System.system_time(:second)),
        metadata: Keyword.get(opts, :metadata, %{})
      }
    end
  end

  @callback aggregate([Vote.t()]) :: map()
  @callback strategy_name() :: String.t()

  defmodule ScoreSummary do
    @moduledoc "Arithmetic and confidence-weighted statistics for scored votes."
    @type t :: %__MODULE__{
            mean: float(),
            min_score: number(),
            max_score: number(),
            std_dev: float(),
            weighted_mean: float(),
            vote_count: non_neg_integer()
          }
    defstruct [:mean, :min_score, :max_score, :std_dev, :weighted_mean, :vote_count]
  end

  @doc "Aggregate scored vote maps using the runtime-neutral score-summary-v1 contract."
  @spec aggregate_votes([map()]) :: ScoreSummary.t()
  def aggregate_votes([]), do: raise(ArgumentError, "Cannot aggregate empty list of votes")

  def aggregate_votes(votes) when is_list(votes) do
    scores = Enum.map(votes, &Map.fetch!(&1, :score))
    confidences = Enum.map(votes, &Map.fetch!(&1, :confidence))
    mean = Enum.sum(scores) / length(scores)
    variance = Enum.sum(Enum.map(scores, &((&1 - mean) * (&1 - mean)))) / length(scores)
    total_confidence = Enum.sum(confidences)

    weighted_mean =
      if total_confidence > 0 do
        Enum.zip(scores, confidences)
        |> Enum.reduce(0, fn {score, confidence}, acc -> acc + score * confidence end)
        |> Kernel./(total_confidence)
      else
        mean
      end

    %ScoreSummary{
      mean: mean,
      min_score: Enum.min(scores),
      max_score: Enum.max(scores),
      std_dev: :math.sqrt(variance),
      weighted_mean: weighted_mean,
      vote_count: length(votes)
    }
  end
end

defmodule Sw4rm.Voting.MajorityVote do
  @moduledoc "Simple majority: most common choice wins."
  @behaviour Sw4rm.Voting

  @impl true
  def strategy_name, do: "majority-vote"

  @impl true
  def aggregate([]), do: %{winner: nil, count: 0, total: 0, distribution: %{}}

  def aggregate(votes) do
    dist =
      Enum.reduce(votes, %{}, fn v, acc ->
        Map.update(acc, v.choice, 1, &(&1 + 1))
      end)

    {winner, count} = Enum.max_by(dist, fn {_k, v} -> v end)
    %{winner: winner, count: count, total: length(votes), distribution: dist}
  end
end

defmodule Sw4rm.Voting.SimpleAverage do
  @moduledoc "Average numeric choices."
  @behaviour Sw4rm.Voting

  @impl true
  def strategy_name, do: "simple-average"

  @impl true
  def aggregate([]), do: %{average: nil, count: 0, min: nil, max: nil, stddev: nil}

  def aggregate(votes) do
    choices = Enum.map(votes, & &1.choice)
    count = length(choices)
    sum = Enum.sum(choices)
    average = sum / count
    min_val = Enum.min(choices)
    max_val = Enum.max(choices)
    variance = Enum.sum(Enum.map(choices, fn x -> (x - average) * (x - average) end)) / count
    stddev = :math.sqrt(variance)

    %{average: average, count: count, min: min_val, max: max_val, stddev: stddev}
  end
end

defmodule Sw4rm.Voting.BordaCount do
  @moduledoc "Borda count: choices are ranked preference lists. Points: (n-1) for 1st, (n-2) for 2nd, etc."
  @behaviour Sw4rm.Voting

  @impl true
  def strategy_name, do: "borda-count"

  @impl true
  def aggregate([]), do: %{winner: nil, scores: %{}, total_votes: 0}

  def aggregate(votes) do
    scores =
      Enum.reduce(votes, %{}, fn v, acc ->
        prefs = v.choice
        n = length(prefs)

        prefs
        |> Enum.with_index()
        |> Enum.reduce(acc, fn {choice, rank}, inner_acc ->
          Map.update(inner_acc, choice, n - rank - 1, &(&1 + n - rank - 1))
        end)
      end)

    {winner, _score} = Enum.max_by(scores, fn {_k, v} -> v end, fn -> {nil, 0} end)
    %{winner: winner, scores: scores, total_votes: length(votes)}
  end
end

defmodule Sw4rm.Voting.ConfidenceWeighted do
  @moduledoc "Weighted voting where each vote is weighted by confidence in [0,1]."
  @behaviour Sw4rm.Voting

  @impl true
  def strategy_name, do: "confidence-weighted"

  @impl true
  def aggregate([]), do: %{winner: nil, weighted_scores: %{}, total_weight: 0.0, total_votes: 0}

  def aggregate(votes) do
    {scores, total_weight} =
      Enum.reduce(votes, {%{}, 0.0}, fn v, {acc, tw} ->
        conf = v.confidence || 1.0
        {Map.update(acc, v.choice, conf, &(&1 + conf)), tw + conf}
      end)

    {winner, _score} = Enum.max_by(scores, fn {_k, v} -> v end, fn -> {nil, 0} end)

    %{
      winner: winner,
      weighted_scores: scores,
      total_weight: total_weight,
      total_votes: length(votes)
    }
  end
end
