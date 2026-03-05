defmodule Sw4rm.Proto.Hitl.HitlInvocation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :reason_type, 1,
    type: Sw4rm.Proto.Common.HitlReasonType,
    json_name: "reasonType",
    enum: true

  field :context, 2, type: :bytes
  field :proposed_actions, 3, repeated: true, type: :string, json_name: "proposedActions"
  field :priority, 4, type: :int32
end

defmodule Sw4rm.Proto.Hitl.HitlDecision do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :action, 1, type: :string
  field :decision_payload, 2, type: :bytes, json_name: "decisionPayload"
  field :rationale, 3, type: :string
end

defmodule Sw4rm.Proto.Hitl.HitlService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.hitl.HitlService", protoc_gen_elixir_version: "0.14.0"

  rpc :Decide, Sw4rm.Proto.Hitl.HitlInvocation, Sw4rm.Proto.Hitl.HitlDecision
end

defmodule Sw4rm.Proto.Hitl.HitlService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Hitl.HitlService.Service
end
