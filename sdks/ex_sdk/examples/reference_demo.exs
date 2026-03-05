# SW4RM Elixir SDK Reference Demo
#
# Self-contained script exercising the full SDK lifecycle locally.
# No gRPC services required.
#
# Run: mix run examples/reference_demo.exs

IO.puts("=== SW4RM Elixir SDK Reference Demo ===\n")

# ──────────────────────────────────────────────
# 1. Agent Registration & Config
# ──────────────────────────────────────────────
IO.puts("--- 1. Agent Registration & Config ---")

config = Sw4rm.Config.from_env()
IO.puts("  Config loaded: #{map_size(Map.from_struct(config.endpoints))} service endpoints")

{:ok, sm} = Sw4rm.StateMachine.start_link()

assert_state = fn expected ->
  actual = Sw4rm.StateMachine.current_state(sm)
  unless actual == expected, do: raise("Expected #{expected}, got #{actual}")
  actual
end

assert_state.(:initializing)
{:ok, :runnable} = Sw4rm.StateMachine.transition(sm, :runnable)
IO.puts("  State machine: initializing -> runnable")

# ──────────────────────────────────────────────
# 2. Envelope Construction
# ──────────────────────────────────────────────
IO.puts("\n--- 2. Envelope Construction ---")

payload = Jason.encode!(%{action: "data_send", data: "hello world"})

det_hash =
  Sw4rm.Envelope.compute_deterministic_hash(%{
    producer: config.agent_id,
    op: "data_send",
    nonce: "a1b2c3d4"
  })

idem_token = Sw4rm.Envelope.make_idempotency_token(config.agent_id, "data_send", det_hash)

env =
  Sw4rm.Envelope.new(
    producer_id: config.agent_id,
    message_type: "DATA",
    payload: payload,
    idempotency_token: idem_token,
    parent_correlation_id: ""
  )

:ok = Sw4rm.Envelope.validate!(env)
IO.puts("  message_id: #{env.message_id}")
IO.puts("  idempotency_token: #{env.idempotency_token}")
IO.puts("  parent_correlation_id: #{inspect(env.parent_correlation_id)}")
IO.puts("  validation: passed")

# ──────────────────────────────────────────────
# 3. State Machine Lifecycle
# ──────────────────────────────────────────────
IO.puts("\n--- 3. State Machine Lifecycle ---")

transitions = [
  {:scheduled, "runnable -> scheduled"},
  {:running, "scheduled -> running"},
  {:waiting, "running -> waiting"},
  {:running, "waiting -> running"},
  {:completed, "running -> completed"},
  {:runnable, "completed -> runnable"}
]

for {target, label} <- transitions do
  {:ok, ^target} = Sw4rm.StateMachine.transition(sm, target)
  IO.puts("  #{label}")
end

IO.puts("  Full lifecycle traversal complete")

# ──────────────────────────────────────────────
# 4. Activity Buffer
# ──────────────────────────────────────────────
IO.puts("\n--- 4. Activity Buffer ---")

{:ok, buf} = Sw4rm.ActivityBuffer.start_link(max_items: 5)

for i <- 1..3 do
  {:ok, _} =
    Sw4rm.ActivityBuffer.upsert(buf,
      task_id: "task-#{i}",
      repo_id: "repo-main",
      worktree_id: "wt-#{i}",
      description: "Activity #{i}"
    )
end

IO.puts("  Tracked #{Sw4rm.ActivityBuffer.size(buf)} activities")

removed = Sw4rm.ActivityBuffer.reconcile(buf, %{"task-1" => :completed, "task-2" => :running})
IO.puts("  Reconciled: removed #{removed} (completed + unknown)")
IO.puts("  Remaining: #{Sw4rm.ActivityBuffer.size(buf)}")

# ──────────────────────────────────────────────
# 5. Negotiation Flow
# ──────────────────────────────────────────────
IO.puts("\n--- 5. Negotiation Flow ---")

alias Sw4rm.NegotiationRoom
alias Sw4rm.NegotiationRoom.{Proposal, Critique}
alias Sw4rm.Voting.{Vote, ConfidenceWeighted}
alias Sw4rm.Voting.Aggregator

{:ok, room} = NegotiationRoom.start_link(room_id: "room-demo", name: nil)

{:ok, artifact_id} =
  NegotiationRoom.submit_proposal(room, %Proposal{
    artifact_id: "art-1",
    producer_id: "agent-1",
    artifact: "implementation plan v1",
    content_type: "text/plain",
    requested_critics: ["critic-a", "critic-b", "critic-c"]
  })

IO.puts("  Proposal submitted: #{artifact_id}")

for {critic, score, conf} <- [
      {"critic-a", 8.5, 0.9},
      {"critic-b", 7.0, 0.7},
      {"critic-c", 9.0, 0.95}
    ] do
  :ok =
    NegotiationRoom.add_critique(room, artifact_id, %Critique{
      critic_id: critic,
      score: score,
      confidence: conf,
      passed: true,
      strengths: ["solid"],
      weaknesses: [],
      recommendations: []
    })
end

votes_data = NegotiationRoom.get_votes(room, artifact_id)
IO.puts("  Collected #{length(votes_data)} critiques")

# Run voting aggregation
{:ok, agg} = Aggregator.start_link()

majority_votes = [
  Vote.new(choice: :approve, agent_id: "critic-a"),
  Vote.new(choice: :approve, agent_id: "critic-b"),
  Vote.new(choice: :revise, agent_id: "critic-c")
]

maj_result = Aggregator.run_vote(agg, majority_votes)
IO.puts("  MajorityVote winner: #{maj_result.winner} (#{maj_result.count}/#{maj_result.total})")

Aggregator.set_strategy(agg, ConfidenceWeighted)

cw_votes = [
  Vote.new(choice: :approve, confidence: 0.9, agent_id: "critic-a"),
  Vote.new(choice: :approve, confidence: 0.7, agent_id: "critic-b"),
  Vote.new(choice: :revise, confidence: 0.95, agent_id: "critic-c")
]

cw_result = Aggregator.run_vote(agg, cw_votes)
IO.puts("  ConfidenceWeighted winner: #{cw_result.winner}")

NegotiationRoom.decide(room, artifact_id, %{outcome: :approved, reason: "majority approved"})
decision = NegotiationRoom.get_decision(room, artifact_id)
IO.puts("  Decision: #{decision.outcome}")

# ──────────────────────────────────────────────
# 6. Worktree Management
# ──────────────────────────────────────────────
IO.puts("\n--- 6. Worktree Management ---")

{:ok, wt} = Sw4rm.WorktreeState.start_link()
IO.puts("  Initial state: #{Sw4rm.WorktreeState.current_state(wt)}")

{:ok, :bound_home} = Sw4rm.WorktreeState.bind(wt, "wt-home", "repo-1", "main")
IO.puts("  Bound to home: wt-home/main")

{:ok, :switch_pending} = Sw4rm.WorktreeState.request_switch(wt, "wt-feat", "repo-1", "feature-x")
IO.puts("  Switch requested: wt-feat/feature-x")

{:ok, :bound_non_home} = Sw4rm.WorktreeState.approve_switch(wt)
IO.puts("  Switch approved: bound_non_home")

{:ok, :bound_home} = Sw4rm.WorktreeState.revert_to_home(wt)
IO.puts("  Reverted to home: bound_home")

history = Sw4rm.WorktreeState.history(wt)
IO.puts("  Transitions recorded: #{length(history)}")

# ──────────────────────────────────────────────
# 7. Handoff Delegation (SW4-004)
# ──────────────────────────────────────────────
IO.puts("\n--- 7. Handoff Delegation (SW4-004) ---")

alias Sw4rm.Handoff
alias Sw4rm.Handoff.BudgetEnvelope
alias Sw4rm.Cancellation

{:ok, ho} = Handoff.start_link()

budget = %BudgetEnvelope{
  token_budget_remaining: 10_000,
  wall_time_remaining_ms: 60_000,
  deadline_epoch_ms: System.system_time(:millisecond) + 60_000,
  max_delegation_depth: 3,
  current_depth: 0
}

{:ok, parent_id} =
  Handoff.request_handoff(ho, %{
    from_agent: "leader",
    to_agent: "worker-1",
    correlation_id: "mission-1",
    budget: budget
  })

{:ok, _accepted} = Handoff.accept(ho, parent_id)
IO.puts("  Handoff #{parent_id} accepted")

# Child delegation
child_budget = %{budget | current_depth: 1}

{:ok, child_id} =
  Handoff.request_handoff(ho, %{
    from_agent: "worker-1",
    to_agent: "worker-2",
    correlation_id: "sub-1",
    budget: child_budget
  })

Handoff.register_child(ho, "mission-1", "sub-1")
IO.puts("  Child delegation: #{child_id} (depth=1)")

# Depth limit
deep_budget = %BudgetEnvelope{max_delegation_depth: 3, current_depth: 3}

case Handoff.request_handoff(ho, %{from_agent: "w2", to_agent: "w3", budget: deep_budget}) do
  {:error, :depth_exceeded} -> IO.puts("  Depth limit enforced at depth=3")
  _ -> IO.puts("  ERROR: depth limit not enforced!")
end

# Cancellation with CancellationManager
cancel_time = System.system_time(:millisecond)

cancel_state =
  Cancellation.new(now_ms_fn: fn -> cancel_time end)
  |> Cancellation.register_child_delegation("mission-1", "sub-1")

{:ok, cancel_state} =
  Cancellation.handle_cancel_delegation(cancel_state, %{
    correlation_id: "mission-1",
    reason: "abort",
    grace_period_ms: 10_000
  })

IO.puts("  Cancellation cascaded: mission-1 + sub-1")
IO.puts("  Grace period: #{Cancellation.effective_grace_period_ms(cancel_state, "mission-1")}ms")

before_expiry = cancel_time + 9_999
after_expiry = cancel_time + 10_000

IO.puts(
  "  Grace expired (before): #{Cancellation.is_grace_expired?(cancel_state, "mission-1", before_expiry)}"
)

IO.puts(
  "  Grace expired (after):  #{Cancellation.is_grace_expired?(cancel_state, "mission-1", after_expiry)}"
)

# ──────────────────────────────────────────────
# 8. Gateway Spillover (SW4-005)
# ──────────────────────────────────────────────
IO.puts("\n--- 8. Gateway Spillover (SW4-005) ---")

alias Sw4rm.Gateway
alias Sw4rm.Gateway.PeerDescriptor

{:ok, gw} = Gateway.start_link(agent_id: "local", capabilities: [:code])

peers = [
  %PeerDescriptor{agent_id: "peer-1", capabilities: [:code]},
  %PeerDescriptor{agent_id: "peer-2", capabilities: [:code, :review]}
]

Gateway.set_peers(gw, peers)

now = System.system_time(:millisecond)
Gateway.update_peer_health(gw, "peer-1", %{state: :running, last_heartbeat_ms: now})
Gateway.update_peer_health(gw, "peer-2", %{state: :running, last_heartbeat_ms: now})

IO.puts("  Registered #{length(peers)} peers")

{:ok, selected} = Gateway.select_peer(gw)
IO.puts("  Selected peer: #{selected.agent_id}")

{:ok, redirect} = Gateway.emit_redirect(gw, %{message_id: "m1"})

IO.puts(
  "  Redirect to: #{redirect.redirect_to} (error_code=#{redirect.error_code}, no retry_after_ms per spec)"
)

# ──────────────────────────────────────────────
# 9. Delegation with redirect following
# ──────────────────────────────────────────────
IO.puts("\n--- 9. Delegation with Redirect Following ---")

alias Sw4rm.Delegation

# Simulate redirect chain: a -> b -> c (accepted)
send_fn = fn request ->
  case request.to_agent do
    "gw-a" ->
      %{
        accepted: false,
        rejection_code: 20,
        rejection_reason: "busy",
        redirect_to_agent_id: "gw-b"
      }

    "gw-b" ->
      %{
        accepted: false,
        rejection_code: 20,
        rejection_reason: "busy",
        redirect_to_agent_id: "gw-c"
      }

    "gw-c" ->
      %{accepted: true, redirect_to_agent_id: ""}
  end
end

result =
  Delegation.delegate_to_swarm(%{
    send_handoff_fn: send_fn,
    from_agent: "parent",
    to_agent: "gw-a",
    reason: "delegate",
    request_id: "demo-req",
    delegation_policy: %{allow_spillover_routing: true, max_redirects: 5}
  })

IO.puts("  Accepted: #{result.accepted}")
IO.puts("  Attempts: #{inspect(result.attempts)}")

# Loop detection
loop_fn = fn request ->
  case request.to_agent do
    "x" ->
      %{accepted: false, rejection_code: 20, rejection_reason: "busy", redirect_to_agent_id: "y"}

    "y" ->
      %{accepted: false, rejection_code: 20, rejection_reason: "busy", redirect_to_agent_id: "x"}
  end
end

loop_result =
  Delegation.delegate_to_swarm(%{
    send_handoff_fn: loop_fn,
    from_agent: "parent",
    to_agent: "x",
    reason: "delegate",
    request_id: "demo-loop",
    delegation_policy: %{allow_spillover_routing: true, max_redirects: 10}
  })

IO.puts("  Loop detected: #{loop_result.rejection_reason}")

# ──────────────────────────────────────────────
# 10. Audit & Persistence
# ──────────────────────────────────────────────
IO.puts("\n--- 10. Audit & Persistence ---")

alias Sw4rm.Audit.{AuditRecord, NoOp, InMemory}

# NoOp auditor
noop_proof = NoOp.create_proof(nil, env, %{})
IO.puts("  NoOp proof: #{noop_proof.proof_type} (verified=#{noop_proof.verified})")

# InMemory auditor
{:ok, auditor} = InMemory.start_link()
proof = InMemory.create_proof(auditor, env, %{})
IO.puts("  InMemory proof: #{proof.proof_type}")

verified = InMemory.verify_proof(auditor, proof, env)
IO.puts("  Proof verified: #{verified}")

record = AuditRecord.new(envelope_id: env.message_id, action: "send", actor_id: config.agent_id)
record_id = InMemory.record_audit(auditor, record)
IO.puts("  Recorded audit: #{record_id}")

records = InMemory.query_records(auditor, action: "send")
IO.puts("  Query by action=send: #{length(records)} record(s)")

# ──────────────────────────────────────────────
# 11. Interceptor Chain
# ──────────────────────────────────────────────
IO.puts("\n--- 11. Interceptor Chain ---")

alias Sw4rm.Interceptor.{Chain, Timing, Logging}

chain =
  Chain.new()
  |> Chain.add(Timing)
  |> Chain.add(Logging)

IO.puts("  Chain: #{length(chain.interceptors)} interceptors")

_processed = Chain.process_request(chain, %{type: "test", payload: "demo"})
IO.puts("  Request processed through chain")

_resp = Chain.process_response(chain, %{status: :ok, data: "result"})
IO.puts("  Response processed through chain (reverse order)")

# ──────────────────────────────────────────────
# 12. ACK Tracking
# ──────────────────────────────────────────────
IO.puts("\n--- 12. ACK Tracking ---")

alias Sw4rm.AckManager

{:ok, ack} = AckManager.start_link(agent_id: config.agent_id)

{:ok, _} = AckManager.track_outgoing(ack, "msg-001")
{:ok, _} = AckManager.track_outgoing(ack, "msg-002")
IO.puts("  Tracked 2 outgoing messages")

{:ok, _} = AckManager.update(ack, "msg-001", :received)
{:ok, _} = AckManager.update(ack, "msg-001", :fulfilled)
IO.puts("  msg-001: received -> fulfilled")

unacked = AckManager.get_unacked(ack, :out)
IO.puts("  Unacked outgoing: #{length(unacked)}")

IO.puts("  Total tracked: #{AckManager.count(ack)}")

# ──────────────────────────────────────────────
IO.puts("\n=== All 12 sections completed successfully ===")
