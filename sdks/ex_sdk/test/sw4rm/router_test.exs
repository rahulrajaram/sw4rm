defmodule Sw4rm.RouterTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Proto.Router

  test "StreamItem carries the router delivery sequence" do
    item = %Router.StreamItem{seq: 42}
    assert item.seq == 42
  end

  test "DeliveryAckRequest represents successful delivery" do
    request = %Router.DeliveryAckRequest{
      agent_id: "worker-1",
      seq: 42,
      message_id: "message-1",
      outcome: :DELIVERY_ACK_OUTCOME_DELIVERED
    }

    assert request.agent_id == "worker-1"
    assert request.seq == 42
    assert request.message_id == "message-1"
    assert request.outcome == :DELIVERY_ACK_OUTCOME_DELIVERED
  end

  test "DeliveryAckRequest represents permanent failure" do
    request = %Router.DeliveryAckRequest{
      agent_id: "worker-1",
      seq: 42,
      outcome: :DELIVERY_ACK_OUTCOME_PERMANENT_FAILURE
    }

    assert request.outcome == :DELIVERY_ACK_OUTCOME_PERMANENT_FAILURE
  end
end
