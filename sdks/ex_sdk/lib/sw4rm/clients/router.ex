defmodule Sw4rm.Clients.Router do
  @moduledoc "Client for RouterService."
  use Sw4rm.Transport.Client, service: Sw4rm.Proto.Router.RouterService, timeout_service: :router

  @doc "Send a message through the router."
  def send_message(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().router)
    unary_call(endpoint, :send_message, request, opts)
  end

  @doc "Open a server-streaming subscription for incoming messages."
  def stream_incoming(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().router)
    server_stream(endpoint, :stream_incoming, request, opts)
  end
end
