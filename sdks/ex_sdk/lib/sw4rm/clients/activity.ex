defmodule Sw4rm.Clients.Activity do
  @moduledoc "Client for ActivityService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Activity.ActivityService,
    timeout_service: :activity

  @doc "Append an artifact to an activity record."
  def append_artifact(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().activity)
    unary_call(endpoint, :append_artifact, request, opts)
  end

  @doc "List artifacts for an activity."
  def list_artifacts(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().activity)
    unary_call(endpoint, :list_artifacts, request, opts)
  end
end
