# Basic Agent Example
#
# Demonstrates:
# - Building an envelope with the Three-ID model
# - Agent lifecycle state machine transitions
# - Sequence number generation
# - Activity buffer tracking
#
# Run: mix run examples/basic_agent.exs

alias Sw4rm.{Envelope, StateMachine, ActivityBuffer, Config}
alias Sw4rm.Envelope.SequenceTracker

IO.puts("=== SW4RM Basic Agent Example ===\n")

# 1. Load configuration
config = Config.from_env()
IO.puts("Agent ID: #{config.agent_id}")
IO.puts("Router endpoint: #{config.endpoints.router}")

# 2. Start supporting services
{:ok, seq} = SequenceTracker.start_link()
{:ok, sm} = StateMachine.start_link()
{:ok, buf} = ActivityBuffer.start_link(max_items: 100)

# 3. Agent lifecycle: initializing -> runnable -> scheduled -> running
IO.puts("\n--- Lifecycle ---")
IO.puts("State: #{StateMachine.current_state(sm)}")

{:ok, _} = StateMachine.transition(sm, :runnable)
IO.puts("State: #{StateMachine.current_state(sm)}")

{:ok, _} = StateMachine.transition(sm, :scheduled)
{:ok, _} = StateMachine.transition(sm, :running)
IO.puts("State: #{StateMachine.current_state(sm)}")

# 4. Build and validate an envelope
IO.puts("\n--- Envelope ---")
seq_num = SequenceTracker.next(seq)

hash = Envelope.compute_deterministic_hash(%{target: "agent-2", action: "greet"})
token = Envelope.make_idempotency_token(config.agent_id, "send", hash)

env =
  Envelope.new(
    producer_id: config.agent_id,
    message_type: :task,
    sequence_number: seq_num,
    idempotency_token: token,
    payload: ~s({"greeting": "Hello from #{config.agent_id}!"})
  )

:ok = Envelope.validate!(env)
IO.puts("Message ID: #{env.message_id}")
IO.puts("Correlation ID: #{env.correlation_id}")
IO.puts("Idempotency token: #{env.idempotency_token}")
IO.puts("Sequence: #{env.sequence_number}")
IO.puts("HLC Timestamp: #{env.hlc_timestamp}")
IO.puts("Content length: #{env.content_length} bytes")

# 5. Track activity
IO.puts("\n--- Activity Buffer ---")

{:ok, _entry} =
  ActivityBuffer.upsert(buf,
    task_id: "task-001",
    repo_id: "my-repo",
    worktree_id: "wt-main",
    branch: "main",
    description: "Processing greeting task"
  )

IO.puts("Buffer size: #{ActivityBuffer.size(buf)}")
IO.puts("Recent activities:")

for entry <- ActivityBuffer.recent(buf, 5) do
  IO.puts("  - [#{entry.task_id}] #{entry.description}")
end

# 6. Complete the task
{:ok, _} = StateMachine.transition(sm, :completed)
IO.puts("\nFinal state: #{StateMachine.current_state(sm)}")
IO.puts("\nDone!")
