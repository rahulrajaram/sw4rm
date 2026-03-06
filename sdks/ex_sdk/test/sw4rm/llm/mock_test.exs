defmodule Sw4rm.LLM.MockTest do
  use ExUnit.Case, async: true

  alias Sw4rm.LLM.Mock

  setup do
    {:ok, mock} = Mock.start_link(responses: ["Alpha", "Beta", "Gamma"])
    on_exit(fn -> if Process.alive?(mock), do: Mock.stop(mock) end)
    %{mock: mock}
  end

  describe "query/2" do
    test "returns first response", %{mock: mock} do
      {:ok, resp} = Mock.query("hello", client: mock)
      assert resp.content == "Alpha"
    end

    test "cycles through responses", %{mock: mock} do
      {:ok, r1} = Mock.query("a", client: mock)
      {:ok, r2} = Mock.query("b", client: mock)
      {:ok, r3} = Mock.query("c", client: mock)
      {:ok, r4} = Mock.query("d", client: mock)

      assert r1.content == "Alpha"
      assert r2.content == "Beta"
      assert r3.content == "Gamma"
      assert r4.content == "Alpha"
    end

    test "returns model in response", %{mock: mock} do
      {:ok, resp} = Mock.query("test", client: mock)
      assert resp.model == "mock-model"
    end

    test "overrides model via option", %{mock: mock} do
      {:ok, resp} = Mock.query("test", client: mock, model: "custom-model")
      assert resp.model == "custom-model"
    end

    test "includes usage data", %{mock: mock} do
      {:ok, resp} = Mock.query("test", client: mock)
      assert is_map(resp.usage)
      assert resp.usage.input_tokens >= 1
      assert resp.usage.output_tokens >= 1
    end

    test "includes metadata", %{mock: mock} do
      {:ok, resp} = Mock.query("test", client: mock)
      assert resp.metadata.provider == "mock"
      assert resp.metadata.mock == true
    end
  end

  describe "call_count/1" do
    test "starts at zero", %{mock: mock} do
      assert Mock.call_count(mock) == 0
    end

    test "increments on each query", %{mock: mock} do
      Mock.query("a", client: mock)
      Mock.query("b", client: mock)
      assert Mock.call_count(mock) == 2
    end
  end

  describe "call_history/1" do
    test "records prompt and options", %{mock: mock} do
      Mock.query("my prompt", client: mock, system_prompt: "sys", max_tokens: 512)
      [call] = Mock.call_history(mock)
      assert call.prompt == "my prompt"
      assert call.system_prompt == "sys"
      assert call.max_tokens == 512
    end

    test "records multiple calls in order", %{mock: mock} do
      Mock.query("first", client: mock)
      Mock.query("second", client: mock)
      history = Mock.call_history(mock)
      assert length(history) == 2
      assert Enum.at(history, 0).prompt == "first"
      assert Enum.at(history, 1).prompt == "second"
    end
  end

  describe "reset/1" do
    test "resets count, history, and response index", %{mock: mock} do
      Mock.query("a", client: mock)
      Mock.query("b", client: mock)
      Mock.reset(mock)

      assert Mock.call_count(mock) == 0
      assert Mock.call_history(mock) == []

      # After reset, should start from first response again
      {:ok, resp} = Mock.query("c", client: mock)
      assert resp.content == "Alpha"
    end
  end

  describe "stream_query/2" do
    test "returns word chunks", %{mock: mock} do
      {:ok, chunks} = Mock.stream_query("test", client: mock)
      assert is_list(chunks)
      joined = Enum.join(chunks)
      assert joined == "Alpha"
    end

    test "multi-word response splits into chunks" do
      {:ok, mock} = Mock.start_link(responses: ["Hello World Today"])
      {:ok, chunks} = Mock.stream_query("test", client: mock)
      assert length(chunks) == 3
      assert Enum.join(chunks) == "Hello World Today"
      Mock.stop(mock)
    end
  end

  describe "default response" do
    test "echoes prompt when no responses configured" do
      {:ok, mock} = Mock.start_link()
      {:ok, resp} = Mock.query("my question", client: mock)
      assert resp.content == "Mock response to: my question"
      Mock.stop(mock)
    end
  end

  describe "response_fn" do
    test "uses function to generate content" do
      {:ok, mock} = Mock.start_link(response_fn: fn p -> String.upcase(p) end)
      {:ok, resp} = Mock.query("hello", client: mock)
      assert resp.content == "HELLO"
      Mock.stop(mock)
    end

    test "response_fn takes precedence over responses list" do
      {:ok, mock} =
        Mock.start_link(
          responses: ["ignored"],
          response_fn: fn _ -> "from fn" end
        )

      {:ok, resp} = Mock.query("test", client: mock)
      assert resp.content == "from fn"
      Mock.stop(mock)
    end
  end

  describe "custom default_model" do
    test "uses provided default_model" do
      {:ok, mock} = Mock.start_link(default_model: "my-custom-model")
      {:ok, resp} = Mock.query("test", client: mock)
      assert resp.model == "my-custom-model"
      Mock.stop(mock)
    end
  end
end
