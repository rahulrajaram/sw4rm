defmodule Sw4rm.HandoffTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Handoff
  alias Sw4rm.Handoff.BudgetEnvelope

  setup do
    {:ok, ho} = Handoff.start_link()
    %{ho: ho}
  end

  describe "request_handoff/2" do
    test "creates a pending handoff", %{ho: ho} do
      req = %{from_agent: "agent-1", to_agent: "agent-2"}
      assert {:ok, handoff_id} = Handoff.request_handoff(ho, req)
      assert is_binary(handoff_id)

      record = Handoff.get(ho, handoff_id)
      assert record.status == :pending
      assert record.from_agent == "agent-1"
      assert record.to_agent == "agent-2"
    end

    test "accepts custom handoff_id", %{ho: ho} do
      req = %{from_agent: "a1", to_agent: "a2", handoff_id: "custom-id"}
      assert {:ok, "custom-id"} = Handoff.request_handoff(ho, req)
    end

    test "rejects when depth budget exceeded", %{ho: ho} do
      budget = %BudgetEnvelope{max_delegation_depth: 2, current_depth: 2}
      req = %{from_agent: "a1", to_agent: "a2", budget: budget}
      assert {:error, :depth_exceeded} = Handoff.request_handoff(ho, req)
    end

    test "allows within depth budget", %{ho: ho} do
      budget = %BudgetEnvelope{max_delegation_depth: 3, current_depth: 1}
      req = %{from_agent: "a1", to_agent: "a2", budget: budget}
      assert {:ok, _id} = Handoff.request_handoff(ho, req)
    end
  end

  describe "accept/2" do
    test "transitions pending to accepted", %{ho: ho} do
      {:ok, id} = Handoff.request_handoff(ho, %{from_agent: "a1", to_agent: "a2"})
      assert {:ok, record} = Handoff.accept(ho, id)
      assert record.status == :accepted
      assert record.accepted_at != nil
    end

    test "fails for non-pending", %{ho: ho} do
      {:ok, id} = Handoff.request_handoff(ho, %{from_agent: "a1", to_agent: "a2"})
      Handoff.accept(ho, id)
      assert {:error, :not_pending} = Handoff.accept(ho, id)
    end

    test "fails for unknown id", %{ho: ho} do
      assert {:error, :not_found} = Handoff.accept(ho, "nope")
    end
  end

  describe "reject/3" do
    test "transitions pending to rejected", %{ho: ho} do
      {:ok, id} = Handoff.request_handoff(ho, %{from_agent: "a1", to_agent: "a2"})
      assert {:ok, record} = Handoff.reject(ho, id, "overloaded")
      assert record.status == :rejected
      assert record.rejection_reason == "overloaded"
    end

    test "fails for non-pending", %{ho: ho} do
      {:ok, id} = Handoff.request_handoff(ho, %{from_agent: "a1", to_agent: "a2"})
      Handoff.accept(ho, id)
      assert {:error, :not_pending} = Handoff.reject(ho, id)
    end
  end

  describe "get_pending/2" do
    test "returns pending handoffs for agent", %{ho: ho} do
      Handoff.request_handoff(ho, %{from_agent: "a1", to_agent: "a2"})
      Handoff.request_handoff(ho, %{from_agent: "a1", to_agent: "a2"})
      Handoff.request_handoff(ho, %{from_agent: "a1", to_agent: "a3"})

      pending = Handoff.get_pending(ho, "a2")
      assert length(pending) == 2
    end

    test "returns empty for unknown agent", %{ho: ho} do
      assert Handoff.get_pending(ho, "nobody") == []
    end

    test "accepted handoffs removed from pending", %{ho: ho} do
      {:ok, id} = Handoff.request_handoff(ho, %{from_agent: "a1", to_agent: "a2"})
      Handoff.accept(ho, id)
      assert Handoff.get_pending(ho, "a2") == []
    end
  end

  describe "complete/3" do
    test "marks handoff as completed", %{ho: ho} do
      {:ok, id} = Handoff.request_handoff(ho, %{from_agent: "a1", to_agent: "a2"})
      Handoff.accept(ho, id)
      assert :ok = Handoff.complete(ho, id, %{output: "done"})

      record = Handoff.get(ho, id)
      assert record.status == :completed
      assert record.result == %{output: "done"}
    end
  end

  describe "cancel_delegation/2" do
    test "cancels handoffs by correlation_id", %{ho: ho} do
      {:ok, id} =
        Handoff.request_handoff(ho, %{
          from_agent: "a1",
          to_agent: "a2",
          correlation_id: "corr-1"
        })

      assert {:ok, _count} = Handoff.cancel_delegation(ho, "corr-1")
      record = Handoff.get(ho, id)
      assert record.status == :cancelled
    end

    test "cascading cancellation through children", %{ho: ho} do
      {:ok, id1} =
        Handoff.request_handoff(ho, %{
          from_agent: "a1",
          to_agent: "a2",
          correlation_id: "parent"
        })

      {:ok, id2} =
        Handoff.request_handoff(ho, %{
          from_agent: "a2",
          to_agent: "a3",
          correlation_id: "child"
        })

      Handoff.register_child(ho, "parent", "child")

      {:ok, count} = Handoff.cancel_delegation(ho, "parent")
      assert count >= 2

      assert Handoff.get(ho, id1).status == :cancelled
      assert Handoff.get(ho, id2).status == :cancelled
    end
  end

  describe "register_child/3" do
    test "registers parent-child relationship", %{ho: ho} do
      assert :ok = Handoff.register_child(ho, "parent-corr", "child-corr")
    end
  end
end
