defmodule Sw4rm.NegotiationEventsTest do
  use ExUnit.Case, async: true

  alias Sw4rm.NegotiationEvents
  alias Sw4rm.NegotiationEvents.Event

  setup do
    {:ok, emitter} = NegotiationEvents.start_link()
    %{emitter: emitter}
  end

  describe "on/off" do
    test "registers and unregisters type-specific listener", %{emitter: em} do
      listener = fn _event -> :ok end
      NegotiationEvents.on(em, :proposal_submitted, listener)
      assert NegotiationEvents.listener_count(em, :proposal_submitted) == 1

      NegotiationEvents.off(em, :proposal_submitted, listener)
      assert NegotiationEvents.listener_count(em, :proposal_submitted) == 0
    end

    test "registers global listener", %{emitter: em} do
      listener = fn _event -> :ok end
      NegotiationEvents.on(em, :all, listener)
      assert NegotiationEvents.listener_count(em, :all) == 1
    end
  end

  describe "emit/1" do
    test "dispatches to type-specific listeners", %{emitter: em} do
      test_pid = self()
      NegotiationEvents.on(em, :proposal_submitted, fn e -> send(test_pid, {:got, e}) end)

      event = %Event{event_type: :proposal_submitted, room_id: "room-1", agent_id: "a1"}
      NegotiationEvents.emit(em, event)

      assert_receive {:got, %Event{event_type: :proposal_submitted}}
    end

    test "dispatches to global listeners", %{emitter: em} do
      test_pid = self()
      NegotiationEvents.on(em, :all, fn e -> send(test_pid, {:global, e}) end)

      event = %Event{event_type: :vote_cast, room_id: "room-1"}
      NegotiationEvents.emit(em, event)

      assert_receive {:global, %Event{event_type: :vote_cast}}
    end

    test "records event in history", %{emitter: em} do
      event = %Event{event_type: :approved, room_id: "room-1"}
      NegotiationEvents.emit(em, event)

      history = NegotiationEvents.history(em)
      assert length(history) == 1
      assert hd(history).event_type == :approved
    end
  end

  describe "emit_event/5" do
    test "creates and emits event", %{emitter: em} do
      test_pid = self()
      NegotiationEvents.on(em, :room_created, fn e -> send(test_pid, {:event, e}) end)

      NegotiationEvents.emit_event(em, :room_created, "room-1", "agent-1", %{desc: "test"})
      assert_receive {:event, %Event{event_type: :room_created, room_id: "room-1"}}
    end
  end

  describe "history/2" do
    test "filters by event_type", %{emitter: em} do
      NegotiationEvents.emit(em, %Event{event_type: :approved, room_id: "r1"})
      NegotiationEvents.emit(em, %Event{event_type: :rejected, room_id: "r1"})

      result = NegotiationEvents.history(em, event_type: :approved)
      assert length(result) == 1
    end

    test "filters by room_id", %{emitter: em} do
      NegotiationEvents.emit(em, %Event{event_type: :approved, room_id: "r1"})
      NegotiationEvents.emit(em, %Event{event_type: :approved, room_id: "r2"})

      result = NegotiationEvents.history(em, room_id: "r1")
      assert length(result) == 1
    end

    test "respects limit", %{emitter: em} do
      for _ <- 1..5, do: NegotiationEvents.emit(em, %Event{event_type: :approved, room_id: "r1"})
      assert length(NegotiationEvents.history(em, limit: 3)) == 3
    end
  end

  describe "clear_history/1" do
    test "removes all history", %{emitter: em} do
      NegotiationEvents.emit(em, %Event{event_type: :approved, room_id: "r1"})
      NegotiationEvents.clear_history(em)
      assert NegotiationEvents.history(em) == []
    end
  end

  describe "clear_listeners/1" do
    test "removes all listeners", %{emitter: em} do
      NegotiationEvents.on(em, :approved, fn _ -> :ok end)
      NegotiationEvents.on(em, :all, fn _ -> :ok end)
      NegotiationEvents.clear_listeners(em)
      assert NegotiationEvents.listener_count(em) == 0
    end
  end

  describe "event_types/0" do
    test "returns list of event types" do
      types = NegotiationEvents.event_types()
      assert :proposal_submitted in types
      assert :room_closed in types
      assert length(types) == 10
    end
  end
end
