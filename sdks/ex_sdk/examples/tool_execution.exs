# Tool Execution Example
#
# Demonstrates:
# - Interceptor chain setup
# - Envelope construction for tool calls
# - ACK tracking for messages
# - Worktree state management
#
# Run: mix run examples/tool_execution.exs
#
# Note: This example demonstrates local SDK features.
# Actual gRPC calls require a running SW4RM server.

alias Sw4rm.{Envelope, AckManager, WorktreeState}
alias Sw4rm.Interceptor.{Chain, Timing, Logging}
alias Sw4rm.Envelope.SequenceTracker

IO.puts("=== SW4RM Tool Execution Example ===\n")

# 1. Set up interceptor chain
IO.puts("--- Interceptor Chain ---")

chain =
  Chain.new()
  |> Chain.add(Timing)
  |> Chain.add(Logging)

IO.puts("Chain has #{length(chain.interceptors)} interceptors")

# 2. Set up worktree binding
IO.puts("\n--- Worktree Binding ---")
{:ok, wts} = WorktreeState.start_link()
IO.puts("State: #{WorktreeState.current_state(wts)}")

{:ok, :bound_home} = WorktreeState.bind(wts, "wt-main", "my-repo", "main")
IO.puts("Bound to: #{WorktreeState.get_current_binding(wts).worktree_id}")

# Request switch to feature branch
{:ok, :switch_pending} =
  WorktreeState.request_switch(wts, "wt-feature", "my-repo", "feature/tool-call")

IO.puts("Switch pending to: #{WorktreeState.get_pending_switch(wts).branch}")

{:ok, :bound_non_home} = WorktreeState.approve_switch(wts)
binding = WorktreeState.get_current_binding(wts)
IO.puts("Now bound to: #{binding.worktree_id} (#{binding.branch})")

# 3. Build tool call envelope
IO.puts("\n--- Tool Call Envelope ---")
{:ok, seq} = SequenceTracker.start_link()

tool_payload =
  Jason.encode!(%{
    "tool_name" => "file_search",
    "arguments" => %{
      "pattern" => "**/*.ex",
      "directory" => "/src"
    }
  })

env =
  Envelope.new(
    producer_id: "agent-1",
    message_type: :tool_call,
    sequence_number: SequenceTracker.next(seq),
    payload: tool_payload,
    repo_id: binding.repo_id,
    worktree_id: binding.worktree_id
  )

# Process through interceptor chain
processed = Chain.process_request(chain, %{envelope: env, metadata: %{tool: "file_search"}})
IO.puts("Envelope message_id: #{env.message_id}")
IO.puts("Content length: #{env.content_length} bytes")

# 4. Track the outgoing message with ACK manager
IO.puts("\n--- ACK Tracking ---")
{:ok, am} = AckManager.start_link(agent_id: "agent-1")

{:ok, ack_record} = AckManager.track_outgoing(am, env.message_id)
IO.puts("Tracked outgoing: #{ack_record.message_id} (stage=#{ack_record.stage})")

# Simulate receiving ACK
{:ok, updated} = AckManager.update(am, env.message_id, :received)
IO.puts("Updated stage: #{updated.stage}")

# Simulate tool result
{:ok, fulfilled} =
  AckManager.update(am, env.message_id, :fulfilled, note: "tool returned 42 files")

IO.puts("Fulfilled: #{fulfilled.note}")

# Check unacked
unacked = AckManager.get_unacked(am)
IO.puts("Unacked messages: #{length(unacked)}")

# 5. Revert worktree
IO.puts("\n--- Worktree Revert ---")
{:ok, :bound_home} = WorktreeState.revert_to_home(wts)
IO.puts("Reverted to: #{WorktreeState.get_current_binding(wts).worktree_id}")

# Show history
IO.puts("\nWorktree transition history:")

for entry <- WorktreeState.history(wts) |> Enum.reverse() do
  IO.puts("  #{entry.from_state} -> #{entry.to_state}")
end

IO.puts("\nDone!")
