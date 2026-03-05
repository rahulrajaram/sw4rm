defmodule Sw4rm.Proto.Scheduler.SubmitTaskRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :task_id, 2, type: :string, json_name: "taskId"
  field :priority, 3, type: :int32
  field :params, 4, type: :bytes
  field :content_type, 5, type: :string, json_name: "contentType"
  field :scope, 6, type: :string
end

defmodule Sw4rm.Proto.Scheduler.SubmitTaskResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :accepted, 1, type: :bool
  field :reason, 2, type: :string
end

defmodule Sw4rm.Proto.Scheduler.PreemptRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :task_id, 2, type: :string, json_name: "taskId"
  field :reason, 3, type: :string
end

defmodule Sw4rm.Proto.Scheduler.PreemptResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :enqueued, 1, type: :bool
end

defmodule Sw4rm.Proto.Scheduler.ShutdownAgentRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :grace_period, 2, type: Google.Protobuf.Duration, json_name: "gracePeriod"
end

defmodule Sw4rm.Proto.Scheduler.ShutdownAgentResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
end

defmodule Sw4rm.Proto.Scheduler.PollActivityBufferRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
end

defmodule Sw4rm.Proto.Scheduler.ActivityEntry do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :task_id, 1, type: :string, json_name: "taskId"
  field :repo_id, 2, type: :string, json_name: "repoId"
  field :worktree_id, 3, type: :string, json_name: "worktreeId"
  field :branch, 4, type: :string
  field :description, 5, type: :string
  field :timestamp, 6, type: :string
end

defmodule Sw4rm.Proto.Scheduler.PollActivityBufferResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :entries, 1, repeated: true, type: Sw4rm.Proto.Scheduler.ActivityEntry
end

defmodule Sw4rm.Proto.Scheduler.PurgeActivityRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :agent_id, 1, type: :string, json_name: "agentId"
  field :task_ids, 2, repeated: true, type: :string, json_name: "taskIds"
end

defmodule Sw4rm.Proto.Scheduler.PurgeActivityResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :purged, 1, type: :uint32
end

defmodule Sw4rm.Proto.Scheduler.SchedulerService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.scheduler.SchedulerService", protoc_gen_elixir_version: "0.14.0"

  rpc :SubmitTask,
      Sw4rm.Proto.Scheduler.SubmitTaskRequest,
      Sw4rm.Proto.Scheduler.SubmitTaskResponse

  rpc :RequestPreemption,
      Sw4rm.Proto.Scheduler.PreemptRequest,
      Sw4rm.Proto.Scheduler.PreemptResponse

  rpc :ShutdownAgent,
      Sw4rm.Proto.Scheduler.ShutdownAgentRequest,
      Sw4rm.Proto.Scheduler.ShutdownAgentResponse

  rpc :PollActivityBuffer,
      Sw4rm.Proto.Scheduler.PollActivityBufferRequest,
      Sw4rm.Proto.Scheduler.PollActivityBufferResponse

  rpc :PurgeActivity,
      Sw4rm.Proto.Scheduler.PurgeActivityRequest,
      Sw4rm.Proto.Scheduler.PurgeActivityResponse
end

defmodule Sw4rm.Proto.Scheduler.SchedulerService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Scheduler.SchedulerService.Service
end
