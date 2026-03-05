defmodule Sw4rm.Envelope do
  @moduledoc """
  Envelope construction and manipulation implementing the Three-ID model (spec S11.3).

  Three identifiers track messages:
  1. `message_id` (UUIDv4) - unique per delivery attempt
  2. `correlation_id` (UUIDv4) - groups related operations
  3. `idempotency_token` - enables exactly-once semantics
  """

  @type t :: %__MODULE__{}
  defstruct [
    :message_id,
    :idempotency_token,
    :producer_id,
    :correlation_id,
    :sequence_number,
    :retry_count,
    :message_type,
    :content_type,
    :content_length,
    :repo_id,
    :worktree_id,
    :hlc_timestamp,
    :ttl_ms,
    :state,
    :parent_correlation_id,
    # SDK-local extension, not in canonical proto
    :effective_policy_id,
    :payload,
    # SDK-local extension, not in canonical proto
    :audit_proof,
    # SDK-local extension, not in canonical proto
    :audit_policy_id
  ]

  @doc """
  Build a new envelope.

  Required keys: `:producer_id`, `:message_type`.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    producer_id = Keyword.fetch!(opts, :producer_id)
    message_type = Keyword.fetch!(opts, :message_type)
    payload = Keyword.get(opts, :payload, <<>>)

    %__MODULE__{
      message_id: generate_uuid(),
      idempotency_token: Keyword.get(opts, :idempotency_token, ""),
      producer_id: producer_id,
      correlation_id: Keyword.get(opts, :correlation_id, generate_uuid()),
      sequence_number: Keyword.get(opts, :sequence_number, 1),
      retry_count: Keyword.get(opts, :retry_count, 0),
      message_type: message_type,
      content_type: Keyword.get(opts, :content_type, "application/json"),
      content_length: byte_size(payload),
      repo_id: Keyword.get(opts, :repo_id, ""),
      worktree_id: Keyword.get(opts, :worktree_id, ""),
      hlc_timestamp: generate_hlc_timestamp(),
      ttl_ms: Keyword.get(opts, :ttl_ms, 0),
      state: Keyword.get(opts, :state, :sent),
      parent_correlation_id: Keyword.get(opts, :parent_correlation_id, ""),
      effective_policy_id: Keyword.get(opts, :effective_policy_id, ""),
      payload: payload,
      audit_proof: Keyword.get(opts, :audit_proof, <<>>),
      audit_policy_id: Keyword.get(opts, :audit_policy_id, "")
    }
  end

  @doc "Generate a new UUIDv4 string."
  @spec generate_uuid() :: String.t()
  def generate_uuid do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)

    <<a::48, 4::4, b::12, 2::2, c::62>>
    |> Base.encode16(case: :lower)
    |> format_uuid()
  end

  defp format_uuid(<<a::binary-8, b::binary-4, c::binary-4, d::binary-4, e::binary-12>>) do
    "#{a}-#{b}-#{c}-#{d}-#{e}"
  end

  @doc "Generate HLC timestamp in canonical format `HLC:<wall>:<logical>:<node>`."
  @spec generate_hlc_timestamp() :: String.t()
  def generate_hlc_timestamp do
    wall_us = System.os_time(:microsecond)
    {:ok, hostname} = :inet.gethostname()
    "HLC:#{wall_us}:0:#{hostname}"
  end

  @doc """
  Compute deterministic SHA-256 hash from canonical operation parameters.
  Returns first 16 hex characters.
  """
  @spec compute_deterministic_hash(map() | keyword()) :: String.t()
  def compute_deterministic_hash(params) when is_list(params) do
    params |> Enum.into(%{}) |> compute_deterministic_hash()
  end

  def compute_deterministic_hash(params) when is_map(params) do
    canonical =
      params
      |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
      |> Enum.map_join(":", fn {k, v} -> "#{k}:#{inspect(v)}" end)

    :crypto.hash(:sha256, canonical)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  @doc "Create idempotency token: `{producer_id}:{operation_type}:{hash}`."
  @spec make_idempotency_token(String.t(), String.t(), String.t()) :: String.t()
  def make_idempotency_token(producer_id, operation_type, deterministic_hash) do
    "#{producer_id}:#{operation_type}:#{deterministic_hash}"
  end

  @doc "Validate envelope structure. Raises `Sw4rm.Error.Validation` on failure."
  @spec validate!(t()) :: :ok
  def validate!(%__MODULE__{} = env) do
    validate_field!(env.message_id, "message_id", "must not be nil")
    validate_field!(env.producer_id, "producer_id", "must not be nil")
    validate_field!(env.correlation_id, "correlation_id", "must not be nil")
    validate_field!(env.message_type, "message_type", "must not be nil")

    unless is_integer(env.sequence_number) and env.sequence_number > 0 do
      raise Sw4rm.Error.Validation,
        message: "sequence_number must be positive integer",
        field: "sequence_number",
        constraint: "positive integer"
    end

    unless is_integer(env.retry_count) and env.retry_count >= 0 do
      raise Sw4rm.Error.Validation,
        message: "retry_count must be non-negative integer",
        field: "retry_count",
        constraint: "non-negative integer"
    end

    :ok
  end

  @terminal_states [:fulfilled, :rejected, :failed, :timed_out]

  @doc "Check if an envelope state is terminal."
  @spec terminal_state?(atom()) :: boolean()
  def terminal_state?(state), do: state in @terminal_states

  @doc "Update envelope state, returning a new struct."
  @spec update_state(t(), atom()) :: t()
  def update_state(%__MODULE__{} = env, new_state), do: %{env | state: new_state}

  # -- Helpers --

  defp validate_field!(nil, field, constraint) do
    raise Sw4rm.Error.Validation,
      message: "#{field} validation failed",
      field: field,
      constraint: constraint
  end

  defp validate_field!(_, _field, _constraint), do: :ok
end
