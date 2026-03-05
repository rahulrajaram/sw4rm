defmodule Sw4rm.Proto.Workflow.NodeStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :NODE_STATUS_UNSPECIFIED, 0
  field :PENDING, 1
  field :READY, 2
  field :RUNNING, 3
  field :COMPLETED, 4
  field :FAILED, 5
  field :SKIPPED, 6
end

defmodule Sw4rm.Proto.Workflow.TriggerType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :TRIGGER_TYPE_UNSPECIFIED, 0
  field :EVENT, 1
  field :SCHEDULE, 2
  field :MANUAL, 3
  field :DEPENDENCY, 4
end

defmodule Sw4rm.Proto.Workflow.WorkflowNode.InputMappingEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Sw4rm.Proto.Workflow.WorkflowNode.OutputMappingEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Sw4rm.Proto.Workflow.WorkflowNode.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Sw4rm.Proto.Workflow.WorkflowNode do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :node_id, 1, type: :string, json_name: "nodeId"
  field :agent_id, 2, type: :string, json_name: "agentId"
  field :dependencies, 3, repeated: true, type: :string

  field :trigger_type, 4,
    type: Sw4rm.Proto.Workflow.TriggerType,
    json_name: "triggerType",
    enum: true

  field :input_mapping, 5,
    repeated: true,
    type: Sw4rm.Proto.Workflow.WorkflowNode.InputMappingEntry,
    json_name: "inputMapping",
    map: true

  field :output_mapping, 6,
    repeated: true,
    type: Sw4rm.Proto.Workflow.WorkflowNode.OutputMappingEntry,
    json_name: "outputMapping",
    map: true

  field :metadata, 7,
    repeated: true,
    type: Sw4rm.Proto.Workflow.WorkflowNode.MetadataEntry,
    map: true
end

defmodule Sw4rm.Proto.Workflow.WorkflowDefinition.NodesEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Sw4rm.Proto.Workflow.WorkflowNode
end

defmodule Sw4rm.Proto.Workflow.WorkflowDefinition.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Sw4rm.Proto.Workflow.WorkflowDefinition do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :workflow_id, 1, type: :string, json_name: "workflowId"

  field :nodes, 2,
    repeated: true,
    type: Sw4rm.Proto.Workflow.WorkflowDefinition.NodesEntry,
    map: true

  field :created_at, 3, type: Google.Protobuf.Timestamp, json_name: "createdAt"

  field :metadata, 4,
    repeated: true,
    type: Sw4rm.Proto.Workflow.WorkflowDefinition.MetadataEntry,
    map: true
end

defmodule Sw4rm.Proto.Workflow.NodeState do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :node_id, 1, type: :string, json_name: "nodeId"
  field :status, 2, type: Sw4rm.Proto.Workflow.NodeStatus, enum: true
  field :started_at, 3, type: Google.Protobuf.Timestamp, json_name: "startedAt"
  field :completed_at, 4, type: Google.Protobuf.Timestamp, json_name: "completedAt"
  field :output, 5, type: :string
  field :error, 6, type: :string
end

defmodule Sw4rm.Proto.Workflow.WorkflowState.NodeStatesEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Sw4rm.Proto.Workflow.NodeState
end

defmodule Sw4rm.Proto.Workflow.WorkflowState.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Sw4rm.Proto.Workflow.WorkflowState do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :workflow_id, 1, type: :string, json_name: "workflowId"

  field :node_states, 2,
    repeated: true,
    type: Sw4rm.Proto.Workflow.WorkflowState.NodeStatesEntry,
    json_name: "nodeStates",
    map: true

  field :workflow_data, 3, type: :string, json_name: "workflowData"
  field :started_at, 4, type: Google.Protobuf.Timestamp, json_name: "startedAt"
  field :completed_at, 5, type: Google.Protobuf.Timestamp, json_name: "completedAt"

  field :metadata, 6,
    repeated: true,
    type: Sw4rm.Proto.Workflow.WorkflowState.MetadataEntry,
    map: true
end

defmodule Sw4rm.Proto.Workflow.CreateWorkflowRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :definition, 1, type: Sw4rm.Proto.Workflow.WorkflowDefinition
end

defmodule Sw4rm.Proto.Workflow.CreateWorkflowResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :workflow_id, 1, type: :string, json_name: "workflowId"
  field :success, 2, type: :bool
  field :error, 3, type: :string
end

defmodule Sw4rm.Proto.Workflow.StartWorkflowRequest.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Sw4rm.Proto.Workflow.StartWorkflowRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :workflow_id, 1, type: :string, json_name: "workflowId"
  field :workflow_data, 2, type: :string, json_name: "workflowData"

  field :metadata, 3,
    repeated: true,
    type: Sw4rm.Proto.Workflow.StartWorkflowRequest.MetadataEntry,
    map: true
end

defmodule Sw4rm.Proto.Workflow.StartWorkflowResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :workflow_id, 1, type: :string, json_name: "workflowId"
  field :state, 2, type: Sw4rm.Proto.Workflow.WorkflowState
  field :success, 3, type: :bool
  field :error, 4, type: :string
end

defmodule Sw4rm.Proto.Workflow.GetWorkflowStateRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :workflow_id, 1, type: :string, json_name: "workflowId"
end

defmodule Sw4rm.Proto.Workflow.GetWorkflowStateResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :state, 1, type: Sw4rm.Proto.Workflow.WorkflowState
  field :success, 2, type: :bool
  field :error, 3, type: :string
end

defmodule Sw4rm.Proto.Workflow.ResumeWorkflowRequest.MetadataEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Sw4rm.Proto.Workflow.ResumeWorkflowRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :workflow_id, 1, type: :string, json_name: "workflowId"
  field :node_id, 2, type: :string, json_name: "nodeId"
  field :workflow_data, 3, type: :string, json_name: "workflowData"

  field :metadata, 4,
    repeated: true,
    type: Sw4rm.Proto.Workflow.ResumeWorkflowRequest.MetadataEntry,
    map: true
end

defmodule Sw4rm.Proto.Workflow.ResumeWorkflowResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :workflow_id, 1, type: :string, json_name: "workflowId"
  field :state, 2, type: Sw4rm.Proto.Workflow.WorkflowState
  field :success, 3, type: :bool
  field :error, 4, type: :string
end

defmodule Sw4rm.Proto.Workflow.WorkflowService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "sw4rm.workflow.WorkflowService",
    protoc_gen_elixir_version: "0.14.0"

  rpc :CreateWorkflow,
      Sw4rm.Proto.Workflow.CreateWorkflowRequest,
      Sw4rm.Proto.Workflow.CreateWorkflowResponse

  rpc :StartWorkflow,
      Sw4rm.Proto.Workflow.StartWorkflowRequest,
      Sw4rm.Proto.Workflow.StartWorkflowResponse

  rpc :GetWorkflowState,
      Sw4rm.Proto.Workflow.GetWorkflowStateRequest,
      Sw4rm.Proto.Workflow.GetWorkflowStateResponse

  rpc :ResumeWorkflow,
      Sw4rm.Proto.Workflow.ResumeWorkflowRequest,
      Sw4rm.Proto.Workflow.ResumeWorkflowResponse
end

defmodule Sw4rm.Proto.Workflow.WorkflowService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Workflow.WorkflowService.Service
end
