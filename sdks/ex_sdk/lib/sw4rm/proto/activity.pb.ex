defmodule Sw4rm.Proto.Activity.Artifact do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :kind, 2, type: :string
  field :version, 3, type: :string
  field :content_type, 4, type: :string, json_name: "contentType"
  field :content, 5, type: :bytes
  field :created_at, 6, type: :string, json_name: "createdAt"
end

defmodule Sw4rm.Proto.Activity.AppendArtifactRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :artifact, 1, type: Sw4rm.Proto.Activity.Artifact
end

defmodule Sw4rm.Proto.Activity.AppendArtifactResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Activity.ListArtifactsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :negotiation_id, 1, type: :string, json_name: "negotiationId"
  field :kind, 2, type: :string
end

defmodule Sw4rm.Proto.Activity.ListArtifactsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :items, 1, repeated: true, type: Sw4rm.Proto.Activity.Artifact
end

defmodule Sw4rm.Proto.Activity.ActivityService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.activity.ActivityService", protoc_gen_elixir_version: "0.14.0"

  rpc :AppendArtifact,
      Sw4rm.Proto.Activity.AppendArtifactRequest,
      Sw4rm.Proto.Activity.AppendArtifactResponse

  rpc :ListArtifacts,
      Sw4rm.Proto.Activity.ListArtifactsRequest,
      Sw4rm.Proto.Activity.ListArtifactsResponse
end

defmodule Sw4rm.Proto.Activity.ActivityService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Activity.ActivityService.Service
end
