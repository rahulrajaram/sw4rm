defmodule Sw4rm.Clients.Logging do
  @moduledoc "Client for LoggingService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Logging.LoggingService,
    timeout_service: :logging

  def ingest(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().logging)
    unary_call(endpoint, :ingest, request, opts)
  end
end
