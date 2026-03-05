defmodule Sw4rm.Clients.NegotiationRoom do
  @moduledoc "Client for NegotiationRoomService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.NegotiationRoom.NegotiationRoomService,
    timeout_service: :negotiation_room

  @doc "Submit a proposal to the negotiation room."
  def submit_proposal(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation_room)
    unary_call(endpoint, :submit_proposal, request, opts)
  end

  @doc "Submit a vote/critique on a proposal."
  def submit_vote(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation_room)
    unary_call(endpoint, :submit_vote, request, opts)
  end

  @doc "Retrieve all votes for a given artifact."
  def get_votes(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation_room)
    unary_call(endpoint, :get_votes, request, opts)
  end

  @doc "Get the final decision for a proposal."
  def get_decision(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation_room)
    unary_call(endpoint, :get_decision, request, opts)
  end

  @doc "Block until a decision is reached for a proposal."
  def wait_for_decision(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation_room)
    unary_call(endpoint, :wait_for_decision, request, opts)
  end
end
