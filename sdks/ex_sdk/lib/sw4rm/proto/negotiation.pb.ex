defmodule Sw4rm.Proto.Negotiation.NegotiationOpen do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :correlation_id, 2, type: :string, json_name: "correlationId"
  field :topic, 3, type: :string
  field :participants, 4, repeated: true, type: :string
  field :intensity, 5, type: Sw4rm.Proto.Common.DebateIntensity, enum: true
  field :debate_timeout, 6, type: Google.Protobuf.Duration, json_name: "debateTimeout"
end

defmodule Sw4rm.Proto.Negotiation.Proposal do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :from_agent, 2, type: :string, json_name: "fromAgent"
  field :content_type, 3, type: :string, json_name: "contentType"
  field :payload, 4, type: :bytes
end

defmodule Sw4rm.Proto.Negotiation.CounterProposal do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :from_agent, 2, type: :string, json_name: "fromAgent"
  field :content_type, 3, type: :string, json_name: "contentType"
  field :payload, 4, type: :bytes
end

defmodule Sw4rm.Proto.Negotiation.Evaluation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :from_agent, 2, type: :string, json_name: "fromAgent"
  field :confidence_score, 3, type: :double, json_name: "confidenceScore"
  field :notes, 4, type: :string
end

defmodule Sw4rm.Proto.Negotiation.Decision do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :decided_by, 2, type: :string, json_name: "decidedBy"
  field :content_type, 3, type: :string, json_name: "contentType"
  field :result, 4, type: :bytes
end

defmodule Sw4rm.Proto.Negotiation.AbortRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Negotiation.NegotiationService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "sw4rm.negotiation.NegotiationService",
    protoc_gen_elixir_version: "0.14.0"

  rpc :Open, Sw4rm.Proto.Negotiation.NegotiationOpen, Sw4rm.Proto.Common.Empty
  rpc :Propose, Sw4rm.Proto.Negotiation.Proposal, Sw4rm.Proto.Common.Empty
  rpc :Counter, Sw4rm.Proto.Negotiation.CounterProposal, Sw4rm.Proto.Common.Empty
  rpc :Evaluate, Sw4rm.Proto.Negotiation.Evaluation, Sw4rm.Proto.Common.Empty
  rpc :Decide, Sw4rm.Proto.Negotiation.Decision, Sw4rm.Proto.Common.Empty
  rpc :Abort, Sw4rm.Proto.Negotiation.AbortRequest, Sw4rm.Proto.Common.Empty
end

defmodule Sw4rm.Proto.Negotiation.NegotiationService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Negotiation.NegotiationService.Service
end
