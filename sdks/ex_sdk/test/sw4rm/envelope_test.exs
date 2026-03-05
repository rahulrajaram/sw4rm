defmodule Sw4rm.EnvelopeTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Envelope

  describe "new/1" do
    test "builds an envelope with required fields" do
      env = Envelope.new(producer_id: "agent-1", message_type: :task)
      assert env.producer_id == "agent-1"
      assert env.message_type == :task
      assert is_binary(env.message_id)
      assert is_binary(env.correlation_id)
      assert env.sequence_number == 1
      assert env.retry_count == 0
      assert env.state == :sent
      assert env.content_type == "application/json"
    end

    test "raises on missing producer_id" do
      assert_raise KeyError, fn ->
        Envelope.new(message_type: :task)
      end
    end

    test "raises on missing message_type" do
      assert_raise KeyError, fn ->
        Envelope.new(producer_id: "agent-1")
      end
    end

    test "sets content_length from payload" do
      payload = "hello world"
      env = Envelope.new(producer_id: "p", message_type: :task, payload: payload)
      assert env.content_length == byte_size(payload)
    end

    test "accepts optional fields" do
      env =
        Envelope.new(
          producer_id: "agent-1",
          message_type: :task,
          correlation_id: "corr-123",
          sequence_number: 5,
          retry_count: 2,
          ttl_ms: 60_000,
          repo_id: "repo-1",
          worktree_id: "wt-1"
        )

      assert env.correlation_id == "corr-123"
      assert env.sequence_number == 5
      assert env.retry_count == 2
      assert env.ttl_ms == 60_000
    end
  end

  describe "generate_uuid/0" do
    test "produces valid UUIDv4 format" do
      uuid = Envelope.generate_uuid()

      assert Regex.match?(
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
               uuid
             )
    end

    test "produces unique values" do
      uuids = for _ <- 1..100, do: Envelope.generate_uuid()
      assert length(Enum.uniq(uuids)) == 100
    end
  end

  describe "generate_hlc_timestamp/0" do
    test "produces HLC-prefixed timestamp" do
      hlc = Envelope.generate_hlc_timestamp()
      assert String.starts_with?(hlc, "HLC:")
      parts = String.split(hlc, ":")
      assert length(parts) == 4
    end
  end

  describe "compute_deterministic_hash/1" do
    test "produces 16-char hex string" do
      hash = Envelope.compute_deterministic_hash(%{a: 1, b: 2})
      assert byte_size(hash) == 16
      assert Regex.match?(~r/^[0-9a-f]{16}$/, hash)
    end

    test "same input produces same hash" do
      params = %{operation: "send", target: "agent-2"}
      h1 = Envelope.compute_deterministic_hash(params)
      h2 = Envelope.compute_deterministic_hash(params)
      assert h1 == h2
    end

    test "different input produces different hash" do
      h1 = Envelope.compute_deterministic_hash(%{a: 1})
      h2 = Envelope.compute_deterministic_hash(%{a: 2})
      assert h1 != h2
    end

    test "accepts keyword list" do
      h1 = Envelope.compute_deterministic_hash(a: 1, b: 2)
      h2 = Envelope.compute_deterministic_hash(%{a: 1, b: 2})
      assert h1 == h2
    end
  end

  describe "make_idempotency_token/3" do
    test "creates colon-separated token" do
      token = Envelope.make_idempotency_token("agent-1", "send", "abcd1234")
      assert token == "agent-1:send:abcd1234"
    end
  end

  describe "validate!/1" do
    test "passes for valid envelope" do
      env = Envelope.new(producer_id: "agent-1", message_type: :task)
      assert Envelope.validate!(env) == :ok
    end

    test "raises on nil message_id" do
      env = %Envelope{
        producer_id: "a",
        message_type: :t,
        message_id: nil,
        correlation_id: "c",
        sequence_number: 1,
        retry_count: 0
      }

      assert_raise Sw4rm.Error.Validation, fn -> Envelope.validate!(env) end
    end

    test "raises on nil producer_id" do
      env = %Envelope{
        message_id: "m",
        producer_id: nil,
        message_type: :t,
        correlation_id: "c",
        sequence_number: 1,
        retry_count: 0
      }

      assert_raise Sw4rm.Error.Validation, fn -> Envelope.validate!(env) end
    end

    test "raises on non-positive sequence_number" do
      env = %Envelope{
        message_id: "m",
        producer_id: "p",
        message_type: :t,
        correlation_id: "c",
        sequence_number: 0,
        retry_count: 0
      }

      assert_raise Sw4rm.Error.Validation, fn -> Envelope.validate!(env) end
    end

    test "raises on negative retry_count" do
      env = %Envelope{
        message_id: "m",
        producer_id: "p",
        message_type: :t,
        correlation_id: "c",
        sequence_number: 1,
        retry_count: -1
      }

      assert_raise Sw4rm.Error.Validation, fn -> Envelope.validate!(env) end
    end
  end

  describe "terminal_state?/1" do
    test "terminal states" do
      for state <- [:fulfilled, :rejected, :failed, :timed_out] do
        assert Envelope.terminal_state?(state)
      end
    end

    test "non-terminal states" do
      for state <- [:sent, :received, :read, :unspecified] do
        refute Envelope.terminal_state?(state)
      end
    end
  end

  describe "update_state/2" do
    test "returns envelope with new state" do
      env = Envelope.new(producer_id: "p", message_type: :t)
      updated = Envelope.update_state(env, :fulfilled)
      assert updated.state == :fulfilled
      assert updated.producer_id == env.producer_id
    end
  end
end
