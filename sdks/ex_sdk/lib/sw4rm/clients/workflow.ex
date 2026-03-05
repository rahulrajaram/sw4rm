defmodule Sw4rm.Clients.Workflow do
  @moduledoc "Client for WorkflowService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Workflow.WorkflowService,
    timeout_service: :workflow

  @doc "Create a new workflow definition."
  def create_workflow(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().workflow)
    unary_call(endpoint, :create_workflow, request, opts)
  end

  @doc "Start execution of a workflow."
  def start_workflow(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().workflow)
    unary_call(endpoint, :start_workflow, request, opts)
  end

  @doc "Get the current state of a running workflow."
  def get_workflow_state(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().workflow)
    unary_call(endpoint, :get_workflow_state, request, opts)
  end

  @doc "Resume a paused or waiting workflow."
  def resume_workflow(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().workflow)
    unary_call(endpoint, :resume_workflow, request, opts)
  end
end
