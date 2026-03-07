defmodule Sw4rm.NegotiationRoomTest do
  use ExUnit.Case, async: true

  alias Sw4rm.NegotiationRoom
  alias Sw4rm.NegotiationRoom.{Proposal, Critique, Store}

  defp force_collection_timeout(room, artifact_id) do
    send(room, {:collection_timeout, artifact_id})
    await_decision(room, artifact_id, 50)
  end

  defp await_decision(_room, _artifact_id, 0), do: flunk("decision was not recorded in time")

  defp await_decision(room, artifact_id, retries) do
    case NegotiationRoom.get_decision(room, artifact_id) do
      nil ->
        Process.sleep(10)
        await_decision(room, artifact_id, retries - 1)

      decision ->
        decision
    end
  end

  describe "NegotiationRoom" do
    setup do
      {:ok, room} = NegotiationRoom.start_link(room_id: "room-1")
      %{room: room}
    end

    test "submit_proposal stores proposal", %{room: room} do
      proposal = %Proposal{artifact_id: "art-1", producer_id: "agent-1", artifact: "code"}
      assert {:ok, "art-1"} = NegotiationRoom.submit_proposal(room, proposal)
    end

    test "rejects duplicate proposal", %{room: room} do
      proposal = %Proposal{artifact_id: "art-1", producer_id: "agent-1"}
      NegotiationRoom.submit_proposal(room, proposal)
      assert {:error, :already_exists} = NegotiationRoom.submit_proposal(room, proposal)
    end

    test "add_critique to existing proposal", %{room: room} do
      NegotiationRoom.submit_proposal(room, %Proposal{artifact_id: "art-1", producer_id: "a1"})
      critique = %Critique{critic_id: "critic-1", score: 8, passed: true}
      assert :ok = NegotiationRoom.add_critique(room, "art-1", critique)
    end

    test "critique fails for unknown artifact", %{room: room} do
      critique = %Critique{critic_id: "c1", score: 5}
      assert {:error, :not_found} = NegotiationRoom.add_critique(room, "nope", critique)
    end

    test "rejects duplicate critique from same critic", %{room: room} do
      NegotiationRoom.submit_proposal(room, %Proposal{artifact_id: "art-1", producer_id: "a1"})
      critique = %Critique{critic_id: "critic-1", score: 8}
      NegotiationRoom.add_critique(room, "art-1", critique)
      assert {:error, :already_voted} = NegotiationRoom.add_critique(room, "art-1", critique)
    end

    test "get_votes returns critiques", %{room: room} do
      NegotiationRoom.submit_proposal(room, %Proposal{artifact_id: "art-1", producer_id: "a1"})
      NegotiationRoom.add_critique(room, "art-1", %Critique{critic_id: "c1", score: 8})
      NegotiationRoom.add_critique(room, "art-1", %Critique{critic_id: "c2", score: 7})

      votes = NegotiationRoom.get_votes(room, "art-1")
      assert length(votes) == 2
    end

    test "decide and get_decision", %{room: room} do
      NegotiationRoom.submit_proposal(room, %Proposal{artifact_id: "art-1", producer_id: "a1"})
      NegotiationRoom.decide(room, "art-1", :approved)
      assert NegotiationRoom.get_decision(room, "art-1") == :approved
    end

    test "list_proposals returns all", %{room: room} do
      NegotiationRoom.submit_proposal(room, %Proposal{artifact_id: "a1", producer_id: "p1"})
      NegotiationRoom.submit_proposal(room, %Proposal{artifact_id: "a2", producer_id: "p2"})
      assert length(NegotiationRoom.list_proposals(room)) == 2
    end

    test "room_info returns summary", %{room: room} do
      info = NegotiationRoom.room_info(room)
      assert info.room_id == "room-1"
      assert info.proposal_count == 0
    end
  end

  describe "SW4-001 vote collection timeout" do
    test "timeout fires and auto-decides with quorum met" do
      {:ok, room} = NegotiationRoom.start_link(room_id: "timeout-quorum-met")

      proposal = %Proposal{
        artifact_id: "art-t1",
        producer_id: "p1",
        requested_critics: ["c1", "c2"],
        vote_collection_timeout_s: 60,
        quorum_policy: %{rule: {:minimum_fraction, 0.5}, on_failure: :fail_closed}
      }

      NegotiationRoom.submit_proposal(room, proposal)
      NegotiationRoom.add_critique(room, "art-t1", %Critique{critic_id: "c1", score: 8})

      decision = force_collection_timeout(room, "art-t1")
      assert decision != nil
      assert decision.quorum_met == true
      assert decision.collection_timeout_reached == true
      assert decision.votes_received == 1
      assert decision.votes_expected == 2
    end

    test "timeout fires and escalates with fail-closed when quorum not met" do
      {:ok, room} = NegotiationRoom.start_link(room_id: "timeout-quorum-fail")

      proposal = %Proposal{
        artifact_id: "art-t2",
        producer_id: "p1",
        requested_critics: ["c1", "c2", "c3"],
        vote_collection_timeout_s: 60,
        quorum_policy: %{rule: {:require_all, true}, on_failure: :fail_closed}
      }

      NegotiationRoom.submit_proposal(room, proposal)
      NegotiationRoom.add_critique(room, "art-t2", %Critique{critic_id: "c1", score: 8})

      decision = force_collection_timeout(room, "art-t2")
      assert decision.quorum_met == false
      assert decision.outcome == :escalated_to_hitl

      assert decision.unavailable_critics == ["c2", "c3"] or
               Enum.sort(decision.unavailable_critics) == ["c2", "c3"]
    end

    test "late votes after timeout are stored but don't affect decision" do
      {:ok, room} = NegotiationRoom.start_link(room_id: "timeout-late")

      proposal = %Proposal{
        artifact_id: "art-t3",
        producer_id: "p1",
        requested_critics: ["c1", "c2"],
        vote_collection_timeout_s: 60,
        quorum_policy: %{rule: {:minimum_fraction, 0.5}, on_failure: :fail_closed}
      }

      NegotiationRoom.submit_proposal(room, proposal)
      NegotiationRoom.add_critique(room, "art-t3", %Critique{critic_id: "c1", score: 8})

      decision_before = force_collection_timeout(room, "art-t3")
      assert decision_before != nil

      # Late vote — accepted but marked as late
      assert {:ok, :late_vote} =
               NegotiationRoom.add_critique(room, "art-t3", %Critique{critic_id: "c2", score: 9})

      # Decision unchanged
      decision_after = NegotiationRoom.get_decision(room, "art-t3")
      assert decision_after.votes_received == decision_before.votes_received
    end

    test "quorum evaluation at decision time with default policy" do
      {:ok, room} = NegotiationRoom.start_link(room_id: "timeout-default")

      proposal = %Proposal{
        artifact_id: "art-t4",
        producer_id: "p1",
        requested_critics: ["c1", "c2"],
        vote_collection_timeout_s: 60
      }

      NegotiationRoom.submit_proposal(room, proposal)
      NegotiationRoom.add_critique(room, "art-t4", %Critique{critic_id: "c1", score: 7})

      decision = force_collection_timeout(room, "art-t4")
      # Default policy: minimum_fraction 0.5 → 1 of 2 is enough
      assert decision.quorum_met == true
    end
  end

  describe "Store" do
    setup do
      {:ok, store} = Store.start_link()
      %{store: store}
    end

    test "create_room starts a new room", %{store: store} do
      assert {:ok, pid} = Store.create_room(store, "store-room-1")
      assert is_pid(pid)
    end

    test "rejects duplicate room", %{store: store} do
      Store.create_room(store, "store-room-dup")
      assert {:error, :already_exists} = Store.create_room(store, "store-room-dup")
    end

    test "get_room returns pid", %{store: store} do
      Store.create_room(store, "store-room-get")
      assert is_pid(Store.get_room(store, "store-room-get"))
    end

    test "get_room returns nil for missing", %{store: store} do
      assert Store.get_room(store, "nope") == nil
    end

    test "close_room stops the process", %{store: store} do
      {:ok, pid} = Store.create_room(store, "store-room-close")
      assert :ok = Store.close_room(store, "store-room-close")
      refute Process.alive?(pid)
    end

    test "close_room returns error for missing", %{store: store} do
      assert {:error, :not_found} = Store.close_room(store, "nope")
    end

    test "list_rooms returns room ids", %{store: store} do
      Store.create_room(store, "store-r1")
      Store.create_room(store, "store-r2")
      rooms = Store.list_rooms(store)
      assert Enum.sort(rooms) == ["store-r1", "store-r2"]
    end
  end
end
