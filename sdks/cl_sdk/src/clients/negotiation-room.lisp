;;;; negotiation-room.lisp - Negotiation Room client for SW4RM
;;;;
;;;; Manages multi-agent artifact approval workflows using the Negotiation
;;;; Room pattern. Supports submitting artifacts for review, collecting votes
;;;; from critics, and coordinating the review process.

(in-package :sw4rm)

;;;; Client Class

(defclass negotiation-room-client (base-client)
  ()
  (:documentation "Client for managing negotiation room operations.

The negotiation room client manages the lifecycle of artifact proposals
through the multi-agent review process:

Workflow:
  1. Producer submits an artifact proposal
  2. Critics evaluate and submit votes
  3. Coordinator retrieves votes and makes decision
  4. Decision is stored and made available

This is a local client (not gRPC-based) that uses in-memory or file-based
storage for proposals, votes, and decisions. For distributed deployments,
use a shared storage backend.

Note: This differs from the NegotiationService (negotiation.lisp) which
handles general multi-agent negotiations. The negotiation room is specifically
for artifact approval workflows."))

;;;; RPC Methods (Local, not gRPC)

(defgeneric create-room (client room-id &key description metadata)
  (:documentation "Create a new negotiation room.

Initializes a negotiation room for artifact review workflows.

Args:
  client: The negotiation-room-client instance.
  room-id: Unique identifier for the room.
  description: Optional human-readable description.
  metadata: Optional metadata alist.

Returns:
  Room creation response plist with :room-id and :created-at.

Signals:
  RPC-ERROR: If room creation fails (e.g., room already exists).

Example:
  (create-room client \"room-code-review\"
               :description \"Code artifact review room\"
               :metadata '((:team . \"backend\")))"))

(defmethod create-room ((client negotiation-room-client) room-id
                        &key description metadata)
  ;; Stub: Local implementation would use in-memory or file-based storage
  (error 'rpc-error
         :message "CreateRoom not implemented - requires storage backend integration"
         :code "UNIMPLEMENTED"))

(defgeneric submit-artifact (client artifact-proposal)
  (:documentation "Submit an artifact proposal for multi-agent review.

Stores the proposal and initializes empty vote tracking for the artifact.
This method is typically called by producer agents.

Args:
  client: The negotiation-room-client instance.
  artifact-proposal: Artifact proposal plist with:
    :artifact-type (keyword) - Type: :code, :document, :design, etc.
    :artifact-id (string) - Unique artifact identifier
    :producer-id (string) - Agent ID of producer
    :artifact (bytes) - Artifact content
    :artifact-content-type (string) - MIME type
    :requested-critics (list) - List of critic agent IDs
    :negotiation-room-id (string) - Room identifier

Returns:
  The artifact-id of the submitted proposal.

Signals:
  RPC-ERROR: If a proposal with the same artifact-id already exists.

Example:
  (submit-artifact client
                   (list :artifact-type :code
                         :artifact-id \"code-123\"
                         :producer-id \"agent-producer\"
                         :artifact (babel:string-to-octets \"(defun hello () 'world)\")
                         :artifact-content-type \"text/x-common-lisp\"
                         :requested-critics '(\"critic-1\" \"critic-2\")
                         :negotiation-room-id \"room-1\"))"))

(defmethod submit-artifact ((client negotiation-room-client) artifact-proposal)
  ;; Stub: Local implementation would save to storage backend
  (error 'rpc-error
         :message "SubmitArtifact not implemented - requires storage backend integration"
         :code "UNIMPLEMENTED"))

(defgeneric add-critique (client vote)
  (:documentation "Submit a critic's vote for an artifact.

Adds the vote to the collection for the specified artifact. This method
is typically called by critic agents after evaluating an artifact.

Args:
  client: The negotiation-room-client instance.
  vote: Negotiation vote plist with:
    :artifact-id (string) - Artifact being evaluated
    :critic-id (string) - Agent ID of critic
    :score (float) - Numeric score (0.0-10.0)
    :confidence (float) - Confidence in score (0.0-1.0)
    :passed (boolean) - Whether artifact passes review
    :strengths (list of strings) - Identified strengths
    :weaknesses (list of strings) - Identified weaknesses
    :recommendations (list of strings) - Improvement suggestions
    :negotiation-room-id (string) - Room identifier

Returns:
  NIL on success.

Signals:
  RPC-ERROR: If no proposal exists or critic has already voted.

Example:
  (add-critique client
                (list :artifact-id \"code-123\"
                      :critic-id \"critic-1\"
                      :score 8.5
                      :confidence 0.9
                      :passed t
                      :strengths '(\"Good structure\")
                      :weaknesses '(\"Needs tests\")
                      :recommendations '(\"Add unit tests\")
                      :negotiation-room-id \"room-1\"))"))

(defmethod add-critique ((client negotiation-room-client) vote)
  ;; Stub: Local implementation would validate and store vote
  (error 'rpc-error
         :message "AddCritique not implemented - requires storage backend integration"
         :code "UNIMPLEMENTED"))

(defgeneric score-artifact (client artifact-id)
  (:documentation "Retrieve all votes for a specific artifact.

Returns all critic votes that have been submitted for the artifact.
This method is typically called by coordinator agents to aggregate
votes and make decisions.

Args:
  client: The negotiation-room-client instance.
  artifact-id: The identifier of the artifact.

Returns:
  List of vote plists (empty list if no votes yet).

Signals:
  RPC-ERROR: If no proposal exists for the artifact-id.

Example:
  (score-artifact client \"code-123\")
  => ((:critic-id \"critic-1\" :score 8.5 :passed t)
      (:critic-id \"critic-2\" :score 7.0 :passed t))"))

(defmethod score-artifact ((client negotiation-room-client) artifact-id)
  ;; Stub: Local implementation would retrieve votes from storage
  (error 'rpc-error
         :message "ScoreArtifact not implemented - requires storage backend integration"
         :code "UNIMPLEMENTED"))

(defgeneric get-room-status (client room-id)
  (:documentation "Get the status and statistics of a negotiation room.

Retrieves room metadata, pending proposals, and summary statistics.

Args:
  client: The negotiation-room-client instance.
  room-id: Unique identifier of the room.

Returns:
  Room status plist with:
    :room-id (string) - Room identifier
    :pending-proposals (integer) - Number of pending proposals
    :completed-decisions (integer) - Number of completed reviews
    :active-critics (list) - List of critic agent IDs with pending reviews

Signals:
  RPC-ERROR: If room not found.

Example:
  (get-room-status client \"room-1\")
  => (:room-id \"room-1\"
      :pending-proposals 2
      :completed-decisions 5
      :active-critics (\"critic-1\" \"critic-2\"))"))

(defmethod get-room-status ((client negotiation-room-client) room-id)
  ;; Stub: Local implementation would aggregate statistics from storage
  (error 'rpc-error
         :message "GetRoomStatus not implemented - requires storage backend integration"
         :code "UNIMPLEMENTED"))

;;;; Additional Helper Methods

(defgeneric get-decision (client artifact-id)
  (:documentation "Retrieve the decision for a specific artifact if available.

Returns the final decision if one has been made, or NIL if the artifact
is still under review.

Args:
  client: The negotiation-room-client instance.
  artifact-id: The identifier of the artifact.

Returns:
  The negotiation decision plist if available, NIL otherwise.

Signals:
  RPC-ERROR: If no proposal exists for the artifact-id.

Example:
  (get-decision client \"code-123\")
  => (:artifact-id \"code-123\"
      :outcome :approved
      :aggregated-score 8.2)"))

(defmethod get-decision ((client negotiation-room-client) artifact-id)
  ;; Stub: Local implementation would retrieve decision from storage
  (error 'rpc-error
         :message "GetDecision not implemented - requires storage backend integration"
         :code "UNIMPLEMENTED"))

(defgeneric wait-for-decision (client artifact-id &key timeout-s poll-interval-s)
  (:documentation "Wait for a decision to be made on an artifact.

Polls for a decision until one is available or the timeout is reached.
This method is useful for producer agents waiting for the outcome of
their artifact review.

Args:
  client: The negotiation-room-client instance.
  artifact-id: The identifier of the artifact.
  timeout-s: Maximum time to wait in seconds (default: 30.0).
  poll-interval-s: Time between polling attempts in seconds (default: 0.1).

Returns:
  The negotiation decision once available.

Signals:
  RPC-ERROR: If no proposal exists for the artifact-id.
  RPC-TIMEOUT: If no decision is made within the timeout period.

Example:
  (wait-for-decision client \"code-123\" :timeout-s 10.0)
  => (:artifact-id \"code-123\" :outcome :approved)"))

(defmethod wait-for-decision ((client negotiation-room-client) artifact-id
                              &key (timeout-s 30.0) (poll-interval-s 0.1))
  ;; Stub: Local implementation would poll storage for decision
  (error 'rpc-error
         :message "WaitForDecision not implemented - requires storage backend integration"
         :code "UNIMPLEMENTED"))
