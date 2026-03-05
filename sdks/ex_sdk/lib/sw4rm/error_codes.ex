defmodule Sw4rm.ErrorCodes do
  @moduledoc """
  Centralized proto ErrorCode enum integer values (from common.proto).

  Provides named accessors for use in conformance vectors, gateway redirects,
  cancellation logic, and validation errors.
  """

  @error_code_unspecified 0
  @buffer_full 1
  @no_route 2
  @ack_timeout 3
  @agent_unavailable 4
  @agent_shutdown 5
  @validation_error 6
  @permission_denied 7
  @unsupported_message_type 8
  @oversize_payload 9
  @tool_timeout 10
  @partial_delivery 11
  @forced_preemption 12
  @ttl_expired 13
  @duplicate_detected 14
  @already_in_progress 15
  @overloaded 16
  @redirect 20
  @internal_error 99

  @doc "ERROR_CODE_UNSPECIFIED (0)."
  def error_code_unspecified, do: @error_code_unspecified
  @doc "BUFFER_FULL (1)."
  def buffer_full, do: @buffer_full
  @doc "NO_ROUTE (2)."
  def no_route, do: @no_route
  @doc "ACK_TIMEOUT (3)."
  def ack_timeout, do: @ack_timeout
  @doc "AGENT_UNAVAILABLE (4)."
  def agent_unavailable, do: @agent_unavailable
  @doc "AGENT_SHUTDOWN (5)."
  def agent_shutdown, do: @agent_shutdown
  @doc "VALIDATION_ERROR (6)."
  def validation_error, do: @validation_error
  @doc "PERMISSION_DENIED (7)."
  def permission_denied, do: @permission_denied
  @doc "UNSUPPORTED_MESSAGE_TYPE (8)."
  def unsupported_message_type, do: @unsupported_message_type
  @doc "OVERSIZE_PAYLOAD (9)."
  def oversize_payload, do: @oversize_payload
  @doc "TOOL_TIMEOUT (10)."
  def tool_timeout, do: @tool_timeout
  @doc "PARTIAL_DELIVERY (11)."
  def partial_delivery, do: @partial_delivery
  @doc "FORCED_PREEMPTION (12)."
  def forced_preemption, do: @forced_preemption
  @doc "TTL_EXPIRED (13)."
  def ttl_expired, do: @ttl_expired
  @doc "DUPLICATE_DETECTED (14)."
  def duplicate_detected, do: @duplicate_detected
  @doc "ALREADY_IN_PROGRESS (15)."
  def already_in_progress, do: @already_in_progress
  @doc "OVERLOADED (16)."
  def overloaded, do: @overloaded
  @doc "REDIRECT (20)."
  def redirect, do: @redirect
  @doc "INTERNAL_ERROR (99)."
  def internal_error, do: @internal_error

  @doc "Convert a string error code name to its integer value."
  @spec from_string(String.t()) :: non_neg_integer()
  def from_string("ERROR_CODE_UNSPECIFIED"), do: @error_code_unspecified
  def from_string("BUFFER_FULL"), do: @buffer_full
  def from_string("NO_ROUTE"), do: @no_route
  def from_string("ACK_TIMEOUT"), do: @ack_timeout
  def from_string("AGENT_UNAVAILABLE"), do: @agent_unavailable
  def from_string("AGENT_SHUTDOWN"), do: @agent_shutdown
  def from_string("VALIDATION_ERROR"), do: @validation_error
  def from_string("PERMISSION_DENIED"), do: @permission_denied
  def from_string("UNSUPPORTED_MESSAGE_TYPE"), do: @unsupported_message_type
  def from_string("OVERSIZE_PAYLOAD"), do: @oversize_payload
  def from_string("TOOL_TIMEOUT"), do: @tool_timeout
  def from_string("PARTIAL_DELIVERY"), do: @partial_delivery
  def from_string("FORCED_PREEMPTION"), do: @forced_preemption
  def from_string("TTL_EXPIRED"), do: @ttl_expired
  def from_string("DUPLICATE_DETECTED"), do: @duplicate_detected
  def from_string("ALREADY_IN_PROGRESS"), do: @already_in_progress
  def from_string("OVERLOADED"), do: @overloaded
  def from_string("REDIRECT"), do: @redirect
  def from_string("INTERNAL_ERROR"), do: @internal_error
  def from_string(unknown), do: raise(ArgumentError, "unknown error code: #{inspect(unknown)}")
end
