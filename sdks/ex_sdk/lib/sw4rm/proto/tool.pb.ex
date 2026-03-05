defmodule Sw4rm.Proto.Tool.ExecutionPolicy do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :timeout, 1, type: Google.Protobuf.Duration
  field :max_retries, 2, type: :uint32, json_name: "maxRetries"
  field :backoff, 3, type: :string
  field :worktree_required, 4, type: :bool, json_name: "worktreeRequired"
  field :network_policy, 5, type: :string, json_name: "networkPolicy"
  field :privilege_level, 6, type: :string, json_name: "privilegeLevel"
  field :budget_cpu_ms, 7, type: :uint64, json_name: "budgetCpuMs"
  field :budget_wall_ms, 8, type: :uint64, json_name: "budgetWallMs"
end

defmodule Sw4rm.Proto.Tool.ToolCall do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :call_id, 1, type: :string, json_name: "callId"
  field :tool_name, 2, type: :string, json_name: "toolName"
  field :provider_id, 3, type: :string, json_name: "providerId"
  field :content_type, 4, type: :string, json_name: "contentType"
  field :args, 5, type: :bytes
  field :policy, 6, type: Sw4rm.Proto.Tool.ExecutionPolicy
  field :stream, 7, type: :bool
end

defmodule Sw4rm.Proto.Tool.ToolFrame do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :call_id, 1, type: :string, json_name: "callId"
  field :frame_no, 2, type: :uint64, json_name: "frameNo"
  field :final, 3, type: :bool
  field :content_type, 4, type: :string, json_name: "contentType"
  field :data, 5, type: :bytes
  field :summary, 6, type: :bytes
end

defmodule Sw4rm.Proto.Tool.ToolError do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :call_id, 1, type: :string, json_name: "callId"
  field :error_code, 2, type: :string, json_name: "errorCode"
  field :message, 3, type: :string
end

defmodule Sw4rm.Proto.Tool.ToolService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.tool.ToolService", protoc_gen_elixir_version: "0.14.0"

  rpc :Call, Sw4rm.Proto.Tool.ToolCall, Sw4rm.Proto.Tool.ToolFrame
  rpc :CallStream, Sw4rm.Proto.Tool.ToolCall, stream(Sw4rm.Proto.Tool.ToolFrame)
  rpc :Cancel, Sw4rm.Proto.Tool.ToolCall, Sw4rm.Proto.Tool.ToolError
end

defmodule Sw4rm.Proto.Tool.ToolService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Tool.ToolService.Service
end
