defmodule Sw4rm.Clients.Reasoning do
  @moduledoc "Client for ReasoningProxy."
  use Sw4rm.Transport.Client,
    service: Sw4rm.Proto.Reasoning.ReasoningProxy,
    timeout_service: :reasoning

  def check_parallelism(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().reasoning)
    unary_call(endpoint, :check_parallelism, request, opts)
  end

  def evaluate_debate(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().reasoning)
    unary_call(endpoint, :evaluate_debate, request, opts)
  end

  def summarize(request, opts \\ []) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().reasoning)
    unary_call(endpoint, :summarize, request, opts)
  end
end
