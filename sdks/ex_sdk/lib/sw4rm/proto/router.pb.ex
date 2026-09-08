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

defmodule Sw4rm.Proto.Router.DeliveryAckOutcome do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :DELIVERY_ACK_OUTCOME_DELIVERED, 0
  field :DELIVERY_ACK_OUTCOME_PERMANENT_FAILURE, 1
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
  field :seq, 2, type: :int64
end

defmodule Sw4rm.Proto.Router.DeliveryAckRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :seq, 2, type: :int64
  field :message_id, 3, type: :string, json_name: "messageId"

  field :outcome, 4,
    type: Sw4rm.Proto.Router.DeliveryAckOutcome,
    enum: true
end

defmodule Sw4rm.Proto.Router.DeliveryAckResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :recorded, 1, type: :bool
end

defmodule Sw4rm.Proto.Router.RouterService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.router.RouterService", protoc_gen_elixir_version: "0.14.0"

  rpc :SendMessage, Sw4rm.Proto.Router.SendMessageRequest, Sw4rm.Proto.Router.SendMessageResponse
  rpc :StreamIncoming, Sw4rm.Proto.Router.StreamRequest, stream(Sw4rm.Proto.Router.StreamItem)

  rpc :AckDelivery,
      Sw4rm.Proto.Router.DeliveryAckRequest,
      Sw4rm.Proto.Router.DeliveryAckResponse
end

defmodule Sw4rm.Proto.Router.RouterService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Router.RouterService.Service
end
