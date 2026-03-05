defmodule Sw4rm.Proto.Router.SendMessageRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :msg, 1, type: Sw4rm.Proto.Common.Envelope
end

defmodule Sw4rm.Proto.Router.SendMessageResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :accepted, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Router.StreamRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
end

defmodule Sw4rm.Proto.Router.StreamItem do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :msg, 1, type: Sw4rm.Proto.Common.Envelope
end

defmodule Sw4rm.Proto.Router.RouterService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.router.RouterService", protoc_gen_elixir_version: "0.14.0"

  rpc :SendMessage, Sw4rm.Proto.Router.SendMessageRequest, Sw4rm.Proto.Router.SendMessageResponse
  rpc :StreamIncoming, Sw4rm.Proto.Router.StreamRequest, stream(Sw4rm.Proto.Router.StreamItem)
end

defmodule Sw4rm.Proto.Router.RouterService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Router.RouterService.Service
end
