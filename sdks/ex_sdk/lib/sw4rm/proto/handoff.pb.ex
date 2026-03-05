defmodule Sw4rm.Proto.Handoff.HandoffStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :HANDOFF_STATUS_UNSPECIFIED, 0
  field :PENDING, 1
  field :ACCEPTED, 2
  field :REJECTED, 3
  field :COMPLETED, 4
  field :EXPIRED, 5
end

defmodule Sw4rm.Proto.Handoff.BudgetEnvelope do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :token_budget_remaining, 1, type: :uint64, json_name: "tokenBudgetRemaining"
  field :wall_time_remaining_ms, 2, type: :uint64, json_name: "wallTimeRemainingMs"
  field :deadline_epoch_ms, 3, type: :uint64, json_name: "deadlineEpochMs"
  field :current_depth, 4, type: :uint32, json_name: "currentDepth"
  field :max_delegation_depth, 5, type: :uint32, json_name: "maxDelegationDepth"
end

defmodule Sw4rm.Proto.Handoff.SwarmDelegationPolicy do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :max_retries_on_overloaded, 1, type: :uint32, json_name: "maxRetriesOnOverloaded"
  field :initial_backoff_ms, 2, type: :uint64, json_name: "initialBackoffMs"
  field :backoff_multiplier, 3, type: :double, json_name: "backoffMultiplier"
  field :max_backoff_ms, 4, type: :uint64, json_name: "maxBackoffMs"
  field :allow_spillover_routing, 5, type: :bool, json_name: "allowSpilloverRouting"
  field :max_redirects, 6, type: :uint32, json_name: "maxRedirects"
end

defmodule Sw4rm.Proto.Handoff.CancelDelegation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :correlation_id, 1, type: :string, json_name: "correlationId"
  field :reason, 2, type: :string
  field :grace_period_ms, 3, type: :uint64, json_name: "gracePeriodMs"
end

defmodule Sw4rm.Proto.Handoff.CancelDelegationResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :acknowledged, 1, type: :bool
  field :message, 2, type: :string
end

defmodule Sw4rm.Proto.Handoff.HandoffRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :request_id, 1, type: :string, json_name: "requestId"
  field :from_agent, 2, type: :string, json_name: "fromAgent"
  field :to_agent, 3, type: :string, json_name: "toAgent"
  field :reason, 4, type: :string
  field :context_snapshot, 5, type: :bytes, json_name: "contextSnapshot"

  field :capabilities_required, 6,
    repeated: true,
    type: :string,
    json_name: "capabilitiesRequired"

  field :priority, 7, type: :int32
  field :timeout, 8, type: Google.Protobuf.Duration
  field :budget, 100, type: Sw4rm.Proto.Handoff.BudgetEnvelope

  field :delegation_policy, 101,
    type: Sw4rm.Proto.Handoff.SwarmDelegationPolicy,
    json_name: "delegationPolicy"
end

defmodule Sw4rm.Proto.Handoff.HandoffResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :request_id, 1, type: :string, json_name: "requestId"
  field :accepted, 2, type: :bool
  field :accepting_agent, 3, type: :string, json_name: "acceptingAgent"
  field :rejection_reason, 4, type: :string, json_name: "rejectionReason"

  field :rejection_code, 100,
    type: Sw4rm.Proto.Common.ErrorCode,
    json_name: "rejectionCode",
    enum: true

  field :retry_after_ms, 101, type: :uint64, json_name: "retryAfterMs"
  field :redirect_to_agent_id, 110, type: :string, json_name: "redirectToAgentId"
end

defmodule Sw4rm.Proto.Handoff.GetPendingHandoffsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
end

defmodule Sw4rm.Proto.Handoff.GetPendingHandoffsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :pending_requests, 1,
    repeated: true,
    type: Sw4rm.Proto.Handoff.HandoffRequest,
    json_name: "pendingRequests"
end

defmodule Sw4rm.Proto.Handoff.CompleteHandoffRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :request_id, 1, type: :string, json_name: "requestId"
  field :status, 2, type: Sw4rm.Proto.Handoff.HandoffStatus, enum: true
end

defmodule Sw4rm.Proto.Handoff.CompleteHandoffResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :success, 1, type: :bool
  field :message, 2, type: :string
end

defmodule Sw4rm.Proto.Handoff.HandoffService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.handoff.HandoffService", protoc_gen_elixir_version: "0.14.0"

  rpc :RequestHandoff, Sw4rm.Proto.Handoff.HandoffRequest, Sw4rm.Proto.Common.Empty
  rpc :AcceptHandoff, Sw4rm.Proto.Handoff.HandoffResponse, Sw4rm.Proto.Common.Empty
  rpc :RejectHandoff, Sw4rm.Proto.Handoff.HandoffResponse, Sw4rm.Proto.Common.Empty

  rpc :GetPendingHandoffs,
      Sw4rm.Proto.Handoff.GetPendingHandoffsRequest,
      Sw4rm.Proto.Handoff.GetPendingHandoffsResponse

  rpc :CompleteHandoff,
      Sw4rm.Proto.Handoff.CompleteHandoffRequest,
      Sw4rm.Proto.Handoff.CompleteHandoffResponse

  rpc :CancelDelegation,
      Sw4rm.Proto.Handoff.CancelDelegation,
      Sw4rm.Proto.Handoff.CancelDelegationResponse
end

defmodule Sw4rm.Proto.Handoff.HandoffService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Handoff.HandoffService.Service
end
