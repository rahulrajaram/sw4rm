defmodule Sw4rm.TimeoutProfiles do
  @moduledoc """
  Per-service timeout profiles (SW4-002).

  Replaces the universal 30s default with operation-appropriate timeouts.
  Provides automatic profile selection, clamping, and override support.
  """

  require Logger

  @standard_profiles %{
    heartbeat: %{
      default_timeout_ms: 5_000,
      min_timeout_ms: 1_000,
      max_timeout_ms: 30_000,
      allow_infinite: false
    },
    registration: %{
      default_timeout_ms: 30_000,
      min_timeout_ms: 5_000,
      max_timeout_ms: 120_000,
      allow_infinite: false
    },
    task_submit: %{
      default_timeout_ms: 30_000,
      min_timeout_ms: 5_000,
      max_timeout_ms: 300_000,
      allow_infinite: false
    },
    message_route: %{
      default_timeout_ms: 10_000,
      min_timeout_ms: 1_000,
      max_timeout_ms: 60_000,
      allow_infinite: false
    },
    negotiation_open: %{
      default_timeout_ms: 60_000,
      min_timeout_ms: 10_000,
      max_timeout_ms: 600_000,
      allow_infinite: false
    },
    negotiation_vote: %{
      default_timeout_ms: 300_000,
      min_timeout_ms: 30_000,
      max_timeout_ms: 1_800_000,
      allow_infinite: true
    },
    negotiation_decision: %{
      default_timeout_ms: 60_000,
      min_timeout_ms: 5_000,
      max_timeout_ms: 300_000,
      allow_infinite: false
    },
    handoff: %{
      default_timeout_ms: 60_000,
      min_timeout_ms: 10_000,
      max_timeout_ms: 300_000,
      allow_infinite: false
    },
    workflow_submit: %{
      default_timeout_ms: 30_000,
      min_timeout_ms: 5_000,
      max_timeout_ms: 120_000,
      allow_infinite: false
    },
    workflow_status: %{
      default_timeout_ms: 10_000,
      min_timeout_ms: 1_000,
      max_timeout_ms: 60_000,
      allow_infinite: false
    },
    tool_call: %{
      default_timeout_ms: 30_000,
      min_timeout_ms: 1_000,
      max_timeout_ms: 3_600_000,
      allow_infinite: true
    },
    hitl_escalate: %{
      default_timeout_ms: 300_000,
      min_timeout_ms: 60_000,
      max_timeout_ms: 3_600_000,
      allow_infinite: true
    }
  }

  @doc "Return the profile struct for the given profile name, or nil."
  @spec get_profile(atom()) :: map() | nil
  def get_profile(name), do: Map.get(@standard_profiles, name)

  @doc """
  Compute the effective timeout for a profile, applying clamping.

  If `override_ms` is nil, returns the profile default.
  If `override_ms` is 0 and profile allows infinite, returns 0.
  If `override_ms` is 0 and profile does not allow infinite, returns default and logs warning.
  Otherwise clamps to [min, max] and logs warning if clamped.
  """
  @spec effective_timeout(atom(), non_neg_integer() | nil) :: non_neg_integer()
  def effective_timeout(profile_name, override_ms \\ nil) do
    case get_profile(profile_name) do
      nil ->
        override_ms || Sw4rm.Constants.default_timeout_ms()

      profile ->
        compute_effective(profile_name, profile, override_ms)
    end
  end

  defp compute_effective(_name, profile, nil), do: profile.default_timeout_ms

  defp compute_effective(name, profile, 0) do
    if profile.allow_infinite do
      0
    else
      Logger.warning(
        "SW4-002: timeout=0 (infinite) not allowed for profile #{name}, using default #{profile.default_timeout_ms}ms"
      )

      profile.default_timeout_ms
    end
  end

  defp compute_effective(name, profile, override) do
    cond do
      override < profile.min_timeout_ms ->
        Logger.warning(
          "SW4-002: timeout #{override}ms below min for profile #{name}, clamping to #{profile.min_timeout_ms}ms"
        )

        profile.min_timeout_ms

      override > profile.max_timeout_ms ->
        Logger.warning(
          "SW4-002: timeout #{override}ms above max for profile #{name}, clamping to #{profile.max_timeout_ms}ms"
        )

        profile.max_timeout_ms

      true ->
        override
    end
  end

  # Service/method → profile mappings (spec §3)

  @rpc_profiles %{
    # Registry
    {:registry, :register_agent} => :registration,
    {:registry, :heartbeat} => :heartbeat,
    {:registry, :deregister_agent} => :registration,
    # Router
    {:router, :send_message} => :message_route,
    {:router, :stream_incoming} => :message_route,
    # Scheduler
    {:scheduler, :submit_task} => :task_submit,
    {:scheduler, :request_preemption} => :task_submit,
    {:scheduler, :shutdown_agent} => :task_submit,
    {:scheduler, :poll_activity_buffer} => :workflow_status,
    {:scheduler, :purge_activity} => :task_submit,
    # Negotiation
    {:negotiation, :open} => :negotiation_open,
    {:negotiation, :propose} => :negotiation_open,
    {:negotiation, :counter} => :negotiation_open,
    {:negotiation, :evaluate} => :negotiation_vote,
    {:negotiation, :decide} => :negotiation_decision,
    {:negotiation, :abort} => :negotiation_decision,
    # NegotiationRoom
    {:negotiation_room, :submit_proposal} => :negotiation_open,
    {:negotiation_room, :submit_vote} => :negotiation_vote,
    {:negotiation_room, :get_votes} => :negotiation_decision,
    {:negotiation_room, :get_decision} => :negotiation_decision,
    {:negotiation_room, :wait_for_decision} => :negotiation_vote,
    # Handoff
    {:handoff, :request_handoff} => :handoff,
    {:handoff, :accept_handoff} => :handoff,
    {:handoff, :reject_handoff} => :message_route,
    {:handoff, :get_pending_handoffs} => :workflow_status,
    {:handoff, :complete_handoff} => :handoff,
    {:handoff, :cancel_delegation} => :handoff,
    # Tool
    {:tool, :call} => :tool_call,
    {:tool, :call_stream} => :tool_call,
    {:tool, :cancel} => :message_route,
    # HITL
    {:hitl, :decide} => :hitl_escalate,
    # Workflow
    {:workflow, :create_workflow} => :workflow_submit,
    {:workflow, :start_workflow} => :workflow_submit,
    {:workflow, :get_workflow_state} => :workflow_status,
    {:workflow, :resume_workflow} => :workflow_submit,
    # Worktree
    {:worktree, :bind} => :registration,
    {:worktree, :unbind} => :registration,
    {:worktree, :request_switch} => :handoff,
    {:worktree, :approve_switch} => :handoff,
    {:worktree, :reject_switch} => :message_route,
    {:worktree, :status} => :workflow_status,
    # Connector
    {:connector, :register_provider} => :registration,
    {:connector, :describe_tools} => :message_route,
    # Reasoning
    {:reasoning, :check_parallelism} => :message_route,
    {:reasoning, :evaluate_debate} => :negotiation_vote,
    {:reasoning, :summarize} => :tool_call,
    # Activity
    {:activity, :append_artifact} => :task_submit,
    {:activity, :list_artifacts} => :workflow_status,
    # Logging
    {:logging, :ingest} => :message_route,
    # SchedulerPolicy
    {:scheduler_policy, :set_negotiation_policy} => :task_submit,
    {:scheduler_policy, :get_negotiation_policy} => :workflow_status,
    {:scheduler_policy, :set_policy_profiles} => :task_submit,
    {:scheduler_policy, :list_policy_profiles} => :workflow_status,
    {:scheduler_policy, :get_effective_policy} => :workflow_status,
    {:scheduler_policy, :submit_evaluation} => :task_submit,
    {:scheduler_policy, :hitl_action} => :hitl_escalate
  }

  @doc "Return the timeout profile name for a given service/method pair."
  @spec profile_for_rpc(atom(), atom()) :: atom() | nil
  def profile_for_rpc(service, method) do
    Map.get(@rpc_profiles, {service, method})
  end
end
