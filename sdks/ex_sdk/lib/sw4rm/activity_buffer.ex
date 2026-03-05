defmodule Sw4rm.ActivityBuffer do
  @moduledoc """
  Activity buffer for tracking agent activities per SW4RM spec S10.

  GenServer managing in-flight operations with capacity enforcement.
  """
  use GenServer

  defmodule Entry do
    @moduledoc "A single activity entry."
    @type t :: %__MODULE__{}
    defstruct [:task_id, :repo_id, :worktree_id, :branch, :timestamp, :description]
  end

  # -- Client API --

  @doc "Start the activity buffer. Options: `:max_items` (default 1000)."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    max_items = Keyword.get(opts, :max_items, 1000)
    GenServer.start_link(__MODULE__, max_items, name: name)
  end

  @doc "Insert or update an activity entry. Returns `{:ok, entry}` or `{:error, %BufferFull{}}`."
  @spec upsert(GenServer.server(), keyword()) ::
          {:ok, Entry.t()} | {:error, Sw4rm.Error.BufferFull.t()}
  def upsert(server, opts), do: GenServer.call(server, {:upsert, opts})

  @doc "Remove an activity entry by key fields."
  @spec remove(GenServer.server(), String.t() | nil, String.t() | nil, String.t() | nil) ::
          boolean()
  def remove(server, task_id, repo_id, worktree_id) do
    GenServer.call(server, {:remove, activity_key(task_id, repo_id, worktree_id)})
  end

  @doc "Get an activity entry by key fields."
  @spec get(GenServer.server(), String.t() | nil, String.t() | nil, String.t() | nil) ::
          Entry.t() | nil
  def get(server, task_id, repo_id, worktree_id) do
    GenServer.call(server, {:get, activity_key(task_id, repo_id, worktree_id)})
  end

  @doc "List activities matching optional filters."
  @spec list(GenServer.server(), keyword()) :: [Entry.t()]
  def list(server, filters \\ []), do: GenServer.call(server, {:list, filters})

  @doc "Get the most recent activities."
  @spec recent(GenServer.server(), non_neg_integer()) :: [Entry.t()]
  def recent(server, limit \\ 10), do: GenServer.call(server, {:recent, limit})

  @doc "Purge entries for completed, failed, or absent task IDs. Returns count removed."
  @spec reconcile(GenServer.server(), %{String.t() => atom()}) :: non_neg_integer()
  def reconcile(server, task_states), do: GenServer.call(server, {:reconcile, task_states})

  @doc "Remove all entries. Returns count removed."
  @spec clear(GenServer.server()) :: non_neg_integer()
  def clear(server), do: GenServer.call(server, :clear)

  @doc "Current number of entries."
  @spec size(GenServer.server()) :: non_neg_integer()
  def size(server), do: GenServer.call(server, :size)

  # -- Callbacks --

  @impl true
  def init(max_items), do: {:ok, %{entries: %{}, max_items: max_items}}

  @impl true
  def handle_call({:upsert, opts}, _from, s) do
    entry = %Entry{
      task_id: Keyword.get(opts, :task_id),
      repo_id: Keyword.get(opts, :repo_id),
      worktree_id: Keyword.get(opts, :worktree_id),
      branch: Keyword.get(opts, :branch),
      timestamp: System.system_time(:second),
      description: Keyword.get(opts, :description)
    }

    key = activity_key(entry.task_id, entry.repo_id, entry.worktree_id)
    existing = Map.get(s.entries, key)

    cond do
      existing != nil ->
        {:reply, {:ok, entry}, %{s | entries: Map.put(s.entries, key, entry)}}

      map_size(s.entries) >= s.max_items ->
        error =
          Sw4rm.Error.BufferFull.exception(
            message: "Activity buffer at capacity (#{map_size(s.entries)}/#{s.max_items})",
            current_size: map_size(s.entries),
            max_size: s.max_items
          )

        {:reply, {:error, error}, s}

      true ->
        {:reply, {:ok, entry}, %{s | entries: Map.put(s.entries, key, entry)}}
    end
  end

  def handle_call({:remove, key}, _from, s) do
    {val, entries} = Map.pop(s.entries, key)
    {:reply, val != nil, %{s | entries: entries}}
  end

  def handle_call({:get, key}, _from, s), do: {:reply, Map.get(s.entries, key), s}

  def handle_call({:list, filters}, _from, s) do
    task_id = Keyword.get(filters, :task_id)
    repo_id = Keyword.get(filters, :repo_id)

    result =
      s.entries
      |> Map.values()
      |> Enum.filter(fn e ->
        (task_id == nil or e.task_id == task_id) and
          (repo_id == nil or e.repo_id == repo_id)
      end)

    {:reply, result, s}
  end

  def handle_call({:recent, limit}, _from, s) do
    result =
      s.entries
      |> Map.values()
      |> Enum.sort_by(& &1.timestamp, :desc)
      |> Enum.take(limit)

    {:reply, result, s}
  end

  def handle_call({:reconcile, task_states}, _from, s) do
    {keep, removed} =
      Enum.split_with(s.entries, fn {_key, entry} ->
        case Map.get(task_states, entry.task_id) do
          nil -> false
          :completed -> false
          :failed -> false
          _ -> true
        end
      end)

    {:reply, length(removed), %{s | entries: Map.new(keep)}}
  end

  def handle_call(:clear, _from, s) do
    count = map_size(s.entries)
    {:reply, count, %{s | entries: %{}}}
  end

  def handle_call(:size, _from, s), do: {:reply, map_size(s.entries), s}

  # -- Helpers --

  defp activity_key(task_id, repo_id, worktree_id) do
    "#{task_id || ""}/#{repo_id || ""}/#{worktree_id || ""}"
  end
end
