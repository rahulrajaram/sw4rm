defmodule Sw4rm.Audit do
  @moduledoc """
  Audit behaviour with NoOp and InMemory implementations.
  """

  defmodule Proof do
    @moduledoc "Cryptographic proof for audit verification."
    @type t :: %__MODULE__{}
    defstruct [:proof_id, :proof_type, :proof_data, :created_at, :verified]
  end

  defmodule AuditRecord do
    @moduledoc "Record of an auditable action."
    @type t :: %__MODULE__{}
    defstruct [:record_id, :envelope_id, :action, :actor_id, :timestamp, :proof, :metadata]

    @doc "Build an audit record from keyword options."
    def new(opts \\ []) do
      now = System.system_time(:second)

      %__MODULE__{
        record_id: Keyword.get(opts, :record_id, "record-#{now}-#{:rand.uniform(1_000_000)}"),
        envelope_id: Keyword.get(opts, :envelope_id),
        action: Keyword.get(opts, :action),
        actor_id: Keyword.get(opts, :actor_id),
        timestamp: now,
        proof: Keyword.get(opts, :proof),
        metadata: Keyword.get(opts, :metadata, %{})
      }
    end
  end

  @callback create_proof(auditor :: term(), envelope :: term(), policy :: term()) :: Proof.t()
  @callback verify_proof(auditor :: term(), proof :: Proof.t(), envelope :: term()) :: boolean()
  @callback record_audit(auditor :: term(), record :: AuditRecord.t()) :: String.t() | nil
  @callback query_records(auditor :: term(), opts :: keyword()) :: [AuditRecord.t()]

  @doc "Compute SHA-256 hash of an envelope."
  def compute_envelope_hash(envelope) do
    :crypto.hash(:sha256, inspect(envelope))
    |> Base.encode16(case: :lower)
  end
end

defmodule Sw4rm.Audit.NoOp do
  @moduledoc "Auditor that does nothing. Useful for testing."
  @behaviour Sw4rm.Audit

  @impl true
  def create_proof(_auditor, _envelope, _policy) do
    %Sw4rm.Audit.Proof{
      proof_id: "noop-#{System.system_time(:second)}",
      proof_type: :no_op,
      proof_data: nil,
      created_at: System.system_time(:second),
      verified: true
    }
  end

  @impl true
  def verify_proof(_auditor, _proof, _envelope), do: true

  @impl true
  def record_audit(_auditor, _record), do: nil

  @impl true
  def query_records(_auditor, _opts), do: []
end

defmodule Sw4rm.Audit.InMemory do
  @moduledoc "In-memory auditor with SHA-256 proofs (GenServer)."
  @behaviour Sw4rm.Audit
  use GenServer

  alias Sw4rm.Audit
  alias Sw4rm.Audit.Proof

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    max_records = Keyword.get(opts, :max_records, 10_000)
    GenServer.start_link(__MODULE__, max_records, name: name)
  end

  @impl Sw4rm.Audit
  def create_proof(server, envelope, _policy) do
    GenServer.call(server, {:create_proof, envelope})
  end

  @impl Sw4rm.Audit
  def verify_proof(server, proof, envelope) do
    GenServer.call(server, {:verify_proof, proof, envelope})
  end

  @impl Sw4rm.Audit
  def record_audit(server, record), do: GenServer.call(server, {:record, record})

  @impl Sw4rm.Audit
  def query_records(server, opts \\ []), do: GenServer.call(server, {:query, opts})

  def clear(server), do: GenServer.call(server, :clear)

  @impl true
  def init(max_records), do: {:ok, %{records: [], max_records: max_records}}

  @impl true
  def handle_call({:create_proof, envelope}, _from, s) do
    hash = Audit.compute_envelope_hash(envelope)
    now = System.system_time(:second)

    proof = %Proof{
      proof_id: "proof-#{now}-#{:rand.uniform(1_000_000)}",
      proof_type: :sha256_hash,
      proof_data: hash,
      created_at: now,
      verified: false
    }

    {:reply, proof, s}
  end

  def handle_call({:verify_proof, %Proof{proof_type: :sha256_hash} = proof, envelope}, _from, s) do
    actual = Audit.compute_envelope_hash(envelope)
    {:reply, proof.proof_data == actual, s}
  end

  def handle_call({:verify_proof, _, _}, _from, s), do: {:reply, false, s}

  def handle_call({:record, record}, _from, s) do
    records = Enum.take([record | s.records], s.max_records)
    {:reply, record.record_id, %{s | records: records}}
  end

  def handle_call({:query, opts}, _from, s) do
    result = s.records
    envelope_id = Keyword.get(opts, :envelope_id)
    action = Keyword.get(opts, :action)
    actor_id = Keyword.get(opts, :actor_id)
    from_time = Keyword.get(opts, :from_time)
    to_time = Keyword.get(opts, :to_time)
    limit = Keyword.get(opts, :limit)

    result =
      if envelope_id, do: Enum.filter(result, &(&1.envelope_id == envelope_id)), else: result

    result = if action, do: Enum.filter(result, &(&1.action == action)), else: result
    result = if actor_id, do: Enum.filter(result, &(&1.actor_id == actor_id)), else: result
    result = if from_time, do: Enum.filter(result, &(&1.timestamp >= from_time)), else: result
    result = if to_time, do: Enum.filter(result, &(&1.timestamp <= to_time)), else: result
    result = if limit, do: Enum.take(result, limit), else: result

    {:reply, result, s}
  end

  def handle_call(:clear, _from, s), do: {:reply, :ok, %{s | records: []}}
end
