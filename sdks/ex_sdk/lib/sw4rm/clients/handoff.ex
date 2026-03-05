defmodule Sw4rm.Clients.Handoff do
  @moduledoc "Client for HandoffService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Handoff.HandoffService,
    timeout_service: :handoff

  @doc "Request a handoff to another agent."
  def request_handoff(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().handoff)
    unary_call(endpoint, :request_handoff, request, opts)
  end

  @doc "Accept a pending handoff."
  def accept_handoff(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().handoff)
    unary_call(endpoint, :accept_handoff, request, opts)
  end

  @doc "Reject a pending handoff."
  def reject_handoff(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().handoff)
    unary_call(endpoint, :reject_handoff, request, opts)
  end

  @doc "Get all pending handoffs for an agent."
  def get_pending_handoffs(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().handoff)
    unary_call(endpoint, :get_pending_handoffs, request, opts)
  end

  @doc "Complete a handoff with result."
  def complete_handoff(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().handoff)
    unary_call(endpoint, :complete_handoff, request, opts)
  end

  @doc "Cancel a delegation and cascade to children."
  def cancel_delegation(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().handoff)
    unary_call(endpoint, :cancel_delegation, request, opts)
  end
end
