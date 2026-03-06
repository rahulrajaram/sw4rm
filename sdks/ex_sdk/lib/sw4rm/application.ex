defmodule Sw4rm.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Registry, keys: :unique, name: Sw4rm.ClientRegistry},
      Sw4rm.LLM.RateLimiter
    ]

    opts = [strategy: :one_for_one, name: Sw4rm.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
