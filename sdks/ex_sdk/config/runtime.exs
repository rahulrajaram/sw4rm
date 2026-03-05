import Config

config :sw4rm_sdk,
  endpoints: %{
    router: System.get_env("SW4RM_ROUTER_ADDR", "http://localhost:50051"),
    registry: System.get_env("SW4RM_REGISTRY_ADDR", "http://localhost:50052"),
    scheduler: System.get_env("SW4RM_SCHEDULER_ADDR", "http://localhost:50053"),
    hitl: System.get_env("SW4RM_HITL_ADDR", "http://localhost:50054"),
    worktree: System.get_env("SW4RM_WORKTREE_ADDR", "http://localhost:50055"),
    tool: System.get_env("SW4RM_TOOL_ADDR", "http://localhost:50056"),
    connector: System.get_env("SW4RM_CONNECTOR_ADDR", "http://localhost:50057"),
    negotiation: System.get_env("SW4RM_NEGOTIATION_ADDR", "http://localhost:50058"),
    reasoning: System.get_env("SW4RM_REASONING_ADDR", "http://localhost:50059"),
    logging: System.get_env("SW4RM_LOGGING_ADDR", "http://localhost:50060"),
    activity: System.get_env("SW4RM_ACTIVITY_ADDR", "http://localhost:50061"),
    scheduler_policy: System.get_env("SW4RM_SCHEDULER_POLICY_ADDR", "http://localhost:50062"),
    handoff: System.get_env("SW4RM_HANDOFF_ADDR", "http://localhost:50071")
  },
  agent: %{
    agent_id: System.get_env("AGENT_ID", "agent-1"),
    name: System.get_env("AGENT_NAME", "Agent"),
    description: System.get_env("AGENT_DESCRIPTION"),
    version: System.get_env("AGENT_VERSION", "0.1.0"),
    capabilities:
      case System.get_env("AGENT_CAPABILITIES") do
        nil -> []
        raw -> raw |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
      end,
    communication_class:
      case System.get_env("AGENT_COMMUNICATION_CLASS") do
        nil -> 2
        val -> String.to_integer(val)
      end
  }
