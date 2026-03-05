defmodule Sw4rm.Proto.Reasoning.ParallelismCheckRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :scope_a, 1, type: :string, json_name: "scopeA"
  field :scope_b, 2, type: :string, json_name: "scopeB"
end

defmodule Sw4rm.Proto.Reasoning.ParallelismCheckResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :confidence_score, 1, type: :double, json_name: "confidenceScore"
  field :notes, 2, type: :string
end

defmodule Sw4rm.Proto.Reasoning.DebateEvaluateRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :proposal_a, 2, type: :string, json_name: "proposalA"
  field :proposal_b, 3, type: :string, json_name: "proposalB"
  field :intensity, 4, type: :string
end

defmodule Sw4rm.Proto.Reasoning.DebateEvaluateResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :confidence_score, 1, type: :double, json_name: "confidenceScore"
  field :notes, 2, type: :string
end

defmodule Sw4rm.Proto.Reasoning.TextSegment do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :kind, 1, type: :string
  field :content, 2, type: :string
  field :seq, 3, type: :int64
  field :at, 4, type: :string
end

defmodule Sw4rm.Proto.Reasoning.SummarizeRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
  field :segments, 2, repeated: true, type: Sw4rm.Proto.Reasoning.TextSegment
  field :max_tokens, 3, type: :uint32, json_name: "maxTokens"
  field :mode, 4, type: :string
end

defmodule Sw4rm.Proto.Reasoning.SummarizeResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :summary, 1, type: :string
  field :tokens, 2, type: :uint32
  field :cost_cents, 3, type: :double, json_name: "costCents"
  field :model, 4, type: :string
end

defmodule Sw4rm.Proto.Reasoning.ReasoningProxy.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.reasoning.ReasoningProxy", protoc_gen_elixir_version: "0.14.0"

  rpc :CheckParallelism,
      Sw4rm.Proto.Reasoning.ParallelismCheckRequest,
      Sw4rm.Proto.Reasoning.ParallelismCheckResponse

  rpc :EvaluateDebate,
      Sw4rm.Proto.Reasoning.DebateEvaluateRequest,
      Sw4rm.Proto.Reasoning.DebateEvaluateResponse

  rpc :Summarize, Sw4rm.Proto.Reasoning.SummarizeRequest, Sw4rm.Proto.Reasoning.SummarizeResponse
end

defmodule Sw4rm.Proto.Reasoning.ReasoningProxy.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Reasoning.ReasoningProxy.Service
end
