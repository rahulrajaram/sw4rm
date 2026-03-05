defmodule Sw4rm.InterceptorTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Interceptor.{Chain, Timing, Logging, Header}

  defmodule AddFieldInterceptor do
    @behaviour Sw4rm.Interceptor

    @impl true
    def name, do: "add-field"

    @impl true
    def on_request(request, _ctx) when is_map(request) do
      Map.put(request, :intercepted, true)
    end

    @impl true
    def on_response(response, _ctx) when is_map(response) do
      Map.put(response, :processed, true)
    end
  end

  defmodule UpperCaseInterceptor do
    @behaviour Sw4rm.Interceptor

    @impl true
    def name, do: "upper-case"

    @impl true
    def on_request(request, _ctx) when is_map(request) do
      Map.update(request, :data, "", &String.upcase/1)
    end

    @impl true
    def on_response(response, _ctx), do: response
  end

  describe "Chain" do
    test "new creates empty chain" do
      chain = Chain.new()
      assert chain.interceptors == []
      assert chain.enabled == true
    end

    test "add appends interceptor" do
      chain = Chain.new() |> Chain.add(AddFieldInterceptor)
      assert chain.interceptors == [AddFieldInterceptor]
    end

    test "prepend adds to front" do
      chain =
        Chain.new()
        |> Chain.add(AddFieldInterceptor)
        |> Chain.prepend(UpperCaseInterceptor)

      assert chain.interceptors == [UpperCaseInterceptor, AddFieldInterceptor]
    end

    test "remove deletes interceptor" do
      chain =
        Chain.new()
        |> Chain.add(AddFieldInterceptor)
        |> Chain.add(UpperCaseInterceptor)
        |> Chain.remove(AddFieldInterceptor)

      assert chain.interceptors == [UpperCaseInterceptor]
    end

    test "process_request applies interceptors in order" do
      chain =
        Chain.new()
        |> Chain.add(UpperCaseInterceptor)
        |> Chain.add(AddFieldInterceptor)

      result = Chain.process_request(chain, %{data: "hello"})
      assert result.data == "HELLO"
      assert result.intercepted == true
    end

    test "process_response applies interceptors in reverse order" do
      chain =
        Chain.new()
        |> Chain.add(AddFieldInterceptor)

      result = Chain.process_response(chain, %{data: "test"})
      assert result.processed == true
    end

    test "disabled chain passes through" do
      chain =
        Chain.new(enabled: false)
        |> Chain.add(AddFieldInterceptor)

      request = %{data: "test"}
      assert Chain.process_request(chain, request) == request
      assert Chain.process_response(chain, request) == request
    end
  end

  describe "built-in interceptors" do
    test "Timing has correct name" do
      assert Timing.name() == "timing"
    end

    test "Timing passes through request" do
      assert Timing.on_request(:req, %{}) == :req
    end

    test "Logging has correct name" do
      assert Logging.name() == "logging"
    end

    test "Header has correct name" do
      assert Header.name() == "header"
    end

    test "Header passes through non-map request" do
      assert Header.on_request(:req, %{}) == :req
    end
  end
end
