defmodule Sw4rm.Clients.Hitl do
  @moduledoc "Client for HitlService."
  use Sw4rm.Transport.Client, service: Sw4rm.Proto.Hitl.HitlService, timeout_service: :hitl

  @doc "Submit a human-in-the-loop decision."
  def decide(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().hitl)
    unary_call(endpoint, :decide, request, opts)
  end
end
