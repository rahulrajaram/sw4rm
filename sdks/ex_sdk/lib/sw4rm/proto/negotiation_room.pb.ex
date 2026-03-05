defmodule Sw4rm.Proto.NegotiationRoom.QuorumFailureAction do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :QUORUM_FAIL_CLOSED, 0
  field :QUORUM_FAIL_WITH_ABSTAIN, 1
  field :QUORUM_FAIL_WITH_AVAILABLE, 2
end

defmodule Sw4rm.Proto.NegotiationRoom.QuorumPolicy do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  oneof :rule, 0

  field :minimum_votes, 1, type: :uint32, json_name: "minimumVotes", oneof: 0
  field :minimum_fraction, 2, type: :float, json_name: "minimumFraction", oneof: 0
  field :require_all, 3, type: :bool, json_name: "requireAll", oneof: 0

  field :on_failure, 4,
    type: Sw4rm.Proto.NegotiationRoom.QuorumFailureAction,
    json_name: "onFailure",
    enum: true
end

defmodule Sw4rm.Proto.NegotiationRoom.LateVote do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :critic_id, 1, type: :string, json_name: "criticId"
  field :vote, 2, type: Sw4rm.Proto.NegotiationRoom.NegotiationVote
  field :received_at, 3, type: Google.Protobuf.Timestamp, json_name: "receivedAt"
end

defmodule Sw4rm.Proto.NegotiationRoom.ArtifactType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :ARTIFACT_TYPE_UNSPECIFIED, 0
  field :REQUIREMENTS, 1
  field :PLAN, 2
  field :CODE, 3
  field :DEPLOYMENT, 4
end

defmodule Sw4rm.Proto.NegotiationRoom.DecisionOutcome do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :DECISION_OUTCOME_UNSPECIFIED, 0
  field :APPROVED, 1
  field :REVISION_REQUESTED, 2
  field :ESCALATED_TO_HITL, 3
end

defmodule Sw4rm.Proto.NegotiationRoom.NegotiationProposal do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :artifact_type, 1,
    type: Sw4rm.Proto.NegotiationRoom.ArtifactType,
    json_name: "artifactType",
    enum: true

  field :artifact_id, 2, type: :string, json_name: "artifactId"
  field :producer_id, 3, type: :string, json_name: "producerId"
  field :artifact, 4, type: :bytes
  field :artifact_content_type, 5, type: :string, json_name: "artifactContentType"
  field :requested_critics, 6, repeated: true, type: :string, json_name: "requestedCritics"
  field :negotiation_room_id, 7, type: :string, json_name: "negotiationRoomId"
  field :created_at, 8, type: Google.Protobuf.Timestamp, json_name: "createdAt"

  # SW4-001 extension fields
  field :vote_collection_timeout_s, 100, type: :uint32, json_name: "voteCollectionTimeoutS"

  field :quorum_policy, 101,
    type: Sw4rm.Proto.NegotiationRoom.QuorumPolicy,
    json_name: "quorumPolicy"
end

defmodule Sw4rm.Proto.NegotiationRoom.NegotiationVote do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :artifact_id, 1, type: :string, json_name: "artifactId"
  field :critic_id, 2, type: :string, json_name: "criticId"
  field :score, 3, type: :double
  field :confidence, 4, type: :double
  field :passed, 5, type: :bool
  field :strengths, 6, repeated: true, type: :string
  field :weaknesses, 7, repeated: true, type: :string
  field :recommendations, 8, repeated: true, type: :string
  field :negotiation_room_id, 9, type: :string, json_name: "negotiationRoomId"
  field :voted_at, 10, type: Google.Protobuf.Timestamp, json_name: "votedAt"
end

defmodule Sw4rm.Proto.NegotiationRoom.AggregatedScore do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :mean, 1, type: :double
  field :min_score, 2, type: :double, json_name: "minScore"
  field :max_score, 3, type: :double, json_name: "maxScore"
  field :std_dev, 4, type: :double, json_name: "stdDev"
  field :weighted_mean, 5, type: :double, json_name: "weightedMean"
  field :vote_count, 6, type: :int32, json_name: "voteCount"
end

defmodule Sw4rm.Proto.NegotiationRoom.NegotiationDecision do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :artifact_id, 1, type: :string, json_name: "artifactId"
  field :outcome, 2, type: Sw4rm.Proto.NegotiationRoom.DecisionOutcome, enum: true
  field :votes, 3, repeated: true, type: Sw4rm.Proto.NegotiationRoom.NegotiationVote

  field :aggregated_score, 4,
    type: Sw4rm.Proto.NegotiationRoom.AggregatedScore,
    json_name: "aggregatedScore"

  field :policy_version, 5, type: :string, json_name: "policyVersion"
  field :reason, 6, type: :string
  field :negotiation_room_id, 7, type: :string, json_name: "negotiationRoomId"
  field :decided_at, 8, type: Google.Protobuf.Timestamp, json_name: "decidedAt"

  # SW4-001 extension fields
  field :quorum_met, 100, type: :bool, json_name: "quorumMet"
  field :votes_received, 101, type: :uint32, json_name: "votesReceived"
  field :votes_expected, 102, type: :uint32, json_name: "votesExpected"
  field :collection_timeout_reached, 103, type: :bool, json_name: "collectionTimeoutReached"

  field :unavailable_critics, 104,
    repeated: true,
    type: :string,
    json_name: "unavailableCritics"

  field :late_votes, 105,
    repeated: true,
    type: Sw4rm.Proto.NegotiationRoom.LateVote,
    json_name: "lateVotes"
end

defmodule Sw4rm.Proto.NegotiationRoom.SubmitProposalRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :proposal, 1, type: Sw4rm.Proto.NegotiationRoom.NegotiationProposal
end

defmodule Sw4rm.Proto.NegotiationRoom.SubmitProposalResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :artifact_id, 1, type: :string, json_name: "artifactId"
  field :negotiation_room_id, 2, type: :string, json_name: "negotiationRoomId"
end

defmodule Sw4rm.Proto.NegotiationRoom.SubmitVoteRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :vote, 1, type: Sw4rm.Proto.NegotiationRoom.NegotiationVote
end

defmodule Sw4rm.Proto.NegotiationRoom.SubmitVoteResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :artifact_id, 1, type: :string, json_name: "artifactId"
  field :critic_id, 2, type: :string, json_name: "criticId"
end

defmodule Sw4rm.Proto.NegotiationRoom.GetVotesRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :artifact_id, 1, type: :string, json_name: "artifactId"
  field :negotiation_room_id, 2, type: :string, json_name: "negotiationRoomId"
end

defmodule Sw4rm.Proto.NegotiationRoom.GetVotesResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :votes, 1, repeated: true, type: Sw4rm.Proto.NegotiationRoom.NegotiationVote
  field :vote_count, 2, type: :int32, json_name: "voteCount"
end

defmodule Sw4rm.Proto.NegotiationRoom.GetDecisionRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :artifact_id, 1, type: :string, json_name: "artifactId"
  field :negotiation_room_id, 2, type: :string, json_name: "negotiationRoomId"
end

defmodule Sw4rm.Proto.NegotiationRoom.GetDecisionResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :decision, 1, type: Sw4rm.Proto.NegotiationRoom.NegotiationDecision
end

defmodule Sw4rm.Proto.NegotiationRoom.WaitForDecisionRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :artifact_id, 1, type: :string, json_name: "artifactId"
  field :negotiation_room_id, 2, type: :string, json_name: "negotiationRoomId"
  field :timeout_seconds, 3, type: :uint32, json_name: "timeoutSeconds"
end

defmodule Sw4rm.Proto.NegotiationRoom.WaitForDecisionResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.0", syntax: :proto3

  field :decision, 1, type: Sw4rm.Proto.NegotiationRoom.NegotiationDecision
end

defmodule Sw4rm.Proto.NegotiationRoom.NegotiationRoomService.Service do
  @moduledoc false

  use GRPC.Service,
    name: "sw4rm.negotiation_room.NegotiationRoomService",
    protoc_gen_elixir_version: "0.14.0"

  rpc :SubmitProposal,
      Sw4rm.Proto.NegotiationRoom.SubmitProposalRequest,
      Sw4rm.Proto.NegotiationRoom.SubmitProposalResponse

  rpc :SubmitVote,
      Sw4rm.Proto.NegotiationRoom.SubmitVoteRequest,
      Sw4rm.Proto.NegotiationRoom.SubmitVoteResponse

  rpc :GetVotes,
      Sw4rm.Proto.NegotiationRoom.GetVotesRequest,
      Sw4rm.Proto.NegotiationRoom.GetVotesResponse

  rpc :GetDecision,
      Sw4rm.Proto.NegotiationRoom.GetDecisionRequest,
      Sw4rm.Proto.NegotiationRoom.GetDecisionResponse

  rpc :WaitForDecision,
      Sw4rm.Proto.NegotiationRoom.WaitForDecisionRequest,
      Sw4rm.Proto.NegotiationRoom.WaitForDecisionResponse
end

defmodule Sw4rm.Proto.NegotiationRoom.NegotiationRoomService.Stub do
  @moduledoc false

  use GRPC.Stub, service: Sw4rm.Proto.NegotiationRoom.NegotiationRoomService.Service
end
