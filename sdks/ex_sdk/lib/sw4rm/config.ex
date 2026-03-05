defmodule Sw4rm.Config do
  @moduledoc """
  Configuration structures and env-var loaders for SW4RM SDK.
  """

  alias Sw4rm.Constants

  defmodule Endpoints do
    @moduledoc "Service endpoint addresses for all SW4RM services."
    @type t :: %__MODULE__{}
    defstruct router: nil,
              registry: nil,
              scheduler: nil,
              hitl: nil,
              worktree: nil,
              tool: nil,
              connector: nil,
              negotiation: nil,
              reasoning: nil,
              logging: nil,
              activity: nil,
              scheduler_policy: nil,
              handoff: nil,
              negotiation_room: nil,
              workflow: nil
  end

  defmodule AgentConfig do
    @moduledoc "Agent runtime configuration."
    @type t :: %__MODULE__{}
    defstruct agent_id: "agent-1",
              name: "Agent",
              description: nil,
              version: "0.1.0",
              capabilities: [],
              endpoints: nil,
              timeout_ms: 30_000,
              retry_max_attempts: 3,
              heartbeat_interval_ms: 30_000,
              communication_class: 2,
              modalities_supported: ["application/json"],
              public_key: nil,
              metadata: %{}
  end

  @doc "Build default endpoints, honoring `SW4RM_*_ADDR` env vars."
  @spec default_endpoints() :: Endpoints.t()
  def default_endpoints do
    %Endpoints{
      router: env("SW4RM_ROUTER_ADDR", Constants.default_addr(Constants.router_port())),
      registry: env("SW4RM_REGISTRY_ADDR", Constants.default_addr(Constants.registry_port())),
      scheduler: env("SW4RM_SCHEDULER_ADDR", Constants.default_addr(Constants.scheduler_port())),
      hitl: env("SW4RM_HITL_ADDR", Constants.default_addr(Constants.hitl_port())),
      worktree: env("SW4RM_WORKTREE_ADDR", Constants.default_addr(Constants.worktree_port())),
      tool: env("SW4RM_TOOL_ADDR", Constants.default_addr(Constants.tool_port())),
      connector: env("SW4RM_CONNECTOR_ADDR", Constants.default_addr(Constants.connector_port())),
      negotiation:
        env("SW4RM_NEGOTIATION_ADDR", Constants.default_addr(Constants.negotiation_port())),
      reasoning: env("SW4RM_REASONING_ADDR", Constants.default_addr(Constants.reasoning_port())),
      logging: env("SW4RM_LOGGING_ADDR", Constants.default_addr(Constants.logging_port())),
      activity: env("SW4RM_ACTIVITY_ADDR", Constants.default_addr(Constants.activity_port())),
      scheduler_policy:
        env(
          "SW4RM_SCHEDULER_POLICY_ADDR",
          Constants.default_addr(Constants.scheduler_policy_port())
        ),
      handoff: env("SW4RM_HANDOFF_ADDR", Constants.default_addr(Constants.handoff_port())),
      negotiation_room:
        env(
          "SW4RM_NEGOTIATION_ROOM_ADDR",
          Constants.default_addr(Constants.negotiation_room_port())
        ),
      workflow: env("SW4RM_WORKFLOW_ADDR", Constants.default_addr(Constants.workflow_port()))
    }
  end

  @doc "Load full agent configuration from environment variables."
  @spec from_env() :: AgentConfig.t()
  def from_env do
    %AgentConfig{
      agent_id: env("AGENT_ID", "agent-1"),
      name: env("AGENT_NAME", "Agent"),
      description: System.get_env("AGENT_DESCRIPTION"),
      version: env("AGENT_VERSION", "0.1.0"),
      capabilities: parse_csv(System.get_env("AGENT_CAPABILITIES")),
      endpoints: default_endpoints(),
      timeout_ms: env_int("SW4RM_TIMEOUT_MS", Constants.default_timeout_ms()),
      retry_max_attempts:
        env_int("SW4RM_RETRY_MAX_ATTEMPTS", Constants.default_retry_max_attempts()),
      heartbeat_interval_ms:
        env_int("SW4RM_HEARTBEAT_INTERVAL_MS", Constants.default_heartbeat_interval_ms()),
      communication_class: env_int("AGENT_COMMUNICATION_CLASS", 2),
      modalities_supported:
        parse_csv(System.get_env("AGENT_MODALITIES_SUPPORTED"))
        |> then(fn
          [] -> ["application/json"]
          list -> list
        end)
    }
  end

  # -- Helpers --

  defp env(key, default), do: System.get_env(key) || default

  defp env_int(key, default) do
    case System.get_env(key) do
      nil -> default
      val -> String.to_integer(val)
    end
  end

  defp parse_csv(nil), do: []

  defp parse_csv(raw) do
    raw
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
