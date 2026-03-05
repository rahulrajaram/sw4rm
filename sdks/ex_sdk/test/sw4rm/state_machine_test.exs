defmodule Sw4rm.StateMachineTest do
  use ExUnit.Case, async: true

  alias Sw4rm.StateMachine

  setup do
    {:ok, sm} = StateMachine.start_link()
    %{sm: sm}
  end

  describe "init" do
    test "defaults to :initializing", %{sm: sm} do
      assert StateMachine.current_state(sm) == :initializing
    end

    test "accepts custom initial state" do
      {:ok, sm} = StateMachine.start_link(initial_state: :running)
      assert StateMachine.current_state(sm) == :running
    end
  end

  describe "transition/3" do
    test "valid transition succeeds", %{sm: sm} do
      assert {:ok, :runnable} = StateMachine.transition(sm, :runnable)
      assert StateMachine.current_state(sm) == :runnable
    end

    test "invalid transition returns error", %{sm: sm} do
      assert {:error, %Sw4rm.Error.StateTransition{}} = StateMachine.transition(sm, :running)
    end

    test "full lifecycle path", %{sm: sm} do
      assert {:ok, :runnable} = StateMachine.transition(sm, :runnable)
      assert {:ok, :scheduled} = StateMachine.transition(sm, :scheduled)
      assert {:ok, :running} = StateMachine.transition(sm, :running)
      assert {:ok, :completed} = StateMachine.transition(sm, :completed)
    end

    test "failure and recovery path", %{sm: sm} do
      assert {:ok, :failed} = StateMachine.transition(sm, :failed)
      assert {:ok, :recovering} = StateMachine.transition(sm, :recovering)
      assert {:ok, :runnable} = StateMachine.transition(sm, :runnable)
    end

    test "running to waiting and back", %{sm: sm} do
      StateMachine.transition(sm, :runnable)
      StateMachine.transition(sm, :scheduled)
      StateMachine.transition(sm, :running)
      assert {:ok, :waiting} = StateMachine.transition(sm, :waiting)
      assert {:ok, :running} = StateMachine.transition(sm, :running)
    end

    test "running to suspended path", %{sm: sm} do
      StateMachine.transition(sm, :runnable)
      StateMachine.transition(sm, :scheduled)
      StateMachine.transition(sm, :running)
      assert {:ok, :suspended} = StateMachine.transition(sm, :suspended)
      assert {:ok, :resumed} = StateMachine.transition(sm, :resumed)
      assert {:ok, :running} = StateMachine.transition(sm, :running)
    end

    test "shutting_down path", %{sm: sm} do
      StateMachine.transition(sm, :runnable)
      StateMachine.transition(sm, :scheduled)
      StateMachine.transition(sm, :running)
      assert {:ok, :shutting_down} = StateMachine.transition(sm, :shutting_down)
      assert {:ok, :failed} = StateMachine.transition(sm, :failed)
    end
  end

  describe "can_transition?/2" do
    test "returns true for valid transition", %{sm: sm} do
      assert StateMachine.can_transition?(sm, :runnable)
    end

    test "returns false for invalid transition", %{sm: sm} do
      refute StateMachine.can_transition?(sm, :running)
    end
  end

  describe "valid_transitions/1" do
    test "returns valid next states", %{sm: sm} do
      assert StateMachine.valid_transitions(sm) == [:runnable, :failed]
    end
  end

  describe "transitions_for/1 (pure)" do
    test "returns transitions for :running" do
      assert StateMachine.transitions_for(:running) ==
               [:waiting, :waiting_resources, :suspended, :completed, :failed, :shutting_down]
    end

    test "returns empty for unknown state" do
      assert StateMachine.transitions_for(:nonexistent) == []
    end
  end

  describe "history/2" do
    test "records initial state entry", %{sm: sm} do
      history = StateMachine.history(sm)
      assert length(history) == 1
      [entry] = history
      assert entry.from_state == nil
      assert entry.to_state == :initializing
    end

    test "records transitions", %{sm: sm} do
      StateMachine.transition(sm, :runnable)
      StateMachine.transition(sm, :scheduled)
      history = StateMachine.history(sm)
      assert length(history) == 3
    end

    test "respects limit", %{sm: sm} do
      StateMachine.transition(sm, :runnable)
      StateMachine.transition(sm, :scheduled)
      history = StateMachine.history(sm, 2)
      assert length(history) == 2
    end
  end

  describe "hooks" do
    test "before hook is called on transition", %{sm: sm} do
      test_pid = self()
      hook = fn from, to, _ts, _meta -> send(test_pid, {:before, from, to}) end
      StateMachine.add_before_hook(sm, hook)
      StateMachine.transition(sm, :runnable)
      assert_receive {:before, :initializing, :runnable}
    end

    test "after hook is called on transition", %{sm: sm} do
      test_pid = self()
      hook = fn _from, to, _ts, _meta -> send(test_pid, {:after, to}) end
      StateMachine.add_after_hook(sm, hook)
      StateMachine.transition(sm, :runnable)
      assert_receive {:after, :runnable}
    end

    test "hooks not called on invalid transition", %{sm: sm} do
      test_pid = self()
      hook = fn _from, _to, _ts, _meta -> send(test_pid, :hook_called) end
      StateMachine.add_before_hook(sm, hook)
      StateMachine.transition(sm, :running)
      refute_receive :hook_called
    end
  end
end
