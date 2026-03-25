# SW4RM Elixir SDK — Activity & Envelope Lifecycle Walkthrough
#
# A focused walkthrough of the agent lifecycle, envelope construction,
# state machine transitions, and activity buffer management.
#
# Extracted from the broader reference_demo.exs to serve as a clean
# entry point for understanding these core concepts.
#
# Run: mix run examples/activity_walkthrough.exs

IO.puts("=== SW4RM Activity & Envelope Lifecycle Walkthrough ===\n")

# ──────────────────────────────────────────────
# 1. Agent Configuration
# ──────────────────────────────────────────────
IO.puts("--- 1. Agent Configuration ---")

config = Sw4rm.Config.from_env()
IO.puts("  Agent ID: #{config.agent_id}")
IO.puts("  Endpoints configured: #{map_size(Map.from_struct(config.endpoints))}")

# ──────────────────────────────────────────────
# 2. State Machine Lifecycle
# ──────────────────────────────────────────────
IO.puts("\n--- 2. State Machine Lifecycle ---")
IO.puts("  States: initializing -> runnable -> scheduled -> running -> waiting -> completed")

{:ok, sm} = Sw4rm.StateMachine.start_link()

assert_state = fn expected ->
  actual = Sw4rm.StateMachine.current_state(sm)
  unless actual == expected, do: raise("Expected #{expected}, got #{actual}")
  actual
end

assert_state.(:initializing)
IO.puts("  Current: initializing")

{:ok, :runnable} = Sw4rm.StateMachine.transition(sm, :runnable)
IO.puts("  Transition: initializing -> runnable")

{:ok, :scheduled} = Sw4rm.StateMachine.transition(sm, :scheduled)
IO.puts("  Transition: runnable -> scheduled")

{:ok, :running} = Sw4rm.StateMachine.transition(sm, :running)
IO.puts("  Transition: scheduled -> running")

# Demonstrate wait/resume cycle
{:ok, :waiting} = Sw4rm.StateMachine.transition(sm, :waiting)
IO.puts("  Transition: running -> waiting (blocked on I/O)")

{:ok, :running} = Sw4rm.StateMachine.transition(sm, :running)
IO.puts("  Transition: waiting -> running (resumed)")

{:ok, :completed} = Sw4rm.StateMachine.transition(sm, :completed)
IO.puts("  Transition: running -> completed")

# Reset for next task
{:ok, :runnable} = Sw4rm.StateMachine.transition(sm, :runnable)
IO.puts("  Transition: completed -> runnable (ready for next task)")

# ──────────────────────────────────────────────
# 3. Envelope Construction
# ──────────────────────────────────────────────
IO.puts("\n--- 3. Envelope Construction ---")
IO.puts("  Envelopes carry three IDs: message_id, correlation_id, idempotency_token")

payload = Jason.encode!(%{action: "code_review", data: %{file: "main.py", lines: 42}})

det_hash =
  Sw4rm.Envelope.compute_deterministic_hash(%{
    producer: config.agent_id,
    op: "code_review",
    nonce: "review-001"
  })

idem_token = Sw4rm.Envelope.make_idempotency_token(config.agent_id, "code_review", det_hash)

env =
  Sw4rm.Envelope.new(
    producer_id: config.agent_id,
    message_type: "DATA",
    payload: payload,
    idempotency_token: idem_token,
    parent_correlation_id: ""
  )

:ok = Sw4rm.Envelope.validate!(env)

IO.puts("  message_id:          #{env.message_id}")
IO.puts("  correlation_id:      #{env.correlation_id}")
IO.puts("  idempotency_token:   #{env.idempotency_token}")
IO.puts("  message_type:        #{env.message_type}")
IO.puts("  validation:          passed")

# Demonstrate child envelope with parent correlation
child_env =
  Sw4rm.Envelope.new(
    producer_id: config.agent_id,
    message_type: "ACK",
    payload: Jason.encode!(%{status: "received"}),
    idempotency_token: Sw4rm.Envelope.make_idempotency_token(config.agent_id, "ack", det_hash),
    parent_correlation_id: env.correlation_id
  )

:ok = Sw4rm.Envelope.validate!(child_env)
IO.puts("\n  Child envelope:")
IO.puts("    message_id:              #{child_env.message_id}")
IO.puts("    parent_correlation_id:   #{child_env.parent_correlation_id}")
IO.puts("    Linked to parent:        #{child_env.parent_correlation_id == env.correlation_id}")

# ──────────────────────────────────────────────
# 4. Activity Buffer
# ──────────────────────────────────────────────
IO.puts("\n--- 4. Activity Buffer ---")
IO.puts("  Tracks in-flight activities with bounded capacity and reconciliation")

{:ok, buf} = Sw4rm.ActivityBuffer.start_link(max_items: 5)

# Track several activities
activities = [
  %{task_id: "lint-1", repo_id: "repo-main", worktree_id: "wt-1", description: "Lint pass"},
  %{task_id: "test-2", repo_id: "repo-main", worktree_id: "wt-1", description: "Unit tests"},
  %{task_id: "build-3", repo_id: "repo-main", worktree_id: "wt-2", description: "Build artifact"},
  %{task_id: "deploy-4", repo_id: "repo-main", worktree_id: "wt-2", description: "Deploy staging"}
]

for act <- activities do
  {:ok, _} = Sw4rm.ActivityBuffer.upsert(buf, Map.to_list(act))
end

IO.puts("  Tracked #{Sw4rm.ActivityBuffer.size(buf)} activities")

# Reconcile: mark some as completed, leave others running
status_map = %{
  "lint-1" => :completed,
  "test-2" => :running,
  "build-3" => :completed
}

removed = Sw4rm.ActivityBuffer.reconcile(buf, status_map)
IO.puts("  Reconciled with external status:")
IO.puts("    lint-1:   completed -> removed")
IO.puts("    test-2:   running   -> kept")
IO.puts("    build-3:  completed -> removed")
IO.puts("    deploy-4: unknown   -> removed (not in status map)")
IO.puts("  Removed #{removed} activities, remaining: #{Sw4rm.ActivityBuffer.size(buf)}")

# ──────────────────────────────────────────────
IO.puts("\n=== Activity & Envelope Walkthrough Complete ===")
IO.puts("\nKey concepts covered:")
IO.puts("  1. State machine: 6 states with valid transition paths")
IO.puts("  2. Envelopes: three-ID model (message, correlation, idempotency)")
IO.puts("  3. Parent-child correlation for message threading")
IO.puts("  4. Activity buffer: bounded tracking with reconciliation")
