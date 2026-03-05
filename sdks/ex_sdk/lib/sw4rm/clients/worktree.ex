defmodule Sw4rm.Clients.Worktree do
  @moduledoc "Client for WorktreeService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Worktree.WorktreeService,
    timeout_service: :worktree

  def bind(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().worktree)
    unary_call(endpoint, :bind, request, opts)
  end

  def unbind(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().worktree)
    unary_call(endpoint, :unbind, request, opts)
  end

  def request_switch(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().worktree)
    unary_call(endpoint, :request_switch, request, opts)
  end

  def approve_switch(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().worktree)
    unary_call(endpoint, :approve_switch, request, opts)
  end

  def reject_switch(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().worktree)
    unary_call(endpoint, :reject_switch, request, opts)
  end

  def status(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().worktree)
    unary_call(endpoint, :status, request, opts)
  end
end
