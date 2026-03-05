defmodule Sw4rm.Proto.Scheduler.SetNegotiationPolicyRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :policy, 1, type: Sw4rm.Proto.Policy.NegotiationPolicy
end

defmodule Sw4rm.Proto.Scheduler.SetNegotiationPolicyResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Scheduler.GetNegotiationPolicyRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3
end

defmodule Sw4rm.Proto.Scheduler.GetNegotiationPolicyResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :policy, 1, type: Sw4rm.Proto.Policy.NegotiationPolicy
end

defmodule Sw4rm.Proto.Scheduler.SetPolicyProfilesRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :profiles, 1, repeated: true, type: Sw4rm.Proto.Policy.PolicyProfile
end

defmodule Sw4rm.Proto.Scheduler.SetPolicyProfilesResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Scheduler.ListPolicyProfilesRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3
end

defmodule Sw4rm.Proto.Scheduler.ListPolicyProfilesResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :profiles, 1, repeated: true, type: Sw4rm.Proto.Policy.PolicyProfile
end

defmodule Sw4rm.Proto.Scheduler.GetEffectivePolicyRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
end

defmodule Sw4rm.Proto.Scheduler.GetEffectivePolicyResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :effective, 1, type: Sw4rm.Proto.Policy.EffectivePolicy
end

defmodule Sw4rm.Proto.Scheduler.SubmitEvaluationRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :report, 2, type: Sw4rm.Proto.Policy.EvaluationReport
end

defmodule Sw4rm.Proto.Scheduler.SubmitEvaluationResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :accepted, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Scheduler.HitlActionRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :action, 2, type: :string
  field :rationale, 3, type: :string
end

defmodule Sw4rm.Proto.Scheduler.HitlActionResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Scheduler.SchedulerPolicyService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "sw4rm.scheduler.SchedulerPolicyService",
    protoc_gen_elixir_version: "0.14.0"

  rpc :SetNegotiationPolicy,
      Sw4rm.Proto.Scheduler.SetNegotiationPolicyRequest,
      Sw4rm.Proto.Scheduler.SetNegotiationPolicyResponse

  rpc :GetNegotiationPolicy,
      Sw4rm.Proto.Scheduler.GetNegotiationPolicyRequest,
      Sw4rm.Proto.Scheduler.GetNegotiationPolicyResponse

  rpc :SetPolicyProfiles,
      Sw4rm.Proto.Scheduler.SetPolicyProfilesRequest,
      Sw4rm.Proto.Scheduler.SetPolicyProfilesResponse

  rpc :ListPolicyProfiles,
      Sw4rm.Proto.Scheduler.ListPolicyProfilesRequest,
      Sw4rm.Proto.Scheduler.ListPolicyProfilesResponse

  rpc :GetEffectivePolicy,
      Sw4rm.Proto.Scheduler.GetEffectivePolicyRequest,
      Sw4rm.Proto.Scheduler.GetEffectivePolicyResponse

  rpc :SubmitEvaluation,
      Sw4rm.Proto.Scheduler.SubmitEvaluationRequest,
      Sw4rm.Proto.Scheduler.SubmitEvaluationResponse

  rpc :HitlAction,
      Sw4rm.Proto.Scheduler.HitlActionRequest,
      Sw4rm.Proto.Scheduler.HitlActionResponse
end

defmodule Sw4rm.Proto.Scheduler.SchedulerPolicyService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Scheduler.SchedulerPolicyService.Service
end
