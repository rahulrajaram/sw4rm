defmodule Sw4rm.Delegation do
  @moduledoc """
  Standalone delegate_to_swarm function for SW4-005 conformance.

  Handles redirect loop detection, max redirect enforcement, and
  spillover routing policy.
  """

  @default_max_redirects 2

  @type result :: %{
          accepted: boolean(),
          rejection_code: integer(),
          rejection_reason: String.t(),
          redirect_to_agent_id: String.t(),
          attempts: [String.t()]
        }

  @doc """
  Delegate a handoff request to a swarm, following redirects according to policy.

  ## Map keys

    * `:send_handoff_fn` - `fn(request) -> response` (required, injectable)
    * `:from_agent` - originating agent ID
    * `:to_agent` - initial target agent ID
    * `:reason` - delegation reason
    * `:request_id` - unique request identifier
    * `:budget` - `%{deadline_epoch_ms: int, wall_time_remaining_ms: int}`
    * `:delegation_policy` - `%{allow_spillover_routing: bool, max_redirects: int}`
    * `:now_ms_fn` - `fn() -> integer` (optional, injectable for testing)

  """
  @spec delegate_to_swarm(map()) :: result()
  def delegate_to_swarm(opts) do
    send_fn = Map.fetch!(opts, :send_handoff_fn)
    to_agent = Map.fetch!(opts, :to_agent)
    from_agent = Map.get(opts, :from_agent, "")
    reason = Map.get(opts, :reason, "")
    request_id = Map.get(opts, :request_id, "")
    budget = Map.get(opts, :budget, %{})
    policy = Map.get(opts, :delegation_policy, %{})
    now_ms_fn = Map.get(opts, :now_ms_fn, fn -> System.system_time(:millisecond) end)

    allow_spillover = Map.get(policy, :allow_spillover_routing, false)
    max_redirects_raw = Map.get(policy, :max_redirects, 0)

    effective_max_redirects =
      if max_redirects_raw == 0, do: @default_max_redirects, else: max_redirects_raw

    request = %{
      request_id: request_id,
      from_agent: from_agent,
      to_agent: to_agent,
      reason: reason,
      budget: budget
    }

    do_delegate(
      send_fn,
      request,
      to_agent,
      allow_spillover,
      effective_max_redirects,
      MapSet.new(),
      [],
      now_ms_fn
    )
  end

  defp do_delegate(
         send_fn,
         request,
         current_target,
         allow_spillover,
         max_redirects,
         visited,
         attempts,
         now_ms_fn
       ) do
    hop_start = now_ms_fn.()
    attempts = attempts ++ [current_target]
    response = send_fn.(%{request | to_agent: current_target})

    cond do
      response.accepted ->
        %{
          accepted: true,
          rejection_code: 0,
          rejection_reason: "",
          redirect_to_agent_id: "",
          attempts: attempts
        }

      not is_redirect?(response) ->
        %{
          accepted: false,
          rejection_code: Map.get(response, :rejection_code, 0),
          rejection_reason: Map.get(response, :rejection_reason, ""),
          redirect_to_agent_id: "",
          attempts: attempts
        }

      not allow_spillover ->
        %{
          accepted: false,
          rejection_code: Sw4rm.ErrorCodes.redirect(),
          rejection_reason: Map.get(response, :rejection_reason, ""),
          redirect_to_agent_id: Map.get(response, :redirect_to_agent_id, ""),
          attempts: attempts
        }

      true ->
        redirect_target = Map.get(response, :redirect_to_agent_id, "")
        visited = MapSet.put(visited, current_target)

        # Deduct wall-time elapsed during this hop from the budget
        hop_elapsed = now_ms_fn.() - hop_start
        budget = request.budget
        updated_budget = deduct_wall_time(budget, hop_elapsed)
        request = %{request | budget: updated_budget}

        cond do
          String.trim(redirect_target) == "" ->
            %{
              accepted: false,
              rejection_code: Sw4rm.ErrorCodes.validation_error(),
              rejection_reason: "redirect target must be non-empty",
              redirect_to_agent_id: "",
              attempts: attempts
            }

          MapSet.member?(visited, redirect_target) ->
            %{
              accepted: false,
              rejection_code: Sw4rm.ErrorCodes.validation_error(),
              rejection_reason: "redirect loop detected",
              redirect_to_agent_id: "",
              attempts: attempts
            }

          length(attempts) >= max_redirects + 1 ->
            %{
              accepted: false,
              rejection_code: Sw4rm.ErrorCodes.redirect(),
              rejection_reason: Map.get(response, :rejection_reason, ""),
              redirect_to_agent_id: redirect_target,
              attempts: attempts
            }

          true ->
            do_delegate(
              send_fn,
              request,
              redirect_target,
              allow_spillover,
              max_redirects,
              visited,
              attempts,
              now_ms_fn
            )
        end
    end
  end

  defp deduct_wall_time(budget, elapsed_ms) when is_map(budget) do
    case Map.get(budget, :wall_time_remaining_ms) do
      nil -> budget
      remaining -> Map.put(budget, :wall_time_remaining_ms, max(0, remaining - elapsed_ms))
    end
  end

  defp deduct_wall_time(budget, _elapsed_ms), do: budget

  defp is_redirect?(response) do
    redirect_to = Map.get(response, :redirect_to_agent_id, "")
    redirect_to != nil and redirect_to != ""
  end
end
