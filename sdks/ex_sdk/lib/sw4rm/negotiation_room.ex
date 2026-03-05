defmodule Sw4rm.NegotiationRoom do
  @moduledoc """
  GenServer per negotiation room managing proposals, critiques, votes, and decisions.

  Supports SW4-001 extensions: quorum policies, vote collection timeouts,
  late vote tracking, and unavailable critic detection.
  """
  use GenServer

  defmodule Proposal do
    @moduledoc false
    defstruct [
      :artifact_id,
      :producer_id,
      :artifact,
      :content_type,
      :requested_critics,
      :metadata,
      vote_collection_timeout_s: 300,
      quorum_policy: nil
    ]
  end

  defmodule Critique do
    @moduledoc false
    defstruct [
      :critic_id,
      :score,
      :confidence,
      :passed,
      :strengths,
      :weaknesses,
      :recommendations
    ]
  end

  # -- Client API --

  @doc "Start a negotiation room. Required: `:room_id`."
  def start_link(opts \\ []) do
    room_id = Keyword.fetch!(opts, :room_id)
    name = Keyword.get(opts, :name, via_name(room_id))
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Submit a `%Proposal{}` to the room."
  def submit_proposal(server, proposal), do: GenServer.call(server, {:submit, proposal})

  @doc "Add a `%Critique{}` for the given artifact ID."
  def add_critique(server, artifact_id, critique),
    do: GenServer.call(server, {:critique, artifact_id, critique})

  @doc "Get all critiques/votes for an artifact."
  def get_votes(server, artifact_id), do: GenServer.call(server, {:get_votes, artifact_id})

  @doc "Record a final decision for an artifact."
  def decide(server, artifact_id, decision),
    do: GenServer.call(server, {:decide, artifact_id, decision})

  @doc "Get the recorded decision for an artifact, or `nil`."
  def get_decision(server, artifact_id), do: GenServer.call(server, {:get_decision, artifact_id})

  @doc "List all submitted proposals."
  def list_proposals(server), do: GenServer.call(server, :list_proposals)

  @doc "Return room metadata (room_id, description, counts)."
  def room_info(server), do: GenServer.call(server, :info)

  defp via_name(room_id),
    do: {:via, Registry, {Sw4rm.ClientRegistry, {:negotiation_room, room_id}}}

  # -- Callbacks --

  @impl true
  def init(opts) do
    {:ok,
     %{
       room_id: Keyword.fetch!(opts, :room_id),
       description: Keyword.get(opts, :description),
       created_at: System.system_time(:second),
       proposals: %{},
       votes: %{},
       decisions: %{},
       timers: %{},
       timed_out: MapSet.new(),
       late_votes: %{},
       unavailable_critics: %{}
     }}
  end

  @impl true
  def handle_call({:submit, %Proposal{} = p}, _from, s) do
    if Map.has_key?(s.proposals, p.artifact_id) do
      {:reply, {:error, :already_exists}, s}
    else
      policy = p.quorum_policy || Sw4rm.QuorumPolicy.default_policy()
      proposal = %{p | quorum_policy: policy}

      s =
        %{
          s
          | proposals: Map.put(s.proposals, p.artifact_id, proposal),
            votes: Map.put(s.votes, p.artifact_id, []),
            late_votes: Map.put(s.late_votes, p.artifact_id, []),
            unavailable_critics: Map.put(s.unavailable_critics, p.artifact_id, [])
        }

      s = schedule_collection_timeout(s, proposal)

      {:reply, {:ok, p.artifact_id}, s}
    end
  end

  def handle_call({:critique, artifact_id, %Critique{} = c}, _from, s) do
    case Map.get(s.proposals, artifact_id) do
      nil ->
        {:reply, {:error, :not_found}, s}

      _proposal ->
        if MapSet.member?(s.timed_out, artifact_id) do
          # After timeout — store as late vote
          late = Map.get(s.late_votes, artifact_id, [])

          late_entry = %{
            critic_id: c.critic_id,
            vote: c,
            received_at: System.system_time(:second)
          }

          s = %{s | late_votes: Map.put(s.late_votes, artifact_id, [late_entry | late])}
          {:reply, {:ok, :late_vote}, s}
        else
          existing = Map.get(s.votes, artifact_id, [])

          if Enum.any?(existing, &(&1.critic_id == c.critic_id)) do
            {:reply, {:error, :already_voted}, s}
          else
            {:reply, :ok, %{s | votes: Map.put(s.votes, artifact_id, [c | existing])}}
          end
        end
    end
  end

  def handle_call({:get_votes, artifact_id}, _from, s) do
    {:reply, Map.get(s.votes, artifact_id, []), s}
  end

  def handle_call({:decide, artifact_id, decision}, _from, s) do
    {:reply, :ok, %{s | decisions: Map.put(s.decisions, artifact_id, decision)}}
  end

  def handle_call({:get_decision, artifact_id}, _from, s) do
    {:reply, Map.get(s.decisions, artifact_id), s}
  end

  def handle_call(:list_proposals, _from, s) do
    {:reply, Map.values(s.proposals), s}
  end

  def handle_call(:info, _from, s) do
    {:reply,
     %{
       room_id: s.room_id,
       description: s.description,
       created_at: s.created_at,
       proposal_count: map_size(s.proposals),
       decision_count: map_size(s.decisions)
     }, s}
  end

  @impl true
  def handle_info({:collection_timeout, artifact_id}, s) do
    if Map.has_key?(s.decisions, artifact_id) do
      # Already decided — ignore timeout
      {:noreply, s}
    else
      s = %{s | timed_out: MapSet.put(s.timed_out, artifact_id)}

      proposal = Map.get(s.proposals, artifact_id)
      votes = Map.get(s.votes, artifact_id, [])
      requested = proposal.requested_critics || []
      policy = proposal.quorum_policy || Sw4rm.QuorumPolicy.default_policy()

      {result, details} = Sw4rm.QuorumPolicy.evaluate(votes, requested, policy)

      voted_ids = MapSet.new(Enum.map(votes, & &1.critic_id))
      unavailable = Enum.reject(requested, &MapSet.member?(voted_ids, &1))

      s = %{s | unavailable_critics: Map.put(s.unavailable_critics, artifact_id, unavailable)}

      decision = %{
        outcome: decision_outcome(result, details),
        quorum_met: result == :quorum_met,
        votes_received: details.votes_received,
        votes_expected: details.votes_expected,
        collection_timeout_reached: true,
        unavailable_critics: unavailable,
        votes: votes
      }

      s = %{s | decisions: Map.put(s.decisions, artifact_id, decision)}
      {:noreply, s}
    end
  end

  def handle_info(_msg, s), do: {:noreply, s}

  # -- Private --

  defp schedule_collection_timeout(s, proposal) do
    timeout_s = proposal.vote_collection_timeout_s || 300
    timeout_ms = timeout_s * 1000
    ref = Process.send_after(self(), {:collection_timeout, proposal.artifact_id}, timeout_ms)
    %{s | timers: Map.put(s.timers, proposal.artifact_id, ref)}
  end

  defp decision_outcome(:quorum_met, _details), do: :approved

  defp decision_outcome(:quorum_not_met, %{action: {:escalate_hitl, _}}),
    do: :escalated_to_hitl

  defp decision_outcome(:quorum_not_met, %{action: :decided_with_abstains}),
    do: :approved_with_abstains

  defp decision_outcome(:quorum_not_met, %{action: :decided_with_available}),
    do: :approved_with_available
end

defmodule Sw4rm.NegotiationRoom.Store do
  @moduledoc "Registry of active negotiation rooms."
  use GenServer

  @doc "Start the room store."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc "Create and start a new negotiation room with the given ID."
  def create_room(server, room_id, opts \\ []) do
    GenServer.call(server, {:create, room_id, opts})
  end

  @doc "Look up a room's PID by ID, or `nil`."
  def get_room(server, room_id), do: GenServer.call(server, {:get, room_id})

  @doc "Stop and remove a room by ID."
  def close_room(server, room_id), do: GenServer.call(server, {:close, room_id})

  @doc "List all active room IDs."
  def list_rooms(server), do: GenServer.call(server, :list)

  @impl true
  def init(:ok), do: {:ok, %{rooms: %{}}}

  @impl true
  def handle_call({:create, room_id, opts}, _from, s) do
    if Map.has_key?(s.rooms, room_id) do
      {:reply, {:error, :already_exists}, s}
    else
      room_opts = [room_id: room_id] ++ opts

      case Sw4rm.NegotiationRoom.start_link(room_opts) do
        {:ok, pid} ->
          {:reply, {:ok, pid}, %{s | rooms: Map.put(s.rooms, room_id, pid)}}

        {:error, _} = err ->
          {:reply, err, s}
      end
    end
  end

  def handle_call({:get, room_id}, _from, s) do
    {:reply, Map.get(s.rooms, room_id), s}
  end

  def handle_call({:close, room_id}, _from, s) do
    case Map.pop(s.rooms, room_id) do
      {nil, _} ->
        {:reply, {:error, :not_found}, s}

      {pid, rooms} ->
        GenServer.stop(pid, :normal)
        {:reply, :ok, %{s | rooms: rooms}}
    end
  end

  def handle_call(:list, _from, s) do
    {:reply, Map.keys(s.rooms), s}
  end
end
