defmodule Sw4rm.Clients.Negotiation do
  @moduledoc "Client for NegotiationService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Negotiation.NegotiationService,
    timeout_service: :negotiation

  @doc "Open a new negotiation session."
  def open(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation)
    unary_call(endpoint, :open, request, opts)
  end

  @doc "Submit a proposal to an active negotiation."
  def propose(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation)
    unary_call(endpoint, :propose, request, opts)
  end

  @doc "Submit a counter-proposal."
  def counter(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation)
    unary_call(endpoint, :counter, request, opts)
  end

  @doc "Submit an evaluation/critique for a proposal."
  def evaluate(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation)
    unary_call(endpoint, :evaluate, request, opts)
  end

  @doc "Record a final decision on a negotiation."
  def decide(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation)
    unary_call(endpoint, :decide, request, opts)
  end

  @doc "Abort an active negotiation."
  def abort(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().negotiation)
    unary_call(endpoint, :abort, request, opts)
  end
end
