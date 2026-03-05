defmodule Sw4rm.AuditTest do
  use ExUnit.Case, async: true

  alias Sw4rm.Audit
  alias Sw4rm.Audit.{Proof, AuditRecord, NoOp, InMemory}

  describe "compute_envelope_hash/1" do
    test "produces hex string" do
      hash = Audit.compute_envelope_hash(%{message_id: "m1", payload: "data"})
      assert is_binary(hash)
      assert Regex.match?(~r/^[0-9a-f]+$/, hash)
    end

    test "same input produces same hash" do
      env = %{a: 1}
      assert Audit.compute_envelope_hash(env) == Audit.compute_envelope_hash(env)
    end
  end

  describe "NoOp" do
    test "create_proof returns noop proof" do
      proof = NoOp.create_proof(:noop, %{}, "policy")
      assert proof.proof_type == :no_op
      assert proof.verified == true
    end

    test "verify_proof always true" do
      assert NoOp.verify_proof(:noop, %Proof{}, %{})
    end

    test "record_audit returns nil" do
      assert NoOp.record_audit(:noop, %AuditRecord{}) == nil
    end

    test "query_records returns empty" do
      assert NoOp.query_records(:noop, []) == []
    end
  end

  describe "InMemory" do
    setup do
      {:ok, auditor} = InMemory.start_link()
      %{auditor: auditor}
    end

    test "create_proof generates SHA-256 proof", %{auditor: a} do
      proof = InMemory.create_proof(a, %{message_id: "m1"}, "policy")
      assert proof.proof_type == :sha256_hash
      assert is_binary(proof.proof_data)
      assert proof.verified == false
    end

    test "verify_proof matches same envelope", %{auditor: a} do
      env = %{message_id: "m1", data: "test"}
      proof = InMemory.create_proof(a, env, "policy")
      assert InMemory.verify_proof(a, proof, env)
    end

    test "verify_proof fails for different envelope", %{auditor: a} do
      proof = InMemory.create_proof(a, %{data: "original"}, "policy")
      refute InMemory.verify_proof(a, proof, %{data: "modified"})
    end

    test "record_audit stores record", %{auditor: a} do
      record = AuditRecord.new(envelope_id: "e1", action: :send, actor_id: "agent-1")
      id = InMemory.record_audit(a, record)
      assert is_binary(id)

      records = InMemory.query_records(a)
      assert length(records) == 1
    end

    test "query_records filters by envelope_id", %{auditor: a} do
      InMemory.record_audit(a, AuditRecord.new(envelope_id: "e1", action: :send))
      InMemory.record_audit(a, AuditRecord.new(envelope_id: "e2", action: :receive))

      result = InMemory.query_records(a, envelope_id: "e1")
      assert length(result) == 1
      assert hd(result).envelope_id == "e1"
    end

    test "query_records filters by action", %{auditor: a} do
      InMemory.record_audit(a, AuditRecord.new(action: :send))
      InMemory.record_audit(a, AuditRecord.new(action: :receive))

      result = InMemory.query_records(a, action: :send)
      assert length(result) == 1
    end

    test "query_records respects limit", %{auditor: a} do
      for _ <- 1..5, do: InMemory.record_audit(a, AuditRecord.new(action: :send))
      result = InMemory.query_records(a, limit: 3)
      assert length(result) == 3
    end

    test "clear removes all records", %{auditor: a} do
      InMemory.record_audit(a, AuditRecord.new(action: :send))
      InMemory.clear(a)
      assert InMemory.query_records(a) == []
    end
  end

  describe "AuditRecord.new/1" do
    test "generates record_id" do
      record = AuditRecord.new(action: :send)
      assert String.starts_with?(record.record_id, "record-")
    end

    test "sets timestamp" do
      record = AuditRecord.new()
      assert is_integer(record.timestamp)
    end
  end
end
