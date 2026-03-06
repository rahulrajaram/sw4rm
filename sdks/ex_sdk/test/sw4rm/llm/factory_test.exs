defmodule Sw4rm.LLM.FactoryTest do
  use ExUnit.Case, async: true

  alias Sw4rm.LLM.Factory

  describe "create_llm_client/1 with mock" do
    test "creates mock client" do
      {:ok, {module, pid}} =
        Factory.create_llm_client(client_type: "mock", responses: ["factory test"])

      assert module == Sw4rm.LLM.Mock
      assert is_pid(pid)

      {:ok, resp} = module.query("hello", client: pid)
      assert resp.content == "factory test"

      Sw4rm.LLM.Mock.stop(pid)
    end

    test "passes model to mock" do
      {:ok, {module, pid}} =
        Factory.create_llm_client(client_type: "mock", model: "custom-model")

      {:ok, resp} = module.query("hello", client: pid)
      assert resp.model == "custom-model"

      Sw4rm.LLM.Mock.stop(pid)
    end
  end

  describe "create_llm_client/1 with unknown type" do
    test "returns error for unknown client type" do
      assert {:error, msg} = Factory.create_llm_client(client_type: "unknown")
      assert msg =~ "Unknown LLM client type"
      assert msg =~ "unknown"
    end
  end

  describe "create_llm_client/1 with groq (no key)" do
    test "returns authentication error without API key" do
      # Ensure no env var is set (assuming test environment has none)
      original = System.get_env("GROQ_API_KEY")
      System.delete_env("GROQ_API_KEY")

      result = Factory.create_llm_client(client_type: "groq")

      case result do
        {:error, {:authentication, msg}} ->
          assert msg =~ "Groq"

        {:ok, _} ->
          # API key may be in ~/.groq, that's fine
          :ok
      end

      if original, do: System.put_env("GROQ_API_KEY", original)
    end
  end

  describe "create_llm_client/1 with anthropic (no key)" do
    test "returns authentication error without API key" do
      original = System.get_env("ANTHROPIC_API_KEY")
      System.delete_env("ANTHROPIC_API_KEY")

      result = Factory.create_llm_client(client_type: "anthropic")

      case result do
        {:error, {:authentication, msg}} ->
          assert msg =~ "Anthropic"

        {:ok, _} ->
          # API key may be in ~/.anthropic, that's fine
          :ok
      end

      if original, do: System.put_env("ANTHROPIC_API_KEY", original)
    end
  end

  describe "case insensitivity" do
    test "handles uppercase client type" do
      {:ok, {module, pid}} = Factory.create_llm_client(client_type: "MOCK")
      assert module == Sw4rm.LLM.Mock
      Sw4rm.LLM.Mock.stop(pid)
    end

    test "handles mixed case client type" do
      {:ok, {module, pid}} = Factory.create_llm_client(client_type: "Mock")
      assert module == Sw4rm.LLM.Mock
      Sw4rm.LLM.Mock.stop(pid)
    end
  end
end
