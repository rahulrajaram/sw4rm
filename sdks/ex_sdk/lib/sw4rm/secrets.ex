defmodule Sw4rm.Secrets do
  @moduledoc """
  Secret management with pluggable backends.
  """

  @callback get_secret(backend :: term(), key :: String.t()) :: String.t() | nil
  @callback set_secret(backend :: term(), key :: String.t(), value :: String.t()) ::
              :ok | {:error, term()}
  @callback delete_secret(backend :: term(), key :: String.t()) :: boolean()
  @callback list_secrets(backend :: term()) :: [String.t()]
end

defmodule Sw4rm.Secrets.EnvBackend do
  @moduledoc "Read-only secret backend reading from environment variables with a configurable prefix."
  @behaviour Sw4rm.Secrets

  defstruct prefix: "SW4RM_SECRET_"

  @impl true
  def get_secret(%__MODULE__{prefix: prefix}, key) do
    System.get_env("#{prefix}#{String.upcase(key)}")
  end

  @impl true
  def set_secret(_, _, _), do: {:error, :read_only}

  @impl true
  def delete_secret(_, _), do: false

  @impl true
  def list_secrets(_), do: []
end

defmodule Sw4rm.Secrets.FileBackend do
  @moduledoc "File-based secret backend storing secrets in a JSON file. GenServer for thread safety."
  @behaviour Sw4rm.Secrets
  use GenServer

  defstruct [:file_path, :cache]

  # -- Client API --

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    file_path = Keyword.get(opts, :file_path, Path.expand("~/.secrets.json"))
    GenServer.start_link(__MODULE__, file_path, name: name)
  end

  @impl Sw4rm.Secrets
  def get_secret(server, key), do: GenServer.call(server, {:get, key})

  @impl Sw4rm.Secrets
  def set_secret(server, key, value), do: GenServer.call(server, {:set, key, value})

  @impl Sw4rm.Secrets
  def delete_secret(server, key), do: GenServer.call(server, {:delete, key})

  @impl Sw4rm.Secrets
  def list_secrets(server), do: GenServer.call(server, :list)

  # -- Callbacks --

  @impl true
  def init(file_path) do
    cache = load_from_file(file_path)
    {:ok, %{file_path: file_path, cache: cache}}
  end

  @impl true
  def handle_call({:get, key}, _from, s), do: {:reply, Map.get(s.cache, key), s}

  def handle_call({:set, key, value}, _from, s) do
    cache = Map.put(s.cache, key, value)
    save_to_file(s.file_path, cache)
    {:reply, :ok, %{s | cache: cache}}
  end

  def handle_call({:delete, key}, _from, s) do
    if Map.has_key?(s.cache, key) do
      cache = Map.delete(s.cache, key)
      save_to_file(s.file_path, cache)
      {:reply, true, %{s | cache: cache}}
    else
      {:reply, false, s}
    end
  end

  def handle_call(:list, _from, s), do: {:reply, Map.keys(s.cache), s}

  # -- Helpers --

  defp load_from_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} when is_list(data) ->
            Enum.into(data, %{}, fn entry ->
              {Map.get(entry, "key", ""), Map.get(entry, "value", "")}
            end)

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp save_to_file(path, cache) do
    entries = Enum.map(cache, fn {k, v} -> %{"key" => k, "value" => v} end)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(entries, pretty: true))
  end
end

defmodule Sw4rm.Secrets.Resolver do
  @moduledoc """
  Ordered backend chain that queries multiple secret backends.
  First backend to return a value wins.
  """

  defstruct backends: [], fallback: nil

  @doc "Create a resolver with the given backends."
  def new(backends, opts \\ []) do
    %__MODULE__{
      backends: backends,
      fallback: Keyword.get(opts, :fallback)
    }
  end

  @doc "Resolve a secret by querying backends in order."
  def resolve(%__MODULE__{backends: backends, fallback: fallback}, key) do
    Enum.find_value(backends, fallback, fn
      %Sw4rm.Secrets.EnvBackend{} = b ->
        Sw4rm.Secrets.EnvBackend.get_secret(b, key)

      pid when is_pid(pid) ->
        Sw4rm.Secrets.FileBackend.get_secret(pid, key)

      {mod, server} ->
        mod.get_secret(server, key)
    end)
  end
end
