defmodule Sw4rm.ConfigTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Config
  alias Sw4rm.Config.{Endpoints, AgentConfig}

  describe "default_endpoints/0" do
    test "returns Endpoints struct with all services" do
      endpoints = Config.default_endpoints()
      assert %Endpoints{} = endpoints
      assert is_binary(endpoints.router)
      assert is_binary(endpoints.registry)
      assert is_binary(endpoints.scheduler)
      assert is_binary(endpoints.hitl)
      assert is_binary(endpoints.worktree)
      assert is_binary(endpoints.tool)
      assert is_binary(endpoints.connector)
      assert is_binary(endpoints.negotiation)
      assert is_binary(endpoints.reasoning)
      assert is_binary(endpoints.logging)
      assert is_binary(endpoints.activity)
      assert is_binary(endpoints.scheduler_policy)
      assert is_binary(endpoints.handoff)
    end

    test "uses http://localhost defaults" do
      endpoints = Config.default_endpoints()
      assert String.starts_with?(endpoints.router, "http://localhost:")
    end

    test "honors env var overrides" do
      System.put_env("SW4RM_ROUTER_ADDR", "custom:9999")
      endpoints = Config.default_endpoints()
      assert endpoints.router == "custom:9999"
      System.delete_env("SW4RM_ROUTER_ADDR")
    end
  end

  describe "from_env/0" do
    test "returns AgentConfig with defaults" do
      config = Config.from_env()
      assert %AgentConfig{} = config
      assert config.agent_id == "agent-1"
      assert config.name == "Agent"
      assert is_integer(config.timeout_ms)
      assert %Endpoints{} = config.endpoints
    end

    test "reads agent_id from env" do
      System.put_env("AGENT_ID", "custom-agent")
      config = Config.from_env()
      assert config.agent_id == "custom-agent"
      System.delete_env("AGENT_ID")
    end

    test "parses capabilities CSV" do
      System.put_env("AGENT_CAPABILITIES", "code,review,test")
      config = Config.from_env()
      assert config.capabilities == ["code", "review", "test"]
      System.delete_env("AGENT_CAPABILITIES")
    end
  end
end
