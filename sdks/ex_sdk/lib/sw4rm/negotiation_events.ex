defmodule Sw4rm.NegotiationEvents do
  @moduledoc """
  GenServer-based event emitter for negotiation room activities.

  Uses Registry-backed PubSub for event dispatch.
  """
  use GenServer

  @event_types ~w(
    proposal_submitted critique_added vote_cast round_complete
    approved rejected participant_joined participant_left
    room_created room_closed
  )a

  defmodule Event do
    @moduledoc "Negotiation event."
    @type t :: %__MODULE__{}
    defstruct [:event_id, :event_type, :room_id, :agent_id, :timestamp, :data]
  end

  # -- Client API --

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    max_history = Keyword.get(opts, :max_history, 1000)
    GenServer.start_link(__MODULE__, max_history, name: name)
  end

  @doc "Register a listener for a specific event type or `:all`."
  def on(server, event_type, listener) when is_function(listener, 1) do
    GenServer.call(server, {:on, event_type, listener})
  end

  @doc "Unregister a listener."
  def off(server, event_type, listener) do
    GenServer.call(server, {:off, event_type, listener})
  end

  @doc "Emit a pre-built event."
  def emit(server, %Event{} = event), do: GenServer.call(server, {:emit, event})

  @doc "Create and emit an event."
  def emit_event(server, event_type, room_id, agent_id, data) do
    event = %Event{
      event_id: "event-#{System.system_time(:millisecond)}-#{:rand.uniform(1_000_000)}",
      event_type: event_type,
      room_id: room_id,
      agent_id: agent_id,
      timestamp: System.system_time(:second),
      data: data
    }

    emit(server, event)
  end

  @doc "Get event history with optional filters."
  def history(server, opts \\ []), do: GenServer.call(server, {:history, opts})

  @doc "Clear all event history."
  def clear_history(server), do: GenServer.call(server, :clear_history)

  @doc "Clear all listeners."
  def clear_listeners(server), do: GenServer.call(server, :clear_listeners)

  @doc "Count registered listeners."
  def listener_count(server, event_type \\ nil) do
    GenServer.call(server, {:listener_count, event_type})
  end

  @doc "Return the list of valid negotiation event type atoms."
  def event_types, do: @event_types

  # -- Callbacks --

  @impl true
  def init(max_history) do
    {:ok,
     %{
       listeners: %{},
       global_listeners: [],
       history: [],
       max_history: max_history
     }}
  end

  @impl true
  def handle_call({:on, :all, listener}, _from, s) do
    {:reply, :ok, %{s | global_listeners: [listener | s.global_listeners]}}
  end

  def handle_call({:on, event_type, listener}, _from, s) do
    listeners = Map.update(s.listeners, event_type, [listener], &[listener | &1])
    {:reply, :ok, %{s | listeners: listeners}}
  end

  def handle_call({:off, :all, listener}, _from, s) do
    {:reply, :ok, %{s | global_listeners: List.delete(s.global_listeners, listener)}}
  end

  def handle_call({:off, event_type, listener}, _from, s) do
    listeners = Map.update(s.listeners, event_type, [], &List.delete(&1, listener))
    {:reply, :ok, %{s | listeners: listeners}}
  end

  def handle_call({:emit, event}, _from, s) do
    history = Enum.take([event | s.history], s.max_history)

    type_listeners = Map.get(s.listeners, event.event_type, [])
    Enum.each(type_listeners, fn l -> safe_call(l, event) end)
    Enum.each(s.global_listeners, fn l -> safe_call(l, event) end)

    {:reply, event, %{s | history: history}}
  end

  def handle_call({:history, opts}, _from, s) do
    result = s.history
    event_type = Keyword.get(opts, :event_type)
    room_id = Keyword.get(opts, :room_id)
    limit = Keyword.get(opts, :limit)

    result = if event_type, do: Enum.filter(result, &(&1.event_type == event_type)), else: result
    result = if room_id, do: Enum.filter(result, &(&1.room_id == room_id)), else: result
    result = if limit, do: Enum.take(result, limit), else: result

    {:reply, result, s}
  end

  def handle_call(:clear_history, _from, s), do: {:reply, :ok, %{s | history: []}}

  def handle_call(:clear_listeners, _from, s) do
    {:reply, :ok, %{s | listeners: %{}, global_listeners: []}}
  end

  def handle_call({:listener_count, nil}, _from, s) do
    type_count = s.listeners |> Map.values() |> Enum.map(&length/1) |> Enum.sum()
    {:reply, type_count + length(s.global_listeners), s}
  end

  def handle_call({:listener_count, :all}, _from, s) do
    {:reply, length(s.global_listeners), s}
  end

  def handle_call({:listener_count, event_type}, _from, s) do
    {:reply, length(Map.get(s.listeners, event_type, [])), s}
  end

  defp safe_call(listener, event) do
    listener.(event)
  rescue
    e ->
      require Logger
      Logger.warning("Error in event listener: #{inspect(e)}")
  end
end
