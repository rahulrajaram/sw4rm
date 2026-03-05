defmodule Sw4rm.Clients.Connector do
  @moduledoc "Client for ConnectorService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Connector.ConnectorService,
    timeout_service: :connector

  @doc "Register a tool provider with the connector service."
  def register_provider(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().connector)
    unary_call(endpoint, :register_provider, request, opts)
  end

  @doc "Describe available tools from a registered provider."
  def describe_tools(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().connector)
    unary_call(endpoint, :describe_tools, request, opts)
  end
end
