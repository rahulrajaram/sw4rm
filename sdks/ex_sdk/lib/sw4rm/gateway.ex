defmodule Sw4rm.Gateway do
  @moduledoc """
  SW4-005 spillover routing: health-aware peer selection and redirect emission.

  GenServer managing peer descriptors, runtime health state, and round-robin
  peer selection for gateway redirect scenarios.
  """
  use GenServer

  @default_liveness_threshold_ms 30_000
  @non_serving_states [:initializing, :failed, :shutting_down]

  defmodule PeerDescriptor do
    @moduledoc "Gateway peer metadata for redirect eligibility."
    @type t :: %__MODULE__{}
    defstruct [:agent_id, registration_type: :swarm_gateway, capabilities: []]
  end

  defmodule PeerRuntimeState do
    @moduledoc "Mutable health state for a known peer."
    @type t :: %__MODULE__{}
    defstruct state: :running, last_heartbeat_ms: 0, cooldown_until_ms: 0
  end

  # -- Client API --

  @doc "Start the gateway. Options: `:agent_id`, `:capabilities`, `:liveness_threshold_ms`."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc "Set the list of peer descriptors."
  def set_peers(server, peers), do: GenServer.call(server, {:set_peers, peers})

  @doc "Update health state for a peer."
  def update_peer_health(server, agent_id, state_update) do
    GenServer.call(server, {:update_health, agent_id, state_update})
  end

  @doc "Select the next eligible peer for redirect (round-robin, health-filtered)."
  def select_peer(server, opts \\ []), do: GenServer.call(server, {:select_peer, opts})

  @doc "Build a redirect envelope for the selected peer."
  def emit_redirect(server, original_envelope, opts \\ []) do
    GenServer.call(server, {:emit_redirect, original_envelope, opts})
  end

  @doc "Get all known peers and their health state."
  def list_peers(server), do: GenServer.call(server, :list_peers)

  # -- Callbacks --

  @impl true
  def init(opts) do
    {:ok,
     %{
       local_agent_id: Keyword.get(opts, :agent_id, ""),
       local_capabilities: Keyword.get(opts, :capabilities, []),
       liveness_threshold_ms:
         Keyword.get(opts, :liveness_threshold_ms, @default_liveness_threshold_ms),
       peers: [],
       runtime: %{},
       rr_cursor: 0
     }}
  end

  @impl true
  def handle_call({:set_peers, peers}, _from, s) do
    descriptors =
      Enum.map(peers, fn
        %PeerDescriptor{} = p -> p
        map when is_map(map) -> struct(PeerDescriptor, map)
      end)

    {:reply, :ok, %{s | peers: descriptors}}
  end

  def handle_call({:update_health, agent_id, update}, _from, s) do
    current = Map.get(s.runtime, agent_id, %PeerRuntimeState{})
    updated = Map.merge(current, update)
    {:reply, :ok, %{s | runtime: Map.put(s.runtime, agent_id, updated)}}
  end

  def handle_call({:select_peer, opts}, _from, s) do
    case eligible_peers(s, opts) do
      [] ->
        {:reply, {:error, :no_eligible_peers}, s}

      peers ->
        idx = rem(s.rr_cursor, length(peers))
        selected = Enum.at(peers, idx)
        {:reply, {:ok, selected}, %{s | rr_cursor: s.rr_cursor + 1}}
    end
  end

  def handle_call({:emit_redirect, envelope, opts}, _from, s) do
    case eligible_peers(s, opts) do
      [] ->
        {:reply, {:error, :no_eligible_peers}, s}

      peers ->
        idx = rem(s.rr_cursor, length(peers))
        selected = Enum.at(peers, idx)

        redirect = %{
          redirect_to: selected.agent_id,
          original_envelope: envelope,
          error_code: Sw4rm.ErrorCodes.redirect()
        }

        {:reply, {:ok, redirect}, %{s | rr_cursor: s.rr_cursor + 1}}
    end
  end

  def handle_call(:list_peers, _from, s) do
    result =
      Enum.map(s.peers, fn peer ->
        health = Map.get(s.runtime, peer.agent_id, %PeerRuntimeState{})
        {peer, health}
      end)

    {:reply, result, s}
  end

  # -- Helpers --

  defp eligible_peers(s, opts) do
    now = Keyword.get(opts, :now_ms, System.system_time(:millisecond))
    required_caps = Keyword.get(opts, :capabilities, s.local_capabilities)

    Enum.filter(s.peers, fn peer ->
      peer.agent_id != s.local_agent_id and
        capabilities_match?(peer.capabilities, required_caps) and
        peer_healthy?(s.runtime, peer.agent_id, now, s.liveness_threshold_ms)
    end)
  end

  defp capabilities_match?(peer_caps, required_caps) do
    required_set = MapSet.new(required_caps)
    peer_set = MapSet.new(peer_caps)
    MapSet.subset?(required_set, peer_set)
  end

  defp peer_healthy?(runtime, agent_id, now, threshold) do
    case Map.get(runtime, agent_id) do
      nil ->
        true

      %PeerRuntimeState{} = rt ->
        rt.state not in @non_serving_states and
          (rt.last_heartbeat_ms == 0 or now - rt.last_heartbeat_ms < threshold) and
          now >= rt.cooldown_until_ms
    end
  end
end
