defmodule Sw4rm.Proto.Registry.RegistrationType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :REGISTRATION_TYPE_UNSPECIFIED, 0
  field :STANDARD_AGENT, 1
  field :SWARM_GATEWAY, 2
end

defmodule Sw4rm.Proto.Registry.AgentDescriptor do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :name, 2, type: :string
  field :description, 3, type: :string
  field :capabilities, 4, repeated: true, type: :string

  field :communication_class, 5,
    type: Sw4rm.Proto.Common.CommunicationClass,
    json_name: "communicationClass",
    enum: true

  field :modalities_supported, 6, repeated: true, type: :string, json_name: "modalitiesSupported"
  field :reasoning_connectors, 7, repeated: true, type: :string, json_name: "reasoningConnectors"
  field :public_key, 8, type: :bytes, json_name: "publicKey"

  field :registration_type, 100,
    type: Sw4rm.Proto.Registry.RegistrationType,
    json_name: "registrationType",
    enum: true

  field :max_concurrent_delegations, 101, type: :uint32, json_name: "maxConcurrentDelegations"
end

defmodule Sw4rm.Proto.Registry.RegisterAgentRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent, 1, type: Sw4rm.Proto.Registry.AgentDescriptor
end

defmodule Sw4rm.Proto.Registry.RegisterAgentResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :accepted, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Registry.HeartbeatRequest.HealthEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Sw4rm.Proto.Registry.HeartbeatRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :state, 2, type: Sw4rm.Proto.Common.AgentState, enum: true

  field :health, 3,
    repeated: true,
    type: Sw4rm.Proto.Registry.HeartbeatRequest.HealthEntry,
    map: true
end

defmodule Sw4rm.Proto.Registry.HeartbeatResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
end

defmodule Sw4rm.Proto.Registry.DeregisterAgentRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Registry.DeregisterAgentResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
end

defmodule Sw4rm.Proto.Registry.RegistryService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.registry.RegistryService", protoc_gen_elixir_version: "0.14.0"

  rpc :RegisterAgent,
      Sw4rm.Proto.Registry.RegisterAgentRequest,
      Sw4rm.Proto.Registry.RegisterAgentResponse

  rpc :Heartbeat, Sw4rm.Proto.Registry.HeartbeatRequest, Sw4rm.Proto.Registry.HeartbeatResponse

  rpc :DeregisterAgent,
      Sw4rm.Proto.Registry.DeregisterAgentRequest,
      Sw4rm.Proto.Registry.DeregisterAgentResponse
end

defmodule Sw4rm.Proto.Registry.RegistryService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Registry.RegistryService.Service
end
