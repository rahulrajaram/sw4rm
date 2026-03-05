defmodule Sw4rm.Clients.Registry do
  @moduledoc "Client for RegistryService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Registry.RegistryService,
    timeout_service: :registry

  @doc "Register an agent descriptor with the registry service."
  def register_agent(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().registry)
    unary_call(endpoint, :register_agent, request, opts)
  end

  @doc "Send a heartbeat with agent state and health metadata."
  def heartbeat(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().registry)
    unary_call(endpoint, :heartbeat, request, opts)
  end

  @doc "Deregister an agent from the registry."
  def deregister_agent(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().registry)
    unary_call(endpoint, :deregister_agent, request, opts)
  end
end
