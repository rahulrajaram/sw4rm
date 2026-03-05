defmodule Sw4rm.Clients.SchedulerPolicy do
  @moduledoc "Client for SchedulerPolicyService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Scheduler.SchedulerPolicyService,
    timeout_service: :scheduler_policy

  @doc "Set the negotiation policy for a scheduler."
  def set_negotiation_policy(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler_policy)
    unary_call(endpoint, :set_negotiation_policy, request, opts)
  end

  @doc "Get the current negotiation policy."
  def get_negotiation_policy(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler_policy)
    unary_call(endpoint, :get_negotiation_policy, request, opts)
  end

  @doc "Set policy profiles for the scheduler."
  def set_policy_profiles(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler_policy)
    unary_call(endpoint, :set_policy_profiles, request, opts)
  end

  @doc "List all configured policy profiles."
  def list_policy_profiles(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler_policy)
    unary_call(endpoint, :list_policy_profiles, request, opts)
  end

  @doc "Get the effective (merged) policy for a given context."
  def get_effective_policy(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler_policy)
    unary_call(endpoint, :get_effective_policy, request, opts)
  end

  @doc "Submit an evaluation result to the policy service."
  def submit_evaluation(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler_policy)
    unary_call(endpoint, :submit_evaluation, request, opts)
  end

  @doc "Trigger a human-in-the-loop action via the policy service."
  def hitl_action(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler_policy)
    unary_call(endpoint, :hitl_action, request, opts)
  end
end
