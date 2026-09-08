defmodule Sw4rm.Persistence do
  @moduledoc """
  Persistence behaviour with pluggable backends.
  """

  @callback save_records(backend :: term(), records :: list(), opts :: keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}
  @callback load_records(backend :: term(), opts :: keyword()) :: {:ok, list()} | {:error, term()}
  @callback clear_records(backend :: term(), opts :: keyword()) ::
              {:ok, non_neg_integer()} | {:error, term()}
end

defmodule Sw4rm.Persistence.InMemory do
  @moduledoc "In-memory persistence backend (for testing). Uses Agent for state."
  @behaviour Sw4rm.Persistence
  use Agent

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    Agent.start_link(fn -> %{} end, name: name)
  end

  @impl true
  def save_records(agent, records, opts \\ []) do
    ns = Keyword.get(opts, :namespace, "default")
    Agent.update(agent, &Map.put(&1, ns, records))
    {:ok, length(records)}
  end

  @impl true
  def load_records(agent, opts \\ []) do
    ns = Keyword.get(opts, :namespace, "default")
    {:ok, Agent.get(agent, &Map.get(&1, ns, []))}
  end

  @impl true
  def clear_records(agent, opts \\ []) do
    ns = Keyword.get(opts, :namespace, "default")

    count =
      Agent.get_and_update(agent, fn storage ->
        records = Map.get(storage, ns, [])
        {length(records), Map.delete(storage, ns)}
      end)

    {:ok, count}
  end

  def list_namespaces(agent) do
    Agent.get(agent, &Map.keys/1)
  end
end

defmodule Sw4rm.Persistence.JsonFile do
  @moduledoc "JSON file-based persistence backend. GenServer for thread safety."
  @behaviour Sw4rm.Persistence
  use GenServer

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    base_dir = Keyword.get(opts, :base_directory, Path.expand("~/.sw4rm/"))
    GenServer.start_link(__MODULE__, base_dir, name: name)
  end

  @impl Sw4rm.Persistence
  def save_records(server, records, opts \\ []) do
    GenServer.call(server, {:save, records, opts})
  end

  @impl Sw4rm.Persistence
  def load_records(server, opts \\ []) do
    GenServer.call(server, {:load, opts})
  end

  @impl Sw4rm.Persistence
  def clear_records(server, opts \\ []) do
    GenServer.call(server, {:clear, opts})
  end

  def list_namespaces(server), do: GenServer.call(server, :list_namespaces)

  # -- Callbacks --

  @impl true
  def init(base_dir) do
    File.mkdir_p!(base_dir)
    {:ok, %{base_dir: base_dir}}
  end

  @impl true
  def handle_call({:save, records, opts}, _from, s) do
    path = ns_path(s.base_dir, opts)
    dir = Path.dirname(path)

    case Jason.encode(records, pretty: true) do
      {:ok, json} ->
        result = durable_write(path, dir, json)

        reply =
          case result do
            :ok -> {:ok, length(records)}
            {:error, reason} -> {:error, reason}
          end

        {:reply, reply, s}

      {:error, reason} ->
        {:reply, {:error, reason}, s}
    end
  end

  def handle_call({:load, opts}, _from, s) do
    path = ns_path(s.base_dir, opts)

    result =
      case File.read(path) do
        {:ok, content} -> Jason.decode(content)
        {:error, :enoent} -> {:ok, []}
        {:error, reason} -> {:error, reason}
      end

    {:reply, result, s}
  end

  def handle_call({:clear, opts}, _from, s) do
    path = ns_path(s.base_dir, opts)

    count =
      case File.read(path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, records} -> length(records)
            _ -> 0
          end

        _ ->
          0
      end

    result =
      case File.rm(path) do
        :ok -> fsync_directory(Path.dirname(path))
        {:error, :enoent} -> :ok
        {:error, reason} -> {:error, reason}
      end

    reply = if result == :ok, do: {:ok, count}, else: result
    {:reply, reply, s}
  end

  def handle_call(:list_namespaces, _from, s) do
    namespaces =
      case File.ls(s.base_dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.map(&String.trim_trailing(&1, ".json"))

        _ ->
          []
      end

    {:reply, namespaces, s}
  end

  defp ns_path(base_dir, opts) do
    ns = Keyword.get(opts, :namespace, "default")
    Path.join(base_dir, "#{ns}.json")
  end

  # Write, sync, rename, and sync the containing directory.  A rename alone
  # protects readers from partial JSON but does not make the directory entry
  # durable across a crash.
  defp durable_write(path, dir, content) do
    temp_path = Path.rootname(path) <> ".tmp"

    with :ok <- File.mkdir_p(dir),
         {:ok, io} <- File.open(temp_path, [:write, :binary]),
         :ok <- write_and_sync(io, content),
         :ok <- File.close(io),
         :ok <- File.rename(temp_path, path),
         :ok <- fsync_directory(dir) do
      :ok
    else
      {:error, _reason} = error ->
        _ = File.rm(temp_path)
        error
    end
  end

  defp write_and_sync(io, content) do
    with :ok <- IO.binwrite(io, content),
         :ok <- :file.sync(io) do
      :ok
    end
  end

  defp fsync_directory(dir) do
    # :directory is required by the Erlang file driver; ordinary :read
    # rejects directory descriptors with :eisdir.
    case :file.open(String.to_charlist(dir), [:read, :directory]) do
      {:ok, fd} ->
        result = :file.sync(fd)
        _ = :file.close(fd)
        result

      {:error, reason} ->
        {:error, reason}
    end
  end
end
