defmodule Sw4rm.AckManager do
  @moduledoc """
  ACK lifecycle manager for message tracking per spec S11.

  GenServer tracking outgoing and incoming message acknowledgements.
  """
  use GenServer

  defmodule Record do
    @moduledoc "ACK tracking record for a single message."
    @type t :: %__MODULE__{}
    defstruct [:message_id, :stage, :error_code, :direction, :timestamp_ms, :note]
  end

  @terminal_stages [:fulfilled, :rejected, :failed, :timed_out]

  # -- Client API --

  @doc "Start the ACK manager. Required: `:agent_id`. Options: `:ack_timeout_seconds` (default 10)."
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Begin tracking an outgoing message by ID. Returns `{:error, {:already_tracked, id}}` if duplicate."
  @spec track_outgoing(GenServer.server(), String.t()) :: {:ok, Record.t()} | {:error, term()}
  def track_outgoing(server, message_id),
    do: GenServer.call(server, {:track_outgoing, message_id})

  @doc "Begin tracking an incoming message by ID. Returns `{:error, {:already_tracked, id}}` if duplicate."
  @spec track_incoming(GenServer.server(), String.t()) :: {:ok, Record.t()} | {:error, term()}
  def track_incoming(server, message_id),
    do: GenServer.call(server, {:track_incoming, message_id})

  @doc "Update the ACK stage for a tracked message. Accepts optional `:error_code` and `:note`."
  @spec update(GenServer.server(), String.t(), atom(), keyword()) ::
          {:ok, Record.t()} | {:error, term()}
  def update(server, message_id, stage, opts \\ []) do
    GenServer.call(server, {:update, message_id, stage, opts})
  end

  @doc "Return all non-terminal records, optionally filtered by `:in` or `:out` direction."
  @spec get_unacked(GenServer.server(), atom() | nil) :: [Record.t()]
  def get_unacked(server, direction \\ nil), do: GenServer.call(server, {:get_unacked, direction})

  @doc "Return records whose age exceeds the configured `:ack_timeout_seconds`."
  @spec reconcile_stale(GenServer.server()) :: [Record.t()]
  def reconcile_stale(server), do: GenServer.call(server, :reconcile_stale)

  @doc "Remove a tracked message by ID. Returns the record or `nil`."
  @spec remove(GenServer.server(), String.t()) :: Record.t() | nil
  def remove(server, message_id), do: GenServer.call(server, {:remove, message_id})

  @doc "Return the total number of tracked messages."
  @spec count(GenServer.server()) :: non_neg_integer()
  def count(server), do: GenServer.call(server, :count)

  # -- Callbacks --

  @impl true
  def init(opts) do
    agent_id = Keyword.fetch!(opts, :agent_id)
    timeout_s = Keyword.get(opts, :ack_timeout_seconds, 10)
    {:ok, %{agent_id: agent_id, pending: %{}, timeout_s: timeout_s}}
  end

  @impl true
  def handle_call({:track_outgoing, mid}, _from, s) do
    if Map.has_key?(s.pending, mid) do
      {:reply, {:error, {:already_tracked, mid}}, s}
    else
      record = %Record{
        message_id: mid,
        stage: :unspecified,
        error_code: :unspecified,
        direction: :out,
        timestamp_ms: System.system_time(:millisecond),
        note: ""
      }

      {:reply, {:ok, record}, %{s | pending: Map.put(s.pending, mid, record)}}
    end
  end

  def handle_call({:track_incoming, mid}, _from, s) do
    if Map.has_key?(s.pending, mid) do
      {:reply, {:error, {:already_tracked, mid}}, s}
    else
      record = %Record{
        message_id: mid,
        stage: :received,
        error_code: :unspecified,
        direction: :in,
        timestamp_ms: System.system_time(:millisecond),
        note: ""
      }

      {:reply, {:ok, record}, %{s | pending: Map.put(s.pending, mid, record)}}
    end
  end

  def handle_call({:update, mid, stage, opts}, _from, s) do
    case Map.get(s.pending, mid) do
      nil ->
        {:reply, {:error, {:not_tracked, mid}}, s}

      record ->
        updated =
          record
          |> Map.put(:stage, stage)
          |> then(fn r ->
            case Keyword.get(opts, :error_code) do
              nil -> r
              ec -> Map.put(r, :error_code, ec)
            end
          end)
          |> then(fn r ->
            case Keyword.get(opts, :note) do
              nil -> r
              n -> Map.put(r, :note, n)
            end
          end)

        {:reply, {:ok, updated}, %{s | pending: Map.put(s.pending, mid, updated)}}
    end
  end

  def handle_call({:get_unacked, direction}, _from, s) do
    result =
      s.pending
      |> Map.values()
      |> Enum.filter(fn r ->
        r.stage not in @terminal_stages and
          (direction == nil or r.direction == direction)
      end)

    {:reply, result, s}
  end

  def handle_call(:reconcile_stale, _from, s) do
    now = System.system_time(:millisecond)
    timeout_ms = s.timeout_s * 1000

    stale =
      s.pending
      |> Map.values()
      |> Enum.filter(fn r ->
        r.stage not in @terminal_stages and now - r.timestamp_ms > timeout_ms
      end)

    {:reply, stale, s}
  end

  def handle_call({:remove, mid}, _from, s) do
    {val, pending} = Map.pop(s.pending, mid)
    {:reply, val, %{s | pending: pending}}
  end

  def handle_call(:count, _from, s), do: {:reply, map_size(s.pending), s}
end
