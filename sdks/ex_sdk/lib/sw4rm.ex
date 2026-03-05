defmodule Sw4rm do
  @moduledoc """
  Elixir SDK for the SW4RM multi-agent coordination protocol (v0.6.0).

  SW4RM provides infrastructure for orchestrating autonomous coding agents
  across shared repositories. This SDK implements the full protocol including:

  - **Message routing** via gRPC with Three-ID envelope model
  - **Agent lifecycle** state machine (spec S8)
  - **Activity buffer** for tracking in-flight operations (spec S10)
  - **Worktree management** for isolated Git operations (spec S16)
  - **Multi-agent negotiation** with pluggable voting strategies (spec S17)
  - **Inter-swarm composition** with delegation and handoff (SW4-004)
  - **Spillover routing** via health-aware gateway selection (SW4-005)

  ## Quick Start

      # Register an agent
      {:ok, _} = Sw4rm.Clients.Registry.register_agent(%{
        agent_id: "agent-1",
        name: "CodeBot",
        capabilities: ["code_review", "testing"]
      })

      # Send a message
      envelope = Sw4rm.Envelope.new(
        producer_id: "agent-1",
        message_type: :DATA,
        payload: Jason.encode!(%{task: "review PR #42"})
      )
      {:ok, _} = Sw4rm.Clients.Router.send_message(envelope)

  ## Architecture

  The SDK uses OTP patterns for concurrency:

  - `GenServer` for stateful components (StateMachine, ActivityBuffer, AckManager)
  - `Registry` for named client lookup
  - Behaviours for pluggable backends (Voting, Secrets, Persistence, Audit)
  - `{:ok, _} | {:error, _}` tuples everywhere; exceptions only in `!` variants
  """

  @doc "Returns the SDK version string."
  @spec version() :: String.t()
  def version, do: "0.6.0"
end
