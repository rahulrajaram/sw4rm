defmodule Sw4rm.Proto.Logging.LogEvent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ts, 1, type: Google.Protobuf.Timestamp
  field :correlation_id, 2, type: :string, json_name: "correlationId"
  field :agent_id, 3, type: :string, json_name: "agentId"
  field :event_type, 4, type: :string, json_name: "eventType"
  field :level, 5, type: :string
  field :details_json, 6, type: :string, json_name: "detailsJson"
end

defmodule Sw4rm.Proto.Logging.IngestResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ok, 1, type: :bool
end

defmodule Sw4rm.Proto.Logging.LoggingService.Service do
  @moduledoc false

  use GRPC.Service, name: "sw4rm.logging.LoggingService", protoc_gen_elixir_version: "0.14.0"

  rpc :Ingest, Sw4rm.Proto.Logging.LogEvent, Sw4rm.Proto.Logging.IngestResponse
end

defmodule Sw4rm.Proto.Logging.LoggingService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.Logging.LoggingService.Service
end
