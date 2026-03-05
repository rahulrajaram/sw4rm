defmodule Sw4rm.Transport.ChannelManager do
  @moduledoc """
  GenServer managing gRPC channels (one per service endpoint).

  Lazy connection on first `get_channel/2`, with reconnect and disconnect support.
  """
  use GenServer

  # -- Client API --

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Get or create a gRPC channel for the given service endpoint."
  @spec get_channel(GenServer.server(), String.t()) :: {:ok, GRPC.Channel.t()} | {:error, term()}
  def get_channel(server, endpoint) do
    GenServer.call(server, {:get_channel, endpoint})
  end

  @doc "Force reconnect to a specific endpoint."
  @spec reconnect(GenServer.server(), String.t()) :: {:ok, GRPC.Channel.t()} | {:error, term()}
  def reconnect(server, endpoint) do
    GenServer.call(server, {:reconnect, endpoint})
  end

  @doc "Disconnect all channels."
  @spec disconnect_all(GenServer.server()) :: :ok
  def disconnect_all(server), do: GenServer.call(server, :disconnect_all)

  @doc "List all connected endpoints."
  @spec connected_endpoints(GenServer.server()) :: [String.t()]
  def connected_endpoints(server), do: GenServer.call(server, :connected_endpoints)

  # -- Callbacks --

  @impl true
  def init(_opts), do: {:ok, %{channels: %{}}}

  @impl true
  def handle_call({:get_channel, endpoint}, _from, s) do
    case Map.get(s.channels, endpoint) do
      nil ->
        case connect(endpoint) do
          {:ok, channel} ->
            {:reply, {:ok, channel}, %{s | channels: Map.put(s.channels, endpoint, channel)}}

          {:error, _} = err ->
            {:reply, err, s}
        end

      channel ->
        {:reply, {:ok, channel}, s}
    end
  end

  def handle_call({:reconnect, endpoint}, _from, s) do
    case Map.get(s.channels, endpoint) do
      nil -> :ok
      old -> GRPC.Stub.disconnect(old)
    end

    case connect(endpoint) do
      {:ok, channel} ->
        {:reply, {:ok, channel}, %{s | channels: Map.put(s.channels, endpoint, channel)}}

      {:error, _} = err ->
        {:reply, err, %{s | channels: Map.delete(s.channels, endpoint)}}
    end
  end

  def handle_call(:disconnect_all, _from, s) do
    Enum.each(s.channels, fn {_ep, ch} ->
      try do
        GRPC.Stub.disconnect(ch)
      rescue
        _ -> :ok
      end
    end)

    {:reply, :ok, %{s | channels: %{}}}
  end

  def handle_call(:connected_endpoints, _from, s) do
    {:reply, Map.keys(s.channels), s}
  end

  @impl true
  def terminate(_reason, s) do
    Enum.each(s.channels, fn {_ep, ch} ->
      try do
        GRPC.Stub.disconnect(ch)
      rescue
        _ -> :ok
      end
    end)
  end

  # -- Helpers --

  defp connect(endpoint) do
    # Parse endpoint URL to extract host:port
    uri = URI.parse(endpoint)
    host = uri.host || "localhost"
    port = uri.port || 50051
    target = "#{host}:#{port}"

    try do
      GRPC.Stub.connect(target)
    rescue
      e -> {:error, e}
    end
  end
end
