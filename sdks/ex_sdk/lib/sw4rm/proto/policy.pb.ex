defmodule Sw4rm.Proto.Policy.NegotiationPolicy.Hitl do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :mode, 1, type: :string
end

defmodule Sw4rm.Proto.Policy.NegotiationPolicy.Scoring do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :require_schema_valid, 1, type: :bool, json_name: "requireSchemaValid"
  field :require_examples_pass, 2, type: :bool, json_name: "requireExamplesPass"
  field :llm_weight, 3, type: :float, json_name: "llmWeight"
end

defmodule Sw4rm.Proto.Policy.NegotiationPolicy do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :max_rounds, 1, type: :uint32, json_name: "maxRounds"
  field :score_threshold, 2, type: :float, json_name: "scoreThreshold"
  field :diff_tolerance, 3, type: :float, json_name: "diffTolerance"
  field :round_timeout_ms, 4, type: :uint64, json_name: "roundTimeoutMs"
  field :token_budget_per_round, 5, type: :uint64, json_name: "tokenBudgetPerRound"
  field :total_token_budget, 6, type: :uint64, json_name: "totalTokenBudget"
  field :oscillation_limit, 7, type: :uint32, json_name: "oscillationLimit"
  field :hitl, 8, type: Sw4rm.Proto.Policy.NegotiationPolicy.Hitl
  field :scoring, 9, type: Sw4rm.Proto.Policy.NegotiationPolicy.Scoring
end

defmodule Sw4rm.Proto.Policy.AgentPreferences do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :max_rounds, 1, type: :uint32, json_name: "maxRounds"
  field :score_threshold, 2, type: :float, json_name: "scoreThreshold"
  field :diff_tolerance, 3, type: :float, json_name: "diffTolerance"
  field :round_timeout_ms, 4, type: :uint64, json_name: "roundTimeoutMs"
  field :token_budget_per_round, 5, type: :uint64, json_name: "tokenBudgetPerRound"
  field :total_token_budget, 6, type: :uint64, json_name: "totalTokenBudget"
  field :oscillation_limit, 7, type: :uint32, json_name: "oscillationLimit"
end

defmodule Sw4rm.Proto.Policy.EffectivePolicy.AppliedEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: Sw4rm.Proto.Policy.AgentPreferences
end

defmodule Sw4rm.Proto.Policy.EffectivePolicy do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :policy, 1, type: Sw4rm.Proto.Policy.NegotiationPolicy

  field :applied, 2,
    repeated: true,
    type: Sw4rm.Proto.Policy.EffectivePolicy.AppliedEntry,
    map: true
end

defmodule Sw4rm.Proto.Policy.PolicyProfile do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :name, 1, type: :string
  field :policy, 2, type: Sw4rm.Proto.Policy.NegotiationPolicy
end

defmodule Sw4rm.Proto.Policy.DeltaSummary do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :magnitude, 1, type: :float
  field :changed_paths, 2, repeated: true, type: :string, json_name: "changedPaths"
end

defmodule Sw4rm.Proto.Policy.EvaluationReport do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :from_agent, 1, type: :string, json_name: "fromAgent"
  field :deterministic_score, 2, type: :float, json_name: "deterministicScore"
  field :llm_confidence, 3, type: :float, json_name: "llmConfidence"
  field :notes, 4, type: :string
  field :delta, 5, type: Sw4rm.Proto.Policy.DeltaSummary
end

defmodule Sw4rm.Proto.Policy.DecisionReport do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :decided_by, 1, type: :string, json_name: "decidedBy"
  field :final_score, 2, type: :float, json_name: "finalScore"
  field :rationale, 3, type: :string
  field :stop_reason, 4, type: :string, json_name: "stopReason"
end
