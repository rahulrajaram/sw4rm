defmodule Sw4rm.EnvelopeWireBoundaryTest do
  use ExUnit.Case, async: true
  alias Sw4rm.Envelope

  @vectors __DIR__
           |> Path.join("../../../../tests/conformance_vectors/idempotency_vectors.json")
           |> File.read!()
           |> Jason.decode!()
           |> Map.fetch!("vectors")
  for vector <- @vectors do
    @vector vector
    test "portable idempotency #{@vector["id"]}" do
      if @vector["rejected"] do
        # R43: LF in producer/operation must be rejected, not hashed.
        assert_raise Sw4rm.Error.Validation, fn ->
          Envelope.compute_idempotency_token(
            @vector["producer_id"],
            @vector["operation"],
            Base.decode16!(@vector["canonical_hex"], case: :lower)
          )
        end
      else
        assert Envelope.compute_idempotency_token(
                 @vector["producer_id"],
                 @vector["operation"],
                 Base.decode16!(@vector["canonical_hex"], case: :lower)
               ) == @vector["token"]
      end
    end
  end

  test "SDK envelope composes with protobuf without losing lineage or timestamp" do
    envelope =
      Envelope.new(
        producer_id: "sender",
        message_type: :data,
        parent_correlation_id: "parent",
        sequence_number: 18_446_744_073_709_551_615,
        timestamp: %Google.Protobuf.Timestamp{seconds: -1, nanos: 125},
        payload: <<0, 255>>
      )

    restored =
      envelope
      |> Envelope.to_proto()
      |> Sw4rm.Proto.Common.Envelope.encode()
      |> Sw4rm.Proto.Common.Envelope.decode()
      |> Envelope.from_proto()

    assert restored.parent_correlation_id == "parent"
    assert restored.sequence_number == 18_446_744_073_709_551_615
    assert restored.timestamp == %Google.Protobuf.Timestamp{seconds: -1, nanos: 125}
    assert restored.payload == <<0, 255>>
    assert Envelope.to_proto(restored) == Envelope.to_proto(envelope)
  end
end
