defmodule Sw4rm.Clients.Scheduler do
  @moduledoc "Client for SchedulerService."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Scheduler.SchedulerService,
    timeout_service: :scheduler

  @doc "Submit a task to the scheduler."
  def submit_task(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler)
    unary_call(endpoint, :submit_task, request, opts)
  end

  @doc "Request preemption of a running agent."
  def request_preemption(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler)
    unary_call(endpoint, :request_preemption, request, opts)
  end

  @doc "Initiate graceful shutdown of an agent."
  def shutdown_agent(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler)
    unary_call(endpoint, :shutdown_agent, request, opts)
  end

  @doc "Poll the activity buffer for pending entries."
  def poll_activity_buffer(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler)
    unary_call(endpoint, :poll_activity_buffer, request, opts)
  end

  @doc "Purge completed activities from the buffer."
  def purge_activity(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().scheduler)
    unary_call(endpoint, :purge_activity, request, opts)
  end
end
