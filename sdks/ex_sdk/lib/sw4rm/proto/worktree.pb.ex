defmodule Sw4rm.Proto.Worktree.BindRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :repo_id, 2, type: :string, json_name: "repoId"
  field :worktree_id, 3, type: :string, json_name: "worktreeId"
end

defmodule Sw4rm.Proto.Worktree.BindResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Worktree.UnbindRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
end

defmodule Sw4rm.Proto.Worktree.UnbindResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
end

defmodule Sw4rm.Proto.Worktree.SwitchRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :target_worktree_id, 2, type: :string, json_name: "targetWorktreeId"
  field :requires_hitl, 3, type: :bool, json_name: "requiresHitl"
end

defmodule Sw4rm.Proto.Worktree.SwitchApprove do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :target_worktree_id, 2, type: :string, json_name: "targetWorktreeId"
  field :ttl_ms, 3, type: :uint64, json_name: "ttlMs"
end

defmodule Sw4rm.Proto.Worktree.SwitchReject do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Worktree.StatusRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
end

defmodule Sw4rm.Proto.Worktree.StatusResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :repo_id, 1, type: :string, json_name: "repoId"
  field :worktree_id, 2, type: :string, json_name: "worktreeId"
  field :state, 3, type: :string
end

defmodule Sw4rm.Proto.Worktree.WorktreeService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.worktree.WorktreeService", protoc_gen_elixir_version: "0.14.0"

  rpc :Bind, Sw4rm.Proto.Worktree.BindRequest, Sw4rm.Proto.Worktree.BindResponse
  rpc :Unbind, Sw4rm.Proto.Worktree.UnbindRequest, Sw4rm.Proto.Worktree.UnbindResponse
  rpc :RequestSwitch, Sw4rm.Proto.Worktree.SwitchRequest, Sw4rm.Proto.Worktree.StatusResponse
  rpc :ApproveSwitch, Sw4rm.Proto.Worktree.SwitchApprove, Sw4rm.Proto.Worktree.StatusResponse
  rpc :RejectSwitch, Sw4rm.Proto.Worktree.SwitchReject, Sw4rm.Proto.Worktree.StatusResponse
  rpc :Status, Sw4rm.Proto.Worktree.StatusRequest, Sw4rm.Proto.Worktree.StatusResponse
end

defmodule Sw4rm.Proto.Worktree.WorktreeService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Worktree.WorktreeService.Service
end
