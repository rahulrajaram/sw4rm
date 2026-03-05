defmodule Sw4rm.Envelope.SequenceTracker do
  @moduledoc """
  GenServer-based monotonic sequence number generator.

  Uses OTP process isolation for thread-safe sequence tracking.
  """
  use GenServer

  # -- Client API --

  @doc "Start a sequence tracker. Options: `:start` (default 1)."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    start = Keyword.get(opts, :start, 1)
    GenServer.start_link(__MODULE__, start - 1, name: name)
  end

  @doc "Get the next sequence number."
  @spec next(GenServer.server()) :: pos_integer()
  def next(server), do: GenServer.call(server, :next)

  # -- Callbacks --

  @impl true
  def init(counter), do: {:ok, counter}

  @impl true
  def handle_call(:next, _from, counter) do
    next_val = counter + 1
    {:reply, next_val, next_val}
  end
end
