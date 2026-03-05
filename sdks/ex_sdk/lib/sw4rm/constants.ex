defmodule Sw4rm.Constants do
  @moduledoc """
  Protocol constants and defaults for SW4RM SDK.

  Proto-defined enums (MessageType, AgentState, etc.) are generated in
  `Sw4rm.Proto.Common.*`. This module defines SDK-level defaults for ports,
  timeouts, buffer limits, and envelope/worktree state atoms that are not
  part of the protobuf definitions.
  """

  # Default service ports (spec S5)
  @router_port 50051
  @registry_port 50052
  @scheduler_port 50053
  @hitl_port 50054
  @worktree_port 50055
  @tool_port 50056
  @connector_port 50057
  @negotiation_port 50058
  @reasoning_port 50059
  @logging_port 50060
  @activity_port 50061
  @scheduler_policy_port 50062
  @handoff_port 50071
  @negotiation_room_port 50072
  @workflow_port 50073

  # Default timeouts and limits
  @default_timeout_ms 30_000
  @default_retry_max_attempts 3
  @default_heartbeat_interval_ms 30_000
  @default_ack_timeout_ms 10_000
  @default_activity_buffer_size 10_000
  @default_activity_buffer_per_agent 100
  @default_deduplication_window_seconds 3600

  @default_host "localhost"

  # Envelope states (spec S11)
  @envelope_states ~w(unspecified sent received read fulfilled rejected failed timed_out)a

  # Worktree states (spec S16)
  @worktree_states ~w(unspecified unbound bound_home switch_pending bound_non_home bind_failed)a

  # -- Accessors --

  def router_port, do: @router_port
  def registry_port, do: @registry_port
  def scheduler_port, do: @scheduler_port
  def hitl_port, do: @hitl_port
  def worktree_port, do: @worktree_port
  def tool_port, do: @tool_port
  def connector_port, do: @connector_port
  def negotiation_port, do: @negotiation_port
  def reasoning_port, do: @reasoning_port
  def logging_port, do: @logging_port
  def activity_port, do: @activity_port
  def scheduler_policy_port, do: @scheduler_policy_port
  def handoff_port, do: @handoff_port
  def negotiation_room_port, do: @negotiation_room_port
  def workflow_port, do: @workflow_port

  def default_timeout_ms, do: @default_timeout_ms
  def default_retry_max_attempts, do: @default_retry_max_attempts
  def default_heartbeat_interval_ms, do: @default_heartbeat_interval_ms
  def default_ack_timeout_ms, do: @default_ack_timeout_ms
  def default_activity_buffer_size, do: @default_activity_buffer_size
  def default_activity_buffer_per_agent, do: @default_activity_buffer_per_agent
  def default_deduplication_window_seconds, do: @default_deduplication_window_seconds
  def default_host, do: @default_host

  def envelope_states, do: @envelope_states
  def worktree_states, do: @worktree_states

  @doc "Build default endpoint address for a given service port."
  @spec default_addr(non_neg_integer()) :: String.t()
  def default_addr(port), do: "http://#{@default_host}:#{port}"
end
