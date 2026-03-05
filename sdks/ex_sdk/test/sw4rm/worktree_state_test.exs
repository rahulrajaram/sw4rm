defmodule Sw4rm.WorktreeStateTest do
  use ExUnit.Case, async: true

  alias Sw4rm.WorktreeState

  setup do
    {:ok, ws} = WorktreeState.start_link()
    %{ws: ws}
  end

  describe "init" do
    test "starts in :unbound state", %{ws: ws} do
      assert WorktreeState.current_state(ws) == :unbound
    end
  end

  describe "bind/4" do
    test "transitions from unbound to bound_home", %{ws: ws} do
      assert {:ok, :bound_home} = WorktreeState.bind(ws, "wt-1", "repo-1", "main")
      assert WorktreeState.current_state(ws) == :bound_home
    end

    test "sets current and home bindings", %{ws: ws} do
      WorktreeState.bind(ws, "wt-1", "repo-1", "main")
      binding = WorktreeState.get_current_binding(ws)
      assert binding.worktree_id == "wt-1"
      assert binding.repo_id == "repo-1"
      assert binding.branch == "main"
      assert WorktreeState.get_home_binding(ws) == binding
    end

    test "fails from invalid state", %{ws: ws} do
      WorktreeState.bind(ws, "wt-1", "repo-1", "main")
      WorktreeState.request_switch(ws, "wt-2", "repo-1", "feature")

      assert {:error, %Sw4rm.Error.Worktree{}} =
               WorktreeState.bind(ws, "wt-3", "repo-1", "other")
    end
  end

  describe "unbind/1" do
    test "transitions from bound_home to unbound", %{ws: ws} do
      WorktreeState.bind(ws, "wt-1", "repo-1", "main")
      assert {:ok, :unbound} = WorktreeState.unbind(ws)
      assert WorktreeState.current_state(ws) == :unbound
      assert WorktreeState.get_current_binding(ws) == nil
    end

    test "fails from unbound", %{ws: ws} do
      assert {:error, _} = WorktreeState.unbind(ws)
    end
  end

  describe "switch workflow" do
    test "full switch: request -> approve", %{ws: ws} do
      WorktreeState.bind(ws, "wt-1", "repo-1", "main")

      assert {:ok, :switch_pending} =
               WorktreeState.request_switch(ws, "wt-2", "repo-1", "feature")

      assert WorktreeState.get_pending_switch(ws) != nil

      assert {:ok, :bound_non_home} = WorktreeState.approve_switch(ws)
      assert WorktreeState.current_state(ws) == :bound_non_home

      binding = WorktreeState.get_current_binding(ws)
      assert binding.worktree_id == "wt-2"
      assert binding.branch == "feature"
    end

    test "switch rejected returns to bound_home", %{ws: ws} do
      WorktreeState.bind(ws, "wt-1", "repo-1", "main")
      WorktreeState.request_switch(ws, "wt-2", "repo-1", "feature")

      assert {:ok, :bound_home} = WorktreeState.reject_switch(ws)
      assert WorktreeState.current_state(ws) == :bound_home
      assert WorktreeState.get_pending_switch(ws) == nil
    end
  end

  describe "revert_to_home/1" do
    test "transitions from bound_non_home to bound_home", %{ws: ws} do
      WorktreeState.bind(ws, "wt-1", "repo-1", "main")
      WorktreeState.request_switch(ws, "wt-2", "repo-1", "feature")
      WorktreeState.approve_switch(ws)

      assert {:ok, :bound_home} = WorktreeState.revert_to_home(ws)
      binding = WorktreeState.get_current_binding(ws)
      assert binding.worktree_id == "wt-1"
    end
  end

  describe "history/1" do
    test "records transitions", %{ws: ws} do
      WorktreeState.bind(ws, "wt-1", "repo-1", "main")
      history = WorktreeState.history(ws)
      assert length(history) == 1
      assert hd(history).from_state == :unbound
      assert hd(history).to_state == :bound_home
    end
  end
end
