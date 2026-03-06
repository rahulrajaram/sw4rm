defmodule Sw4rm.LLM.ClientTest do
  use ExUnit.Case, async: true

  alias Sw4rm.LLM.Client

  describe "extract_opts/1" do
    test "returns defaults when given empty list" do
      result = Client.extract_opts([])
      assert result.system_prompt == nil
      assert result.max_tokens == 4096
      assert result.temperature == 1.0
      assert result.model == nil
    end

    test "overrides defaults with provided values" do
      result =
        Client.extract_opts(
          system_prompt: "Be helpful.",
          max_tokens: 1024,
          temperature: 0.5,
          model: "gpt-4"
        )

      assert result.system_prompt == "Be helpful."
      assert result.max_tokens == 1024
      assert result.temperature == 0.5
      assert result.model == "gpt-4"
    end

    test "ignores unknown keys" do
      result = Client.extract_opts(system_prompt: "test", unknown_key: "value")
      assert result.system_prompt == "test"
      refute Map.has_key?(result, :unknown_key)
    end
  end

  describe "estimate_tokens/1,2" do
    test "estimates based on character count" do
      # 400 chars / 4 = 100 tokens
      prompt = String.duplicate("a", 400)
      assert Client.estimate_tokens(prompt) == 100
    end

    test "has a floor of 100 tokens" do
      assert Client.estimate_tokens("hi") == 100
    end

    test "includes system_prompt in estimate" do
      prompt = String.duplicate("a", 400)
      system = String.duplicate("b", 400)
      # (400 + 400) / 4 = 200
      assert Client.estimate_tokens(prompt, system) == 200
    end

    test "returns 100 for nil system_prompt" do
      assert Client.estimate_tokens("short") == 100
      assert Client.estimate_tokens("short", nil) == 100
    end
  end
end
