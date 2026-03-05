defmodule Sw4rm.ActivityBufferTest do
  use ExUnit.Case, async: true

  alias Sw4rm.ActivityBuffer
  alias Sw4rm.ActivityBuffer.Entry

  setup do
    {:ok, buf} = ActivityBuffer.start_link(max_items: 5)
    %{buf: buf}
  end

  describe "upsert/2" do
    test "inserts new entry", %{buf: buf} do
      assert {:ok, %Entry{task_id: "t1"}} =
               ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1", description: "work")
    end

    test "updates existing entry", %{buf: buf} do
      ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1")

      assert {:ok, %Entry{description: "updated"}} =
               ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1", description: "updated")

      assert ActivityBuffer.size(buf) == 1
    end

    test "returns error when at capacity", %{buf: buf} do
      for i <- 1..5 do
        ActivityBuffer.upsert(buf, task_id: "t#{i}", repo_id: "r1")
      end

      assert {:error, %Sw4rm.Error.BufferFull{}} =
               ActivityBuffer.upsert(buf, task_id: "t6", repo_id: "r1")
    end

    test "allows upsert of existing key when at capacity", %{buf: buf} do
      for i <- 1..5 do
        ActivityBuffer.upsert(buf, task_id: "t#{i}", repo_id: "r1")
      end

      assert {:ok, _} =
               ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1", description: "updated")
    end
  end

  describe "remove/4" do
    test "removes existing entry", %{buf: buf} do
      ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1")
      assert ActivityBuffer.remove(buf, "t1", "r1", nil)
      assert ActivityBuffer.size(buf) == 0
    end

    test "returns false for missing entry", %{buf: buf} do
      refute ActivityBuffer.remove(buf, "nope", nil, nil)
    end
  end

  describe "get/4" do
    test "returns entry if present", %{buf: buf} do
      ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1")
      assert %Entry{task_id: "t1"} = ActivityBuffer.get(buf, "t1", "r1", nil)
    end

    test "returns nil if missing", %{buf: buf} do
      assert ActivityBuffer.get(buf, "nope", nil, nil) == nil
    end
  end

  describe "list/2" do
    test "returns all entries with no filter", %{buf: buf} do
      ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1")
      ActivityBuffer.upsert(buf, task_id: "t2", repo_id: "r2")
      assert length(ActivityBuffer.list(buf)) == 2
    end

    test "filters by task_id", %{buf: buf} do
      ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1")
      ActivityBuffer.upsert(buf, task_id: "t2", repo_id: "r2")
      result = ActivityBuffer.list(buf, task_id: "t1")
      assert length(result) == 1
      assert hd(result).task_id == "t1"
    end

    test "filters by repo_id", %{buf: buf} do
      ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1")
      ActivityBuffer.upsert(buf, task_id: "t2", repo_id: "r2")
      result = ActivityBuffer.list(buf, repo_id: "r2")
      assert length(result) == 1
    end
  end

  describe "recent/2" do
    test "returns most recent entries", %{buf: buf} do
      for i <- 1..3 do
        ActivityBuffer.upsert(buf, task_id: "t#{i}", repo_id: "r1")
      end

      result = ActivityBuffer.recent(buf, 2)
      assert length(result) == 2
    end
  end

  describe "reconcile/2" do
    test "removes completed/failed/unknown tasks", %{buf: buf} do
      ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1")
      ActivityBuffer.upsert(buf, task_id: "t2", repo_id: "r1")
      ActivityBuffer.upsert(buf, task_id: "t3", repo_id: "r1")

      removed = ActivityBuffer.reconcile(buf, %{"t1" => :running, "t2" => :completed})
      assert removed == 2
      assert ActivityBuffer.size(buf) == 1
    end
  end

  describe "clear/1" do
    test "removes all entries and returns count", %{buf: buf} do
      ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1")
      ActivityBuffer.upsert(buf, task_id: "t2", repo_id: "r2")
      assert ActivityBuffer.clear(buf) == 2
      assert ActivityBuffer.size(buf) == 0
    end
  end

  describe "size/1" do
    test "returns entry count", %{buf: buf} do
      assert ActivityBuffer.size(buf) == 0
      ActivityBuffer.upsert(buf, task_id: "t1", repo_id: "r1")
      assert ActivityBuffer.size(buf) == 1
    end
  end
end
