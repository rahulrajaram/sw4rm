defmodule Sw4rm.Interceptor do
  @moduledoc """
  Interceptor behaviour and chain for request/response processing.
  """

  @callback name() :: String.t()
  @callback on_request(request :: term(), context :: map()) :: term()
  @callback on_response(response :: term(), context :: map()) :: term()
end

defmodule Sw4rm.Interceptor.Chain do
  @moduledoc """
  Functional interceptor chain. Interceptors applied in order for requests,
  reverse order for responses.
  """

  @type t :: %__MODULE__{}
  defstruct interceptors: [], enabled: true

  @doc "Create a new empty chain."
  def new(opts \\ []) do
    %__MODULE__{
      interceptors: Keyword.get(opts, :interceptors, []),
      enabled: Keyword.get(opts, :enabled, true)
    }
  end

  @doc "Add an interceptor module to the end of the chain."
  def add(%__MODULE__{} = chain, interceptor) do
    %{chain | interceptors: chain.interceptors ++ [interceptor]}
  end

  @doc "Add an interceptor to the beginning of the chain."
  def prepend(%__MODULE__{} = chain, interceptor) do
    %{chain | interceptors: [interceptor | chain.interceptors]}
  end

  @doc "Remove an interceptor from the chain."
  def remove(%__MODULE__{} = chain, interceptor) do
    %{chain | interceptors: List.delete(chain.interceptors, interceptor)}
  end

  @doc "Process a request through all interceptors in order."
  def process_request(%__MODULE__{enabled: false}, request), do: request

  def process_request(%__MODULE__{interceptors: interceptors}, request) do
    context = %{}

    Enum.reduce(interceptors, request, fn interceptor, req ->
      interceptor.on_request(req, context)
    end)
  end

  @doc "Process a response through all interceptors in reverse order."
  def process_response(%__MODULE__{enabled: false}, response), do: response

  def process_response(%__MODULE__{interceptors: interceptors}, response) do
    context = %{}

    interceptors
    |> Enum.reverse()
    |> Enum.reduce(response, fn interceptor, resp ->
      interceptor.on_response(resp, context)
    end)
  end
end

defmodule Sw4rm.Interceptor.Timing do
  @moduledoc "Example interceptor demonstrating the interceptor API. Context mutations are not threaded through the chain, so timing data is discarded."
  @behaviour Sw4rm.Interceptor

  @impl true
  def name, do: "timing"

  @impl true
  def on_request(request, context) do
    Map.put(context, :start_time, System.monotonic_time(:millisecond))
    request
  end

  @impl true
  def on_response(response, _context), do: response
end

defmodule Sw4rm.Interceptor.Logging do
  @moduledoc "Interceptor that logs requests and responses."
  @behaviour Sw4rm.Interceptor
  require Logger

  @impl true
  def name, do: "logging"

  @impl true
  def on_request(request, _context) do
    Logger.info("SW4RM Request: #{inspect(request, limit: 200)}")
    request
  end

  @impl true
  def on_response(response, _context) do
    Logger.info("SW4RM Response: #{inspect(response, limit: 200)}")
    response
  end
end

defmodule Sw4rm.Interceptor.Header do
  @moduledoc "Interceptor that adds custom headers to requests."
  @behaviour Sw4rm.Interceptor

  @impl true
  def name, do: "header"

  @impl true
  def on_request(request, _context) when is_map(request) do
    headers = Application.get_env(:sw4rm_sdk, :interceptor_headers, %{})
    Map.merge(request, headers)
  end

  def on_request(request, _context), do: request

  @impl true
  def on_response(response, _context), do: response
end
