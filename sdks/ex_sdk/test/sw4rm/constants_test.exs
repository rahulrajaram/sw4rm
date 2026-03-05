defmodule Sw4rm.ConstantsTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Constants

  test "port constants are positive integers" do
    assert Constants.router_port() > 0
    assert Constants.registry_port() > 0
    assert Constants.scheduler_port() > 0
    assert Constants.hitl_port() > 0
    assert Constants.worktree_port() > 0
    assert Constants.tool_port() > 0
    assert Constants.connector_port() > 0
    assert Constants.negotiation_port() > 0
    assert Constants.reasoning_port() > 0
    assert Constants.logging_port() > 0
    assert Constants.activity_port() > 0
    assert Constants.scheduler_policy_port() > 0
    assert Constants.handoff_port() > 0
  end

  test "default_addr formats correctly" do
    addr = Constants.default_addr(50051)
    assert addr == "http://localhost:50051"
  end

  test "default_max_activity_buffer_size is accessible" do
    assert Constants.default_activity_buffer_size() > 0
  end

  test "timeout defaults are positive" do
    assert Constants.default_timeout_ms() > 0
    assert Constants.default_heartbeat_interval_ms() > 0
    assert Constants.default_retry_max_attempts() > 0
  end

  test "envelope_states list" do
    states = Constants.envelope_states()
    assert :sent in states
    assert :fulfilled in states
  end

  test "worktree_states list" do
    states = Constants.worktree_states()
    assert :unbound in states
    assert :bound_home in states
  end
end
