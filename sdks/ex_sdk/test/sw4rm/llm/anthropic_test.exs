defmodule Sw4rm.LLM.AnthropicTest do
  use ExUnit.Case, async: true

  alias Sw4rm.LLM.Anthropic

  describe "new/1" do
    test "returns error without any credentials" do
      original = System.get_env("ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")

      dotfile = Path.expand("~/.anthropic")

      if not File.exists?(dotfile) do
        assert {:error, {:authentication, msg}} = Anthropic.new()
        assert msg =~ "No Anthropic API key"
      end

      if original, do: System.put_env("ANTHROPIC_API_KEY", original)
    end

    test "succeeds with explicit api_key" do
      assert {:ok, client} = Anthropic.new(api_key: "sk-ant-test", rate_limiter: nil)
      assert client.api_key == "sk-ant-test"
      assert client.default_model == "claude-sonnet-4-20250514"
    end

    test "uses custom default_model" do
      {:ok, client} =
        Anthropic.new(api_key: "sk-ant-test", default_model: "claude-3-haiku", rate_limiter: nil)

      assert client.default_model == "claude-3-haiku"
    end

    test "uses custom timeout" do
      {:ok, client} = Anthropic.new(api_key: "sk-ant-test", timeout_ms: 60_000, rate_limiter: nil)
      assert client.timeout_ms == 60_000
    end

    test "reads api_key from environment" do
      original = System.get_env("ANTHROPIC_API_KEY")
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-from-env")

      {:ok, client} = Anthropic.new(rate_limiter: nil)
      assert client.api_key == "sk-ant-from-env"

      if original do
        System.put_env("ANTHROPIC_API_KEY", original)
      else
        System.delete_env("ANTHROPIC_API_KEY")
      end
    end

    test "explicit api_key takes precedence over env" do
      original = System.get_env("ANTHROPIC_API_KEY")
      System.put_env("ANTHROPIC_API_KEY", "sk-ant-from-env")

      {:ok, client} = Anthropic.new(api_key: "sk-ant-explicit", rate_limiter: nil)
      assert client.api_key == "sk-ant-explicit"

      if original do
        System.put_env("ANTHROPIC_API_KEY", original)
      else
        System.delete_env("ANTHROPIC_API_KEY")
      end
    end

    test "default timeout is 300_000ms" do
      {:ok, client} = Anthropic.new(api_key: "sk-ant-test", rate_limiter: nil)
      assert client.timeout_ms == 300_000
    end
  end

  describe "struct fields" do
    test "has expected fields" do
      {:ok, client} = Anthropic.new(api_key: "test", rate_limiter: nil)
      assert Map.has_key?(client, :api_key)
      assert Map.has_key?(client, :default_model)
      assert Map.has_key?(client, :timeout_ms)
      assert Map.has_key?(client, :rate_limiter)
    end
  end
end
