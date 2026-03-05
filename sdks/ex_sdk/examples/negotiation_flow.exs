# Multi-Agent Negotiation Example
#
# Demonstrates:
# - Creating a negotiation room
# - Submitting proposals and critiques
# - Voting with different strategies
# - Making decisions
# - Negotiation events
#
# Run: mix run examples/negotiation_flow.exs

alias Sw4rm.NegotiationRoom
alias Sw4rm.NegotiationRoom.{Proposal, Critique, Store}
alias Sw4rm.NegotiationEvents
alias Sw4rm.Voting.{Vote, MajorityVote, ConfidenceWeighted, Aggregator}

IO.puts("=== SW4RM Negotiation Flow Example ===\n")

# 1. Set up event emitter
{:ok, events} = NegotiationEvents.start_link()

NegotiationEvents.on(events, :all, fn event ->
  IO.puts("  [EVENT] #{event.event_type} in room=#{event.room_id} by agent=#{event.agent_id}")
end)

# 2. Create a negotiation room via the Store
{:ok, store} = Store.start_link()
{:ok, room_pid} = Store.create_room(store, "code-review-001", description: "Review PR #42")

NegotiationEvents.emit_event(events, :room_created, "code-review-001", "scheduler", %{})

# 3. Submit a proposal (code artifact)
IO.puts("\n--- Submitting Proposal ---")

proposal = %Proposal{
  artifact_id: "pr-42-v1",
  producer_id: "coder-agent",
  artifact: %{
    language: "elixir",
    files_changed: 3,
    lines_added: 120,
    lines_removed: 45
  },
  content_type: "application/vnd.sw4rm.code-review",
  requested_critics: ["reviewer-1", "reviewer-2", "reviewer-3"]
}

{:ok, artifact_id} = NegotiationRoom.submit_proposal(room_pid, proposal)
IO.puts("Submitted artifact: #{artifact_id}")

NegotiationEvents.emit_event(events, :proposal_submitted, "code-review-001", "coder-agent", %{
  artifact_id: artifact_id
})

# 4. Critics submit reviews
IO.puts("\n--- Submitting Critiques ---")

critiques = [
  %Critique{
    critic_id: "reviewer-1",
    score: 8,
    confidence: 0.9,
    passed: true,
    strengths: ["Clean code", "Good tests"],
    weaknesses: ["Missing docs"],
    recommendations: ["Add @moduledoc"]
  },
  %Critique{
    critic_id: "reviewer-2",
    score: 7,
    confidence: 0.8,
    passed: true,
    strengths: ["Follows patterns"],
    weaknesses: ["Complex function"],
    recommendations: ["Break up process/3"]
  },
  %Critique{
    critic_id: "reviewer-3",
    score: 5,
    confidence: 0.6,
    passed: false,
    strengths: ["Correct logic"],
    weaknesses: ["No error handling", "No types"],
    recommendations: ["Add typespecs", "Handle edge cases"]
  }
]

for critique <- critiques do
  :ok = NegotiationRoom.add_critique(room_pid, artifact_id, critique)

  NegotiationEvents.emit_event(events, :critique_added, "code-review-001", critique.critic_id, %{
    score: critique.score
  })

  IO.puts("  #{critique.critic_id}: score=#{critique.score} passed=#{critique.passed}")
end

# 5. Run voting aggregation
IO.puts("\n--- Voting ---")
{:ok, aggregator} = Aggregator.start_link(strategy: ConfidenceWeighted)

votes =
  Enum.map(critiques, fn c ->
    choice = if c.passed, do: :approve, else: :request_changes
    Vote.new(agent_id: c.critic_id, choice: choice, confidence: c.confidence)
  end)

result = Aggregator.run_vote(aggregator, votes, round_id: "round-1")
IO.puts("Winner: #{result.winner}")
IO.puts("Weighted scores: #{inspect(result.weighted_scores)}")
IO.puts("Total weight: #{Float.round(result.total_weight, 2)}")

# 6. Make decision
IO.puts("\n--- Decision ---")
decision = result.winner
NegotiationRoom.decide(room_pid, artifact_id, decision)

NegotiationEvents.emit_event(events, :approved, "code-review-001", "scheduler", %{
  decision: decision
})

final = NegotiationRoom.get_decision(room_pid, artifact_id)
IO.puts("Final decision: #{inspect(final)}")

# 7. Room summary
info = NegotiationRoom.room_info(room_pid)
IO.puts("\nRoom info: #{inspect(info)}")

# 8. Event history
IO.puts("\n--- Event History ---")

for event <- NegotiationEvents.history(events) |> Enum.reverse() do
  IO.puts("  #{event.event_type}")
end

# Cleanup
Store.close_room(store, "code-review-001")
IO.puts("\nDone!")
