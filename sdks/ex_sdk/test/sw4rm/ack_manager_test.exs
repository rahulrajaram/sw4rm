defmodule Sw4rm.AckManagerTest do
  use ExUnit.Case, async: true

  alias Sw4rm.AckManager

  setup do
    {:ok, am} = AckManager.start_link(agent_id: "test-agent", ack_timeout_seconds: 1)
    %{am: am}
  end

  describe "track_outgoing/2" do
    test "tracks new outgoing message", %{am: am} do
      assert {:ok, record} = AckManager.track_outgoing(am, "msg-1")
      assert record.message_id == "msg-1"
      assert record.direction == :out
      assert record.stage == :unspecified
    end

    test "rejects duplicate", %{am: am} do
      AckManager.track_outgoing(am, "msg-1")
      assert {:error, {:already_tracked, "msg-1"}} = AckManager.track_outgoing(am, "msg-1")
    end
  end

  describe "track_incoming/2" do
    test "tracks new incoming message", %{am: am} do
      assert {:ok, record} = AckManager.track_incoming(am, "msg-2")
      assert record.direction == :in
      assert record.stage == :received
    end

    test "rejects duplicate", %{am: am} do
      AckManager.track_incoming(am, "msg-2")
      assert {:error, {:already_tracked, "msg-2"}} = AckManager.track_incoming(am, "msg-2")
    end
  end

  describe "update/4" do
    test "updates stage", %{am: am} do
      AckManager.track_outgoing(am, "msg-1")
      assert {:ok, record} = AckManager.update(am, "msg-1", :fulfilled)
      assert record.stage == :fulfilled
    end

    test "updates with error_code and note", %{am: am} do
      AckManager.track_outgoing(am, "msg-1")

      assert {:ok, record} =
               AckManager.update(am, "msg-1", :failed, error_code: :timeout, note: "timed out")

      assert record.error_code == :timeout
      assert record.note == "timed out"
    end

    test "returns error for untracked message", %{am: am} do
      assert {:error, {:not_tracked, "nope"}} = AckManager.update(am, "nope", :fulfilled)
    end
  end

  describe "get_unacked/2" do
    test "returns non-terminal messages", %{am: am} do
      AckManager.track_outgoing(am, "msg-1")
      AckManager.track_outgoing(am, "msg-2")
      AckManager.update(am, "msg-2", :fulfilled)

      unacked = AckManager.get_unacked(am)
      assert length(unacked) == 1
      assert hd(unacked).message_id == "msg-1"
    end

    test "filters by direction", %{am: am} do
      AckManager.track_outgoing(am, "msg-1")
      AckManager.track_incoming(am, "msg-2")

      assert length(AckManager.get_unacked(am, :out)) == 1
      assert length(AckManager.get_unacked(am, :in)) == 1
    end
  end

  describe "remove/2" do
    test "removes tracked message", %{am: am} do
      AckManager.track_outgoing(am, "msg-1")
      record = AckManager.remove(am, "msg-1")
      assert record.message_id == "msg-1"
      assert AckManager.count(am) == 0
    end

    test "returns nil for missing", %{am: am} do
      assert AckManager.remove(am, "nope") == nil
    end
  end

  describe "reconcile_stale/1" do
    test "returns stale non-terminal records", %{am: am} do
      AckManager.track_outgoing(am, "msg-old")
      # Wait for the record to age past the 1-second timeout
      Process.sleep(1100)
      AckManager.track_outgoing(am, "msg-new")

      stale = AckManager.reconcile_stale(am)
      assert length(stale) == 1
      assert hd(stale).message_id == "msg-old"
    end

    test "excludes terminal records from stale", %{am: am} do
      AckManager.track_outgoing(am, "msg-done")
      Process.sleep(1100)
      AckManager.update(am, "msg-done", :fulfilled)

      assert AckManager.reconcile_stale(am) == []
    end
  end

  describe "count/1" do
    test "returns number of tracked messages", %{am: am} do
      assert AckManager.count(am) == 0
      AckManager.track_outgoing(am, "msg-1")
      assert AckManager.count(am) == 1
    end
  end
end
