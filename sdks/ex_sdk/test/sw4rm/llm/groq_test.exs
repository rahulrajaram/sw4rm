defmodule Sw4rm.LLM.GroqTest do
  use ExUnit.Case, async: true

  alias Sw4rm.LLM.Groq

  describe "new/1" do
    test "returns error without any credentials" do
      original = System.get_env("GROQ_API_KEY")
      System.delete_env("GROQ_API_KEY")

      # Only test when no dotfile exists either
      dotfile = Path.expand("~/.groq")

      if not File.exists?(dotfile) do
        assert {:error, {:authentication, msg}} = Groq.new()
        assert msg =~ "No Groq API key"
      end

      if original, do: System.put_env("GROQ_API_KEY", original)
    end

    test "succeeds with explicit api_key" do
      assert {:ok, client} = Groq.new(api_key: "gsk_test_key", rate_limiter: nil)
      assert client.api_key == "gsk_test_key"
      assert client.default_model == "llama-3.3-70b-versatile"
    end

    test "uses custom default_model" do
      {:ok, client} =
        Groq.new(api_key: "gsk_test", default_model: "mixtral-8x7b", rate_limiter: nil)

      assert client.default_model == "mixtral-8x7b"
    end

    test "uses custom timeout" do
      {:ok, client} = Groq.new(api_key: "gsk_test", timeout_ms: 60_000, rate_limiter: nil)
      assert client.timeout_ms == 60_000
    end

    test "reads api_key from environment" do
      original = System.get_env("GROQ_API_KEY")
      System.put_env("GROQ_API_KEY", "gsk_from_env")

      {:ok, client} = Groq.new(rate_limiter: nil)
      assert client.api_key == "gsk_from_env"

      if original do
        System.put_env("GROQ_API_KEY", original)
      else
        System.delete_env("GROQ_API_KEY")
      end
    end

    test "explicit api_key takes precedence over env" do
      original = System.get_env("GROQ_API_KEY")
      System.put_env("GROQ_API_KEY", "gsk_from_env")

      {:ok, client} = Groq.new(api_key: "gsk_explicit", rate_limiter: nil)
      assert client.api_key == "gsk_explicit"

      if original do
        System.put_env("GROQ_API_KEY", original)
      else
        System.delete_env("GROQ_API_KEY")
      end
    end
  end

  describe "struct fields" do
    test "has expected fields" do
      {:ok, client} = Groq.new(api_key: "test", rate_limiter: nil)
      assert Map.has_key?(client, :api_key)
      assert Map.has_key?(client, :default_model)
      assert Map.has_key?(client, :timeout_ms)
      assert Map.has_key?(client, :rate_limiter)
    end
  end
end
