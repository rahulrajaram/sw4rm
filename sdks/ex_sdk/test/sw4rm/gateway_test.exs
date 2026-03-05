defmodule Sw4rm.GatewayTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Gateway
  alias Sw4rm.Gateway.PeerDescriptor

  setup do
    {:ok, gw} = Gateway.start_link(agent_id: "local-agent", capabilities: [:code])
    %{gw: gw}
  end

  describe "set_peers/2" do
    test "sets peer list", %{gw: gw} do
      peers = [
        %PeerDescriptor{agent_id: "peer-1", capabilities: [:code]},
        %PeerDescriptor{agent_id: "peer-2", capabilities: [:code, :review]}
      ]

      assert :ok = Gateway.set_peers(gw, peers)
      result = Gateway.list_peers(gw)
      assert length(result) == 2
    end

    test "accepts maps as peers", %{gw: gw} do
      peers = [%{agent_id: "peer-1", capabilities: [:code]}]
      assert :ok = Gateway.set_peers(gw, peers)
    end
  end

  describe "select_peer/2" do
    test "selects eligible peer", %{gw: gw} do
      peers = [
        %PeerDescriptor{agent_id: "peer-1", capabilities: [:code]},
        %PeerDescriptor{agent_id: "peer-2", capabilities: [:code]}
      ]

      Gateway.set_peers(gw, peers)

      now = System.system_time(:millisecond)
      assert {:ok, %PeerDescriptor{}} = Gateway.select_peer(gw, now_ms: now)
    end

    test "excludes local agent", %{gw: gw} do
      peers = [%PeerDescriptor{agent_id: "local-agent", capabilities: [:code]}]
      Gateway.set_peers(gw, peers)

      assert {:error, :no_eligible_peers} = Gateway.select_peer(gw)
    end

    test "excludes peers without matching capabilities", %{gw: gw} do
      peers = [%PeerDescriptor{agent_id: "peer-1", capabilities: [:review]}]
      Gateway.set_peers(gw, peers)

      assert {:error, :no_eligible_peers} = Gateway.select_peer(gw, capabilities: [:code])
    end

    test "round-robin selection", %{gw: gw} do
      peers = [
        %PeerDescriptor{agent_id: "peer-1", capabilities: [:code]},
        %PeerDescriptor{agent_id: "peer-2", capabilities: [:code]}
      ]

      Gateway.set_peers(gw, peers)

      {:ok, first} = Gateway.select_peer(gw)
      {:ok, second} = Gateway.select_peer(gw)
      assert first.agent_id != second.agent_id
    end
  end

  describe "update_peer_health/3" do
    test "updates peer health state", %{gw: gw} do
      peers = [%PeerDescriptor{agent_id: "peer-1", capabilities: [:code]}]
      Gateway.set_peers(gw, peers)

      Gateway.update_peer_health(gw, "peer-1", %{
        state: :running,
        last_heartbeat_ms: System.system_time(:millisecond)
      })

      [{_peer, health}] = Gateway.list_peers(gw)
      assert health.state == :running
    end

    test "unhealthy peer excluded from selection", %{gw: gw} do
      peers = [%PeerDescriptor{agent_id: "peer-1", capabilities: [:code]}]
      Gateway.set_peers(gw, peers)
      Gateway.update_peer_health(gw, "peer-1", %{state: :failed})

      assert {:error, :no_eligible_peers} = Gateway.select_peer(gw)
    end
  end

  describe "emit_redirect/3" do
    test "builds redirect envelope", %{gw: gw} do
      peers = [%PeerDescriptor{agent_id: "peer-1", capabilities: [:code]}]
      Gateway.set_peers(gw, peers)

      original = %{message_id: "m1", payload: "data"}
      assert {:ok, redirect} = Gateway.emit_redirect(gw, original)
      assert redirect.redirect_to == "peer-1"
      assert redirect.original_envelope == original
      assert redirect.error_code == 20
    end

    test "returns error when no peers", %{gw: gw} do
      assert {:error, :no_eligible_peers} = Gateway.emit_redirect(gw, %{})
    end
  end
end
