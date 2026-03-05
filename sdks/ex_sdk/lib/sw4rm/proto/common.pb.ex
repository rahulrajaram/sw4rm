defmodule Sw4rm.Proto.Common.MessageType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :MESSAGE_TYPE_UNSPECIFIED, 0
  field :CONTROL, 1
  field :DATA, 2
  field :HEARTBEAT, 3
  field :NOTIFICATION, 4
  field :ACKNOWLEDGEMENT, 5
  field :HITL_INVOCATION, 6
  field :WORKTREE_CONTROL, 7
  field :NEGOTIATION, 8
  field :TOOL_CALL, 9
  field :TOOL_RESULT, 10
  field :TOOL_ERROR, 11
end

defmodule Sw4rm.Proto.Common.AckStage do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ACK_STAGE_UNSPECIFIED, 0
  field :RECEIVED, 1
  field :READ, 2
  field :FULFILLED, 3
  field :REJECTED, 4
  field :FAILED, 5
  field :TIMED_OUT, 6
end

defmodule Sw4rm.Proto.Common.ErrorCode do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ERROR_CODE_UNSPECIFIED, 0
  field :BUFFER_FULL, 1
  field :NO_ROUTE, 2
  field :ACK_TIMEOUT, 3
  field :AGENT_UNAVAILABLE, 4
  field :AGENT_SHUTDOWN, 5
  field :VALIDATION_ERROR, 6
  field :PERMISSION_DENIED, 7
  field :UNSUPPORTED_MESSAGE_TYPE, 8
  field :OVERSIZE_PAYLOAD, 9
  field :TOOL_TIMEOUT, 10
  field :PARTIAL_DELIVERY, 11
  field :FORCED_PREEMPTION, 12
  field :TTL_EXPIRED, 13
  field :DUPLICATE_DETECTED, 14
  field :ALREADY_IN_PROGRESS, 15
  field :OVERLOADED, 16
  field :REDIRECT, 20
  field :INTERNAL_ERROR, 99
end

defmodule Sw4rm.Proto.Common.AgentState do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :AGENT_STATE_UNSPECIFIED, 0
  field :INITIALIZING, 1
  field :RUNNABLE, 2
  field :SCHEDULED, 3
  field :RUNNING, 4
  field :WAITING, 5
  field :WAITING_RESOURCES, 6
  field :SUSPENDED, 7
  field :RESUMED, 8
  field :COMPLETED, 9
  field :FAILED_STATE, 10
  field :SHUTTING_DOWN, 11
  field :RECOVERING, 12
end

defmodule Sw4rm.Proto.Common.CommunicationClass do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :COMM_CLASS_UNSPECIFIED, 0
  field :PRIVILEGED, 1
  field :STANDARD, 2
  field :BULK, 3
end

defmodule Sw4rm.Proto.Common.DebateIntensity do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :DEBATE_INTENSITY_UNSPECIFIED, 0
  field :LOWEST, 1
  field :LOW, 2
  field :MEDIUM, 3
  field :HIGH, 4
  field :HIGHEST, 5
end

defmodule Sw4rm.Proto.Common.HitlReasonType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :HITL_REASON_UNSPECIFIED, 0
  field :CONFLICT, 1
  field :SECURITY_APPROVAL, 2
  field :TASK_ESCALATION, 3
  field :MANUAL_OVERRIDE, 4
  field :WORKTREE_OVERRIDE, 5
  field :DEBATE_DEADLOCK, 6
  field :TOOL_PRIVILEGE_ESCALATION, 7
  field :CONNECTOR_APPROVAL, 8
end

defmodule Sw4rm.Proto.Common.EnvelopeState do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ENVELOPE_STATE_UNSPECIFIED, 0
  field :SENT, 1
  field :RECEIVED, 2
  field :READ, 3
  field :FULFILLED, 4
  field :REJECTED, 5
  field :FAILED, 6
  field :TIMED_OUT, 7
end

defmodule Sw4rm.Proto.Common.Envelope do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :message_id, 1, type: :string, json_name: "messageId"
  field :idempotency_token, 2, type: :string, json_name: "idempotencyToken"
  field :producer_id, 3, type: :string, json_name: "producerId"
  field :correlation_id, 4, type: :string, json_name: "correlationId"
  field :sequence_number, 5, type: :uint64, json_name: "sequenceNumber"
  field :retry_count, 6, type: :uint32, json_name: "retryCount"

  field :message_type, 7,
    type: Sw4rm.Proto.Common.MessageType,
    json_name: "messageType",
    enum: true

  field :content_type, 8, type: :string, json_name: "contentType"
  field :content_length, 9, type: :uint64, json_name: "contentLength"
  field :repo_id, 10, type: :string, json_name: "repoId"
  field :worktree_id, 11, type: :string, json_name: "worktreeId"
  field :hlc_timestamp, 12, type: :string, json_name: "hlcTimestamp"
  field :ttl_ms, 13, type: :uint64, json_name: "ttlMs"
  field :timestamp, 14, type: Google.Protobuf.Timestamp
  field :payload, 15, type: :bytes

  field :state, 16,
    type: Sw4rm.Proto.Common.EnvelopeState,
    enum: true

  field :parent_correlation_id, 100, type: :string, json_name: "parentCorrelationId"
end

defmodule Sw4rm.Proto.Common.Ack do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ack_for_message_id, 1, type: :string, json_name: "ackForMessageId"
  field :ack_stage, 2, type: Sw4rm.Proto.Common.AckStage, json_name: "ackStage", enum: true
  field :error_code, 3, type: Sw4rm.Proto.Common.ErrorCode, json_name: "errorCode", enum: true
  field :note, 4, type: :string
end

defmodule Sw4rm.Proto.Common.Empty do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3
end

# SW4-002 extension: Timeout Profiles

defmodule Sw4rm.Proto.Common.TimeoutProfile do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :profile_name, 1, type: :string, json_name: "profileName"
  field :default_timeout_ms, 2, type: :uint32, json_name: "defaultTimeoutMs"
  field :min_timeout_ms, 3, type: :uint32, json_name: "minTimeoutMs"
  field :max_timeout_ms, 4, type: :uint32, json_name: "maxTimeoutMs"
  field :allow_infinite, 5, type: :bool, json_name: "allowInfinite"
end

defmodule Sw4rm.Proto.Common.StreamingTimeoutPolicy do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :initial_timeout_ms, 1, type: :uint32, json_name: "initialTimeoutMs"
  field :message_gap_timeout_ms, 2, type: :uint32, json_name: "messageGapTimeoutMs"
  field :total_timeout_ms, 3, type: :uint32, json_name: "totalTimeoutMs"
end
