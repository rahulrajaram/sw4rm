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

  @doc "Acknowledge delivery of a streamed item by its sequence number."
  def ack_delivery(agent_id, seq, opts \\ []) when is_binary(agent_id) and is_integer(seq) do
    endpoint = Keyword.get(opts, :endpoint, Sw4rm.Config.default_endpoints().router)
    message_id = Keyword.get(opts, :message_id, "")

    outcome =
      if Keyword.get(opts, :permanent_failure, false),
        do: :DELIVERY_ACK_OUTCOME_PERMANENT_FAILURE,
        else: :DELIVERY_ACK_OUTCOME_DELIVERED

    request = %Sw4rm.Proto.Router.DeliveryAckRequest{
      agent_id: agent_id,
      seq: seq,
      message_id: message_id,
      outcome: outcome
    }

    unary_call(endpoint, :ack_delivery, request, opts)
  end
end
