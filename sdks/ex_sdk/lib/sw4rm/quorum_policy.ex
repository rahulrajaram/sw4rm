defmodule Sw4rm.QuorumPolicy do
  @moduledoc """
  Quorum evaluation for negotiation rooms (SW4-001).

  Evaluates whether enough votes have been collected to render a valid decision,
  and applies the configured failure action when quorum is not met.
  """

  @doc "Return the default quorum policy (majority, fail-closed)."
  @spec default_policy() :: map()
  def default_policy do
    %{rule: {:minimum_fraction, 0.5}, on_failure: :fail_closed}
  end

  @doc """
  Evaluate quorum given collected votes, requested critics, and a policy.

  Returns `{:quorum_met, details}` or `{:quorum_not_met, details}`.
  When quorum is not met, the failure action is applied and returned in details.
  """
  @spec evaluate(list(), list(), map()) ::
          {:quorum_met, map()} | {:quorum_not_met, map()}
  def evaluate(votes, requested_critics, policy) do
    voted_ids = MapSet.new(Enum.map(votes, & &1.critic_id))
    expected = length(requested_critics)
    received = MapSet.size(MapSet.intersection(voted_ids, MapSet.new(requested_critics)))
    threshold = compute_threshold(policy.rule, expected)

    details = %{
      votes_received: received,
      votes_expected: expected,
      threshold: threshold
    }

    if received >= threshold do
      {:quorum_met, details}
    else
      failure_result =
        apply_failure_action(policy.on_failure, votes, requested_critics, voted_ids)

      {:quorum_not_met, Map.merge(details, failure_result)}
    end
  end

  defp compute_threshold({:minimum_votes, n}, _expected), do: n

  defp compute_threshold({:minimum_fraction, f}, expected),
    do: ceil(expected * f)

  defp compute_threshold({:require_all, true}, expected), do: expected
  defp compute_threshold({:require_all, false}, _expected), do: 0

  defp apply_failure_action(:fail_closed, _votes, _requested, _voted_ids) do
    %{action: {:escalate_hitl, "Quorum not met — escalating to HITL"}}
  end

  defp apply_failure_action(:fail_with_abstain, votes, requested_critics, voted_ids) do
    missing = Enum.reject(requested_critics, &MapSet.member?(voted_ids, &1))

    abstain_votes =
      Enum.map(missing, fn critic_id ->
        %{critic_id: critic_id, score: 0.0, confidence: 0.0, passed: false, abstain: true}
      end)

    %{
      action: :decided_with_abstains,
      injected_votes: abstain_votes,
      all_votes: votes ++ abstain_votes
    }
  end

  defp apply_failure_action(:fail_with_available, votes, _requested, _voted_ids) do
    %{action: :decided_with_available, all_votes: votes}
  end
end
