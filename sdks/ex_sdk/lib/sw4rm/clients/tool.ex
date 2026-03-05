defmodule Sw4rm.Clients.Tool do
  @moduledoc "Client for ToolService."
  use Sw4rm.Transport.Client, service: Sw4rm.Proto.Tool.ToolService, timeout_service: :tool

  def call(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().tool)
    unary_call(endpoint, :call, request, opts)
  end

  def call_stream(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().tool)
    server_stream(endpoint, :call_stream, request, opts)
  end

  def cancel(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().tool)
    unary_call(endpoint, :cancel, request, opts)
  end
end
