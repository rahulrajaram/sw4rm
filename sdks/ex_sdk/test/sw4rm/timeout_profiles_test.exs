defmodule Sw4rm.TimeoutProfilesTest do
  use ExUnit.Case, async: true

  alias Sw4rm.TimeoutProfiles

  @all_profiles [
    :heartbeat,
    :registration,
    :task_submit,
    :message_route,
    :negotiation_open,
    :negotiation_vote,
    :negotiation_decision,
    :handoff,
    :workflow_submit,
    :workflow_status,
    :tool_call,
    :hitl_escalate
  ]

  describe "get_profile/1" do
    test "all 12 standard profiles exist" do
      for name <- @all_profiles do
        profile = TimeoutProfiles.get_profile(name)
        assert profile != nil, "Profile #{name} should exist"
        assert is_integer(profile.default_timeout_ms)
        assert is_integer(profile.min_timeout_ms)
        assert is_integer(profile.max_timeout_ms)
        assert is_boolean(profile.allow_infinite)
      end
    end

    test "heartbeat profile has correct values" do
      p = TimeoutProfiles.get_profile(:heartbeat)
      assert p.default_timeout_ms == 5_000
      assert p.min_timeout_ms == 1_000
      assert p.max_timeout_ms == 30_000
      assert p.allow_infinite == false
    end

    test "tool_call profile allows infinite" do
      p = TimeoutProfiles.get_profile(:tool_call)
      assert p.allow_infinite == true
    end

    test "returns nil for unknown profile" do
      assert TimeoutProfiles.get_profile(:nonexistent) == nil
    end
  end

  describe "effective_timeout/2" do
    test "returns default when no override" do
      assert TimeoutProfiles.effective_timeout(:heartbeat) == 5_000
      assert TimeoutProfiles.effective_timeout(:registration) == 30_000
    end

    test "returns override when within bounds" do
      assert TimeoutProfiles.effective_timeout(:heartbeat, 10_000) == 10_000
    end

    test "clamps below min" do
      # heartbeat min is 1_000
      assert TimeoutProfiles.effective_timeout(:heartbeat, 500) == 1_000
    end

    test "clamps above max" do
      # heartbeat max is 30_000
      assert TimeoutProfiles.effective_timeout(:heartbeat, 50_000) == 30_000
    end

    test "allows infinite (timeout=0) for infinite-capable profiles" do
      assert TimeoutProfiles.effective_timeout(:tool_call, 0) == 0
      assert TimeoutProfiles.effective_timeout(:hitl_escalate, 0) == 0
      assert TimeoutProfiles.effective_timeout(:negotiation_vote, 0) == 0
    end

    test "rejects infinite (timeout=0) for non-infinite profiles" do
      assert TimeoutProfiles.effective_timeout(:heartbeat, 0) == 5_000
      assert TimeoutProfiles.effective_timeout(:registration, 0) == 30_000
    end

    test "falls back to Constants.default_timeout_ms for unknown profile" do
      assert TimeoutProfiles.effective_timeout(:nonexistent) ==
               Sw4rm.Constants.default_timeout_ms()
    end
  end

  describe "profile_for_rpc/2" do
    test "registry service mappings" do
      assert TimeoutProfiles.profile_for_rpc(:registry, :heartbeat) == :heartbeat
      assert TimeoutProfiles.profile_for_rpc(:registry, :register_agent) == :registration
      assert TimeoutProfiles.profile_for_rpc(:registry, :deregister_agent) == :registration
    end

    test "router service mappings" do
      assert TimeoutProfiles.profile_for_rpc(:router, :send_message) == :message_route
    end

    test "scheduler service mappings" do
      assert TimeoutProfiles.profile_for_rpc(:scheduler, :submit_task) == :task_submit

      assert TimeoutProfiles.profile_for_rpc(:scheduler, :poll_activity_buffer) ==
               :workflow_status
    end

    test "negotiation_room service mappings" do
      assert TimeoutProfiles.profile_for_rpc(:negotiation_room, :submit_proposal) ==
               :negotiation_open

      assert TimeoutProfiles.profile_for_rpc(:negotiation_room, :submit_vote) == :negotiation_vote

      assert TimeoutProfiles.profile_for_rpc(:negotiation_room, :get_decision) ==
               :negotiation_decision
    end

    test "handoff service mappings" do
      assert TimeoutProfiles.profile_for_rpc(:handoff, :request_handoff) == :handoff
      assert TimeoutProfiles.profile_for_rpc(:handoff, :reject_handoff) == :message_route
    end

    test "tool service mappings" do
      assert TimeoutProfiles.profile_for_rpc(:tool, :call) == :tool_call
      assert TimeoutProfiles.profile_for_rpc(:tool, :cancel) == :message_route
    end

    test "hitl service mapping" do
      assert TimeoutProfiles.profile_for_rpc(:hitl, :decide) == :hitl_escalate
    end

    test "workflow service mappings" do
      assert TimeoutProfiles.profile_for_rpc(:workflow, :create_workflow) == :workflow_submit
      assert TimeoutProfiles.profile_for_rpc(:workflow, :get_workflow_state) == :workflow_status
    end

    test "returns nil for unknown RPC" do
      assert TimeoutProfiles.profile_for_rpc(:unknown, :unknown) == nil
    end
  end
end
