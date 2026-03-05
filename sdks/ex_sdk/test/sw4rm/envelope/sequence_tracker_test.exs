defmodule Sw4rm.Envelope.SequenceTrackerTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Envelope.SequenceTracker

  setup do
    {:ok, tracker} = SequenceTracker.start_link()
    %{tracker: tracker}
  end

  test "starts at 1", %{tracker: tracker} do
    assert SequenceTracker.next(tracker) == 1
  end

  test "increments on each call", %{tracker: tracker} do
    assert SequenceTracker.next(tracker) == 1
    assert SequenceTracker.next(tracker) == 2
    assert SequenceTracker.next(tracker) == 3
  end

  test "accepts custom start value" do
    {:ok, tracker} = SequenceTracker.start_link(start: 100)
    assert SequenceTracker.next(tracker) == 100
    assert SequenceTracker.next(tracker) == 101
  end
end
