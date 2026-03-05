defmodule Sw4rm.Control do
  @moduledoc """
  Control message types for scheduler orchestration.

  Structured data types for CONTROL-only messages between scheduler and agents.
  """

  @ct_scheduler_command "application/vnd.sw4rm.scheduler.command+json;v=1"
  @ct_agent_report "application/vnd.sw4rm.agent.report+json;v=1"

  @doc "MIME content type for scheduler commands."
  def content_type_scheduler_command, do: @ct_scheduler_command

  @doc "MIME content type for agent reports."
  def content_type_agent_report, do: @ct_agent_report

  # -- SchedulerCommand --

  defmodule SchedulerCommand do
    @moduledoc "Scheduler CONTROL command directing an agent to a stage."
    @type stage :: :prompt | :plan | :run
    @type t :: %__MODULE__{stage: stage(), input: map() | nil}
    defstruct [:stage, :input]

    @doc "Create a new scheduler command."
    def new(stage, input \\ nil) when stage in [:prompt, :plan, :run] do
      %__MODULE__{stage: stage, input: input}
    end

    @doc "Encode to JSON-compatible map."
    def to_map(%__MODULE__{} = cmd) do
      map = %{"stage" => Atom.to_string(cmd.stage)}
      if cmd.input, do: Map.put(map, "input", cmd.input), else: map
    end

    @doc "Decode from JSON-parsed map."
    def from_map(%{"stage" => stage} = map) do
      %__MODULE__{
        stage: String.to_existing_atom(stage),
        input: Map.get(map, "input")
      }
    end
  end

  # -- AgentReport --

  defmodule ReportFile do
    @moduledoc "A single file artifact in an agent report (base64 encoded)."
    @type t :: %__MODULE__{}
    defstruct [:path, :b64]
  end

  defmodule AgentReport do
    @moduledoc "Agent report with optional file artifacts."
    @type t :: %__MODULE__{}
    defstruct [:agent_id, :stage, :success, :files, :logs, :error]

    @doc "Encode to JSON-compatible map, omitting nil fields."
    def to_map(%__MODULE__{} = r) do
      %{}
      |> put_if(:agent_id, r.agent_id)
      |> put_if(:stage, r.stage)
      |> put_if(:success, r.success)
      |> put_if(:error, r.error)
      |> put_if(:logs, r.logs)
      |> then(fn m ->
        case r.files do
          nil -> m
          [] -> m
          files -> Map.put(m, "files", Enum.map(files, &%{"path" => &1.path, "b64" => &1.b64}))
        end
      end)
    end

    @doc "Decode from JSON-parsed map."
    def from_map(map) do
      files =
        case Map.get(map, "files") do
          nil ->
            nil

          list ->
            Enum.map(list, fn f ->
              %Sw4rm.Control.ReportFile{path: Map.get(f, "path"), b64: Map.get(f, "b64")}
            end)
        end

      %__MODULE__{
        agent_id: Map.get(map, "agent_id"),
        stage: Map.get(map, "stage"),
        success: Map.get(map, "success"),
        files: files,
        logs: Map.get(map, "logs"),
        error: Map.get(map, "error")
      }
    end

    defp put_if(map, _key, nil), do: map
    defp put_if(map, key, val), do: Map.put(map, Atom.to_string(key), val)
  end
end
