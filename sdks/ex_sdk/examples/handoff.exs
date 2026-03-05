# Inter-Swarm Handoff Example (SW4-004)
#
# Demonstrates:
# - Budget envelope creation with depth tracking
# - Handoff request/accept/complete lifecycle
# - Parent-child delegation registration
# - Cascading cancellation
# - Gateway peer selection for spillover routing
#
# Run: mix run examples/handoff.exs

alias Sw4rm.Handoff
alias Sw4rm.Handoff.BudgetEnvelope
alias Sw4rm.Gateway
alias Sw4rm.Gateway.PeerDescriptor

IO.puts("=== SW4RM Inter-Swarm Handoff Example (SW4-004) ===\n")

# 1. Set up handoff manager and gateway
{:ok, ho} = Handoff.start_link()
{:ok, gw} = Gateway.start_link(agent_id: "swarm-leader", capabilities: [:code, :review])

# 2. Configure gateway peers
IO.puts("--- Gateway Peers ---")

peers = [
  %PeerDescriptor{agent_id: "worker-1", capabilities: [:code, :review]},
  %PeerDescriptor{agent_id: "worker-2", capabilities: [:code, :review, :test]},
  %PeerDescriptor{agent_id: "worker-3", capabilities: [:code]}
]

Gateway.set_peers(gw, peers)

# Mark peer health
now = System.system_time(:millisecond)
Gateway.update_peer_health(gw, "worker-1", %{state: :running, last_heartbeat_ms: now})
Gateway.update_peer_health(gw, "worker-2", %{state: :running, last_heartbeat_ms: now})
Gateway.update_peer_health(gw, "worker-3", %{state: :running, last_heartbeat_ms: now})

IO.puts("Registered #{length(peers)} peers")

# 3. Select a peer for delegation
{:ok, selected} = Gateway.select_peer(gw)
IO.puts("Selected peer: #{selected.agent_id}")

# 4. Create budget envelope
IO.puts("\n--- Budget Envelope ---")

budget = %BudgetEnvelope{
  token_budget_remaining: 10_000,
  wall_time_remaining_ms: 60_000,
  deadline_epoch_ms: System.system_time(:millisecond) + 60_000,
  max_delegation_depth: 3,
  current_depth: 0
}

IO.puts("Max depth: #{budget.max_delegation_depth}")
IO.puts("Token budget: #{budget.token_budget_remaining}")
IO.puts("Wall time remaining: #{budget.wall_time_remaining_ms}ms")

# 5. Request parent handoff
IO.puts("\n--- Parent Handoff ---")

{:ok, parent_id} =
  Handoff.request_handoff(ho, %{
    from_agent: "swarm-leader",
    to_agent: selected.agent_id,
    correlation_id: "mission-alpha",
    budget: budget
  })

IO.puts("Created handoff: #{parent_id}")

# Accept the handoff
{:ok, accepted} = Handoff.accept(ho, parent_id)
IO.puts("Accepted at: #{accepted.accepted_at}")

# 6. Worker creates child delegation (depth + 1)
IO.puts("\n--- Child Delegation ---")
child_budget = %{budget | current_depth: budget.current_depth + 1}

{:ok, child_id} =
  Handoff.request_handoff(ho, %{
    from_agent: selected.agent_id,
    to_agent: "worker-2",
    correlation_id: "sub-task-1",
    budget: child_budget
  })

Handoff.register_child(ho, "mission-alpha", "sub-task-1")
IO.puts("Child handoff: #{child_id} (depth=#{child_budget.current_depth})")

# Create another child
{:ok, child_id_2} =
  Handoff.request_handoff(ho, %{
    from_agent: selected.agent_id,
    to_agent: "worker-3",
    correlation_id: "sub-task-2",
    budget: child_budget
  })

Handoff.register_child(ho, "mission-alpha", "sub-task-2")
IO.puts("Child handoff: #{child_id_2} (depth=#{child_budget.current_depth})")

# 7. Demonstrate depth limit
IO.puts("\n--- Depth Limit ---")
deep_budget = %BudgetEnvelope{max_delegation_depth: 3, current_depth: 3}

case Handoff.request_handoff(ho, %{
       from_agent: "worker-2",
       to_agent: "worker-3",
       budget: deep_budget
     }) do
  {:error, :depth_exceeded} ->
    IO.puts(
      "Correctly blocked: depth #{deep_budget.current_depth} >= max #{deep_budget.max_delegation_depth}"
    )

  {:ok, _} ->
    IO.puts("ERROR: should have been blocked!")
end

# 8. Cascading cancellation
IO.puts("\n--- Cascading Cancellation ---")
IO.puts("Cancelling mission-alpha (parent + 2 children)...")

{:ok, cancelled_count} = Handoff.cancel_delegation(ho, "mission-alpha")
IO.puts("Cancelled #{cancelled_count} correlation IDs")

parent_record = Handoff.get(ho, parent_id)
child_record = Handoff.get(ho, child_id)
child_record_2 = Handoff.get(ho, child_id_2)

IO.puts("Parent status: #{parent_record.status}")
IO.puts("Child 1 status: #{child_record.status}")
IO.puts("Child 2 status: #{child_record_2.status}")

# 9. Gateway redirect
IO.puts("\n--- Spillover Redirect ---")
original_envelope = %{message_id: "msg-overflow", payload: "too much work"}

case Gateway.emit_redirect(gw, original_envelope) do
  {:ok, redirect} ->
    IO.puts("Redirect to: #{redirect.redirect_to}")
    IO.puts("Error code: #{redirect.error_code}")

  {:error, reason} ->
    IO.puts("No redirect available: #{inspect(reason)}")
end

IO.puts("\nDone!")
