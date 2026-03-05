defmodule Sw4rm.Proto.Connector.ToolDescriptor do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :tool_name, 1, type: :string, json_name: "toolName"
  field :input_schema, 2, type: :string, json_name: "inputSchema"
  field :output_schema, 3, type: :string, json_name: "outputSchema"
  field :idempotent, 4, type: :bool
  field :needs_worktree, 5, type: :bool, json_name: "needsWorktree"
  field :default_timeout_s, 6, type: :uint32, json_name: "defaultTimeoutS"
  field :max_concurrency, 7, type: :uint32, json_name: "maxConcurrency"
  field :side_effects, 8, type: :string, json_name: "sideEffects"
end

defmodule Sw4rm.Proto.Connector.ProviderRegisterRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :provider_id, 1, type: :string, json_name: "providerId"
  field :tools, 2, repeated: true, type: Sw4rm.Proto.Connector.ToolDescriptor
end

defmodule Sw4rm.Proto.Connector.ProviderRegisterResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Connector.DescribeToolsRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :provider_id, 1, type: :string, json_name: "providerId"
end

defmodule Sw4rm.Proto.Connector.DescribeToolsResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :tools, 1, repeated: true, type: Sw4rm.Proto.Connector.ToolDescriptor
end

defmodule Sw4rm.Proto.Connector.ConnectorService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.connector.ConnectorService", protoc_gen_elixir_version: "0.14.0"

  rpc :RegisterProvider,
      Sw4rm.Proto.Connector.ProviderRegisterRequest,
      Sw4rm.Proto.Connector.ProviderRegisterResponse

  rpc :DescribeTools,
      Sw4rm.Proto.Connector.DescribeToolsRequest,
      Sw4rm.Proto.Connector.DescribeToolsResponse
end

defmodule Sw4rm.Proto.Connector.ConnectorService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Connector.ConnectorService.Service
end
