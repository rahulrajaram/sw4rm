defmodule Sw4rm.Error do
  @moduledoc """
  Exception hierarchy for SW4RM protocol errors.

  All exceptions embed a `:message` and `:error_code` field.
  Specific sub-types add domain-relevant fields.
  """

  defexception [:message, :error_code]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "SW4RM error"),
      error_code: Keyword.get(attrs, :error_code, 99)
    }
  end
end

defmodule Sw4rm.Error.RPC do
  @moduledoc "gRPC communication failure."
  defexception [:message, :error_code, :status_code, :details]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "RPC error"),
      error_code: Keyword.get(attrs, :error_code, 2),
      status_code: Keyword.get(attrs, :status_code),
      details: Keyword.get(attrs, :details)
    }
  end
end

defmodule Sw4rm.Error.RPCTimeout do
  @moduledoc "gRPC deadline exceeded."
  defexception [:message, :error_code, :timeout_ms]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "RPC timeout"),
      error_code: Keyword.get(attrs, :error_code, 3),
      timeout_ms: Keyword.get(attrs, :timeout_ms)
    }
  end
end

defmodule Sw4rm.Error.RPCUnavailable do
  @moduledoc "gRPC service unavailable."
  defexception [:message, :error_code, :endpoint]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "RPC unavailable"),
      error_code: Keyword.get(attrs, :error_code, 4),
      endpoint: Keyword.get(attrs, :endpoint)
    }
  end
end

defmodule Sw4rm.Error.Validation do
  @moduledoc "Input validation failure."
  defexception [:message, :error_code, :field, :constraint]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "Validation error"),
      error_code: Keyword.get(attrs, :error_code, 6),
      field: Keyword.get(attrs, :field),
      constraint: Keyword.get(attrs, :constraint)
    }
  end
end

defmodule Sw4rm.Error.StateTransition do
  @moduledoc "Invalid agent state transition."
  defexception [:message, :error_code, :from_state, :to_state, :allowed_transitions]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "Invalid state transition"),
      error_code: Keyword.get(attrs, :error_code, 99),
      from_state: Keyword.get(attrs, :from_state),
      to_state: Keyword.get(attrs, :to_state),
      allowed_transitions: Keyword.get(attrs, :allowed_transitions, [])
    }
  end
end

defmodule Sw4rm.Error.Timeout do
  @moduledoc "Operation timeout."
  defexception [:message, :error_code, :operation, :timeout_ms]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "Timeout"),
      error_code: Keyword.get(attrs, :error_code, 3),
      operation: Keyword.get(attrs, :operation),
      timeout_ms: Keyword.get(attrs, :timeout_ms)
    }
  end
end

defmodule Sw4rm.Error.BufferFull do
  @moduledoc "Activity buffer at capacity."
  defexception [:message, :error_code, :current_size, :max_size]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "Buffer full"),
      error_code: Keyword.get(attrs, :error_code, 1),
      current_size: Keyword.get(attrs, :current_size),
      max_size: Keyword.get(attrs, :max_size)
    }
  end
end

defmodule Sw4rm.Error.Negotiation do
  @moduledoc "Negotiation protocol failure."
  defexception [:message, :error_code, :negotiation_id, :phase]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "Negotiation error"),
      error_code: Keyword.get(attrs, :error_code, 99),
      negotiation_id: Keyword.get(attrs, :negotiation_id),
      phase: Keyword.get(attrs, :phase)
    }
  end
end

defmodule Sw4rm.Error.Worktree do
  @moduledoc "Worktree binding/management failure."
  defexception [:message, :error_code, :worktree_id, :state]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "Worktree error"),
      error_code: Keyword.get(attrs, :error_code, 99),
      worktree_id: Keyword.get(attrs, :worktree_id),
      state: Keyword.get(attrs, :state)
    }
  end
end

defmodule Sw4rm.Error.DuplicateDetected do
  @moduledoc "Duplicate request detected via idempotency token."
  defexception [:message, :error_code, :idempotency_token]

  @impl true
  def exception(attrs) when is_list(attrs) do
    %__MODULE__{
      message: Keyword.get(attrs, :message, "Duplicate detected"),
      error_code: Keyword.get(attrs, :error_code, 14),
      idempotency_token: Keyword.get(attrs, :idempotency_token)
    }
  end
end
